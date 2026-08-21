# Open `printer_driver_adapter.dll`

A drop-in replacement for RustDesk's closed printer adapter, so remote printing
works in custom-branded builds.

## Why this exists

RustDesk's `printer_driver_adapter.dll` verifies the **calling executable's
Authenticode signature** inside `init()` and refuses to run for anything not
signed by RustDesk. Evidence from the shipped binary:

- imports `WinVerifyTrust` (wintrust.dll), `CertGetNameStringW`, `GetModuleFileNameW`
- links `codesign-verify-rs`, a crate whose only purpose is Authenticode checks
- carries one hardcoded identity constant: `PURSLANEHUABINGRUSTDESK` followed by
  two SHA-256 digests. Purslane Ltd is RustDesk's company; Huabing is the founder.

An unsigned custom build fails with:

```
ERROR [src\server.rs:160] printer service init failed: Failed to init printer driver
```

which is the `fn_init() != 0` branch. Signing with *your own* certificate does
not help — the check is an allow-list of specific identities, not "is it signed".

Everything else in RustDesk's printing chain is open source and works. Only the
capture shim is gated, and it is replaceable: this crate reimplements the same
four-function ABI with no signature check.

## The ABI

From `src/server/printer_service.rs`. Symbols are resolved by these exact
undecorated names, so all exports are `#[no_mangle] extern "C"`:

```rust
pub type Init        = fn(tag_name: *const i8) -> i32;   // 0 = success
pub type Uninit      = fn();
pub type GetPrnData  = fn(dur_mills: u32, data: *mut *mut i8, data_len: *mut u32);
pub type FreePrnData = fn(data: *mut i8);
```

Verified: this DLL's PE export table is byte-for-byte the same set of names as
RustDesk's own (`init`, `uninit`, `get_prn_data`, `free_prn_data`).

## How capture works

No custom print driver, therefore no WHQL signing:

```
  print job
      │
      ▼
  virtual printer  ──►  Local Port whose NAME IS A FILE PATH
   (signed driver)         %ProgramData%\<Tag>\printer-spool\job.prn
                                    │
                                    ▼
                        this adapter polls the directory,
                        opens each file with share_mode = 0
                        (fails while the spooler still holds it),
                        returns the bytes, deletes the file
                                    │
                                    ▼
                        printer_service::run()  ──►  on_printer_data()
                                    │
                                    ▼
                        existing open-source transport → controller prints
```

A Local Port whose name is a full file path makes the spooler write output
straight to that file with no "save as" prompt. The exclusive-open test is how
job completion is detected — no timers, no guessing.

`init()` clears the spool directory, so a stale job can never be replayed onto
the next connection, and any file present afterwards is by definition new.

## Build

```
cargo build --release
```

Output: `target\release\printer_driver_adapter.dll` (~140 KB, no dependencies —
std only).

## How the build wires it in

DVForge does all of this automatically for Windows builds — nothing here needs
to be run by hand.

`builder/orchestrator.py` → `_install_open_printer_adapter()`
: cargo-builds this crate and copies the DLL into the Flutter `Release/` folder,
  overwriting the signature-checked one that `_ensure_windows_printer_driver()`
  downloaded. It runs before the MSI harvest and the portable packer, so the
  replacement ships inside both installers.

`builder/customize.py` → `_apply_printer_port()`
: repoints the printer's port at the spool file. **Two** implementations exist
  and both are patched, because patching only one leaves the printer on the
  wrong port:

  - `libs/remote_printer/src/lib.rs` — Rust, used by `--install-remote-printer`
    and the in-app Settings button.
  - `res/msi/CustomActions/RemotePrinter.cpp` — a full C++ reimplementation used
    by the MSI's `InstallPrinter` custom action. This is the one that runs during
    a normal installer run.

  Only the port changes. The printer keeps its name, and the driver stays
  `RustDesk v4 Printer Driver`.

It runs after `_apply_appname()`, since both files have the app name substituted
into them.

## Verifying a build

After installing, confirm the adapter loaded:

```powershell
Get-ChildItem "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\<App>\log" `
  -Recurse -Filter *.log | Select-String "printer service"
```

Expect `printer service initialized`. The old failure reads
`printer service init failed: Failed to init printer driver`.

Confirm the port is the spool file, not a named port:

```powershell
Get-Printer -Name "<App> Printer" | Select-Object Name,DriverName,PortName
```

`PortName` should be `C:\ProgramData\<App>\printer-spool\job.prn`.

Then connect from another machine, print on the controlled one, and check
`%ProgramData%\<App>\printer-spool\adapter.log` for a `captured` line and the
server log for `Got prn data, data len:`.

## Which driver to render with

The controller prints received bytes via `PrintXPSRawData()`
(`src/platform/windows.rs:4261`), so the payload must be a valid XPS package.

- **`RustDesk v4 Printer Driver`** — already installed if you ever ran the app's
  printer install, and it declares `XpsFormat=XPS` (MS-XPS), which is exactly
  what the receiving end expects. Note its render filter is signed by *Microsoft*
  ("Windows Hardware Compatibility Publisher"), not RustDesk — the signature gate
  is only in the adapter, so this driver has no objection to who calls it.
  Best format match. Check redistribution terms before shipping it yourself.
- **`Microsoft XPS Document Writer v4`** — inbox on every Windows machine and
  unambiguously redistributable, but emits **OpenXPS** (`.oxps`), not MS-XPS.
  May need conversion before `PrintXPSRawData` accepts it.

**Resolved 2026-08-19 by inspecting a real captured job.** A test print through
`Microsoft XPS Document Writer v4` produced a valid OPC package whose root
relationship is:

    Type="http://schemas.openxps.org/oxps/v1.0/fixedrepresentation"

That is **OpenXPS**, not MS-XPS — confirming the mismatch. Use
`RustDesk v4 Printer Driver` instead, which declares `XpsFormat=XPS`. If you must
stay on the inbox driver, the fallback is converting OXPS to MS-XPS, or swapping
`send_raw_data_to_printer` on the receiving end — which is your own code.

`PrintXPSRawData` writes diagnostics to `C:\Windows\temp\test_rustdesk.log` on
failure; check there if a job arrives but does not print.

## Status

| Piece | State |
|---|---|
| Four-function ABI, exports match upstream | verified |
| Capture, completion detection, cleanup | verified by test suite |
| Panic safety across the FFI boundary | `catch_unwind` on every export |
| Loads and initialises inside the real server | not yet run |
| Spooler renders a job into the file port | verified — 37 KB job captured |
| End-to-end print to a remote machine | not yet run |
| XPS vs OpenXPS payload | resolved — inbox v4 driver emits OpenXPS, use RustDesk's driver |

## Notes

`panic = "abort"` is deliberately **not** set. A panic escaping a cdylib into the
RustDesk service would take the whole service down, so every export wraps its body
in `catch_unwind` instead.

Licensing: this is clean-room work against an ABI declared in RustDesk's own
AGPL-3.0 source. It contains no RustDesk code and defeats no protection on their
binary — it replaces it.
