//! Open drop-in replacement for RustDesk's `printer_driver_adapter.dll`.
//!
//! RustDesk's own adapter verifies the calling executable's Authenticode
//! signature against a hardcoded vendor allow-list, so it refuses to start in
//! any custom-branded build. This crate implements the same four-function ABI
//! that `src/server/printer_service.rs` loads, with no signature check.
//!
//! The ABI, as declared upstream:
//!
//! ```ignore
//! pub type Init        = fn(tag_name: *const i8) -> i32;   // 0 = success
//! pub type Uninit      = fn();
//! pub type GetPrnData  = fn(dur_mills: u32, data: *mut *mut i8, data_len: *mut u32);
//! pub type FreePrnData = fn(data: *mut i8);
//! ```
//!
//! Symbols are looked up by these exact undecorated names, so every export is
//! `#[no_mangle] extern "C"`.
//!
//! # How capture works
//!
//! Instead of a custom print driver, this pairs with a printer built on an
//! inbox (already Microsoft-signed) driver whose port is a plain file path
//! under our spool directory. The spooler writes the rendered job there; we
//! pick it up, hand it to RustDesk, and delete it.
//!
//! # Safety
//!
//! Every export catches panics. Unwinding across an FFI boundary is undefined
//! behaviour, and a panic escaping into the RustDesk server process would take
//! the whole service down.

use std::alloc::{alloc, dealloc, Layout};
use std::ffi::CStr;
use std::fs;
use std::io::{Read, Write};
use std::os::raw::c_char;
use std::os::windows::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

/// Bytes reserved before each returned buffer to stash its length.
/// `free_prn_data` only receives a pointer, so the length has to travel with
/// the allocation itself.
const HEADER: usize = 16;
const ALIGN: usize = 8;

/// Windows share mode: 0 means "no other handle may be open". Opening the
/// spool file this way is how we tell that the spooler has finished with it.
const SHARE_NONE: u32 = 0;

struct State {
    dir: PathBuf,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Append a line to `<spool>/adapter.log`. Never fails the caller: if logging
/// breaks there is nothing useful to do about it from inside a print filter.
fn log(dir: &Path, msg: &str) {
    let path = dir.join("adapter.log");
    if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(f, "[{}] {}", now_secs(), msg);
    }
}

/// Strip characters that cannot appear in a Windows path component, so an
/// arbitrary app name can be used as a directory name.
fn sanitize(tag: &str) -> String {
    let cleaned: String = tag
        .chars()
        .map(|c| match c {
            '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*' => '_',
            c if (c as u32) < 0x20 => '_',
            c => c,
        })
        .collect();
    let trimmed = cleaned.trim().trim_end_matches('.').to_string();
    if trimmed.is_empty() {
        "RustDeskPrinter".to_string()
    } else {
        trimmed
    }
}

/// `%ProgramData%\<tag>\printer-spool`, the directory the printer port writes
/// into. ProgramData is used rather than a user profile because the spooler
/// runs as a service account.
fn spool_dir(tag: &str) -> PathBuf {
    let base = std::env::var("ProgramData")
        .or_else(|_| std::env::var("ALLUSERSPROFILE"))
        .unwrap_or_else(|_| "C:\\ProgramData".to_string());
    Path::new(&base).join(sanitize(tag)).join("printer-spool")
}

/// True when the file can be opened with no sharing, i.e. the spooler has
/// closed its handle and the job is complete.
fn read_if_complete(path: &Path) -> Option<Vec<u8>> {
    let mut f = fs::OpenOptions::new()
        .read(true)
        .share_mode(SHARE_NONE)
        .open(path)
        .ok()?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).ok()?;
    if buf.is_empty() {
        return None;
    }
    Some(buf)
}

/// Oldest candidate job in the spool directory, by modification time.
/// `adapter.log` and zero-length files are skipped.
fn oldest_job(dir: &Path) -> Option<PathBuf> {
    let mut best: Option<(SystemTime, PathBuf)> = None;
    for entry in fs::read_dir(dir).ok()?.flatten() {
        let path = entry.path();
        let meta = match entry.metadata() {
            Ok(m) if m.is_file() && m.len() > 0 => m,
            _ => continue,
        };
        if path
            .file_name()
            .and_then(|n| n.to_str())
            .map(|n| n.eq_ignore_ascii_case("adapter.log"))
            .unwrap_or(false)
        {
            continue;
        }
        let mtime = meta.modified().unwrap_or(UNIX_EPOCH);
        match &best {
            Some((t, _)) if *t <= mtime => {}
            _ => best = Some((mtime, path)),
        }
    }
    best.map(|(_, p)| p)
}

