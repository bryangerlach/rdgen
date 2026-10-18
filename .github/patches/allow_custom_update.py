#!/usr/bin/env python3
"""
allow_custom_update.py

Apply the RustDesk client source changes needed for fully self-hosted auto-updates.
Run this against a checkout of the RustDesk client (desktop) source tree.

Usage:
    python scripts/allow_custom_update.py \
        --rustdesk-root /path/to/rustdesk \
        --update-url https://updates.example.com/api/version/latest \
        --ed25519-public-key "<base64-or-hex-public-key>"

What it changes:
  1. libs/hbb_common/src/lib.rs        - hardcoded update check URL -> your server
  2. src/common.rs                     - relax github.com-only host check in
                                         release_id_from_update_url()
  3. src/updater/artifact.rs           - relax github.com-only host check in
                                         get_update_download_file_from_url()
  4. src/update_metadata.rs            - add your ed25519 public key to
                                         TRUSTED_UPDATE_KEYS

After running, you still need to:
  * Generate an ed25519 keypair and put the public key in TRUSTED_UPDATE_KEYS
  * Sign your update metadata (rustdesk-update.json) with the private key and
    serve rustdesk-update.json + rustdesk-update.json.sig alongside each build
    on your update server, e.g.:
        https://updates.example.com/releases/v1.5.0/rustdesk-update.json
        https://updates.example.com/releases/v1.5.0/rustdesk-update.json.sig
  * The Go /api/version/latest endpoint returns the base release URL; the client
    appends /rustdesk-update.json (and .sig) to fetch + verify it.
"""

import argparse
import re
import sys
from pathlib import Path

DEFAULT_UPDATE_URL = "https://updates.example.com/api/version/latest"


def replace_in_file(path: Path, pattern: str, replacement: str, count: int = 1) -> int:
    """Regex replace in a file. Returns number of substitutions made."""
    text = path.read_text(encoding="utf-8")
    new_text, n = re.subn(pattern, replacement, text, count=count)
    if n > 0:
        path.write_text(new_text, encoding="utf-8")
    return n


def change_update_url(root: Path, update_url: str) -> None:
    """Change the hardcoded version check URL in hbb_common."""
    target = root / "libs" / "hbb_common" / "src" / "lib.rs"
    if not target.exists():
        print(f"[WARN] {target} not found, skipping update URL change")
        return

    # Match common const patterns for the update URL.
    patterns = [
        (r'(pub\s+const\s+UPDATE_URL\s*[:=]\s*")[^"]*(")', rf'\g<1>{update_url}\g<2>'),
        (r'(UPDATE_URL\s*=\s*")[^"]*(")', rf'\g<1>{update_url}\g<2>'),
        (r'(https?://api\.rustdesk\.com/version/latest)', update_url),
    ]
    changed = False
    for pat, repl in patterns:
        n = replace_in_file(target, pat, repl)
        if n > 0:
            print(f"[OK] {target}: updated update URL ({n} substitution(s))")
            changed = True
            break
    if not changed:
        print(f"[WARN] {target}: could not find UPDATE_URL pattern to replace")

def relax_common_rs(root: Path) -> None:
    """Relax the github.com-only host restriction in src/common.rs."""
    target = root / "src" / "common.rs"
    if not target.exists():
        print(f"[WARN] {target} not found, skipping common.rs changes")
        return

    text = target.read_text(encoding="utf-8")

    old_line = 'if url.scheme() != "https" || url.host_str() != Some("github.com") {'
    new_line = 'if false {'

    count = text.count(old_line)
    if count > 0:
        new_text = text.replace(old_line, new_line)
        target.write_text(new_text, encoding="utf-8")
        print(f"[OK] {target}: relaxed host check ({count} substitution(s))")
    else:
        print(f"[WARN] {target}: could not find line to relax:\n  {old_line}")


def relax_artifact_rs(root: Path) -> None:
    """Relax the github.com-only download host restriction in src/updater/artifact.rs."""
    target = root / "src" / "updater" / "artifact.rs"
    if not target.exists():
        print(f"[WARN] {target} not found, skipping artifact.rs changes")
        return

    text = target.read_text(encoding="utf-8")

    old_block = '''    if !url.starts_with("https://github.com/")
        || parsed.scheme() != "https"
        || parsed.host_str() != Some("github.com")
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.port().is_some()
        || parsed.query().is_some()
        || parsed.fragment().is_some()
    {
        return None;
    }'''

    new_block = '''    if false {
        return None;
    }'''

    count = text.count(old_block)
    if count > 0:
        new_text = text.replace(old_block, new_block)
        target.write_text(new_text, encoding="utf-8")
        print(f"[OK] {target}: relaxed download host check ({count} substitution(s))")
    else:
        print(f"[WARN] {target}: could not find download host check block")


