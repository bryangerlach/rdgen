#!/usr/bin/env python3
"""Apply the rdgen Theme color selections to a RustDesk checkout.

This is the port of DVForge's builder/customize.py::_apply_theme_color for
rdgen, where customisations are applied by the GitHub workflows instead of a
local builder. The workflows run it after the RustDesk source is checked out
and before Flutter builds the client.

Colors come from the environment (blank means "leave the stock RustDesk
color"). The generator writes the camelCase keys from the saved config into
GITHUB_ENV; the THEME_* aliases are there for local runs:

    THEME_ACCENT / themeColor          accent, accent50, accent80, button, primary
    THEME_SURFACE_LIGHT / themeSurfaceLight
                                        light rail, connection card, settings surface
    THEME_SURFACE_DARK / themeSurfaceDark
                                        dark rail, connection card, settings surface
    THEME_ME_COLOR / themeMeColor       connection-manager / address-book "me" color

Each value is RRGGBB or #RRGGBB. The script is a no-op when all four are
blank, and fails loudly when RustDesk moves the stock tokens so a theme can
never silently disappear from a build.

Usage:
    python themeColors.py [--rustdesk-root PATH]
"""

import argparse
import os
import re
import sys


class ThemeError(Exception):
    pass


def _norm_hex6(color):
    """Return RRGGBB or ''."""
    s = (color or "").strip().lstrip("#").upper()
    return s if re.fullmatch(r"[0-9A-F]{6}", s) else ""


def _hex_rgb(h):
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def _rgb_hex(r, g, b):
    def c(x):
        return max(0, min(255, int(round(x))))

    return f"{c(r):02X}{c(g):02X}{c(b):02X}"


def _mix(hex6, toward, amount):
    """Blend hex6 toward another hex6 (amount 0..1)."""
    r1, g1, b1 = _hex_rgb(hex6)
    r2, g2, b2 = _hex_rgb(toward)
    return _rgb_hex(
        r1 + (r2 - r1) * amount,
        g1 + (g2 - g1) * amount,
        b1 + (b2 - b1) * amount,
    )


def _luma(h):
    r, g, b = _hex_rgb(h)
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0


def _too_close(a, b):
    if not a or not b:
        return False
    r1, g1, b1 = _hex_rgb(a)
    r2, g2, b2 = _hex_rgb(b)
    dist = ((r1 - r2) ** 2 + (g1 - g2) ** 2 + (b1 - b2) ** 2) ** 0.5
    return dist < 55 or abs(_luma(a) - _luma(b)) < 0.14


def _contrast_on(fg, bg):
    """Keep fg, or push it toward black/white so it stands off bg."""
    if not fg:
        return fg
    if not bg or not _too_close(fg, bg):
        return fg
    return _mix(fg, "000000" if _luma(bg) > 0.5 else "FFFFFF", 0.38)