/// Copy `bytes` into a buffer this crate owns, with its length recorded in a
/// header so `free_prn_data` can reconstruct the exact layout.
unsafe fn alloc_buf(bytes: &[u8]) -> *mut c_char {
    let total = HEADER + bytes.len();
    let layout = match Layout::from_size_align(total, ALIGN) {
        Ok(l) => l,
        Err(_) => return ptr::null_mut(),
    };
    let base = alloc(layout);
    if base.is_null() {
        return ptr::null_mut();
    }
    (base as *mut u64).write_unaligned(bytes.len() as u64);
    ptr::copy_nonoverlapping(bytes.as_ptr(), base.add(HEADER), bytes.len());
    base.add(HEADER) as *mut c_char
}

unsafe fn free_buf(data: *mut c_char) {
    if data.is_null() {
        return;
    }
    let base = (data as *mut u8).sub(HEADER);
    let len = (base as *mut u64).read_unaligned() as usize;
    if let Ok(layout) = Layout::from_size_align(HEADER + len, ALIGN) {
        dealloc(base, layout);
    }
}

// ---------------------------------------------------------------------------
// exported ABI
// ---------------------------------------------------------------------------

/// Prepare the spool directory for `tag_name` (RustDesk passes the app name).
/// Returns 0 on success, non-zero on failure — upstream turns any non-zero
/// into "Failed to init printer driver".
#[no_mangle]
pub extern "C" fn init(tag_name: *const c_char) -> i32 {
    let result = std::panic::catch_unwind(|| {
        if tag_name.is_null() {
            return 1;
        }
        let tag = match unsafe { CStr::from_ptr(tag_name) }.to_str() {
            Ok(t) => t.to_string(),
            Err(_) => return 2,
        };
        let dir = spool_dir(&tag);
        if fs::create_dir_all(&dir).is_err() {
            return 3;
        }
        // Drop anything left from a previous run so a stale job cannot be
        // replayed onto the next connection.
        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.is_file()
                    && !p
                        .file_name()
                        .and_then(|n| n.to_str())
                        .map(|n| n.eq_ignore_ascii_case("adapter.log"))
                        .unwrap_or(false)
                {
                    let _ = fs::remove_file(&p);
                }
            }
        }
        log(&dir, &format!("init tag={:?} dir={}", tag, dir.display()));
        match STATE.lock() {
            Ok(mut g) => {
                *g = Some(State { dir });
                0
            }
            Err(_) => 4,
        }
    });
    result.unwrap_or(5)
}

#[no_mangle]
pub extern "C" fn uninit() {
    let _ = std::panic::catch_unwind(|| {
        if let Ok(mut g) = STATE.lock() {
            if let Some(s) = g.as_ref() {
                log(&s.dir, "uninit");
            }
            *g = None;
        }
    });
}

/// Hand back one completed print job, or nothing.
///
/// `dur_mills` is advisory upstream ("data generated in the last N ms"); the
/// spool directory is cleared on `init`, so anything present is by definition
/// new and is returned regardless of age. That avoids dropping a job when the
/// poll loop is delayed.
#[no_mangle]
pub extern "C" fn get_prn_data(_dur_mills: u32, data: *mut *mut c_char, data_len: *mut u32) {
    let _ = std::panic::catch_unwind(|| {
        unsafe {
            if !data.is_null() {
                *data = ptr::null_mut();
            }
            if !data_len.is_null() {
                *data_len = 0;
            }
        }
        if data.is_null() || data_len.is_null() {
            return;
        }
        let guard = match STATE.lock() {
            Ok(g) => g,
            Err(_) => return,
        };
        let Some(state) = guard.as_ref() else { return };
        let Some(job) = oldest_job(&state.dir) else { return };
        // Still open by the spooler means the job is mid-render; try next tick.
        let Some(bytes) = read_if_complete(&job) else { return };
        let _ = fs::remove_file(&job);
        unsafe {
            let buf = alloc_buf(&bytes);
            if buf.is_null() {
                log(&state.dir, "alloc failed, job dropped");
                return;
            }
            *data = buf;
            *data_len = bytes.len() as u32;
        }
        log(
            &state.dir,
            &format!("captured {} ({} bytes)", job.display(), bytes.len()),
        );
    });
}

#[no_mangle]
pub extern "C" fn free_prn_data(data: *mut c_char) {
    let _ = std::panic::catch_unwind(|| unsafe { free_buf(data) });
}