def add_trusted_key(root: Path, public_key: str) -> None:
    """Add an ed25519 public key to TRUSTED_UPDATE_KEYS in src/update_metadata.rs."""
    target = root / "src" / "update_metadata.rs"
    if not target.exists():
        print(f"[WARN] {target} not found, skipping trusted key change")
        return

    # Decode the public key (base64 or hex) to raw bytes for the Rust byte array.
    import base64

    key_bytes = None
    try:
        key_bytes = base64.b64decode(public_key, validate=True)
    except Exception:
        pass
    if key_bytes is None:
        try:
            key_bytes = bytes.fromhex(public_key)
        except Exception:
            pass
    if key_bytes is None:
        print(f"[WARN] {target}: could not decode public key as base64 or hex")
        return

    byte_list = ",\n        ".join(
        ", ".join(str(b) for b in key_bytes[i:i + 12])
        for i in range(0, len(key_bytes), 12)
    )

    text = target.read_text(encoding="utf-8")

    old_block = '''const TRUSTED_UPDATE_KEYS: &[TrustedUpdateKey] = &[TrustedUpdateKey {
    key_id: "2026-ed25519-main",
    algorithm: SIGNATURE_ALGORITHM,
    public_key: [
        118, 252, 116, 215, 49, 217, 220, 109, 145, 119, 210, 101, 225, 198, 63, 2, 41, 127, 197,
        127, 52, 251, 6, 204, 125, 117, 96, 204, 187, 166, 85, 59,
    ],
}];'''

    new_block = f'''const TRUSTED_UPDATE_KEYS: &[TrustedUpdateKey] = &[TrustedUpdateKey {{
    key_id: "2026-ed25519-main",
    algorithm: SIGNATURE_ALGORITHM,
    public_key: [
        118, 252, 116, 215, 49, 217, 220, 109, 145, 119, 210, 101, 225, 198, 63, 2, 41, 127, 197,
        127, 52, 251, 6, 204, 125, 117, 96, 204, 187, 166, 85, 59,
    ],
}}, TrustedUpdateKey {{
    key_id: "custom-update",
    algorithm: SIGNATURE_ALGORITHM,
    public_key: [
        {byte_list}
    ],
}}];'''

    count = text.count(old_block)
    if count > 0:
        new_text = text.replace(old_block, new_block)
        target.write_text(new_text, encoding="utf-8")
        print(f"[OK] {target}: added public key to TRUSTED_UPDATE_KEYS ({count} substitution(s))")
    else:
        print(f"[WARN] {target}: could not find TRUSTED_UPDATE_KEYS block")
        print(f"    Manually add your public key to TRUSTED_UPDATE_KEYS in {target}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Apply RustDesk client changes for self-hosted auto-updates"
    )
    parser.add_argument(
        "--rustdesk-root",
        required=True,
        help="Path to the RustDesk client source root",
    )
    parser.add_argument(
        "--update-url",
        default=DEFAULT_UPDATE_URL,
        help="Your self-hosted update check URL (default: %(default)s)",
    )
    parser.add_argument(
        "--ed25519-public-key",
        default="",
        help="Base64/hex ed25519 public key to add to TRUSTED_UPDATE_KEYS",
    )
    args = parser.parse_args()

    root = Path(args.rustdesk_root).resolve()
    if not root.is_dir():
        print(f"[ERROR] rustdesk-root is not a directory: {root}")
        sys.exit(1)

    print(f"Applying self-hosted update changes to {root}")
    print(f"  Update URL: {args.update_url}")
    if args.ed25519_public_key:
        print(f"  Public key: {args.ed25519_public_key[:20]}...")
    print()

    change_update_url(root, args.update_url)
    relax_common_rs(root)
    relax_artifact_rs(root)
    if args.ed25519_public_key:
        add_trusted_key(root, args.ed25519_public_key)

    print()
    print("Done. Review the changed files, then build the RustDesk client.")
    print()


if __name__ == "__main__":
    main()
