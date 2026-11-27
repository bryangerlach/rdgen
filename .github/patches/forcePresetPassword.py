#!/usr/bin/env python3
"""Make the permanent password baked into custom_.txt authoritative.

RustDesk treats the password in the custom client config as a *preset*: it is
only consulted when the local configuration has no permanent password.  A
machine that already has RustDesk installed (or that used an older custom
client) therefore keeps its old password and ignores the one chosen in the
generator.

This patch makes the preset password win, while keeping the local password as
a fallback:

  * Config::has_permanent_password() reports "set" when a usable preset exists.
  * Config::is_using_preset_password() reports the preset as in use.
  * Config::get_effective_permanent_password_salt() uses the preset salt (or
    the local salt for a plain-text preset) so the login challenge is computed
    against the password the client will actually send.
  * Connection::validate_password() tries the preset before the local storage.
  * trusted_devices::config::normalize() builds its verifier from the preset
    too, so trusted-device checks agree with the password used to log in.

The patcher is idempotent: a marker comment is left in every edited block and
the block is skipped on a second run.  It fails loudly if an expected pattern
is missing, so a future RustDesk refactor cannot silently turn the patch into
a no-op.

Usage:
    python forcePresetPassword.py [--rustdesk-root PATH]
"""

import argparse
import pathlib
import re
import sys


def read_file(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"forcePresetPassword: file not found: {path}")


def write_file(path: pathlib.Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="")


def replace_once(
    text: str,
    pattern: str,
    replacement: str,
    path: pathlib.Path,
    marker: str,
) -> tuple[str, bool]:
    """Replace exactly one match, unless the marker is already present."""
    if marker in text:
        return text, False
    new_text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(
            f"forcePresetPassword: expected pattern not found in {path} "
            f"(marker {marker!r}); refusing to build without the password fix"
        )
    return new_text, True


def patch_hbb_config(root: pathlib.Path) -> bool:
    path = root / "libs" / "hbb_common" / "src" / "config.rs"
    text = read_file(path)
    changed = False

    # has_permanent_password(): prefer the preset before local storage.
    marker = "// RDGEN_PRESET_PASSWORD: has_permanent_password"
    pattern = (
        r"pub fn has_permanent_password\(\) -> bool \{.*?\n    \}"
        r"(?=\n\n    fn has_usable_preset_password)"
    )
    replacement = """pub fn has_permanent_password() -> bool {
        // RDGEN_PRESET_PASSWORD: has_permanent_password
        if Self::has_usable_preset_password() {
            return true;
        }
        let (local_storage, local_salt) = Self::get_local_permanent_password_storage_and_salt();
        if !local_storage.is_empty() {
            return local_permanent_password_storage_is_usable_for_auth(
                &local_storage,
                &local_salt,
            );
        }
        false
    }"""
    text, did = replace_once(text, pattern, replacement, path, marker)
    changed = changed or did

    # is_using_preset_password(): the preset is in use whenever it is usable.
    marker = "// RDGEN_PRESET_PASSWORD: is_using_preset_password"
    pattern = (
        r"pub fn is_using_preset_password\(\) -> bool \{.*?\n    \}"
        r"(?=\n\n    pub fn get_preset_password_storage_and_salt)"
    )
    replacement = """pub fn is_using_preset_password() -> bool {
        // RDGEN_PRESET_PASSWORD: is_using_preset_password
        Self::has_usable_preset_password()
    }"""
    text, did = replace_once(text, pattern, replacement, path, marker)
    changed = changed or did

    # get_effective_permanent_password_salt(): return the preset salt first.
    marker = "// RDGEN_PRESET_PASSWORD: effective_salt"
    pattern = r"(pub fn get_effective_permanent_password_salt\(\) -> String \{)\n"
    replacement = r"""\1
        // RDGEN_PRESET_PASSWORD: effective_salt
        let (preset_storage, preset_salt) = Self::get_preset_password_storage_and_salt();
        if preset_permanent_password_storage_is_usable_for_auth(&preset_storage, &preset_salt) {
            if !preset_salt.is_empty() {
                return preset_salt;
            }
            return Self::get_salt();
        }
"""
    text, did = replace_once(text, pattern, replacement, path, marker)
    changed = changed or did

    if changed:
        write_file(path, text)
    return changed