def _read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def _write(path, text):
    # newline="" writes the line endings exactly as read (git checkouts are LF;
    # a local Windows checkout may be CRLF and must stay that way).
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def apply_theme(root, accent, light, dark, me, log=print):
    """Patch the theme in `root`; returns the number of files changed."""
    if not any((accent, light, dark, me)):
        log("theme colors: none selected; leaving stock RustDesk theme")
        return 0

    common = os.path.join(root, "flutter", "lib", "common.dart")
    if not os.path.isfile(common):
        raise ThemeError(f"{common} not found; is this a RustDesk checkout?")
    text = _read(common)
    n = 0

    def sub(old, new):
        nonlocal text, n
        if old in text:
            text = text.replace(old, new)
            n += 1
            return True
        return False

    missing = []

    if accent:
        log(f"  theme accent -> #{accent}")
        found = sub("0xFF0071FF", f"0xFF{accent}")
        found = sub("0x770071FF", f"0x77{accent}") or found
        found = sub("0xAA0071FF", f"0xAA{accent}") or found
        found = sub("0xFF2C8CFF", f"0xFF{accent}") or found
        found = sub("0xFF2c8cff", f"0xFF{accent}") or found
        # ColorScheme.primary is still stock Material blue after the accent swap.
        found = sub("primary: Colors.blue", f"primary: Color(0xFF{accent})") or found
        if not found and f"0xFF{accent}" not in text:
            missing.append("accent")

        # When accent == surface, ElevatedButtons vanish. Give each theme a
        # fill that still reads as the accent family but stands off the pane.
        light_btn = _contrast_on(accent, light) if light else accent
        dark_btn = _contrast_on(accent, dark) if dark else accent
        if light_btn != accent:
            if sub(
                "        backgroundColor: MyTheme.accent,\n"
                "        shape: RoundedRectangleBorder(\n"
                "          borderRadius: BorderRadius.circular(8.0),\n",
                f"        backgroundColor: Color(0xFF{light_btn}),\n"
                "        shape: RoundedRectangleBorder(\n"
                "          borderRadius: BorderRadius.circular(8.0),\n",
            ):
                log(f"    light buttons -> #{light_btn} (accent too close to surface)")
        if dark_btn != accent:
            if sub(
                "        backgroundColor: MyTheme.accent,\n"
                "        foregroundColor: Colors.white,\n",
                f"        backgroundColor: Color(0xFF{dark_btn}),\n"
                "        foregroundColor: Colors.white,\n",
            ):
                log(f"    dark buttons -> #{dark_btn} (accent too close to surface)")

    # The home-page ID uses MyTheme.idColor once the widget is pointed at it.
    id_hex = me or accent
    if id_hex:
        sub("0xFF00B6F0", f"0xFF{id_hex}")

    if light:
        log(f"  theme light surface -> #{light}")
        # Rail, settings pane and connection card share this color. The title
        # bar is forced white separately (desktop_tab_page/install_page).
        # Dialogs and text-field fills stay white so inputs remain readable.
        hover = _mix(light, "000000", 0.12)
        highlight = _mix(light, "000000", 0.06)
        border = _mix(light, "000000", 0.18)
        found = sub("0xFFEFEFF2", f"0xFF{light}")
        found = sub("scaffoldBackgroundColor: Colors.white,",
                    f"scaffoldBackgroundColor: Color(0xFF{light}),") or found
        found = sub("fillColor: grayBg,", "fillColor: Colors.white,") or found
        found = sub("hoverColor: Color.fromARGB(255, 224, 224, 224),",
                    f"hoverColor: Color(0xFF{hover}),") or found
        found = sub("highlight: Color(0xFFE5E5E5),",
                    f"highlight: Color(0xFF{highlight}),") or found
        found = sub("border: Color(0xFFCCCCCC),",
                    f"border: Color(0xFF{border}),") or found
        found = sub("static const Color border = Color(0xFFCCCCCC);",
                    f"static const Color border = Color(0xFF{border});") or found
        if not found and f"0xFF{light}" not in text:
            missing.append("light surface")

    if dark:
        log(f"  theme dark surface -> #{dark}")
        hover = _mix(dark, "FFFFFF", 0.10)
        highlight = _mix(dark, "FFFFFF", 0.14)
        input_fill = _mix(dark, "FFFFFF", 0.16)
        d_border = _mix(dark, "FFFFFF", 0.22)
        found = sub("fillColor: Color(0xFF24252B),",
                    f"fillColor: Color(0xFF{input_fill}),")
        found = sub("0xFF18191E", f"0xFF{dark}") or found
        found = sub("0xFF24252B", f"0xFF{dark}") or found
        found = sub("0xFF212121", f"0xFF{dark}") or found
        found = sub("hoverColor: Color.fromARGB(255, 45, 46, 53),",
                    f"hoverColor: Color(0xFF{hover}),") or found
        found = sub("highlight: Color(0xFF3F3F3F),",
                    f"highlight: Color(0xFF{highlight}),") or found
        found = sub("border: Color(0xFF555555),",
                    f"border: Color(0xFF{d_border}),") or found
        if not found and f"0xFF{dark}" not in text:
            missing.append("dark surface")

    if me:
        log(f"  theme ID / me color -> #{me}")
        found = sub("0xFF21790B", f"0xFF{me}")
        # Longest token first: "me: Colors.green" is a prefix of
        # "me: Colors.greenAccent", and replacing the short one first would
        # leave a stray "Accent" behind (invalid Dart).
        found = sub("me: Colors.greenAccent,", f"me: Color(0xFF{me}),") or found
        found = sub("me: Colors.green,", f"me: Color(0xFF{me}),") or found
        if not found and f"0xFF{me}" not in text:
            missing.append("ID / me color")

    if missing:
        raise ThemeError(
            "could not find the stock RustDesk theme token(s) for: "
            + ", ".join(missing)
            + f" in {common}. RustDesk probably renamed them; refusing to build "
              "a client whose selected theme colors would be silently ignored."
        )

    if n:
        _write(common, text)
        log(f"    patched {n} theme token(s) in {common}")
    else:
        log("    theme tokens already carry the requested colors; nothing to do")

    changed_files = 1 if n else 0

    home = os.path.join(root, "flutter", "lib", "desktop", "pages",
                        "desktop_home_page.dart")
    if os.path.isfile(home):
        ht = _read(home)
        before = ht
        if id_hex:
            old = ("style: TextStyle(\n"
                   "                          fontSize: 22,\n"
                   "                        ),")
            new = ("style: TextStyle(\n"
                   "                          fontSize: 22,\n"
                   "                          color: MyTheme.idColor,\n"
                   "                        ),")
            if old in ht:
                ht = ht.replace(old, new, 1)
                log("    home-page ID uses MyTheme.idColor")
        if accent:
            a1 = "Color.fromARGB(255, 226, 66, 188)"
            a2 = "Color.fromARGB(255, 244, 114, 124)"
            # Contrast the install card against whichever surface is closer to
            # the accent (dark orange-on-orange was invisible).
            nearest = dark if dark and _too_close(accent, dark) else (
                light if light and _too_close(accent, light) else "")
            c1 = _contrast_on(accent, nearest) if nearest else accent
            c2 = _mix(c1, "FFFFFF" if _luma(c1) < 0.55 else "000000", 0.30)
            if a1 in ht or a2 in ht:
                if a1 in ht:
                    ht = ht.replace(a1, f"Color(0xFF{c1})")
                if a2 in ht:
                    ht = ht.replace(a2, f"Color(0xFF{c2})")
                log(f"    install-help card gradient #{c1} -> #{c2}")
        if ht != before:
            _write(home, ht)
            changed_files += 1

    # Title bar stays neutral chrome so a loud surface does not paint it:
    # light -> white, dark -> stock #18191E (not the user surface).
    if light or dark:
        old_chrome = "backgroundColor: Theme.of(context).colorScheme.background,"
        new_chrome = (
            "backgroundColor: Theme.of(context).brightness == Brightness.light\n"
            "                ? Colors.white\n"
            "                : const Color(0xFF18191E),"
        )
        for rel in (
            "flutter/lib/desktop/pages/desktop_tab_page.dart",
            "flutter/lib/desktop/pages/install_page.dart",
        ):
            path = os.path.join(root, *rel.split("/"))
            if not os.path.isfile(path):
                log(f"    ! {rel} not found; title bar left as-is")
                continue
            ct = _read(path)
            if old_chrome in ct:
                _write(path, ct.replace(old_chrome, new_chrome, 1))
                changed_files += 1
                log(f"    {rel}: title bar stays chrome (white / #18191E)")

        conn = os.path.join(root, "flutter", "lib", "desktop", "pages",
                            "connection_page.dart")
        if os.path.isfile(conn):
            ct = _read(conn)
            old_b = "border: Border.all(color: Theme.of(context).colorScheme.background)"
            new_b = ("border: Border.all(color: MyTheme.color(context).border "
                     "?? MyTheme.border)")
            if old_b in ct:
                _write(conn, ct.replace(old_b, new_b, 1))
                changed_files += 1
                log("    connection card border follows the light/dark theme")

    # The About page copyright banner is a hardcoded stock blue (0xFF2c8cff),
    # not MyTheme.accent, so it stayed Material blue on a custom accent.
    if accent:
        about = os.path.join(root, "flutter", "lib", "desktop", "pages",
                             "desktop_setting_page.dart")
        if os.path.isfile(about):
            at = _read(about)
            fill = accent
            if dark and _too_close(accent, dark):
                fill = _contrast_on(accent, dark)
            elif light and _too_close(accent, light):
                fill = _contrast_on(accent, light)
            old_a = "decoration: const BoxDecoration(color: Color(0xFF2c8cff)),"
            new_a = f"decoration: const BoxDecoration(color: Color(0xFF{fill})),"
            if old_a in at:
                _write(about, at.replace(old_a, new_a, 1))
                changed_files += 1
                log(f"    About copyright banner -> #{fill}")

    return changed_files


