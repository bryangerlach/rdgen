#!/usr/bin/env python3
"""Display a red X for offline peers instead of the amber status dot.

This is the Python replacement for xoffline.diff. It edits
``flutter/lib/common/widgets/peer_card.dart`` and replaces the offline branch
of ``getOnline()``:

    child: CircleAvatar(
        radius: 3, backgroundColor: online ? Colors.green : kColorWarn)

with a red Material close icon, while leaving the online green dot untouched.

The patcher is idempotent: the replacement carries a marker comment and is
skipped on a second run. It fails loudly if RustDesk renames or reshapes
``getOnline()``, so a future refactor cannot silently drop the customisation
again (the old ``git apply`` patch failed that way when ``build_more()`` was
reformatted).

Usage:
    python xoffline.py [--rustdesk-root PATH]
"""

import argparse
import pathlib
import re
import sys

MARKER = "RDGEN_OFFLINE_X"

# getOnline(double rightPadding, bool online) in peer_card.dart.
FUNC_RE = re.compile(
    r"\bWidget\s+getOnline\s*\(\s*double\s+rightPadding\s*,\s*bool\s+online\s*\)\s*\{"
)

# The offline indicator: CircleAvatar(radius: 3, backgroundColor: online ?
# Colors.green : kColorWarn). Only the CircleAvatar expression is matched; the
# closing "));" for Padding/Tooltip is left in place.
DOT_RE = re.compile(
    r"(?P<indent>[ \t]*)child:\s*"
    r"CircleAvatar\(\s*\n"
    r"[ \t]*radius:\s*3\s*,\s*"
    r"backgroundColor:\s*online\s*\?\s*Colors\.green\s*:\s*kColorWarn\s*\)"
)


def find_function(text, name):
    """Return (start, end) for a top-level Dart function body."""
    match = FUNC_RE.search(text)
    if match is None:
        return None
    start = match.start()
    # A top-level function ends at the first line containing only "}".
    end_match = re.search(r"(?m)^\}\s*$", text[match.end():])
    if end_match is None:
        return None
    return start, match.end() + end_match.end()


def apply_xoffline(text):
    """Patch the getOnline() function; returns (new_text, changed)."""
    if MARKER in text:
        return text, False

    bounds = find_function(text, "getOnline")
    if bounds is None:
        raise ValueError(
            "could not find a top-level getOnline(double rightPadding, bool online) "
            "function; RustDesk probably renamed or restructured it"
        )
    start, end = bounds
    body = text[start:end]

    match = DOT_RE.search(body)
    if match is None:
        raise ValueError(
            "getOnline() no longer contains the expected offline indicator "
            "(CircleAvatar with radius 3 and backgroundColor online ? "
            "Colors.green : kColorWarn); refusing to guess"
        )

    indent = match.group("indent")
    replacement = (
        f"{indent}// {MARKER}: show a red X instead of the amber offline dot\n"
        f"{indent}child: online\n"
        f"{indent}    ? CircleAvatar(radius: 3, backgroundColor: Colors.green)\n"
        f"{indent}    : Icon(\n"
        f"{indent}        Icons.close,\n"
        f"{indent}        color: Colors.red,\n"
        f"{indent}        size: 12.0,\n"
        f"{indent}      )"
    )

    new_body = body[:match.start()] + replacement + body[match.end():]
    return text[:start] + new_body + text[end:], True


def read_file(path):
    # Read the raw file so a local Windows CRLF checkout stays CRLF.
    with open(path, "r", encoding="utf-8", newline="") as f:
        return f.read()


def write_file(path, text, newline):
    with open(path, "w", encoding="utf-8", newline=newline) as f:
        f.write(text)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rustdesk-root",
        default=".",
        help="Root of the checked-out RustDesk source tree (default: .)",
    )
    args = parser.parse_args(argv)

    path = (
        pathlib.Path(args.rustdesk_root).resolve()
        / "flutter"
        / "lib"
        / "common"
        / "widgets"
        / "peer_card.dart"
    )
    if not path.is_file():
        print(f"Error: {path} not found; is this a RustDesk checkout?", file=sys.stderr)
        return 1

    raw = read_file(path)
    newline = "\r\n" if "\r\n" in raw else "\n"
    text = raw.replace("\r\n", "\n")

    try:
        new_text, changed = apply_xoffline(text)
    except ValueError as e:
        print(f"Error: {e} (in {path})", file=sys.stderr)
        return 1

    if not changed:
        print(f"xoffline: {path} is already patched; nothing to do.")
        return 0

    write_file(path, new_text, newline)
    print(f"xoffline: replaced the offline indicator in {path}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