def patch_connection(root: pathlib.Path) -> bool:
    path = root / "src" / "server" / "connection.rs"
    text = read_file(path)
    marker = "// RDGEN_PRESET_PASSWORD: validate_password"
    pattern = (
        r"(?P<indent>[ \t]+)let \(local_storage, local_salt\) =\s*\n"
        r"[ \t]+Config::get_local_permanent_password_storage_and_salt\(\);"
    )

    def replacement(match: re.Match) -> str:
        indent = match.group("indent")
        return (
            f"{indent}// RDGEN_PRESET_PASSWORD: validate_password\n"
            f"{indent}let (hard, salt) = Config::get_preset_password_storage_and_salt();\n"
            f"{indent}if preset_permanent_password_storage_is_usable_for_auth(&hard, &salt)\n"
            f"{indent}    && self.validate_preset_password_storage(&hard, &salt)\n"
            f"{indent}{{\n"
            f"{indent}    self.set_conn_audit_primary_auth(ConnAuditPrimaryAuth::PermanentPassword);\n"
            f"{indent}    print_fallback();\n"
            f"{indent}    return true;\n"
            f"{indent}}}\n"
            f"{indent}let (local_storage, local_salt) =\n"
            f"{indent}    Config::get_local_permanent_password_storage_and_salt();"
        )

    if marker in text:
        return False
    new_text, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        raise SystemExit(
            f"forcePresetPassword: expected validate_password block not found in {path}"
        )
    write_file(path, new_text)
    return True


def patch_trusted_devices(root: pathlib.Path) -> bool:
    path = root / "src" / "trusted_devices" / "config.rs"
    if not path.is_file():
        print(f"forcePresetPassword: {path} not present, skipping trusted devices")
        return False

    text = read_file(path)
    marker = "// RDGEN_PRESET_PASSWORD: trusted_devices"
    pattern = (
        r"(fn normalize\(mut password: Password, on_disk: bool\) "
        r"-> \(Option<\[u8; 32\]>, String\) \{)\n"
    )
    replacement = r"""\1
    // RDGEN_PRESET_PASSWORD: trusted_devices
    let (preset, preset_salt) = Config::get_preset_password_storage_and_salt();
    if config::preset_permanent_password_storage_is_usable_for_auth(&preset, &preset_salt) {
        if preset_salt.is_empty() {
            // The login challenge uses the effective salt, which may be
            // generated here if the local config does not have one yet.
            let salt = Config::get_effective_permanent_password_salt();
            return (
                Some(config::compute_permanent_password_h1(&preset, &salt)),
                salt,
            );
        }
        return (
            config::decode_preset_password_h1_from_storage(&preset),
            preset_salt,
        );
    }
"""
    if marker in text:
        return False
    new_text, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        raise SystemExit(
            f"forcePresetPassword: expected normalize() block not found in {path}"
        )
    write_file(path, new_text)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rustdesk-root",
        default=".",
        help="Root of the checked-out RustDesk source tree (default: .)",
    )
    args = parser.parse_args()
    root = pathlib.Path(args.rustdesk_root).resolve()
    if not (root / "libs" / "hbb_common" / "src" / "config.rs").is_file():
        raise SystemExit(f"forcePresetPassword: {root} does not look like a RustDesk tree")

    changed = {
        "config": patch_hbb_config(root),
        "connection": patch_connection(root),
        "trusted_devices": patch_trusted_devices(root),
    }
    for name, did in changed.items():
        print(f"forcePresetPassword: {name}: {'patched' if did else 'already patched'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