def _color_from_env(theme_name, config_name):
    # The workflow step gets the saved config keys (themeColor, ...) from
    # GITHUB_ENV; THEME_* makes local runs and ad-hoc testing explicit.
    return (os.environ.get(theme_name) or os.environ.get(config_name) or "")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rustdesk-root",
        default=os.environ.get("RUSTDESK_ROOT", "."),
        help="RustDesk source checkout (default: current directory)",
    )
    args = parser.parse_args(argv)

    requested = {
        "themeColor": _color_from_env("THEME_ACCENT", "themeColor"),
        "themeSurfaceLight": _color_from_env("THEME_SURFACE_LIGHT", "themeSurfaceLight"),
        "themeSurfaceDark": _color_from_env("THEME_SURFACE_DARK", "themeSurfaceDark"),
        "themeMeColor": _color_from_env("THEME_ME_COLOR", "themeMeColor"),
    }
    bad = [k for k, v in requested.items() if v.strip() and not _norm_hex6(v)]
    if bad:
        print(
            f"Error: {', '.join(bad)} must be a 6-digit hex color "
            "(RRGGBB or #RRGGBB); blank means stock.",
            file=sys.stderr,
        )
        return 2

    accent = _norm_hex6(requested["themeColor"])
    light = _norm_hex6(requested["themeSurfaceLight"])
    dark = _norm_hex6(requested["themeSurfaceDark"])
    me = _norm_hex6(requested["themeMeColor"])

    try:
        changed = apply_theme(args.rustdesk_root, accent, light, dark, me)
    except ThemeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    if not any((accent, light, dark, me)):
        return 0
    print(f"Theme colors applied ({changed} file(s) changed).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
