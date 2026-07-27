#!/bin/bash
set -e

# Auto-fix CRLF line endings on Windows (Git Bash)
# When files are copied to Windows, they may get CRLF endings which corrupt paths
if uname -s 2>/dev/null | grep -q "MINGW\|MSYS\|CYGWIN"; then
    if grep -qP '\r$' "$0" 2>/dev/null; then
        sed -i 's/\r$//' "$0"
        exec bash "$0" "$@"
    fi
fi

# =============================================================================
# RustDesk Local Build Script for Debian LXC
# Based on generator-linux.yml workflow
# =============================================================================
#
# USAGE:
#   1. Edit the CONFIG section below with your build parameters
#   OR use --config to load from a web UI JSON file (same format as creator.nas86.eu)
#   2. Run: ./buildlocal.sh setup          (first time only - installs all deps)
#   3. Run: ./buildlocal.sh build           (builds deb + rpm + AppImage)
#   4. Run: ./buildlocal.sh rebuild         (skips cargo build, only repackages)
#   5. Run: ./buildlocal.sh setup-android   (installs Android SDK/NDK + JDK)
#   6. Run: ./buildlocal.sh build-android   (builds APK for configured targets)
#       Or build specific target: build-android-aarch64, build-android-armv7, build-android-x86_64
#   7. Run: ./buildlocal.sh setup-macos    (installs macOS build deps via brew)
#   8. Run: ./buildlocal.sh build-macos    (builds DMG for configured targets)
#   9. Run: ./buildlocal.sh --config FILE.json build-android  (load settings from JSON)
#  10. Run: ./buildlocal.sh setup-windows   (installs Windows build deps via choco, run on Windows)
#  11. Run: ./buildlocal.sh build-windows   (builds EXE + MSI, run on Windows with Git Bash)
#
# FIRST BUILD: ~38 min (same as CI)
# SUBSEQUENT:  ~12-15 min (cargo cache + vcpkg cache)
# REBUILD:     ~5-8 min (only changes custom.txt, app name, icon, etc.)
# =============================================================================

# ============================ CONFIG ============================
# Edit these values for each build

# RustDesk version (tag from rustdesk/rustdesk repo)
RUSTDESK_VERSION="1.4.9"

# Your rendezvous server
RENDEZVOUS_SERVER="rs-ny.rustdesk.com"

# Your public key (base64)
RS_PUB_KEY="OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw="

# API server URL
API_SERVER="https://creator.nas86.eu"

# App name (no spaces for filename, spaces OK for display)
APPNAME="Musiclover"
FILENAME="Musiclover"

# Custom JSON (base64 encoded) - from Django's custom.txt
CUSTOM_B64="eyJjb25uLXR5cGUiOiJib3RoIiwiYXBpLXVybCI6Imh0dHBzOi8vY3JlYXRvci5uYXM4Ni5ldSIsInJlbmRlenZvdXMtc2VydmVycyI6InJzLW55LnJ1c3RkZXNrLmNvbSIsInJzLXB1Yi1rZXkiOiJPZVZ1S2s1bmxIaVhwK0FQTm4wWTNwQzFJd3B3bjQ0SkdxclFDc1dxbUJ3PSIsInBhc3N3b3JkIjoiTXVzaWNMb3ZlcjEyMyJ9"

# Icon URL (set to "false" to skip custom icon)
ICON_URL="false"

# Logo URL (set to "false" to skip custom logo)
LOGO_URL="false"

# Company name
COMPNAME="Purslane Ltd"

# Extra options (set to "true" to enable)
DELAY_FIX="false"
CYCLE_MONITOR="false"
X_OFFLINE="false"
HIDE_CM="false"
REMOVE_NEW_VERSION_NOTIF="false"
DISABLE_SETTINGS="false"

# Upload to server after build (set to "true" to upload)
UPLOAD_TO_SERVER="false"
UPLOAD_URL="https://creator.nas86.eu"
UPLOAD_TOKEN=""
UPLOAD_UUID=""

# ============================ ANDROID CONFIG ============================
# Android build targets (space-separated): aarch64 armv7 x86_64
ANDROID_TARGETS="aarch64 armv7 x86_64"
# NDK version
NDK_VERSION="r27c"
# cargo-ndk version
CARGO_NDK_VERSION="3.1.2"
# Android SDK path (will be installed here if not present)
ANDROID_SDK_ROOT="/opt/android-sdk"
# Android app ID (must match Play Store if publishing)
ANDROID_APP_ID="com.carriez.flutter_hbb"

# ============================ WINDOWS CONFIG ============================
# Windows build target (only x86_64 supported by RustDesk Flutter)
WINDOWS_TARGET="x86_64-pc-windows-msvc"
WINDOWS_VCPKG_TRIPLET="x64-windows-static"
# Rust version for Windows (sciter requires 1.75)
WINDOWS_RUST_VERSION="1.75"
# Flutter version for Windows
WINDOWS_FLUTTER_VERSION="3.24.5"
# LLVM version for Windows
WINDOWS_LLVM_VERSION="15.0.6"
# vcpkg commit for Windows
WINDOWS_VCPKG_COMMIT_ID="120deac3062162151622ca4860575a33844ba10b"

# ============================ MACOS CONFIG ============================
# macOS build targets (space-separated): aarch64 x86_64
MACOS_TARGETS="aarch64"
# Minimum macOS version to target
MACOS_MIN_VERSION="12.3"
# vcpkg triplet for macOS
MACOS_VCPKG_TRIPLET="arm64-osx"
# Rust version for macOS builds
MACOS_RUST_VERSION="1.81"

# ============================ PATHS =============================
WORKSPACE="/opt/rustdesk-build"
OUTPUT="/opt/rustdesk-output"
VCPKG_ROOT="${VCPKG_ROOT:-/opt/vcpkg}"
FLUTTER_PATH="/opt/flutter"
RUST_VERSION="1.75"
FLUTTER_VERSION="3.24.5"
FLUTTER_RUST_BRIDGE_VERSION="1.80.1"
CARGO_EXPAND_VERSION="1.0.95"
VCPKG_COMMIT_ID="120deac3062162151622ca4860575a33844ba10b"

# ============================ COLORS ============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Use printf so Windows paths with \a \b \t are not interpreted as escapes
log()  { printf '%b[%s]%b %s\n' "${GREEN}"  "$(date +%H:%M:%S)" "${NC}" "$1"; }
warn() { printf '%b[%s] WARN:%b %s\n' "${YELLOW}" "$(date +%H:%M:%S)" "${NC}" "$1"; }
err()  { printf '%b[%s] ERROR:%b %s\n' "${RED}" "$(date +%H:%M:%S)" "${NC}" "$1"; }

# Convert a Git Bash / Unix path to Windows style (C:\...) for native tools
to_win_path() {
    local p="$1"
    if [ -z "$p" ]; then
        echo ""
        return
    fi
    if command -v cygpath &>/dev/null; then
        cygpath -w "$p"
    else
        p="${p#/c/}"; p="${p#/C/}"
        p="C:\\${p//\//\\}"
        echo "$p"
    fi
}

# Find libclang.dll under a directory tree (handles installer layout quirks)
_find_libclang_bin() {
    local root="$1"
    if [ -f "$root/bin/libclang.dll" ]; then
        echo "$root/bin"
        return 0
    fi
    # Search one/two levels (NSIS extract sometimes nests)
    local f
    f=$(find "$root" -maxdepth 3 -name 'libclang.dll' 2>/dev/null | head -1)
    if [ -n "$f" ]; then
        dirname "$f"
        return 0
    fi
    return 1
}

# Install a specific LLVM win64 build from GitHub (Chocolatey often lacks old versions).
# Installs to C:\LLVM-<ver> so it does not clash with a newer system LLVM.
# Prefer 7-Zip extract of the NSIS .exe (no admin); silent /S often fails under Git Bash.
install_windows_llvm() {
    local ver="${1:-15.0.6}"
    local dest="/c/LLVM-${ver}"
    local dest_win
    dest_win="$(to_win_path "$dest")"

    local found
    found=$(_find_libclang_bin "$dest" 2>/dev/null || true)
    if [ -n "$found" ]; then
        log "=== LLVM $ver already present at $(to_win_path "$found") ==="
        export LIBCLANG_PATH="$(to_win_path "$found")"
        export PATH="$found:$PATH"
        return 0
    fi

    # Also accept default install if it is already the requested major version
    if [ -f "/c/Program Files/LLVM/bin/libclang.dll" ]; then
        local existing
        existing=$("/c/Program Files/LLVM/bin/clang" --version 2>/dev/null | head -1 || true)
        if echo "$existing" | grep -q "clang version ${ver%%.*}\."; then
            log "=== System LLVM matches $ver ($existing) ==="
            export LIBCLANG_PATH="$(to_win_path "/c/Program Files/LLVM/bin")"
            return 0
        fi
    fi

    local url="https://github.com/llvm/llvm-project/releases/download/llvmorg-${ver}/LLVM-${ver}-win64.exe"
    # Prefer a stable path (Git Bash /tmp can be ephemeral / hard for elevated installers)
    local installer="/c/rustdesk-build/LLVM-${ver}-win64.exe"
    mkdir -p /c/rustdesk-build 2>/dev/null || true
    if [ ! -f "$installer" ] || [ ! -s "$installer" ]; then
        # Reuse previous download if still in /tmp
        if [ -s "/tmp/LLVM-${ver}-win64.exe" ]; then
            cp -f "/tmp/LLVM-${ver}-win64.exe" "$installer" 2>/dev/null || installer="/tmp/LLVM-${ver}-win64.exe"
        else
            log "=== Downloading LLVM $ver from GitHub (~280MB) ==="
            log "=== URL: $url ==="
            if ! curl -fL --retry 3 -o "$installer" "$url"; then
                err "Failed to download LLVM $ver installer"
                err "Manual download: $url"
                err "Install to: $dest_win  then re-run build-windows"
                return 1
            fi
        fi
    else
        log "=== Reusing downloaded installer: $installer ==="
    fi

    local installer_win
    installer_win="$(to_win_path "$installer")"
    mkdir -p "$dest" 2>/dev/null || true

    # --- Method 1: 7-Zip extract (most reliable, no admin / no UAC) ---
    local seven_z=""
    for p in \
        "/c/Program Files/7-Zip/7z.exe" \
        "/c/Program Files (x86)/7-Zip/7z.exe" \
        "$(command -v 7z 2>/dev/null)" \
        "$(command -v 7za 2>/dev/null)"; do
        if [ -n "$p" ] && [ -x "$p" ] || [ -f "$p" ]; then
            seven_z="$p"
            break
        fi
    done
    if [ -z "$seven_z" ] && command -v choco &>/dev/null; then
        log "=== Installing 7zip (for LLVM extract) ==="
        choco install -y 7zip --no-progress 2>/dev/null || true
        [ -f "/c/Program Files/7-Zip/7z.exe" ] && seven_z="/c/Program Files/7-Zip/7z.exe"
    fi

    if [ -n "$seven_z" ]; then
        log "=== Extracting LLVM $ver with 7-Zip → $dest_win ==="
        # NSIS installers are archives; extract contents directly
        MSYS2_ARG_CONV_EXCL='*' "$seven_z" x -y "-o$(to_win_path "$dest")" "$installer_win" >/tmp/llvm_7z_extract.log 2>&1 \
            || "$seven_z" x -y "-o${dest}" "$installer" >/tmp/llvm_7z_extract.log 2>&1 \
            || true
        found=$(_find_libclang_bin "$dest" 2>/dev/null || true)
        if [ -n "$found" ]; then
            export LIBCLANG_PATH="$(to_win_path "$found")"
            export PATH="$found:$PATH"
            log "=== LLVM $ver extracted: LIBCLANG_PATH=$LIBCLANG_PATH ==="
            return 0
        fi
        warn "7-Zip extract did not yield libclang.dll (see /tmp/llvm_7z_extract.log)"
    fi

    # --- Method 2: NSIS silent install ---
    log "=== Trying NSIS silent install → $dest_win ==="
    # /D= must be last and unquoted (NSIS). Needs admin on some systems.
    MSYS2_ARG_CONV_EXCL='*' cmd.exe /c "\"${installer_win}\" /S /D=${dest_win}" >/tmp/llvm_nsis.log 2>&1 || true
    sleep 3
    # PowerShell Start-Process -Wait (more reliable process wait)
    powershell.exe -NoProfile -Command \
        "Start-Process -FilePath '${installer_win}' -ArgumentList '/S','/D=${dest_win}' -Wait" \
        >/tmp/llvm_ps.log 2>&1 || true

    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        found=$(_find_libclang_bin "$dest" 2>/dev/null || true)
        [ -n "$found" ] && break
        # Also check if installer put it under Program Files
        found=$(_find_libclang_bin "/c/Program Files/LLVM" 2>/dev/null || true)
        if [ -n "$found" ]; then
            local ver_check
            ver_check=$("$found/clang" --version 2>/dev/null | head -1 || true)
            if echo "$ver_check" | grep -q "clang version ${ver%%.*}\."; then
                break
            fi
            found=""
        fi
        sleep 2
    done

    if [ -n "$found" ] && [ -f "$found/libclang.dll" ]; then
        export LIBCLANG_PATH="$(to_win_path "$found")"
        export PATH="$found:$PATH"
        log "=== LLVM $ver installed: LIBCLANG_PATH=$LIBCLANG_PATH ==="
        return 0
    fi

    err "LLVM $ver install failed (silent install often needs Admin / fails under Git Bash)."
    err ""
    err "Do this ONCE manually (recommended):"
    err "  1. Run as Administrator in PowerShell or Explorer:"
    err "       $installer_win"
    err "  2. Install to:  $dest_win"
    err "  3. Confirm file exists:  $dest_win\\bin\\libclang.dll"
    err "  4. Re-run:  ./buildconfig.sh --config ... build-windows"
    err ""
    err "Or extract with 7-Zip GUI: right-click the .exe → 7-Zip → Extract to $dest_win"
    err "Installer saved at: $installer"
    return 1
}

# Detect python command (Windows has python3 as Store stub, use python instead)
if command -v python3 &>/dev/null && python3 -c "print(1)" &>/dev/null; then
    PYTHON="python3"
elif command -v python &>/dev/null && python -c "print(1)" &>/dev/null; then
    PYTHON="python"
else
    PYTHON="python3"
fi

# wget wrapper: Git Bash doesn't have wget, use curl as fallback
if ! command -v wget &>/dev/null; then
    wget() {
        local args=("$@")
        # Parse wget args and convert to curl equivalent
        local out_file=""
        local quiet=""
        local url=""
        local i=0
        while [ $i -lt ${#args[@]} ]; do
            case "${args[$i]}" in
                -O)
                    out_file="${args[$((i+1))]}"
                    i=$((i+2))
                    ;;
                -q)
                    quiet="-s"
                    i=$((i+1))
                    ;;
                *)
                    url="${args[$i]}"
                    i=$((i+1))
                    ;;
            esac
        done
        if [ -n "$out_file" ]; then
            curl -L $quiet -o "$out_file" "$url"
        else
            curl -L $quiet -O "$url"
        fi
    }
fi

# ============================ DISTRO DETECTION =============================
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_FAMILY=""
        case "$ID" in
            debian|ubuntu|linuxmint|pop|raspbian)
                DISTRO_FAMILY="debian"
                ;;
            fedora|rhel|centos|rocky|alma|amzn)
                DISTRO_FAMILY="rhel"
                ;;
            opensuse*|suse|sles|sled)
                DISTRO_FAMILY="suse"
                ;;
            arch|manjaro|endeavouros|garuda)
                DISTRO_FAMILY="arch"
                ;;
            *)
                # Fallback: check for package managers
                if command -v apt-get &>/dev/null; then
                    DISTRO_FAMILY="debian"
                elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
                    DISTRO_FAMILY="rhel"
                elif command -v zypper &>/dev/null; then
                    DISTRO_FAMILY="suse"
                elif command -v pacman &>/dev/null; then
                    DISTRO_FAMILY="arch"
                else
                    DISTRO_FAMILY="unknown"
                fi
                ;;
        esac
    else
        # No /etc/os-release, fallback to package manager detection
        if command -v apt-get &>/dev/null; then
            DISTRO_FAMILY="debian"
        elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
            DISTRO_FAMILY="rhel"
        elif command -v zypper &>/dev/null; then
            DISTRO_FAMILY="suse"
        elif command -v pacman &>/dev/null; then
            DISTRO_FAMILY="arch"
        else
            DISTRO_FAMILY="unknown"
        fi
        DISTRO_ID="$DISTRO_FAMILY"
    fi
    log "=== Detected: $DISTRO_ID ($DISTRO_FAMILY family) ==="
}

# ============================ SETUP =============================
setup() {
    detect_distro
    log "=== Installing system dependencies ==="

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get update -y
            sudo apt-get install -y \
                build-essential clang cmake curl gcc git g++ \
                imagemagick potrace nasm ninja-build pkg-config \
                libayatana-appindicator3-dev libasound2-dev libclang-dev \
                libunwind-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
                libgtk-3-dev libpam0g-dev libpulse-dev libva-dev libvdpau-dev \
                libxcb-randr0-dev libxcb-shape0-dev libxcb-xfixes0-dev \
                libxdo-dev libxfixes-dev llvm-dev python3 python3-pip rpm unzip \
                wget xz-utils libssl-dev libarchive-tools libfuse2 zip autoconf automake libtool gnupg squashfs-tools zsync
            # apt-key was removed in Debian 12+ but appimage-builder still requires it
            if ! command -v apt-key &>/dev/null; then
                sudo ln -sf "$(which gpg)" /usr/local/bin/apt-key
            fi
            ;;
        rhel)
            PKGMGR=""
            if command -v dnf &>/dev/null; then PKGMGR="dnf"; else PKGMGR="yum"; fi
            sudo $PKGMGR install -y \
                clang cmake curl gcc git gcc-c++ \
                ImageMagick potrace nasm ninja-build pkgconf-pkg-config \
                libappindicator-gtk3-devel alsa-lib-devel clang-devel \
                libunwind-devel gstreamer1-devel gstreamer1-plugins-base-devel \
                gtk3-devel pam-devel pulseaudio-libs-devel libva-devel libvdpau-devel \
                libxcb-randr0-devel libxcb-shape0-devel libxcb-xfixes0-devel \
                libxdo-devel libXfixes-devel llvm-devel python3 python3-pip rpm-build unzip \
                wget xz openssl-devel libarchive libfuse2 zip autoconf automake libtool gnupg2 squashfs-tools \
                perl-FindBin perl-IPC-Cmd perl-File-Compare perl-File-Copy
            ;;
        suse)
            sudo zypper refresh
            sudo zypper install -y \
                clang cmake curl gcc git gcc-c++ \
                ImageMagick potrace nasm ninja pkg-config \
                libappindicator3-1-devel alsa-devel clang-devel \
                libunwind-devel gstreamer-devel gstreamer-plugins-base-devel \
                gtk3-devel pam-devel libpulse-devel libva-devel libvdpau-devel \
                libxcb-randr0-devel libxcb-shape0-devel libxcb-xfixes0-devel \
                libxdo-devel libXfixes-devel llvm-devel python3 python3-pip rpm-build unzip \
                wget xz openssl-devel libarchive-tools libfuse2 zip autoconf automake libtool gpg2 squashfs-tools
            ;;
        arch)
            sudo pacman -Syu --noconfirm \
                base-devel clang cmake curl gcc git \
                imagemagick potrace nasm ninja pkg-config \
                libappindicator-gtk3 alsa-lib clang \
                libunwind gstreamer gstreamer-plugins-base \
                gtk3 pam libpulse libva libvdpau \
                libxcb libxdo libxfixes llvm python python-pip rpm-tools unzip \
                wget xz openssl libarchive libfuse2 zip autoconf automake libtool gnupg squashfs-tools
            ;;
        *)
            err "Unsupported distribution. Cannot determine package manager."
            err "Supported: Debian/Ubuntu, Fedora/RHEL/CentOS, openSUSE, Arch"
            exit 1
            ;;
    esac

    log "=== Installing Rust $RUST_VERSION ==="
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "$RUST_VERSION"
    source "$HOME/.cargo/env"

    log "=== Installing stable Rust (for codegen tools only) ==="
    rustup toolchain install stable
    rustup default stable
    cargo install cargo-expand --version "$CARGO_EXPAND_VERSION" --locked
    cargo install flutter_rust_bridge_codegen --version "$FLUTTER_RUST_BRIDGE_VERSION" --features "uuid" --locked
    rustup default "$RUST_VERSION"

    log "=== Installing Flutter $FLUTTER_VERSION ==="
    mkdir -p /opt
    if [ -d "$FLUTTER_PATH/.git" ]; then
        cd "$FLUTTER_PATH"
        git checkout "$FLUTTER_VERSION" 2>/dev/null || true
    else
        cd /opt
        wget "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
        tar xf "flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
        rm "flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
    fi
    echo "export PATH=\"$FLUTTER_PATH/bin:\$PATH\"" >> "$HOME/.bashrc"
    export PATH="$FLUTTER_PATH/bin:$PATH"
    git config --global --add safe.directory "$FLUTTER_PATH"
    cd "$FLUTTER_PATH"
    git checkout "$FLUTTER_VERSION"
    flutter doctor -v
    flutter precache --linux

    log "=== Installing vcpkg ==="
    mkdir -p /opt
    cd /opt
    if [ -d "vcpkg/.git" ]; then
        cd vcpkg
        git fetch --all
        git checkout "$VCPKG_COMMIT_ID"
    else
        rm -rf vcpkg
        git clone https://github.com/microsoft/vcpkg.git
        cd vcpkg
        git checkout "$VCPKG_COMMIT_ID"
    fi
    ./bootstrap-vcpkg.sh
    echo "export VCPKG_ROOT=$VCPKG_ROOT" >> "$HOME/.bashrc"

    log "=== Installing AppImage builder ==="
    pip3 install 'setuptools_scm<8' 'setuptools<70' --force-reinstall 2>/dev/null || sudo pip3 install 'setuptools_scm<8' 'setuptools<70' --force-reinstall
    pip3 install 'wheel<0.46' --ignore-installed 2>/dev/null || sudo pip3 install 'wheel<0.46' --ignore-installed
    pip3 install git+https://github.com/rustdesk-org/appimage-builder.git 2>/dev/null || sudo pip3 install git+https://github.com/rustdesk-org/appimage-builder.git

    log "=== Setup complete! ==="
    echo ""
    echo "Next steps:"
    echo "  1. Edit the CONFIG section at the top of this script"
    echo "  2. Run: ./buildlocal.sh build"
}

# ============================ SETUP ANDROID =============================
setup_android() {
    detect_distro
    log "=== Installing Android build dependencies ==="

    # Install JDK and Android platform tools per distro
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get update -y
            # JDK 17 is REQUIRED — JDK 21's jlink is incompatible with Android SDK 34
            if ! sudo apt-get install -y openjdk-17-jdk-headless unzip wget 2>/dev/null; then
                warn "openjdk-17 not in repos, downloading Temurin JDK 17"
                cd /tmp
                wget -q -O jdk17.tar.gz "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.13%2B11/OpenJDK17U-jdk_x64_linux_hotspot_17.0.13_11.tar.gz"
                sudo mkdir -p /usr/lib/jvm/temurin-17
                sudo tar -xzf jdk17.tar.gz -C /usr/lib/jvm/temurin-17 --strip-components=1
                rm jdk17.tar.gz
                sudo update-alternatives --install /usr/bin/java java /usr/lib/jvm/temurin-17/bin/java 1700
                sudo update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/temurin-17/bin/javac 1700
                sudo update-alternatives --set java /usr/lib/jvm/temurin-17/bin/java
                sudo update-alternatives --set javac /usr/lib/jvm/temurin-17/bin/javac
                log "=== Temurin JDK 17 installed ==="
            fi
            ;;
        rhel)
            PKGMGR="dnf"; command -v dnf &>/dev/null || PKGMGR="yum"
            if ! sudo $PKGMGR install -y java-17-openjdk-devel unzip wget 2>/dev/null; then
                warn "java-17 not found, trying java-21"
                sudo $PKGMGR install -y java-21-openjdk-devel unzip wget
            fi
            ;;
        suse)
            if ! sudo zypper install -y java-17-openjdk-devel unzip wget 2>/dev/null; then
                warn "java-17 not found, trying java-21"
                sudo zypper install -y java-21-openjdk-devel unzip wget
            fi
            ;;
        arch)
            if ! sudo pacman -Syu --noconfirm jdk17-openjdk unzip wget 2>/dev/null; then
                warn "jdk17 not found, trying jdk21-openjdk"
                sudo pacman -Syu --noconfirm jdk21-openjdk unzip wget
            fi
            ;;
        *)
            err "Unsupported distribution for Android build"
            exit 1
            ;;
    esac

    export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which javac))))
    log "=== JAVA_HOME: $JAVA_HOME ==="

    # Install Android SDK command-line tools
    if [ ! -d "$ANDROID_SDK_ROOT/cmdline-tools" ]; then
        log "=== Installing Android SDK command-line tools ==="
        sudo mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
        cd /tmp
        wget -O cmdline-tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
        sudo unzip -q cmdline-tools.zip -d "$ANDROID_SDK_ROOT/cmdline-tools"
        sudo mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
        rm cmdline-tools.zip
    else
        log "=== Android SDK command-line tools already installed ==="
    fi

    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
    local SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

    # Accept licenses and install platform-tools, build-tools, platforms
    log "=== Installing Android SDK packages ==="
    yes | sudo "$SDKMANAGER" --licenses 2>/dev/null || true
    sudo "$SDKMANAGER" "platform-tools" "platforms;android-34" "build-tools;34.0.0"

    # Install NDK
    log "=== Installing Android NDK $NDK_VERSION ==="
    if [ ! -d "$ANDROID_SDK_ROOT/ndk/$NDK_VERSION" ]; then
        # Check if NDK was already extracted to the default dir name
        if [ -d "$ANDROID_SDK_ROOT/android-ndk-${NDK_VERSION}" ]; then
            log "=== NDK already extracted, moving to proper location ==="
            sudo mkdir -p "$ANDROID_SDK_ROOT/ndk"
            sudo mv "$ANDROID_SDK_ROOT/android-ndk-${NDK_VERSION}" "$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"
        else
            cd /tmp
            wget -O ndk.zip "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
            sudo unzip -q ndk.zip -d "$ANDROID_SDK_ROOT/"
            sudo mkdir -p "$ANDROID_SDK_ROOT/ndk"
            sudo mv "$ANDROID_SDK_ROOT/android-ndk-${NDK_VERSION}" "$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"
            rm ndk.zip
        fi
    else
        log "=== NDK $NDK_VERSION already installed ==="
    fi

    export ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"
    export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

    # Verify NDK installation
    if [ ! -f "$ANDROID_NDK_HOME/source.properties" ]; then
        err "NDK not found at $ANDROID_NDK_HOME — source.properties missing"
        err "Try re-running: ./buildlocal.sh setup-android"
        exit 1
    fi
    log "=== NDK verified at $ANDROID_NDK_HOME ==="

    # Add Android env vars to bashrc for persistence
    grep -q "ANDROID_SDK_ROOT" "$HOME/.bashrc" 2>/dev/null || {
        echo "export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT" >> "$HOME/.bashrc"
        echo "export ANDROID_HOME=$ANDROID_SDK_ROOT" >> "$HOME/.bashrc"
        echo "export ANDROID_NDK_HOME=$ANDROID_SDK_ROOT/ndk/$NDK_VERSION" >> "$HOME/.bashrc"
        echo "export ANDROID_NDK_ROOT=$ANDROID_SDK_ROOT/ndk/$NDK_VERSION" >> "$HOME/.bashrc"
        echo "export JAVA_HOME=$JAVA_HOME" >> "$HOME/.bashrc"
    }

    # Install Rust Android targets
    log "=== Installing Rust Android targets ==="
    source "$HOME/.cargo/env"
    for target in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android; do
        rustup target add "$target" 2>/dev/null || log "Target $target already installed"
    done

    # Install cargo-ndk
    log "=== Installing cargo-ndk ==="
    cargo install cargo-ndk --version "$CARGO_NDK_VERSION" --locked 2>/dev/null || log "cargo-ndk already installed"

    log "=== Android setup complete! ==="
    echo ""
    echo "Next steps:"
    echo "  1. Edit the ANDROID CONFIG section at the top of this script"
    echo "  2. Run: ./buildlocal.sh build-android"
}

# ============================ SETUP MACOS =============================
setup_macos() {
    log "=== Setting up macOS build environment ==="

    # Check we're on macOS
    if [ "$(uname)" != "Darwin" ]; then
        err "setup-macos can only run on macOS"
        exit 1
    fi

    # Override Linux-specific paths for macOS
    WORKSPACE="$HOME/rustdesk-build"
    OUTPUT="$HOME/rustdesk-output"
    mkdir -p "$WORKSPACE" "$OUTPUT"

    # Check Xcode command line tools
    if ! xcode-select -p &>/dev/null; then
        err "Xcode Command Line Tools not installed. Run: xcode-select --install"
        exit 1
    fi
    log "=== Xcode Command Line Tools: OK ==="

    # Install Homebrew dependencies
    log "=== Installing brew dependencies ==="
    brew install imagemagick potrace cmake gcc wget ninja create-dmg llvm pkg-config 2>/dev/null || \
        log "brew packages may already be installed"

    # Install NASM 2.16.03 (NOT brew nasm 3.x — incompatible with aom assembly)
    if ! nasm --version 2>/dev/null | grep -q "2.16"; then
        log "=== Installing NASM 2.16.03 ==="
        cd /tmp
        wget -q https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/macosx/nasm-2.16.03-macosx.zip
        unzip -o nasm-2.16.03-macosx.zip
        sudo cp nasm-2.16.03/nasm /usr/local/bin/nasm
        rm -rf nasm-2.16.03*
        cd "$WORKSPACE"
    fi
    log "=== NASM: $(nasm --version) ==="

    # Install Flutter
    if [ ! -d "$FLUTTER_PATH" ]; then
        log "=== Installing Flutter $FLUTTER_VERSION ==="
        sudo mkdir -p "$(dirname "$FLUTTER_PATH")"
        sudo git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_PATH"
        sudo chown -R "$(whoami)" "$FLUTTER_PATH"
    else
        log "=== Flutter already installed at $FLUTTER_PATH ==="
    fi
    export PATH="$FLUTTER_PATH/bin:$PATH"
    flutter --version

    # Install Rust
    if ! command -v rustup &>/dev/null; then
        log "=== Installing Rust ==="
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    source "$HOME/.cargo/env"
    log "=== Installing Rust toolchain $MACOS_RUST_VERSION ==="
    rustup toolchain install "$MACOS_RUST_VERSION" 2>/dev/null || log "Toolchain may already be installed"
    rustup default "$MACOS_RUST_VERSION"
    rustup target add aarch64-apple-darwin 2>/dev/null || log "aarch64 target already installed"
    if echo "$MACOS_TARGETS" | grep -q "x86_64"; then
        rustup target add x86_64-apple-darwin 2>/dev/null || log "x86_64 target already installed"
    fi

    # Install flutter_rust_bridge_codegen
    log "=== Installing flutter_rust_bridge_codegen ==="
    cargo install flutter_rust_bridge_codegen --version "$FLUTTER_RUST_BRIDGE_VERSION" --locked 2>/dev/null || \
        log "flutter_rust_bridge_codegen may already be installed"

    # Install vcpkg
    if [ ! -d "$VCPKG_ROOT" ]; then
        log "=== Installing vcpkg ==="
        sudo mkdir -p "$(dirname "$VCPKG_ROOT")"
        sudo git clone https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT"
        sudo chown -R "$(whoami)" "$VCPKG_ROOT"
        cd "$VCPKG_ROOT"
        git checkout "$VCPKG_COMMIT_ID"
        ./bootstrap-vcpkg.sh
        cd "$WORKSPACE" 2>/dev/null || cd "$HOME"
    else
        log "=== vcpkg already installed at $VCPKG_ROOT ==="
    fi

    # Persist env vars
    grep -q "FLUTTER_PATH" "$HOME/.zshrc" 2>/dev/null || {
        echo "export FLUTTER_PATH=$FLUTTER_PATH" >> "$HOME/.zshrc"
        echo "export PATH=\$FLUTTER_PATH/bin:\$PATH" >> "$HOME/.zshrc"
        echo "export VCPKG_ROOT=$VCPKG_ROOT" >> "$HOME/.zshrc"
        echo "export WORKSPACE=$WORKSPACE" >> "$HOME/.zshrc"
        echo "export OUTPUT=$OUTPUT" >> "$HOME/.zshrc"
    }

    log "=== macOS setup complete! ==="
    echo ""
    echo "Next steps:"
    echo "  1. Edit the MACOS CONFIG section at the top of this script"
    echo "  2. Run: ./buildlocal.sh build-macos"
}

# ============================ WINDOWS ENV CHECK =============================
check_windows_env() {
    local mode="$1"  # "setup" or "build"

    # Force-set Windows paths (override any stale values from .bashrc)
    # Use /c/ style paths which work correctly in Git Bash/MSYS2
    export WORKSPACE="/c/rustdesk-build"
    export OUTPUT="/c/rustdesk-output"
    export VCPKG_ROOT="/c/vcpkg"

    # Check we're on Windows (Git Bash / MSYS2)
    local os_name
    os_name="$(uname -s)"
    if ! echo "$os_name" | grep -q "MINGW\|MSYS\|CYGWIN"; then
        err "$mode-windows can only run on Windows with Git Bash."
        err "Git Bash is NOT installed by default on Windows."
        err "Install Git for Windows from: https://git-scm.com/download/win"
        err "It includes Git Bash automatically."
        if [ "$mode" == "build" ]; then
            err ""
            err "If you don't have a Windows machine, use GitHub Actions instead:"
            err "  Go to your repo → Actions → Custom Windows Client Generator → Run workflow"
        fi
        exit 1
    fi

    log "=== Detected Git Bash on Windows ($os_name) ==="

    # For build mode, check that required tools are installed
    if [ "$mode" == "build" ]; then
        local missing=""
        command -v git &>/dev/null || missing="$missing git"
        command -v python3 &>/dev/null || command -v python &>/dev/null || missing="$missing python3"
        command -v cargo &>/dev/null || missing="$missing cargo(rust)"
        # Flutter may not be in PATH yet on Windows, check FLUTTER_PATH too
        if ! command -v flutter &>/dev/null; then
            if [ -n "${FLUTTER_PATH:-}" ] && [ -x "$FLUTTER_PATH/bin/flutter" ]; then
                export PATH="$FLUTTER_PATH/bin:$PATH"
            elif [ -x "/c/rustdesk-build/flutter/bin/flutter" ]; then
                export FLUTTER_PATH="/c/rustdesk-build/flutter"
                export PATH="$FLUTTER_PATH/bin:$PATH"
            else
                missing="$missing flutter"
            fi
        fi
        command -v magick &>/dev/null || missing="$missing imagemagick"

        # Check LIBCLANG_PATH (required by bindgen for vpx/aom codec bindings)
        local _llvm_found=""
        for p in "/c/Program Files/LLVM/bin" "/c/Program Files (x86)/LLVM/bin" "$HOME/.llvm/bin"; do
            if [ -f "$p/libclang.dll" ]; then
                _llvm_found="$p"
                break
            fi
        done
        if [ -z "$_llvm_found" ] && [ -z "${LIBCLANG_PATH:-}" ]; then
            err "LIBCLANG_PATH not set and libclang.dll not found."
            err "Install LLVM: choco install llvm"
            err "Or run './buildlocal.sh setup-windows' first."
            exit 1
        fi

        if [ -n "$missing" ]; then
            err "Missing required tools:$missing"
            err "Run './buildlocal.sh setup-windows' first to install all dependencies."
            exit 1
        fi

        # Check vcpkg
        if [ ! -d "$VCPKG_ROOT" ]; then
            err "vcpkg not found at $VCPKG_ROOT"
            err "Run './buildlocal.sh setup-windows' first."
            exit 1
        fi

        # Check vcpkg dependencies are installed (ffmpeg headers etc.)
        local vcpkg_triplet="${WINDOWS_VCPKG_TRIPLET:-x64-windows-static}"
        if [ ! -d "$VCPKG_ROOT/installed/$vcpkg_triplet" ] || [ ! -d "$VCPKG_ROOT/installed/$vcpkg_triplet/include/libavutil" ]; then
            err "vcpkg dependencies not installed (missing ffmpeg headers)"
            err "Run './buildlocal.sh setup-windows' first to install vcpkg dependencies."
            err "Or manually: cd $WORKSPACE/rustdesk && $VCPKG_ROOT/vcpkg install --triplet $vcpkg_triplet --x-install-root=$VCPKG_ROOT/installed"
            exit 1
        fi

        # Check RustDesk source
        if [ ! -d "$WORKSPACE/rustdesk" ]; then
            err "RustDesk source not found at $WORKSPACE/rustdesk"
            err "Run './buildlocal.sh setup-windows' first to clone the source."
            exit 1
        fi

        log "=== All build prerequisites found ==="
    fi

    # For setup mode, check that Chocolatey is available
    if [ "$mode" == "setup" ]; then
        if ! command -v choco &>/dev/null; then
            err "Chocolatey is not installed. Chocolatey is required to install build dependencies."
            err "Install Chocolatey first by running this in PowerShell as Administrator:"
            err ""
            err '  Set-ExecutionPolicy Bypass -Scope Process -Force'
            err '  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072'
            err '  iex ((New-Object System.Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))'
            err ""
            err "Then re-run: ./buildlocal.sh setup-windows"
            exit 1
        fi
        log "=== Chocolatey detected ==="
    fi
}

# ============================ SETUP WINDOWS =============================
setup_windows() {
    log "=== Setting up Windows build environment ==="

    check_windows_env "setup"

    # Override workspace/output for Windows
    # Force-set paths (don't use :- default, in case stale values are in .bashrc)
    # Use /c/ style paths which work correctly in Git Bash/MSYS2
    unset WORKSPACE OUTPUT VCPKG_ROOT
    export WORKSPACE="/c/rustdesk-build"
    export OUTPUT="/c/rustdesk-output"
    export VCPKG_ROOT="/c/vcpkg"
    mkdir -p "$WORKSPACE" "$OUTPUT"
    log "=== Paths: WORKSPACE=$WORKSPACE, OUTPUT=$OUTPUT, VCPKG_ROOT=$VCPKG_ROOT ==="

    # Install Chocolatey packages
    log "=== Installing build dependencies via Chocolatey ==="
    choco install -y git python3 rust-ms visualstudio2022buildtools --no-progress 2>/dev/null || \
        log "Some packages may already be installed"

    # Install Visual Studio Build Tools with C++ workload
    log "=== Installing MSVC C++ build tools ==="
    choco install -y visualstudio2022-workload-vctools --no-progress 2>/dev/null || \
        log "VC tools may already be installed"

    # Install LLVM (prefer pinned version from GitHub — Chocolatey often drops old versions)
    # RustDesk scrap bindgen works best with LLVM ~15; LLVM 19+ can yield opaque vpx/aom types.
    log "=== Installing LLVM $WINDOWS_LLVM_VERSION ==="
    install_windows_llvm "$WINDOWS_LLVM_VERSION"

    # Install ImageMagick
    log "=== Installing ImageMagick ==="
    choco install -y imagemagick.app --no-progress 2>/dev/null || log "ImageMagick may already be installed"

    # Install NASM
    log "=== Installing NASM ==="
    choco install -y nasm --no-progress 2>/dev/null || log "NASM may already be installed"

    # Add cargo/bin to PATH (rust-ms choco package installs rustup here)
    export PATH="$HOME/.cargo/bin:$PATH"
    source "$HOME/.cargo/env" 2>/dev/null || true

    # Install Flutter
    log "=== Installing Flutter $WINDOWS_FLUTTER_VERSION ==="
    if ! command -v flutter &>/dev/null; then
        cd "$WORKSPACE"
        git clone https://github.com/flutter/flutter.git -b "$WINDOWS_FLUTTER_VERSION" --depth 1
        export FLUTTER_PATH="$WORKSPACE/flutter"
        echo "export FLUTTER_PATH=$FLUTTER_PATH" >> "$HOME/.bashrc"
        echo "export PATH=\$FLUTTER_PATH/bin:\$PATH" >> "$HOME/.bashrc"
        export PATH="$FLUTTER_PATH/bin:$PATH"
    else
        # Flutter already in PATH, find its location
        if [ -z "$FLUTTER_PATH" ]; then
            FLUTTER_PATH=$(dirname $(dirname $(which flutter)))
            echo "export FLUTTER_PATH=$FLUTTER_PATH" >> "$HOME/.bashrc"
        fi
    fi
    flutter doctor -v

    # Install Rust target
    log "=== Installing Rust target $WINDOWS_TARGET ==="
    # Ensure rustup is in PATH (choco rust-ms puts it in ~/.cargo/bin)
    export PATH="$HOME/.cargo/bin:$PATH"
    if ! command -v rustup &>/dev/null; then
        # Try to find rustup in common locations
        if [ -f "$HOME/.cargo/bin/rustup.exe" ]; then
            export PATH="$HOME/.cargo/bin:$PATH"
        elif [ -f "/c/Users/$USERNAME/.cargo/bin/rustup.exe" ]; then
            export PATH="/c/Users/$USERNAME/.cargo/bin:$PATH"
        else
            err "rustup not found. Trying to install via rust-ms..."
            choco install -y rust-ms --force --no-progress 2>/dev/null || { err "Failed to install Rust"; exit 1; }
            export PATH="$HOME/.cargo/bin:$PATH"
        fi
    fi
    rustup toolchain install "$WINDOWS_RUST_VERSION" 2>/dev/null || log "Toolchain may already be installed"
    rustup default "$WINDOWS_RUST_VERSION" 2>/dev/null || log "Default toolchain may already be set"
    rustup target add "$WINDOWS_TARGET" 2>/dev/null || log "Target may already be installed"

    # Codegen tools (bridge files are gitignored — required for flutter feature)
    log "=== Installing rustfmt + flutter_rust_bridge_codegen $FLUTTER_RUST_BRIDGE_VERSION ==="
    rustup component add rustfmt 2>/dev/null || true
    rustup toolchain install stable 2>/dev/null || true
    rustup component add rustfmt --toolchain stable 2>/dev/null || true
    cargo +stable install cargo-expand --version "$CARGO_EXPAND_VERSION" --locked 2>/dev/null || \
        cargo install cargo-expand --locked 2>/dev/null || log "cargo-expand may already be installed"
    cargo +stable install flutter_rust_bridge_codegen --version "$FLUTTER_RUST_BRIDGE_VERSION" --features "uuid" --locked 2>/dev/null || \
        cargo install flutter_rust_bridge_codegen --version "$FLUTTER_RUST_BRIDGE_VERSION" --features "uuid" --locked 2>/dev/null || \
        log "flutter_rust_bridge_codegen may already be installed"
    rustup default "$WINDOWS_RUST_VERSION" 2>/dev/null || true
    rustup component add rustfmt --toolchain "$WINDOWS_RUST_VERSION" 2>/dev/null || true

    # Setup vcpkg
    log "=== Setting up vcpkg at $VCPKG_ROOT ==="
    if [ ! -d "$VCPKG_ROOT" ] || { [ ! -f "$VCPKG_ROOT/vcpkg" ] && [ ! -f "$VCPKG_ROOT/vcpkg.exe" ]; }; then
        # Remove any stale partial clone
        rm -rf "$VCPKG_ROOT"
        # Clone vcpkg directly to VCPKG_ROOT
        git clone https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT"
        cd "$VCPKG_ROOT"
        git checkout "$WINDOWS_VCPKG_COMMIT_ID"
        ./bootstrap-vcpkg.sh 2>/dev/null || ./bootstrap-vcpkg.bat
    else
        log "=== vcpkg already installed at $VCPKG_ROOT ==="
    fi
    export VCPKG_DEFAULT_HOST_TRIPLET="$WINDOWS_VCPKG_TRIPLET"

    # Clone RustDesk source (needed for vcpkg manifest install)
    log "=== Cloning RustDesk v$RUSTDESK_VERSION ==="
    if [ ! -d "$WORKSPACE/rustdesk" ]; then
        cd "$WORKSPACE"
        git clone --recursive https://github.com/rustdesk/rustdesk.git
        cd rustdesk
        git checkout "$RUSTDESK_VERSION"
        git submodule update --init --recursive
    fi

    # Install vcpkg dependencies from RustDesk's vcpkg.json manifest
    log "=== Installing vcpkg dependencies (this takes 10-30 minutes) ==="
    cd "$WORKSPACE/rustdesk"
    if [ ! -d "$VCPKG_ROOT/installed/$WINDOWS_VCPKG_TRIPLET" ] || [ -z "$(ls -A "$VCPKG_ROOT/installed/$WINDOWS_VCPKG_TRIPLET/lib" 2>/dev/null)" ]; then
        "$VCPKG_ROOT/vcpkg" install \
            --triplet "$WINDOWS_VCPKG_TRIPLET" \
            --x-install-root="$VCPKG_ROOT/installed" || {
            err "vcpkg install failed. Check vcpkg logs:"
            find "$VCPKG_ROOT/" -name "*.log" -exec tail -20 {} \; 2>/dev/null
            exit 1
        }
        log "=== vcpkg dependencies installed ==="
    else
        log "=== vcpkg dependencies already installed ==="
    fi

    log "=== Windows setup complete! ==="
    echo ""
    echo "Next steps:"
    echo "  1. Edit the CONFIG and WINDOWS CONFIG sections at the top of this script"
    echo "  2. Run: ./buildlocal.sh build-windows"
}

# ============================ BUILD =============================
build() {
    detect_distro
    local START_TIME=$(date +%s)
    log "=== Starting build: $APPNAME v$RUSTDESK_VERSION ==="

    source "$HOME/.cargo/env"
    export PATH="$FLUTTER_PATH/bin:$PATH"
    export VCPKG_ROOT="$VCPKG_ROOT"
    export DEB_ARCH=amd64
    export CARGO_INCREMENTAL=0

    mkdir -p "$WORKSPACE" "$OUTPUT"
    cd "$WORKSPACE"

    # --- Clone/update RustDesk ---
    log "=== Cloning RustDesk v$RUSTDESK_VERSION ==="
    if [ -d "rustdesk" ]; then
        cd rustdesk
        git fetch --all --tags
        git reset --hard HEAD
        git clean -fdx
        git checkout "refs/tags/$RUSTDESK_VERSION"
        git submodule update --init --recursive
    else
        git clone --recursive https://github.com/rustdesk/rustdesk.git
        cd rustdesk
        git checkout "refs/tags/$RUSTDESK_VERSION"
        git submodule update --init --recursive
    fi

    git config --global --add safe.directory "*"

    # --- Generate bridge files ---
    log "=== Generating flutter_rust_bridge files ==="
    cd "$WORKSPACE/rustdesk/flutter"
    flutter pub get
    cd "$WORKSPACE/rustdesk"
    ~/.cargo/bin/flutter_rust_bridge_codegen \
        --rust-input ./src/flutter_ffi.rs \
        --dart-output ./flutter/lib/generated_bridge.dart \
        --c-output ./flutter/macos/Runner/bridge_generated.h
    cp ./flutter/macos/Runner/bridge_generated.h ./flutter/ios/Runner/bridge_generated.h 2>/dev/null || true

    # --- Apply patches ---
    log "=== Applying patches ==="
    wget -O allowCustom.diff https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/allowCustom.diff
    git apply allowCustom.diff || warn "allowCustom.diff already applied or failed"
    wget -O removeSetupServerTip.diff https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/removeSetupServerTip.diff
    git apply removeSetupServerTip.diff || warn "removeSetupServerTip.diff already applied or failed"

    # --- Configure server and keys ---
    log "=== Configuring server and keys ==="
    git checkout -- ./src/common.rs ./src/lang/en.rs 2>/dev/null || true
    (cd ./libs/hbb_common && git checkout -- src/config.rs 2>/dev/null) || true
    sed -i -e "s|rs-ny.rustdesk.com|$RENDEZVOUS_SERVER|" ./libs/hbb_common/src/config.rs
    sed -i -e "s|OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=|$RS_PUB_KEY|" ./libs/hbb_common/src/config.rs
    sed -i -e 's|For faster connection, please set up your own server||' ./src/lang/en.rs
    sed -i -e '/const KEY:/,/};/d' ./src/common.rs
    sed -i -e '/let Ok(data) = sign::verify(&data, &pk)/,/};/d' ./src/common.rs
    sed -i -e "s|https://admin.rustdesk.com|$API_SERVER|" ./src/common.rs

    # --- Create custom.txt ---
    log "=== Creating custom.txt ==="
    if [ -n "$CUSTOM_B64" ]; then
        echo "$CUSTOM_B64" | base64 -d > ./custom.txt
    else
        warn "CUSTOM_B64 is empty, creating empty custom.txt"
        echo "" > ./custom.txt
    fi
    sed -i '/intl:/a \ \ archive: ^3.6.1' ./flutter/pubspec.yaml

    # --- Change app name ---
    if [ "$APPNAME" != "rustdesk" ]; then
        log "=== Changing app name to $APPNAME ==="
        sed -i -e "s|description = \"RustDesk Remote Desktop\"|description = \"$APPNAME\"|" ./Cargo.toml
        sed -i -e "s|ProductName = \"RustDesk\"|ProductName = \"$APPNAME\"|" ./Cargo.toml
        sed -i -e "s|FileDescription = \"RustDesk Remote Desktop\"|FileDescription = \"$APPNAME\"|" ./Cargo.toml
        sed -i -e "s|description = \"RustDesk Remote Desktop\"|description = \"$APPNAME\"|" ./libs/portable/Cargo.toml
        sed -i -e "s|ProductName = \"RustDesk\"|ProductName = \"$APPNAME\"|" ./libs/portable/Cargo.toml
        sed -i -e "s|FileDescription = \"RustDesk Remote Desktop\"|FileDescription = \"$APPNAME\"|" ./libs/portable/Cargo.toml
        find ./src/lang -name "*.rs" -exec sed -i -e "s|RustDesk|$APPNAME|" {} \;
        sed -i -e '/-p tmpdeb\/usr\/lib\/rustdesk/d' ./build.py
    fi

    # --- Change company name ---
    if [ "$COMPNAME" != "Purslane Ltd" ]; then
        log "=== Changing company name to $COMPNAME ==="
        sed -i '' -e 's|Purslane Ltd|${{ fromJson(inputs.extras).compname }}|' ./flutter/lib/desktop/pages/desktop_setting_page.dart
        sed -i '' -e 's|Purslane Ltd.|${{ fromJson(inputs.extras).compname }}|' ./flutter/macos/Runner/Configs/AppInfo.xcconfig
        sed -i '' -e 's|"Copyright \u00A9 2025 Purslane Ltd. All rights reserved."|"Copyright \u00A9 2025 ${{ fromJson(inputs.extras).compname }}. All rights reserved."|' ./flutter/windows/runner/Runner.rc
        sed -i '' -e 's|Purslane Ltd|${{ fromJson(inputs.extras).compname }}|' ./flutter/windows/runner/Runner.rc
        sed -i '' -e 's|Purslane Ltd|${{ fromJson(inputs.extras).compname }}|' ./Cargo.toml
        sed -i '' -e 's|Purslane Ltd|${{ fromJson(inputs.extras).compname }}|' ./libs/portable/Cargo.toml
    fi

    # --- Apply icon ---
    if [ "$ICON_URL" != "false" ]; then
        log "=== Applying custom icon ==="
        mv ./res/icon.ico ./res/icon.ico.bak 2>/dev/null || true
        mv ./res/icon.png ./res/icon.png.bak 2>/dev/null || true
        mv ./res/tray-icon.ico ./res/tray-icon.ico.bak 2>/dev/null || true
        if [[ "$ICON_URL" == http* ]]; then
            wget -O ./res/icon.png "$ICON_URL"
        else
            cp "$ICON_URL" ./res/icon.png
        fi
        mv ./res/32x32.png ./res/32x32.png.bak 2>/dev/null || true
        mv ./res/64x64.png ./res/64x64.png.bak 2>/dev/null || true
        mv ./res/128x128.png ./res/128x128.png.bak 2>/dev/null || true
        mv ./res/128x128@2x.png ./res/128x128@2x.png.bak 2>/dev/null || true
        convert ./res/icon.png -define icon:auto-resize=256,64,48,32,16 ./res/icon.ico
        convert ./res/icon.png -define icon:auto-resize=256,64,48,32,16 ./res/tray-icon.ico
        cp ./res/icon.ico ./res/tray-icon.ico
        convert ./res/icon.png -resize 32x32 ./res/32x32.png
        convert ./res/icon.png -resize 64x64 ./res/64x64.png
        convert ./res/icon.png -resize 128x128 ./res/128x128.png
        convert ./res/128x128.png -resize 200% ./res/128x128@2x.png

        # Flutter icon
        mv ./flutter/assets/icon.svg ./flutter/assets/icon.svg.bak 2>/dev/null || true
        convert ./res/icon.png ./flutter/assets/icon.svg
        convert ./res/128x128.png -resize 200% ./flutter/assets/128x128@2x.png 2>/dev/null || true
        cp ./flutter/assets/icon.svg ./res/scalable.svg
        cd ./flutter
        flutter pub get
        dart run flutter_launcher_icons
        cd ..
    fi

    # --- Apply logo ---
    if [ "$LOGO_URL" != "false" ]; then
        log "=== Applying custom logo ==="
        if [[ "$LOGO_URL" == http* ]]; then
            wget -O ./flutter/assets/logo.png "$LOGO_URL"
        else
            cp "$LOGO_URL" ./flutter/assets/logo.png
        fi
    fi

    # --- Optional patches ---
    if [ "$DELAY_FIX" == "true" ]; then
        log "=== Applying delay fix ==="
        sed -i -e 's|!key.is_empty()|false|' ./src/client.rs
    fi

    if [ "$CYCLE_MONITOR" == "true" ]; then
        log "=== Applying cycle monitor patch ==="
        wget https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/cycle_monitor.diff
        git apply cycle_monitor.diff || warn "cycle_monitor.diff failed"
    fi

    if [ "$X_OFFLINE" == "true" ]; then
        log "=== Applying X offline patch ==="
        wget https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/xoffline.diff
        git apply xoffline.diff || warn "xoffline.diff failed"
    fi

    if [ "$HIDE_CM" == "true" ]; then
        log "=== Applying hide-cm patch ==="
        git checkout -- flutter/lib/models/server_model.dart flutter/lib/main.dart flutter/lib/desktop/pages/desktop_setting_page.dart 2>/dev/null || true
        if [ -f "flutter/lib/models/server_model.dart" ]; then
            sed -i 's/bool hideCm = false;/bool _hideCm = false;/' flutter/lib/models/server_model.dart
            sed -i '/bool get clipboardOk => _clipboardOk;/a \
              bool get hideCm => _hideCm;\
              ' flutter/lib/models/server_model.dart
            sed -i 's/\/\*//g' flutter/lib/models/server_model.dart
            sed -i 's/\*\///g' flutter/lib/models/server_model.dart
        fi
        if [ -f "flutter/lib/main.dart" ]; then
            sed -i 's/gFFI.serverModel.hideCm = hide;/\/\/ gFFI.serverModel.hideCm = hide;/' flutter/lib/main.dart
        fi
        if [ -f "flutter/lib/desktop/pages/desktop_setting_page.dart" ]; then
            sed -i "s/\/\/ if (usePassword)/if (usePassword)/" flutter/lib/desktop/pages/desktop_setting_page.dart
            sed -i "s/\/\/   hide_cm(!locked).marginOnly(left: _kContentHSubMargin - 6),/  hide_cm(!locked).marginOnly(left: _kContentHSubMargin - 6),/" flutter/lib/desktop/pages/desktop_setting_page.dart
        fi
    fi

    if [ "$REMOVE_NEW_VERSION_NOTIF" == "true" ]; then
        log "=== Removing new version notification ==="
        sed -i -e 's|updateUrl.isNotEmpty|false|' ./flutter/lib/desktop/pages/desktop_home_page.dart
        sed -i '/let (request, url) =/,/Ok(())/{/Ok(())/!d}' ./src/common.rs
    fi

    if [ "$DISABLE_SETTINGS" == "true" ]; then
        log "=== Disabling settings UI ==="
        wget https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/disableSettings.diff -O disableSettings.diff
        git apply disableSettings.diff || warn "disableSettings.diff failed"
    fi

    # --- Disable rust bridge build (cdylib only) ---
    log "=== Configuring Cargo.toml for cdylib only ==="
    sed -i 's/\["cdylib", "staticlib", "rlib"\]/\["cdylib"\]/g' Cargo.toml

    # --- Build vcpkg dependencies (first time only, cached after) ---
    if [ ! -f "$VCPKG_ROOT/installed/x64-linux/include/opus/opus.h" ]; then
        log "=== Building vcpkg dependencies (first time ~10 min) ==="
        $VCPKG_ROOT/vcpkg install --triplet x64-linux --x-install-root="$VCPKG_ROOT/installed"
    else
        log "=== vcpkg dependencies already cached ==="
    fi

    # --- Build Rust ---
    local RUST_START=$(date +%s)
    log "=== Building Rust (this is the slow part) ==="
    cargo build --lib --features hwcodec,flutter,unix-file-copy-paste --release
    local RUST_END=$(date +%s)
    log "=== Rust build took $(( (RUST_END - RUST_START) / 60 )) min $(( (RUST_END - RUST_START) % 60 )) sec ==="

    # --- Prepare Flutter build ---
    log "=== Building Flutter + packaging ==="
    mkdir -p output
    chmod 777 output -R
    mkdir -p flutter/tmpdeb/usr/share/rustdesk
    cp ./custom.txt ./flutter/tmpdeb/usr/share/rustdesk/custom.txt

    # Apply Flutter 3.24.5 patch
    if [ "$FLUTTER_VERSION" == "3.24.5" ]; then
        cd "$FLUTTER_PATH"
        wget -O flutter_dropdown.patch https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff 2>/dev/null || true
        git apply flutter_dropdown.patch 2>/dev/null || warn "Flutter dropdown patch failed (may already be applied)"
        cd "$WORKSPACE/rustdesk"
    fi

    # --- Build Flutter + package ---
    python3 ./build.py --flutter --skip-cargo

    # --- Rename deb (Debian family only) ---
    if [ "$DISTRO_FAMILY" == "debian" ] || command -v dpkg-deb &>/dev/null; then
        for name in rustdesk*??.deb; do
            [ -f "$name" ] && mv "$name" "$OUTPUT/${FILENAME}-x86_64.deb"
        done
        log "=== DEB package: $OUTPUT/${FILENAME}-x86_64.deb ==="
    else
        warn "Skipping DEB package (not a Debian-family distro: $DISTRO_FAMILY)"
    fi

    # --- Build RPM (works on all distros with rpmbuild) ---
    if command -v rpmbuild &>/dev/null; then
        log "=== Building Fedora RPM ==="
        HBB=$(pwd) rpmbuild ./res/rpm-flutter.spec -bb
        pushd ~/rpmbuild/RPMS/x86_64
        for name in rustdesk*??.rpm; do
            [ -f "$name" ] && mv "$name" "$OUTPUT/${FILENAME}-x86_64.rpm"
        done
        popd
        log "=== RPM package: $OUTPUT/${FILENAME}-x86_64.rpm ==="

        log "=== Building SUSE RPM ==="
        HBB=$(pwd) rpmbuild ./res/rpm-flutter-suse.spec -bb
        pushd ~/rpmbuild/RPMS/x86_64
        for name in rustdesk*??.rpm; do
            [ -f "$name" ] && mv "$name" "$OUTPUT/${FILENAME}-suse-x86_64.rpm"
        done
        popd
        log "=== SUSE RPM: $OUTPUT/${FILENAME}-suse-x86_64.rpm ==="
    else
        warn "Skipping RPM packages (rpmbuild not installed)"
    fi

    # --- Build AppImage (Debian family only — appimage-builder uses apt venv) ---
    if [ "$DISTRO_FAMILY" == "debian" ] && [ -f "$OUTPUT/${FILENAME}-x86_64.deb" ]; then
        log "=== Building AppImage ==="
        cp "$OUTPUT/${FILENAME}-x86_64.deb" appimage/rustdesk.deb
        pushd appimage
        sudo appimage-builder --skip-tests --recipe ./AppImageBuilder-x86_64.yml
        sudo mv ./rustdesk-*.AppImage "./${FILENAME}-x86_64.AppImage" 2>/dev/null || true
        cp "./${FILENAME}-x86_64.AppImage" "$OUTPUT/" 2>/dev/null || warn "AppImage build failed (non-fatal)"
        popd
        log "=== AppImage: $OUTPUT/${FILENAME}-x86_64.AppImage ==="
    else
        warn "Skipping AppImage (requires Debian/apt environment for appimage-builder)"
    fi

    # --- Upload to server ---
    if [ "$UPLOAD_TO_SERVER" == "true" ] && [ -n "$UPLOAD_TOKEN" ]; then
        log "=== Uploading to server ==="
        for ext in deb rpm; do
            curl -i -X POST \
                -H "Content-Type: multipart/form-data" \
                -H "Authorization: Bearer $UPLOAD_TOKEN" \
                -F "file=@$OUTPUT/${FILENAME}-x86_64.${ext}" \
                -F "uuid=$UPLOAD_UUID" \
                "$UPLOAD_URL/save_custom_client" || warn "Upload of ${ext} failed"
        done
        curl -i -X POST \
            -H "Content-Type: multipart/form-data" \
            -H "Authorization: Bearer $UPLOAD_TOKEN" \
            -F "file=@$OUTPUT/${FILENAME}-suse-x86_64.rpm" \
            -F "uuid=$UPLOAD_UUID" \
            "$UPLOAD_URL/save_custom_client" || warn "Upload of suse rpm failed"
        if [ -f "$OUTPUT/${FILENAME}-x86_64.AppImage" ]; then
            curl -i -X POST \
                -H "Content-Type: multipart/form-data" \
                -H "Authorization: Bearer $UPLOAD_TOKEN" \
                -F "file=@$OUTPUT/${FILENAME}-x86_64.AppImage" \
                -F "uuid=$UPLOAD_UUID" \
                "$UPLOAD_URL/save_custom_client" || warn "Upload of AppImage failed"
        fi
    fi

    local END_TIME=$(date +%s)
    local TOTAL=$(( END_TIME - START_TIME ))
    log "=== Build complete in $(( TOTAL / 60 )) min $(( TOTAL % 60 )) sec ==="
    log "=== Output files in $OUTPUT/ ==="
    ls -lh "$OUTPUT/"
}

# ============================ REBUILD =============================
# Skip cargo build, only repackage with new custom.txt/name/icon
rebuild() {
    log "=== Quick rebuild (skip cargo) ==="
    source "$HOME/.cargo/env"
    export PATH="$FLUTTER_PATH/bin:$PATH"
    export VCPKG_ROOT="$VCPKG_ROOT"
    export DEB_ARCH=amd64
    export CARGO_INCREMENTAL=0

    cd "$WORKSPACE/rustdesk"

    # Update custom.txt
    if [ -n "$CUSTOM_B64" ]; then
        echo "$CUSTOM_B64" | base64 -d > ./custom.txt
    fi
    cp ./custom.txt ./flutter/tmpdeb/usr/share/rustdesk/custom.txt

    # Update app name if changed
    if [ "$APPNAME" != "rustdesk" ]; then
        sed -i -e "s|description = \"RustDesk Remote Desktop\"|description = \"$APPNAME\"|" ./Cargo.toml
        sed -i -e "s|ProductName = \"RustDesk\"|ProductName = \"$APPNAME\"|" ./Cargo.toml
        find ./src/lang -name "*.rs" -exec sed -i -e "s|RustDesk|$APPNAME|" {} \;
    fi

    # Rebuild Flutter + package only
    mkdir -p output
    python3 ./build.py --flutter --skip-cargo

    for name in rustdesk*??.deb; do
        mv "$name" "$OUTPUT/${FILENAME}-x86_64.deb"
    done

    HBB=$(pwd) rpmbuild ./res/rpm-flutter.spec -bb
    pushd ~/rpmbuild/RPMS/x86_64
    for name in rustdesk*??.rpm; do
        mv "$name" "$OUTPUT/${FILENAME}-x86_64.rpm"
    done
    popd

    HBB=$(pwd) rpmbuild ./res/rpm-flutter-suse.spec -bb
    pushd ~/rpmbuild/RPMS/x86_64
    for name in rustdesk*??.rpm; do
        mv "$name" "$OUTPUT/${FILENAME}-suse-x86_64.rpm"
    done
    popd

    log "=== Rebuild complete ==="
    ls -lh "$OUTPUT/"
}

# ============================ BUILD ANDROID =============================
build_android() {
    local START_TIME=$(date +%s)
    log "=== Starting Android build: $APPNAME v$RUSTDESK_VERSION ==="

    source "$HOME/.cargo/env"
    export PATH="$FLUTTER_PATH/bin:$PATH"

    # Android env vars
    export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"

    # Detect NDK path (handle both ndk/r27c and android-ndk-r27c layouts)
    local NDK_DIR="$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"
    if [ ! -f "$NDK_DIR/source.properties" ]; then
        local NDK_ALT="$ANDROID_SDK_ROOT/android-ndk-$NDK_VERSION"
        if [ -f "$NDK_ALT/source.properties" ]; then
            log "=== NDK found at alternate path, fixing location ==="
            sudo mkdir -p "$ANDROID_SDK_ROOT/ndk"
            sudo mv "$NDK_ALT" "$NDK_DIR" 2>/dev/null || true
        fi
    fi
    export ANDROID_NDK_HOME="$NDK_DIR"
    export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
    export VCPKG_ROOT="${VCPKG_ROOT:-/opt/vcpkg}"
    # Prefer JDK 17 (matches CI), fall back to whatever javac resolves to
    if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    elif [ -d "/usr/lib/jvm/java-17-openjdk" ]; then
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
    elif [ -d "/usr/lib/jvm/temurin-17" ]; then
        export JAVA_HOME="/usr/lib/jvm/temurin-17"
    else
        export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which javac) 2>/dev/null) 2>/dev/null) 2>/dev/null || echo "/usr/lib/jvm/java-17-openjdk-amd64")
    fi
    export PATH="$JAVA_HOME/bin:$PATH"
    export RUSTFLAGS="-C debug-assertions=on"
    log "=== Using JAVA_HOME=$JAVA_HOME ==="

    # Fail early if JDK != 17 — JDK 21's jlink is incompatible with Android SDK 34
    local DETECTED_JAVA_VER=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | sed 's/.*"\([0-9]*\)\..*/\1/')
    if [ "$DETECTED_JAVA_VER" != "17" ]; then
        err "JDK 17 is required for Android builds (detected JDK $DETECTED_JAVA_VER). JDK 21's jlink fails with Android SDK 34."
        err "Install JDK 17: apt-get install openjdk-17-jdk-headless"
        exit 1
    fi
    log "=== JDK 17 confirmed ==="

    mkdir -p "$WORKSPACE" "$OUTPUT"
    cd "$WORKSPACE"

    # --- Clone/update RustDesk ---
    log "=== Cloning RustDesk v$RUSTDESK_VERSION ==="
    if [ -d "rustdesk" ]; then
        cd rustdesk
        git fetch --all --tags
        git reset --hard HEAD
        git clean -fdx
        git checkout "refs/tags/$RUSTDESK_VERSION"
        git submodule update --init --recursive
    else
        git clone --recursive https://github.com/rustdesk/rustdesk.git
        cd rustdesk
        git checkout "refs/tags/$RUSTDESK_VERSION"
        git submodule update --init --recursive
    fi

    git config --global --add safe.directory "*"

    # --- Generate bridge files ---
    log "=== Generating flutter_rust_bridge files ==="
    cd "$WORKSPACE/rustdesk/flutter"
    flutter pub get
    cd "$WORKSPACE/rustdesk"
    ~/.cargo/bin/flutter_rust_bridge_codegen \
        --rust-input ./src/flutter_ffi.rs \
        --dart-output ./flutter/lib/generated_bridge.dart \
        --c-output ./flutter/macos/Runner/bridge_generated.h
    cp ./flutter/macos/Runner/bridge_generated.h ./flutter/ios/Runner/bridge_generated.h 2>/dev/null || true

    # --- Apply patches ---
    log "=== Applying patches ==="
    wget -O allowCustom.diff https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/allowCustom.diff
    git apply allowCustom.diff || warn "allowCustom.diff already applied or failed"
    wget -O removeSetupServerTip.diff https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/removeSetupServerTip.diff
    git apply removeSetupServerTip.diff || warn "removeSetupServerTip.diff already applied or failed"

    # --- Configure server and keys ---
    log "=== Configuring server and keys ==="
    git checkout -- ./src/common.rs ./src/lang/en.rs 2>/dev/null || true
    (cd ./libs/hbb_common && git checkout -- src/config.rs 2>/dev/null) || true
    sed -i -e "s|rs-ny.rustdesk.com|$RENDEZVOUS_SERVER|" ./libs/hbb_common/src/config.rs
    sed -i -e "s|OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=|$RS_PUB_KEY|" ./libs/hbb_common/src/config.rs
    sed -i -e 's|For faster connection, please set up your own server||' ./src/lang/en.rs
    sed -i -e '/const KEY:/,/};/d' ./src/common.rs
    sed -i -e '/let Ok(data) = sign::verify(&data, &pk)/,/};/d' ./src/common.rs
    sed -i -e "s|https://admin.rustdesk.com|$API_SERVER|" ./src/common.rs

    # --- Create custom.txt in flutter assets ---
    log "=== Creating custom.txt ==="
    mkdir -p ./flutter/assets
    if [ -n "$CUSTOM_B64" ]; then
        echo "$CUSTOM_B64" | base64 -d > ./flutter/assets/custom.txt
        echo "$CUSTOM_B64" | base64 -d > ./custom.txt
    else
        warn "CUSTOM_B64 is empty, creating empty custom.txt"
        echo "" > ./flutter/assets/custom.txt
        echo "" > ./custom.txt
    fi

    # --- Change app name (Android-specific sed commands) ---
    if [ "$APPNAME" != "rustdesk" ]; then
        log "=== Changing app name to $APPNAME ==="
        sed -i -e "s|description = \"RustDesk Remote Desktop\"|description = \"$APPNAME\"|" ./Cargo.toml
        sed -i -e "s|ProductName = \"RustDesk\"|ProductName = \"$APPNAME\"|" ./Cargo.toml
        sed -i -e "s|FileDescription = \"RustDesk Remote Desktop\"|FileDescription = \"$APPNAME\"|" ./Cargo.toml
        sed -i -e "s|OriginalFilename = \"rustdesk.exe\"|OriginalFilename = \"$APPNAME.exe\"|" ./Cargo.toml
        sed -i 's|name = "RustDesk"|name = "'"$APPNAME"'"|' ./Cargo.toml
        find ./src/lang -name "*.rs" -exec sed -i -e "s|RustDesk|$APPNAME|" {} \;
        sed -i -e "s|RustDesk|$APPNAME|" ./flutter/android/app/src/main/res/values/strings.xml
        sed -i -e "s|title: 'RustDesk'|title: '$APPNAME'|" ./flutter/lib/main.dart
        sed -i -e "s|return 'RustDesk';|return '$APPNAME';|" ./flutter/lib/web/bridge.dart
        sed -i 's|android:label="RustDesk"|android:label="'"$APPNAME"'"|' ./flutter/android/app/src/main/AndroidManifest.xml
        sed -i 's|android:label="RustDesk Input"|android:label="'"$APPNAME"' Input"|' ./flutter/android/app/src/main/AndroidManifest.xml
        sed -i 's|RustDesk is Open|'"$APPNAME"' is Open|' ./flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/BootReceiver.kt
        sed -i 's|Show Rustdesk|Show '"$APPNAME"'|' ./flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/FloatingWindowService.kt
        sed -i 's|"RustDesk"|"'"$APPNAME"'"|' ./flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt
        sed -i 's|RustDesk|'"$APPNAME"'|' ./flutter/lib/main.dart
        sed -i 's|"RustDesk"|"'"$APPNAME"'"|' ./flutter/lib/mobile/widgets/dialog.dart
        sed -i 's|"RustDesk"|"'"$APPNAME"'"|' ./libs/hbb_common/src/config.rs
    fi

    # --- Change Android app ID if custom ---
    if [ "$ANDROID_APP_ID" != "com.carriez.flutter_hbb" ]; then
        log "=== Changing Android app ID to $ANDROID_APP_ID ==="
        sed -i -e "s|com.carriez.flutter_hbb|$ANDROID_APP_ID|" ./flutter/android/app/build.gradle
    fi

    # --- Apply icon ---
    if [ "$ICON_URL" != "false" ]; then
        log "=== Applying custom icon ==="
        mv ./res/icon.ico ./res/icon.ico.bak 2>/dev/null || true
        mv ./res/icon.png ./res/icon.png.bak 2>/dev/null || true
        if [[ "$ICON_URL" == http* ]]; then
            wget -O ./res/icon.png "$ICON_URL"
        else
            cp "$ICON_URL" ./res/icon.png
        fi
        convert ./res/icon.png -define icon:auto-resize=256,64,48,32,16 ./res/icon.ico
        convert ./res/icon.png -resize 32x32 ./res/32x32.png
        convert ./res/icon.png -resize 64x64 ./res/64x64.png
        convert ./res/icon.png -resize 128x128 ./res/128x128.png
        convert ./res/128x128.png -resize 200% ./res/128x128@2x.png
        mv ./flutter/assets/icon.svg ./flutter/assets/icon.svg.bak 2>/dev/null || true
        convert ./res/icon.png ./flutter/assets/icon.svg
        convert ./res/128x128.png -resize 200% ./flutter/assets/128x128@2x.png 2>/dev/null || true
        sed -i '/android: true/a \ \ adaptive_icon_background: "#ffffff"' ./flutter/pubspec.yaml
        sed -i '/adaptive_icon_background/a \ \ adaptive_icon_foreground: "../res/icon.png"' ./flutter/pubspec.yaml
        sed -i '/adaptive_icon_foreground:/a \ \ adaptive_icon_foreground_inset: 32' ./flutter/pubspec.yaml
        cd ./flutter
        flutter pub get
        dart run flutter_launcher_icons
        cd ..
        sed -i '/ic_launcher_background/d' ./flutter/android/app/src/main/res/values/colors.xml
    fi

    # --- Apply logo ---
    if [ "$LOGO_URL" != "false" ]; then
        log "=== Applying custom logo ==="
        if [[ "$LOGO_URL" == http* ]]; then
            wget -O ./flutter/assets/logo.png "$LOGO_URL"
        else
            cp "$LOGO_URL" ./flutter/assets/logo.png
        fi
    fi

    # --- Optional patches (same as Linux build) ---
    if [ "$DELAY_FIX" == "true" ]; then
        log "=== Applying delay fix ==="
        sed -i -e 's|!key.is_empty()|false|' ./src/client.rs
    fi

    if [ "$HIDE_CM" == "true" ]; then
        log "=== Applying hide-cm patch ==="
        git checkout -- flutter/lib/models/server_model.dart flutter/lib/main.dart flutter/lib/desktop/pages/desktop_setting_page.dart 2>/dev/null || true
        if [ -f "flutter/lib/models/server_model.dart" ]; then
            sed -i 's/bool hideCm = false;/bool _hideCm = false;/' flutter/lib/models/server_model.dart
            sed -i '/bool get clipboardOk => _clipboardOk;/a \
              bool get hideCm => _hideCm;\
              ' flutter/lib/models/server_model.dart
            sed -i 's/\/\*//g' flutter/lib/models/server_model.dart
            sed -i 's/\*\///g' flutter/lib/models/server_model.dart
        fi
        if [ -f "flutter/lib/main.dart" ]; then
            sed -i 's/gFFI.serverModel.hideCm = hide;/\/\/ gFFI.serverModel.hideCm = hide;/' flutter/lib/main.dart
        fi
        if [ -f "flutter/lib/desktop/pages/desktop_setting_page.dart" ]; then
            sed -i "s/\/\/ if (usePassword)/if (usePassword)/" flutter/lib/desktop/pages/desktop_setting_page.dart
            sed -i "s/\/\/   hide_cm(!locked).marginOnly(left: _kContentHSubMargin - 6),/  hide_cm(!locked).marginOnly(left: _kContentHSubMargin - 6),/" flutter/lib/desktop/pages/desktop_setting_page.dart
        fi
    fi

    if [ "$REMOVE_NEW_VERSION_NOTIF" == "true" ]; then
        log "=== Removing new version notification ==="
        sed -i -e 's|updateUrl.isNotEmpty|false|' ./flutter/lib/mobile/pages/home_page.dart
    fi

    if [ "$DISABLE_SETTINGS" == "true" ]; then
        log "=== Disabling settings UI ==="
        wget https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/disableSettings.diff -O disableSettings.diff
        git apply disableSettings.diff || warn "disableSettings.diff failed"
    fi

    # --- Hide server page popup (Android-specific) ---
    log "=== Hiding server page popups ==="
    sed -i -e 's|int _countdown = bind.isCustomClient() ? 0 : 12;|int _countdown = 0;|' ./flutter/lib/mobile/pages/server_page.dart 2>/dev/null || warn "server_page.dart countdown patch skipped"

    # --- Auto-start service on app launch (Android-specific) ---
    log "=== Enabling auto-start service ==="
    FILE="flutter/lib/mobile/pages/connection_page.dart"
    if [ -f "$FILE" ]; then
        sed -i '/Get\.put(_idEditingController);/a\    bool start = false;\    if(!start){\      start = (!start);\      gFFI.serverModel.startService();\    }' "$FILE"
    fi

    # --- Apply Flutter 3.24.5 dropdown patch ---
    if [ "$FLUTTER_VERSION" == "3.24.5" ]; then
        cd "$FLUTTER_PATH"
        wget -O flutter_dropdown.patch https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff 2>/dev/null || true
        git apply flutter_dropdown.patch 2>/dev/null || warn "Flutter dropdown patch failed (may already be applied)"
        cd "$WORKSPACE/rustdesk"
    fi

    # --- Set bindgen sysroot for Android NDK ---
    # bindgen ignores CC/CXX from cargo-ndk; it needs its own clang args.
    # Do NOT set C_INCLUDE_PATH/CPLUS_INCLUDE_PATH — those leak into host cc
    # (used by ring's build script) and cause Bionic headers to be used instead of glibc.
    local NDK_SYSROOT="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
    export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$NDK_SYSROOT"

    # --- Build Rust for each Android target ---
    for target in $ANDROID_TARGETS; do
        # Map short names to full Rust target triples
        case "$target" in
            aarch64) target="aarch64-linux-android" ;;
            armv7)   target="armv7-linux-androideabi" ;;
            x86_64)  target="x86_64-linux-android" ;;
            x86)     target="i686-linux-android" ;;
        esac

        log "=== Building Rust for $target ==="
        local RUST_START=$(date +%s)

        # Determine Android arch and NDK script
        local ANDROID_ARCH=""
        local NDK_SCRIPT=""
        local FLUTTER_TARGET=""
        local APK_SUFFIX=""
        case "$target" in
            aarch64-linux-android)
                ANDROID_ARCH="arm64-v8a"
                NDK_SCRIPT="ndk_arm64.sh"
                FLUTTER_TARGET="android-arm64"
                APK_SUFFIX="arm64-v8a"
                ;;
            armv7-linux-androideabi)
                ANDROID_ARCH="armeabi-v7a"
                NDK_SCRIPT="ndk_arm.sh"
                FLUTTER_TARGET="android-arm"
                APK_SUFFIX="armeabi-v7a"
                ;;
            x86_64-linux-android)
                ANDROID_ARCH="x86_64"
                NDK_SCRIPT="ndk_x64.sh"
                FLUTTER_TARGET="android-x64"
                APK_SUFFIX="x86_64"
                ;;
            i686-linux-android)
                ANDROID_ARCH="x86"
                NDK_SCRIPT="ndk_x86.sh"
                FLUTTER_TARGET="android-x86"
                APK_SUFFIX="x86"
                ;;
            *)
                err "Unknown target: $target"
                continue
                ;;
        esac

        # Build vcpkg Android dependencies
        log "=== Building vcpkg Android deps for $ANDROID_ARCH ==="
        if [ -f "./flutter/build_android_deps.sh" ]; then
            ./flutter/build_android_deps.sh "$ANDROID_ARCH" || warn "vcpkg Android deps may have partially failed"
        else
            warn "build_android_deps.sh not found, skipping vcpkg Android deps"
        fi

        # Build Rust library via NDK script
        log "=== Running $NDK_SCRIPT ==="
        if [ -f "./flutter/$NDK_SCRIPT" ]; then
            bash ./flutter/$NDK_SCRIPT
        else
            err "NDK script $NDK_SCRIPT not found!"
            continue
        fi

        local RUST_END=$(date +%s)
        log "=== Rust build for $target took $(( (RUST_END - RUST_START) / 60 )) min $(( (RUST_END - RUST_START) % 60 )) sec ==="

        # Copy .so to jniLibs
        local JNIDIR="./flutter/android/app/src/main/jniLibs/$ANDROID_ARCH"
        mkdir -p "$JNIDIR"
        cp "./target/$target/release/liblibrustdesk.so" "$JNIDIR/librustdesk.so"

        # Copy libc++_shared.so from NDK
        local NDK_LIBCXX=""
        case "$target" in
            aarch64-linux-android)
                NDK_LIBCXX="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
                ;;
            armv7-linux-androideabi)
                NDK_LIBCXX="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/arm-linux-androideabi/libc++_shared.so"
                ;;
            x86_64-linux-android)
                NDK_LIBCXX="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/x86_64-linux-android/libc++_shared.so"
                ;;
            i686-linux-android)
                NDK_LIBCXX="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/i686-linux-android/libc++_shared.so"
                ;;
        esac
        if [ -f "$NDK_LIBCXX" ]; then
            cp "$NDK_LIBCXX" "$JNIDIR/"
        fi

        # Update custom.txt in assets
        if [ -n "$CUSTOM_B64" ]; then
            echo "$CUSTOM_B64" | base64 -d > ./flutter/assets/custom.txt
        fi

        # Build Flutter APK
        log "=== Building Flutter APK for $FLUTTER_TARGET ==="
        # Use debug signing (same as CI)
        sed -i "s/signingConfigs.release/signingConfigs.debug/g" ./flutter/android/app/build.gradle 2>/dev/null || true
        # Increase Gradle JVM memory
        sed -i "s/org.gradle.jvmargs=-Xmx1024M/org.gradle.jvmargs=-Xmx2g/g" ./flutter/android/gradle.properties 2>/dev/null || true

        # Clean up any stale Gradle caches from prior JDK 21 attempts
        rm -rf /root/.gradle/caches/7.* /root/.gradle/caches/8.* /root/.gradle/init.gradle 2>/dev/null || true

        cd ./flutter
        flutter build apk "--release" --target-platform "$FLUTTER_TARGET" --split-per-abi

        # Move APK to output
        local APK_FILE="build/app/outputs/flutter-apk/app-${APK_SUFFIX}-release.apk"
        if [ -f "$APK_FILE" ]; then
            mkdir -p "$OUTPUT"
            local ARCH_LABEL=""
            case "$target" in
                aarch64-linux-android) ARCH_LABEL="aarch64" ;;
                armv7-linux-androideabi) ARCH_LABEL="armv7" ;;
                x86_64-linux-android) ARCH_LABEL="x86_64" ;;
                i686-linux-android) ARCH_LABEL="x86" ;;
            esac
            mv "$APK_FILE" "$OUTPUT/${FILENAME}-${ARCH_LABEL}.apk"
            log "=== APK saved: $OUTPUT/${FILENAME}-${ARCH_LABEL}.apk ==="
        else
            err "APK not found at expected path: $APK_FILE"
        fi
        cd "$WORKSPACE/rustdesk"
    done

    # --- Upload to server ---
    if [ "$UPLOAD_TO_SERVER" == "true" ] && [ -n "$UPLOAD_TOKEN" ]; then
        log "=== Uploading APKs to server ==="
        for apk in "$OUTPUT"/*.apk; do
            if [ -f "$apk" ]; then
                curl -i -X POST \
                    -H "Content-Type: multipart/form-data" \
                    -H "Authorization: Bearer $UPLOAD_TOKEN" \
                    -F "file=@$apk" \
                    -F "uuid=$UPLOAD_UUID" \
                    "$UPLOAD_URL/save_custom_client" || warn "Upload of $(basename $apk) failed"
            fi
        done
    fi

    local END_TIME=$(date +%s)
    local TOTAL=$(( END_TIME - START_TIME ))
    log "=== Android build complete in $(( TOTAL / 60 )) min $(( TOTAL % 60 )) sec ==="
    log "=== Output files in $OUTPUT/ ==="
    ls -lh "$OUTPUT/"*.apk 2>/dev/null || warn "No APK files found in output"
}

# ============================ BUILD MACOS =============================
build_macos() {
    local START_TIME=$(date +%s)
    log "=== Starting macOS build: $APPNAME v$RUSTDESK_VERSION ==="

    # Check we're on macOS
    if [ "$(uname)" != "Darwin" ]; then
        err "build-macos can only run on macOS"
        exit 1
    fi

    source "$HOME/.cargo/env"
    export PATH="$FLUTTER_PATH/bin:$PATH"
    export VCPKG_ROOT="$VCPKG_ROOT"
    export CARGO_INCREMENTAL=0

    # Override Linux-specific paths for macOS
    local MAC_WORKSPACE="$HOME/rustdesk-build"
    local MAC_OUTPUT="$HOME/rustdesk-output"
    mkdir -p "$MAC_WORKSPACE" "$MAC_OUTPUT"

    cd "$MAC_WORKSPACE"

    # --- Clone/update RustDesk ---
    log "=== Cloning RustDesk v$RUSTDESK_VERSION ==="
    if [ -d "rustdesk" ]; then
        cd rustdesk
        git fetch --all --tags
        git reset --hard HEAD
        git clean -fdx
        git checkout "refs/tags/$RUSTDESK_VERSION"
        git submodule update --init --recursive
    else
        git clone --recursive https://github.com/rustdesk/rustdesk.git
        cd rustdesk
        git checkout "refs/tags/$RUSTDESK_VERSION"
        git submodule update --init --recursive
    fi

    git config --global --add safe.directory "*"

    # --- Generate bridge files ---
    log "=== Generating flutter_rust_bridge files ==="
    cd "$MAC_WORKSPACE/rustdesk/flutter"
    flutter pub get
    cd "$MAC_WORKSPACE/rustdesk"
    ~/.cargo/bin/flutter_rust_bridge_codegen \
        --rust-input ./src/flutter_ffi.rs \
        --dart-output ./flutter/lib/generated_bridge.dart \
        --c-output ./flutter/macos/Runner/bridge_generated.h
    cp ./flutter/macos/Runner/bridge_generated.h ./flutter/ios/Runner/bridge_generated.h 2>/dev/null || true

    # --- Apply patches ---
    log "=== Applying patches ==="
    wget -O allowCustom.diff https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/allowCustom.diff
    git apply allowCustom.diff || warn "allowCustom.diff already applied or failed"
    wget -O removeSetupServerTip.diff https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/removeSetupServerTip.diff
    git apply removeSetupServerTip.diff || warn "removeSetupServerTip.diff already applied or failed"

    # --- Configure server and keys (macOS sed needs -i '') ---
    log "=== Configuring server and keys ==="
    git checkout -- ./src/common.rs ./src/lang/en.rs 2>/dev/null || true
    (cd ./libs/hbb_common && git checkout -- src/config.rs 2>/dev/null) || true
    sed -i '' -e "s|rs-ny.rustdesk.com|$RENDEZVOUS_SERVER|" ./libs/hbb_common/src/config.rs
    sed -i '' -e "s|OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=|$RS_PUB_KEY|" ./libs/hbb_common/src/config.rs
    sed -i '' -e 's|For faster connection, please set up your own server||' ./src/lang/en.rs
    sed -i '' -e '/const KEY:/,/};/d' ./src/common.rs
    sed -i '' -e '/let Ok(data) = sign::verify(&data, &pk)/,/};/d' ./src/common.rs
    sed -i '' -e "s|https://admin.rustdesk.com|$API_SERVER|" ./src/common.rs

    # --- Create custom.txt ---
    log "=== Creating custom.txt ==="
    if [ -n "$CUSTOM_B64" ]; then
        echo "$CUSTOM_B64" | base64 -d > ./custom.txt
    else
        warn "CUSTOM_B64 is empty, creating empty custom.txt"
        echo "" > ./custom.txt
    fi
    sed -i '' '/intl:/a \
  archive: ^3.6.1' ./flutter/pubspec.yaml

    # --- Change app name ---
    if [ "$APPNAME" != "rustdesk" ]; then
        log "=== Changing app name to $APPNAME ==="
        sed -i '' -e "s|description = \"RustDesk Remote Desktop\"|description = \"$APPNAME\"|" ./Cargo.toml
        sed -i '' -e "s|ProductName = \"RustDesk\"|ProductName = \"$APPNAME\"|" ./Cargo.toml
        sed -i '' -e "s|FileDescription = \"RustDesk Remote Desktop\"|FileDescription = \"$APPNAME\"|" ./Cargo.toml
        sed -i '' -e "s|description = \"RustDesk Remote Desktop\"|description = \"$APPNAME\"|" ./libs/portable/Cargo.toml
        sed -i '' -e "s|ProductName = \"RustDesk\"|ProductName = \"$APPNAME\"|" ./libs/portable/Cargo.toml
        sed -i '' -e "s|FileDescription = \"RustDesk Remote Desktop\"|FileDescription = \"$APPNAME\"|" ./libs/portable/Cargo.toml
        find ./src/lang -name "*.rs" -exec sed -i '' -e "s|RustDesk|$APPNAME|" {} \;
    fi

    # --- Change company name ---
    if [ "$COMPNAME" != "Purslane Ltd" ]; then
        log "=== Changing company name to $COMPNAME ==="
        sed -i '' -e "s|Purslane Ltd|$COMPNAME|" ./flutter/lib/desktop/pages/desktop_setting_page.dart
        sed -i '' -e "s|Purslane Ltd|$COMPNAME|" ./Cargo.toml
        sed -i '' -e "s|Purslane Ltd|$COMPNAME|" ./libs/portable/Cargo.toml
    fi

    # --- Update macOS Info.plist and bundle ID ---
    log "=== Updating macOS Info.plist and bundle ID ==="
    local SANITIZED_APPNAME=$(echo "$APPNAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9.-]//g')
    local BUNDLE_ID="com.carriez.${SANITIZED_APPNAME}"
    log "=== Bundle ID: $BUNDLE_ID ==="

    cp ./flutter/macos/Runner/Info.plist ./flutter/macos/Runner/Info.plist.bak 2>/dev/null || true
    cp ./flutter/macos/Runner/Configs/AppInfo.xcconfig ./flutter/macos/Runner/Configs/AppInfo.xcconfig.bak 2>/dev/null || true
    cp ./flutter/macos/Runner.xcodeproj/project.pbxproj ./flutter/macos/Runner.xcodeproj/project.pbxproj.bak 2>/dev/null || true

    sed -i '' -e "s/PRODUCT_BUNDLE_IDENTIFIER = .*;/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;/g" ./flutter/macos/Runner.xcodeproj/project.pbxproj
    sed -i '' -e "s/PRODUCT_BUNDLE_IDENTIFIER = \".*\";/PRODUCT_BUNDLE_IDENTIFIER = \"$BUNDLE_ID\";/g" ./flutter/macos/Runner.xcodeproj/project.pbxproj
    sed -i '' -e "s/\\\$\\(PRODUCT_BUNDLE_IDENTIFIER\\)/$BUNDLE_ID/g" ./flutter/macos/Runner/Info.plist
    sed -i '' -e "s/com\\.carriez\\.rustdesk/$BUNDLE_ID/g" ./flutter/macos/Runner/Info.plist
    sed -i '' -e "s|PRODUCT_NAME = .*|PRODUCT_NAME = $APPNAME|" ./flutter/macos/Runner/Configs/AppInfo.xcconfig
    sed -i '' -e "s|PRODUCT_BUNDLE_IDENTIFIER = .*|PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID|" ./flutter/macos/Runner/Configs/AppInfo.xcconfig
    sed -i '' -e "s|<string>rustdesk</string>|<string>$APPNAME</string>|" ./flutter/macos/Runner/Info.plist
    sed -i '' -e 's/PRODUCT_NAME = "RustDesk"/PRODUCT_NAME = "'"$APPNAME"'"/' ./flutter/macos/Runner.xcodeproj/project.pbxproj

    # --- Set macOS deployment target ---
    log "=== Setting MACOSX_DEPLOYMENT_TARGET=$MACOS_MIN_VERSION ==="
    sed -i '' -e "s/MACOSX_DEPLOYMENT_TARGET=[0-9]*.[0-9]*/MACOSX_DEPLOYMENT_TARGET=$MACOS_MIN_VERSION/" build.py
    sed -i '' -e "s/platform :osx, '.*'/platform :osx, '$MACOS_MIN_VERSION'/" flutter/macos/Podfile
    sed -i '' -e "s/osx_minimum_system_version = \"[0-9]*.[0-9]*\"/osx_minimum_system_version = \"$MACOS_MIN_VERSION\"/" Cargo.toml
    sed -i '' -e "s/MACOSX_DEPLOYMENT_TARGET = [0-9]*.[0-9]*;/MACOSX_DEPLOYMENT_TARGET = $MACOS_MIN_VERSION;/" flutter/macos/Runner.xcodeproj/project.pbxproj

    # --- Apply icon ---
    if [ "$ICON_URL" != "false" ]; then
        log "=== Applying custom icon ==="
        if [[ "$ICON_URL" == http* ]]; then
            wget -O ./res/icon.png "$ICON_URL"
        else
            cp "$ICON_URL" ./res/icon.png
        fi

        # Standard icons
        magick ./res/icon.png -resize 32x32 ./res/32x32.png 2>/dev/null || convert ./res/icon.png -resize 32x32 ./res/32x32.png
        magick ./res/icon.png -resize 64x64 ./res/64x64.png 2>/dev/null || convert ./res/icon.png -resize 64x64 ./res/64x64.png
        magick ./res/icon.png -resize 128x128 ./res/128x128.png 2>/dev/null || convert ./res/icon.png -resize 128x128 ./res/128x128.png

        # Flutter assets
        cp ./res/icon.png ./flutter/assets/icon.png 2>/dev/null || true
        magick ./res/icon.png -flatten ./temp_icon.pbm 2>/dev/null || convert ./res/icon.png -flatten ./temp_icon.pbm
        potrace --svg -o ./flutter/assets/icon.svg ./temp_icon.pbm
        rm -f ./temp_icon.pbm

        # macOS app icons
        local ICONSET="./flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset"
        mkdir -p "$ICONSET"
        for size in 16 32 64 128 256 512 1024; do
            magick ./res/icon.png -resize ${size}x${size} "$ICONSET/app_icon_${size}.png" 2>/dev/null || \
                convert ./res/icon.png -resize ${size}x${size} "$ICONSET/app_icon_${size}.png"
        done

        # Create .icns
        mkdir -p ./iconset.iconset
        cp "$ICONSET/app_icon_16.png" ./iconset.iconset/icon_16x16.png
        cp "$ICONSET/app_icon_32.png" ./iconset.iconset/icon_16x16@2x.png
        cp "$ICONSET/app_icon_32.png" ./iconset.iconset/icon_32x32.png
        cp "$ICONSET/app_icon_64.png" ./iconset.iconset/icon_32x32@2x.png
        cp "$ICONSET/app_icon_128.png" ./iconset.iconset/icon_128x128.png
        cp "$ICONSET/app_icon_256.png" ./iconset.iconset/icon_128x128@2x.png
        cp "$ICONSET/app_icon_256.png" ./iconset.iconset/icon_256x256.png
        cp "$ICONSET/app_icon_512.png" ./iconset.iconset/icon_256x256@2x.png
        cp "$ICONSET/app_icon_512.png" ./iconset.iconset/icon_512x512.png
        cp "$ICONSET/app_icon_1024.png" ./iconset.iconset/icon_512x512@2x.png
        iconutil -c icns ./iconset.iconset -o ./flutter/macos/Runner/AppIcon.icns
        rm -rf ./iconset.iconset

        # Contents.json
        cat > "$ICONSET/Contents.json" <<'ICONSJSON'
{
  "images": [
    {"size":"16x16","idiom":"mac","filename":"app_icon_16.png","scale":"1x"},
    {"size":"16x16","idiom":"mac","filename":"app_icon_32.png","scale":"2x"},
    {"size":"32x32","idiom":"mac","filename":"app_icon_32.png","scale":"1x"},
    {"size":"32x32","idiom":"mac","filename":"app_icon_64.png","scale":"2x"},
    {"size":"128x128","idiom":"mac","filename":"app_icon_128.png","scale":"1x"},
    {"size":"128x128","idiom":"mac","filename":"app_icon_256.png","scale":"2x"},
    {"size":"256x256","idiom":"mac","filename":"app_icon_256.png","scale":"1x"},
    {"size":"256x256","idiom":"mac","filename":"app_icon_512.png","scale":"2x"},
    {"size":"512x512","idiom":"mac","filename":"app_icon_512.png","scale":"1x"},
    {"size":"512x512","idiom":"mac","filename":"app_icon_1024.png","scale":"2x"}
  ],
  "info": {"version": 1, "author": "xcode"}
}
ICONSJSON

        # macOS tray icons
        magick ./res/icon.png -resize 22x22 -colorspace gray -alpha set -background none -channel A -evaluate set 100% ./res/mac-tray-dark-x2.png 2>/dev/null || true
        magick ./res/icon.png -resize 128x128 ./res/mac-icon.png 2>/dev/null || convert ./res/icon.png -resize 128x128 ./res/mac-icon.png

        # Flutter launcher icons
        cd ./flutter
        flutter pub get
        dart run flutter_launcher_icons 2>/dev/null || flutter pub run flutter_launcher_icons 2>/dev/null || true
        cd ..
    fi

    # --- Apply logo ---
    if [ "$LOGO_URL" != "false" ]; then
        log "=== Applying custom logo ==="
        if [[ "$LOGO_URL" == http* ]]; then
            wget -O ./flutter/assets/logo.png "$LOGO_URL"
        else
            cp "$LOGO_URL" ./flutter/assets/logo.png
        fi
    fi

    # --- Optional patches (macOS sed) ---
    if [ "$DELAY_FIX" == "true" ]; then
        log "=== Applying delay fix ==="
        sed -i '' -e 's|!key.is_empty()|false|' ./src/client.rs
    fi

    if [ "$CYCLE_MONITOR" == "true" ]; then
        log "=== Applying cycle monitor patch ==="
        wget https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/cycle_monitor.diff
        git apply cycle_monitor.diff || warn "cycle_monitor.diff failed"
    fi

    if [ "$X_OFFLINE" == "true" ]; then
        log "=== Applying X offline patch ==="
        wget https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/xoffline.diff
        git apply xoffline.diff || warn "xoffline.diff failed"
    fi

    if [ "$HIDE_CM" == "true" ]; then
        log "=== Applying hide-cm patch ==="
        git checkout -- flutter/lib/models/server_model.dart flutter/lib/main.dart flutter/lib/desktop/pages/desktop_setting_page.dart 2>/dev/null || true
        if [ -f "flutter/lib/models/server_model.dart" ]; then
            sed -i '' 's/bool hideCm = false;/bool _hideCm = false;/' flutter/lib/models/server_model.dart
            sed -i '' '/bool get clipboardOk => _clipboardOk;/a \
              bool get hideCm => _hideCm;\
              ' flutter/lib/models/server_model.dart
            sed -i '' 's/\/\*//g' flutter/lib/models/server_model.dart
            sed -i '' 's/\*\///g' flutter/lib/models/server_model.dart
        fi
        if [ -f "flutter/lib/main.dart" ]; then
            sed -i '' 's/gFFI.serverModel.hideCm = hide;/\/\/ gFFI.serverModel.hideCm = hide;/' flutter/lib/main.dart
        fi
        if [ -f "flutter/lib/desktop/pages/desktop_setting_page.dart" ]; then
            sed -i '' "s/\/\/ if (usePassword)/if (usePassword)/" flutter/lib/desktop/pages/desktop_setting_page.dart
            sed -i '' "s/\/\/   hide_cm(!locked).marginOnly(left: _kContentHSubMargin - 6),/  hide_cm(!locked).marginOnly(left: _kContentHSubMargin - 6),/" flutter/lib/desktop/pages/desktop_setting_page.dart
        fi
    fi

    if [ "$REMOVE_NEW_VERSION_NOTIF" == "true" ]; then
        log "=== Removing new version notification ==="
        sed -i '' -e 's|updateUrl.isNotEmpty|false|' ./flutter/lib/desktop/pages/desktop_home_page.dart
    fi

    if [ "$DISABLE_SETTINGS" == "true" ]; then
        log "=== Disabling settings UI ==="
        wget https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/disableSettings.diff -O disableSettings.diff
        git apply disableSettings.diff || warn "disableSettings.diff failed"
    fi

    # --- Prepare build.py for custom app name ---
    sed -i '' -e "s|RustDesk.app|\"$APPNAME.app\"|" build.py

    # --- Create macOS directory structure ---
    mkdir -p ./build/macos/Build/Products/Release/RustDesk.app/Contents/MacOS

    # --- Build vcpkg dependencies ---
    log "=== Building vcpkg dependencies for $MACOS_VCPKG_TRIPLET ==="
    if [ ! -f "$VCPKG_ROOT/installed/$MACOS_VCPKG_TRIPLET/include/opus/opus.h" ]; then
        log "=== Building vcpkg deps (first time ~10 min) ==="
        "$VCPKG_ROOT/vcpkg" install --triplet "$MACOS_VCPKG_TRIPLET" --x-install-root="$VCPKG_ROOT/installed"
    else
        log "=== vcpkg dependencies already cached ==="
    fi

    # --- Build Rust + Flutter macOS ---
    # build.py handles both Rust and Flutter compilation (matches CI workflow)
    local RUST_START=$(date +%s)
    log "=== Building Rust + Flutter macOS (this is the slow part) ==="
    python3 ./build.py --flutter --hwcodec --unix-file-copy-paste
    local RUST_END=$(date +%s)
    log "=== Build took $(( (RUST_END - RUST_START) / 60 )) min $(( (RUST_END - RUST_START) % 60 )) sec ==="

    # --- Copy custom.txt into app bundle ---
    log "=== Copying custom.txt into app bundle ==="
    # Flutter build output (used for signing + DMG)
    local FLUTTER_APP_DIR="flutter/build/macos/Build/Products/Release/$APPNAME.app"
    if [ ! -d "$FLUTTER_APP_DIR" ]; then
        FLUTTER_APP_DIR="flutter/build/macos/Build/Products/Release/RustDesk.app"
    fi
    if [ -d "$FLUTTER_APP_DIR" ]; then
        mkdir -p "$FLUTTER_APP_DIR/Contents/Resources"
        cp ./custom.txt "$FLUTTER_APP_DIR/Contents/Resources/custom.txt"
        cp ./custom.txt "$FLUTTER_APP_DIR/Contents/MacOS/custom.txt"
        log "=== custom.txt copied to $FLUTTER_APP_DIR ==="
    else
        warn "Flutter app bundle not found at flutter/build/macos/Build/Products/Release/"
    fi
    # Also copy to build/macos path (CI compatibility)
    local APP_DIR="build/macos/Build/Products/Release/$APPNAME.app"
    if [ ! -d "$APP_DIR" ]; then
        APP_DIR="build/macos/Build/Products/Release/RustDesk.app"
    fi
    if [ -d "$APP_DIR" ]; then
        mkdir -p "$APP_DIR/Contents/Resources"
        cp ./custom.txt "$APP_DIR/Contents/Resources/custom.txt"
        cp ./custom.txt "$APP_DIR/Contents/MacOS/custom.txt"
    fi
    mkdir -p ./flutter/assets
    cp ./custom.txt ./flutter/assets/custom.txt 2>/dev/null || true

    # --- Ad-hoc sign ---
    log "=== Ad-hoc signing ==="
    cd flutter/build/macos/Build/Products/Release
    if [ -d "RustDesk.app" ] && [ ! -d "$APPNAME.app" ]; then
        mv "RustDesk.app" "$APPNAME.app"
    fi
    if [ -d "$APPNAME.app" ]; then
        find "$APPNAME.app" -type f -perm +111 -exec codesign --force --sign - {} \; 2>/dev/null || true
        find "$APPNAME.app/Contents/Frameworks" -type f -not -name ".*" -exec \
            codesign --force --sign - {} \; 2>/dev/null || true
        codesign --force --deep --sign - "$APPNAME.app" 2>/dev/null || true
        log "=== Ad-hoc signing complete ==="
    else
        err "App bundle not found for signing"
    fi

    # --- Create DMG ---
    log "=== Creating DMG ==="
    if [ -d "$APPNAME.app" ]; then
        local ARCH_LABEL="aarch64"
        [ "$(uname -m)" == "x86_64" ] && ARCH_LABEL="x86_64"
        create-dmg \
            --volname "$APPNAME" \
            --window-pos 200 120 \
            --window-size 800 400 \
            --icon-size 100 \
            --icon "$APPNAME.app" 200 190 \
            --hide-extension "$APPNAME.app" \
            --app-drop-link 600 185 \
            "$MAC_OUTPUT/${FILENAME}-${ARCH_LABEL}.dmg" \
            "$APPNAME.app" || warn "create-dmg failed"
        if [ -f "$MAC_OUTPUT/${FILENAME}-${ARCH_LABEL}.dmg" ]; then
            log "=== DMG saved: $MAC_OUTPUT/${FILENAME}-${ARCH_LABEL}.dmg ==="
        fi
    else
        err "No app bundle to create DMG from"
    fi

    cd "$MAC_WORKSPACE"

    # --- Upload to server ---
    if [ "$UPLOAD_TO_SERVER" == "true" ] && [ -n "$UPLOAD_TOKEN" ]; then
        log "=== Uploading DMG to server ==="
        for dmg in "$MAC_OUTPUT"/*.dmg; do
            if [ -f "$dmg" ]; then
                curl -i -X POST \
                    -H "Content-Type: multipart/form-data" \
                    -H "Authorization: Bearer $UPLOAD_TOKEN" \
                    -F "file=@$dmg" \
                    -F "uuid=$UPLOAD_UUID" \
                    "$UPLOAD_URL/save_custom_client" || warn "Upload of $(basename $dmg) failed"
            fi
        done
    fi

    local END_TIME=$(date +%s)
    local TOTAL=$(( END_TIME - START_TIME ))
    log "=== macOS build complete in $(( TOTAL / 60 )) min $(( TOTAL % 60 )) sec ==="
    log "=== Output files in $MAC_OUTPUT/ ==="
    ls -lh "$MAC_OUTPUT"/*.dmg 2>/dev/null || warn "No DMG files found in output"
}

# ============================ BUILD WINDOWS =============================
build_windows() {
    local START_TIME=$(date +%s)
    log "=== Starting Windows build: $APPNAME v$RUSTDESK_VERSION ==="

    check_windows_env "build"

    # Override workspace/output for Windows
    # Force-set paths (don't use :- default, in case stale values are in .bashrc)
    # Use /c/ style paths which work correctly in Git Bash/MSYS2 for shell ops.
    # For cargo/bindgen/libclang (native Windows), export Windows-style VCPKG paths.
    unset WORKSPACE OUTPUT VCPKG_ROOT
    local WIN_WORKSPACE="/c/rustdesk-build"
    local WIN_OUTPUT="/c/rustdesk-output"
    local VCPKG_ROOT_UNIX="/c/vcpkg"
    export WORKSPACE="$WIN_WORKSPACE"
    export OUTPUT="$WIN_OUTPUT"
    # Native Windows tools (bindgen/libclang) do NOT understand /c/ paths.
    # scrap/build.rs passes -I$VCPKG_ROOT/installed/... to clang — must be C:\...
    export VCPKG_ROOT="$(to_win_path "$VCPKG_ROOT_UNIX")"
    export VCPKG_INSTALLED_ROOT="$(to_win_path "$VCPKG_ROOT_UNIX/installed")"
    log "=== VCPKG_ROOT=$VCPKG_ROOT (bindgen-safe Windows path) ==="

    # Cargo / rustup (chocolatey rust-ms may not put rustup on a fresh Git Bash PATH)
    export PATH="$HOME/.cargo/bin:/c/Users/${USER:-$USERNAME}/.cargo/bin:$PATH"
    source "$HOME/.cargo/env" 2>/dev/null || true
    # Resolve rustup if only available as .exe
    if ! command -v rustup &>/dev/null; then
        for p in "$HOME/.cargo/bin/rustup.exe" "/c/Users/${USER:-admin}/.cargo/bin/rustup.exe" \
                 "/c/ProgramData/chocolatey/bin/rustup.exe"; do
            if [ -f "$p" ]; then
                export PATH="$(dirname "$p"):$PATH"
                break
            fi
        done
    fi
    export PATH="${FLUTTER_PATH:-$WIN_WORKSPACE/flutter}/bin:$PATH"
    export VCPKG_DEFAULT_HOST_TRIPLET="$WINDOWS_VCPKG_TRIPLET"

    # Set LIBCLANG_PATH for bindgen (scrap crate needs it for vpx/aom FFI bindings)
    # Prefer pinned LLVM 15 (C:\LLVM-15.0.6) over system LLVM 19+/22 which often
    # produces opaque bindgen structs (_address only → "no field g_w" in scrap).
    local llvm_bin=""
    local p clang_ver=""
    for p in \
        "/c/LLVM-${WINDOWS_LLVM_VERSION}/bin" \
        "/c/LLVM-15.0.6/bin" \
        "/c/LLVM-15/bin" \
        "/c/Program Files/LLVM-15.0.6/bin"; do
        if [ -f "$p/libclang.dll" ]; then
            llvm_bin="$p"
            break
        fi
    done

    # Accept system LLVM only if it is major version <= 18
    if [ -z "$llvm_bin" ]; then
        for p in "/c/Program Files/LLVM/bin" "/c/Program Files (x86)/LLVM/bin" "$HOME/.llvm/bin"; do
            if [ -f "$p/libclang.dll" ]; then
                clang_ver=$("$p/clang" --version 2>/dev/null | head -1 || true)
                if echo "$clang_ver" | grep -qE 'clang version (1[0-8])\.'; then
                    llvm_bin="$p"
                    break
                fi
                warn "Skipping $p ($clang_ver) — too new for scrap bindgen"
            fi
        done
    fi

    if [ -z "$llvm_bin" ]; then
        warn "Compatible libclang not found — installing LLVM $WINDOWS_LLVM_VERSION side-by-side..."
        if ! install_windows_llvm "$WINDOWS_LLVM_VERSION"; then
            err "Cannot continue without LLVM $WINDOWS_LLVM_VERSION (LLVM 22 breaks scrap vpx/aom bindings)."
            exit 1
        fi
        llvm_bin=$(_find_libclang_bin "/c/LLVM-${WINDOWS_LLVM_VERSION}" 2>/dev/null || true)
        [ -z "$llvm_bin" ] && llvm_bin="/c/LLVM-${WINDOWS_LLVM_VERSION}/bin"
    fi

    if [ -n "$llvm_bin" ] && [ -f "$llvm_bin/libclang.dll" ]; then
        export LIBCLANG_PATH="$(to_win_path "$llvm_bin")"
        export PATH="$llvm_bin:$PATH"
        log "=== Set LIBCLANG_PATH=$LIBCLANG_PATH ==="
        if [ -x "$llvm_bin/clang.exe" ] || [ -x "$llvm_bin/clang" ]; then
            log "=== clang: $("$llvm_bin/clang" --version 2>/dev/null | head -1) ==="
        fi
        # Final safety: refuse to proceed with LLVM 19+
        clang_ver=$("$llvm_bin/clang" --version 2>/dev/null | head -1 || true)
        if echo "$clang_ver" | grep -qE 'clang version (1[9]|2[0-9])\.'; then
            err "Still using new clang ($clang_ver). scrap will fail with opaque vpx types."
            err "Install LLVM 15 to C:\\LLVM-15.0.6 and re-run."
            exit 1
        fi
    else
        err "LIBCLANG_PATH not set — cannot run scrap bindgen."
        err "Install LLVM 15 manually to C:\\LLVM-15.0.6:"
        err "  https://github.com/llvm/llvm-project/releases/download/llvmorg-15.0.6/LLVM-15.0.6-win64.exe"
        exit 1
    fi

    # Set vcpkg + Windows SDK + MSVC include/lib paths for bindgen and linker.
    # On GitHub Actions runners, INCLUDE/LIB are pre-set with SDK paths.
    # In Git Bash we need to find them manually (vcvars is not loaded by default).
    local vcpkg_installed="$VCPKG_ROOT_UNIX/installed/$WINDOWS_VCPKG_TRIPLET"

    # Find Windows SDK version (latest installed)
    local sdk_base="/c/Program Files (x86)/Windows Kits/10"
    local sdk_ver=""
    if [ -d "$sdk_base/Include" ]; then
        sdk_ver=$(ls "$sdk_base/Include" 2>/dev/null | grep -E '^[0-9]' | sort -V | tail -1)
    fi

    # Find MSVC tools directory (latest version across VS editions / years)
    # vcruntime.h lives here — without it bindgen (kcp-sys etc.) fails.
    local msvc_base=""
    local msvc_candidates=()
    local _nullglob_was_off=1
    shopt -q nullglob || _nullglob_was_off=0
    shopt -s nullglob
    local msvc_roots=(
        "/c/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"
        "/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC"
        "/c/Program Files/Microsoft Visual Studio/2022/Professional/VC/Tools/MSVC"
        "/c/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC"
        "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"
        "/c/Program Files (x86)/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC"
        "/c/Program Files/Microsoft Visual Studio/2019/BuildTools/VC/Tools/MSVC"
        "/c/Program Files/Microsoft Visual Studio/2019/Community/VC/Tools/MSVC"
        "/c/Program Files/Microsoft Visual Studio/2019/Professional/VC/Tools/MSVC"
        "/c/Program Files/Microsoft Visual Studio/2019/Enterprise/VC/Tools/MSVC"
        "/c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Tools/MSVC"
    )
    local msvc_root d
    for msvc_root in "${msvc_roots[@]}"; do
        if [ -d "$msvc_root" ]; then
            for d in "$msvc_root"/*; do
                if [ -f "$d/include/vcruntime.h" ]; then
                    msvc_candidates+=("$d")
                fi
            done
        fi
    done
    # vswhere fallback (installed with Visual Studio Installer)
    local vswhere="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
    if [ ${#msvc_candidates[@]} -eq 0 ] && [ -x "$vswhere" ]; then
        local vs_install
        vs_install=$("$vswhere" -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>/dev/null | tr -d '\r')
        if [ -n "$vs_install" ]; then
            local vs_unix
            if command -v cygpath &>/dev/null; then
                vs_unix=$(cygpath -u "$vs_install")
            else
                vs_unix="$vs_install"
            fi
            for d in "$vs_unix/VC/Tools/MSVC"/*; do
                if [ -f "$d/include/vcruntime.h" ]; then
                    msvc_candidates+=("$d")
                fi
            done
        fi
    fi
    if [ "$_nullglob_was_off" -eq 0 ]; then
        shopt -u nullglob
    fi
    if [ ${#msvc_candidates[@]} -gt 0 ]; then
        # Prefer highest version number
        msvc_base=$(printf '%s\n' "${msvc_candidates[@]}" | sort -V | tail -1)
        log "=== Found MSVC at $msvc_base ==="
    fi

    if [ -z "$msvc_base" ] || [ ! -f "$msvc_base/include/vcruntime.h" ]; then
        err "MSVC C++ headers not found (vcruntime.h missing)."
        err "bindgen needs MSVC includes. Install Visual Studio Build Tools with C++ workload:"
        err "  choco install visualstudio2022buildtools visualstudio2022-workload-vctools -y"
        err "Or re-run: ./buildconfig.sh setup-windows"
        err "Searched under: Program Files/Microsoft Visual Studio/{2019,2022}/{BuildTools,Community,Professional,Enterprise}"
        exit 1
    fi

    # Put cl.exe / link.exe on PATH for cargo build scripts
    if [ -d "$msvc_base/bin/Hostx64/x64" ]; then
        export PATH="$msvc_base/bin/Hostx64/x64:$PATH"
    fi

    # Try to import full env from vcvars64.bat (sets VCINSTALLDIR, WindowsSdkDir, etc.)
    local vcvars=""
    for p in \
        "$(dirname "$(dirname "$(dirname "$msvc_base")")")/Auxiliary/Build/vcvars64.bat" \
        "/c/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Auxiliary/Build/vcvars64.bat" \
        "/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat" \
        "/c/Program Files/Microsoft Visual Studio/2022/Professional/VC/Auxiliary/Build/vcvars64.bat" \
        "/c/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Auxiliary/Build/vcvars64.bat" \
        "/c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat"; do
        if [ -f "$p" ]; then
            vcvars="$p"
            break
        fi
    done
    if [ -n "$vcvars" ]; then
        local win_vcvars env_tmp
        win_vcvars="$(to_win_path "$vcvars")"
        env_tmp=$(mktemp /tmp/vcvars_env.XXXXXX 2>/dev/null || mktemp)
        # Git Bash: prevent path mangling of Windows paths passed to cmd
        # shellcheck disable=SC2030,SC2031
        if MSYS2_ARG_CONV_EXCL='*' cmd.exe /c "call \"${win_vcvars}\" >nul 2>&1 && set" >"$env_tmp" 2>/dev/null \
           || cmd.exe //c "call \"${win_vcvars}\" >nul 2>&1 && set" >"$env_tmp" 2>/dev/null; then
            local line key val
            while IFS= read -r line || [ -n "$line" ]; do
                # Strip CR from cmd.exe output
                line="${line//$'\r'/}"
                case "$line" in
                    INCLUDE=*|LIB=*|LIBPATH=*|VCINSTALLDIR=*|WindowsSdkDir=*|WindowsSDKVersion=*|VCToolsInstallDir=*|UniversalCRTSdkDir=*|UCRTVersion=*)
                        key="${line%%=*}"
                        val="${line#*=}"
                        export "$key=$val"
                        ;;
                esac
            done < "$env_tmp"
            if [ -n "${VCINSTALLDIR:-}" ] || [ -n "${INCLUDE:-}" ]; then
                log "=== Imported env from vcvars64.bat ==="
            else
                warn "vcvars64.bat produced no usable env; using manual INCLUDE/LIB paths"
            fi
        else
            warn "vcvars64.bat import failed; using manual INCLUDE/LIB paths"
        fi
        rm -f "$env_tmp"
    fi

    # Build INCLUDE path (semicolon-separated, Windows style)
    # Always merge our paths so vcpkg + MSVC + SDK are present even if vcvars was partial
    local all_includes="${INCLUDE:-}"
    local p win_p
    for p in \
        "$vcpkg_installed/include" \
        "$msvc_base/include" \
        "$msvc_base/atlmfc/include" \
        "$sdk_base/Include/$sdk_ver/ucrt" \
        "$sdk_base/Include/$sdk_ver/um" \
        "$sdk_base/Include/$sdk_ver/shared" \
        "$sdk_base/Include/$sdk_ver/winrt" \
        "/c/Program Files/LLVM/lib/clang/22/include" \
        "/c/Program Files/LLVM/lib/clang/21/include" \
        "/c/Program Files/LLVM/lib/clang/20/include" \
        "/c/Program Files/LLVM/lib/clang/19/include" \
        "/c/Program Files/LLVM/lib/clang/18/include" \
        "/c/Program Files/LLVM/lib/clang/17/include" \
        "/c/Program Files/LLVM/lib/clang/16/include" \
        "/c/Program Files/LLVM/lib/clang/15/include"; do
        if [ -n "$p" ] && [ -d "$p" ]; then
            win_p="$(to_win_path "$p")"
            case ";$all_includes;" in
                *";$win_p;"*) ;;
                *) all_includes="${all_includes:+$all_includes;}$win_p" ;;
            esac
        fi
    done

    # Build LIB path
    local all_libs="${LIB:-}"
    for p in \
        "$vcpkg_installed/lib" \
        "$msvc_base/lib/x64" \
        "$msvc_base/atlmfc/lib/x64" \
        "$sdk_base/Lib/$sdk_ver/ucrt/x64" \
        "$sdk_base/Lib/$sdk_ver/um/x64"; do
        if [ -n "$p" ] && [ -d "$p" ]; then
            win_p="$(to_win_path "$p")"
            case ";$all_libs;" in
                *";$win_p;"*) ;;
                *) all_libs="${all_libs:+$all_libs;}$win_p" ;;
            esac
        fi
    done

    if [ -z "$all_includes" ]; then
        err "INCLUDE is empty after MSVC/SDK detection"
        exit 1
    fi
    export INCLUDE="$all_includes"
    export LIB="$all_libs"
    log "=== Set INCLUDE (MSVC + SDK + vcpkg) ==="
    log "=== Set LIB (MSVC + SDK + vcpkg) ==="
    # Sanity: vcruntime.h must be reachable for bindgen
    if [ ! -f "$msvc_base/include/vcruntime.h" ]; then
        err "vcruntime.h missing at $msvc_base/include — MSVC install is broken"
        exit 1
    fi
    log "=== vcruntime.h OK at $(to_win_path "$msvc_base/include/vcruntime.h") ==="

    # bindgen (scrap vpx/aom) uses libclang, which needs Windows-style -I paths and MSVC target
    if [ ! -d "$vcpkg_installed/include/vpx" ]; then
        err "libvpx headers missing at $vcpkg_installed/include/vpx"
        err "Run: ./buildconfig.sh setup-windows  (or vcpkg install libvpx:$WINDOWS_VCPKG_TRIPLET)"
        exit 1
    fi
    if [ ! -d "$vcpkg_installed/include/aom" ]; then
        err "aom headers missing at $vcpkg_installed/include/aom"
        err "Run: ./buildconfig.sh setup-windows"
        exit 1
    fi
    local bindgen_args="--target=x86_64-pc-windows-msvc"
    # Clang resource dir (stdint.h etc.) — critical for hwcodec common.h bindgen
    local clang_res=""
    for p in \
        "/c/LLVM-${WINDOWS_LLVM_VERSION}/lib/clang/${WINDOWS_LLVM_VERSION}/include" \
        "/c/LLVM-15.0.6/lib/clang/15.0.6/include" \
        "/c/LLVM-15.0.6/lib/clang/15.0.7/include"; do
        if [ -d "$p" ]; then
            clang_res="$p"
            break
        fi
    done
    # Also probe under LLVM install for any versioned resource dir
    if [ -z "$clang_res" ] && [ -d "/c/LLVM-15.0.6/lib/clang" ]; then
        clang_res=$(find "/c/LLVM-15.0.6/lib/clang" -maxdepth 2 -type d -name include 2>/dev/null | head -1)
    fi
    for p in \
        "$clang_res" \
        "$vcpkg_installed/include" \
        "$msvc_base/include" \
        "$sdk_base/Include/$sdk_ver/ucrt" \
        "$sdk_base/Include/$sdk_ver/shared" \
        "$sdk_base/Include/$sdk_ver/um"; do
        if [ -n "$p" ] && [ -d "$p" ]; then
            bindgen_args="$bindgen_args -I$(to_win_path "$p")"
        fi
    done
    export BINDGEN_EXTRA_CLANG_ARGS="$bindgen_args"
    log "=== Set BINDGEN_EXTRA_CLANG_ARGS for scrap/hwcodec bindgen ==="

    cd "$WIN_WORKSPACE/rustdesk" || { err "RustDesk source not found at $WIN_WORKSPACE/rustdesk"; exit 1; }

    # Clean checkout so patches apply on a pristine tree (matches Linux/Android builds)
    log "=== Checking out clean v$RUSTDESK_VERSION ==="
    git fetch --all --tags 2>/dev/null || true
    git reset --hard HEAD 2>/dev/null || true
    git clean -fdx 2>/dev/null || true
    git checkout "refs/tags/$RUSTDESK_VERSION" 2>/dev/null || \
        git checkout "$RUSTDESK_VERSION" 2>/dev/null || \
        log "Already on $RUSTDESK_VERSION"
    git reset --hard "refs/tags/$RUSTDESK_VERSION" 2>/dev/null || \
        git reset --hard "$RUSTDESK_VERSION" 2>/dev/null || true
    git clean -fdx 2>/dev/null || true
    git submodule update --init --recursive 2>/dev/null || true
    git submodule foreach --recursive 'git reset --hard && git clean -fdx' 2>/dev/null || true

    # --- Generate flutter_rust_bridge files (gitignored: src/bridge_generated.rs) ---
    # Without this: error E0583 file not found for module `bridge_generated` + IntoIntoDart failures
    log "=== Generating flutter_rust_bridge files ==="
    export PATH="$HOME/.cargo/bin:$PATH"
    # rust-ms / rustup may put proxies only under .cargo/bin
    if [ -d "$HOME/.cargo/bin" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi

    # rustfmt is required by flutter_rust_bridge_codegen and bindgen 0.59.
    # A pure exit-0 shim empties FFI (stdin/stdout); a shim that always reads stdin
    # hangs on `rustfmt --version` (waits for TTY EOF). Use a careful pass-through.
    install_rustfmt_passthrough_shim() {
        mkdir -p "$HOME/.cargo/bin"
        local shim_dir="/tmp/rustfmt_shim_$$"
        mkdir -p "$shim_dir"
        cat > "$shim_dir/main.rs" << 'RSEOF'
// Pass-through rustfmt for machines without rustup rustfmt.
// - --version / --help: print and exit (NEVER read stdin — avoids hang)
// - *.rs file args: leave files unchanged (in-place format no-op)
// - piped stdin: copy stdin → stdout (bindgen / some FRB modes)
use std::env;
use std::io::{self, IsTerminal, Read, Write};
use std::process;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    for a in &args {
        if a == "--version" || a == "-V" {
            println!("rustfmt 1.0.0-passthrough-shim");
            process::exit(0);
        }
        if a == "--help" || a == "-h" {
            println!("rustfmt passthrough shim (does not reformat)");
            process::exit(0);
        }
    }
    let has_file = args.iter().any(|a| a.ends_with(".rs") && !a.starts_with('-'));
    let emit_stdout = args.iter().any(|a| a == "--emit" || a.starts_with("--emit=") || a.contains("stdout"));
    if has_file && !emit_stdout {
        process::exit(0);
    }
    // Only read stdin when it is a pipe (not an interactive TTY)
    if io::stdin().is_terminal() {
        process::exit(0);
    }
    let mut buf = Vec::new();
    let _ = io::stdin().read_to_end(&mut buf);
    let _ = io::stdout().write_all(&buf);
    process::exit(0);
}
RSEOF
        # Prefer -C opt-level=0 for fast compile; don't hang waiting on linker forever
        if (cd "$shim_dir" && rustc -C opt-level=0 -o "$HOME/.cargo/bin/rustfmt.exe" main.rs); then
            log "=== Installed pass-through rustfmt.exe shim ==="
            rm -rf "$shim_dir"
            export PATH="$HOME/.cargo/bin:$PATH"
            return 0
        fi
        rm -rf "$shim_dir"
        return 1
    }

    rustfmt_passthrough_ok() {
        # Must not hang: pipe only (shim must not block on TTY)
        local out
        out=$(printf '%s\n' 'pub fn __rd_fmt_test() {}' | rustfmt 2>/dev/null || true)
        echo "$out" | grep -q '__rd_fmt_test'
    }

    export PATH="$HOME/.cargo/bin:$PATH"

    # Prefer real rustfmt next to rustc (works without rustup on PATH)
    local sysroot rf
    sysroot=$(rustc --print sysroot 2>/dev/null | tr -d '\r' || true)
    if [ -n "$sysroot" ]; then
        for rf in "$sysroot/bin/rustfmt.exe" "$sysroot/bin/rustfmt"; do
            if [ -f "$rf" ]; then
                export PATH="$(dirname "$rf"):$PATH"
                log "=== Found rustfmt in rustc sysroot ==="
                break
            fi
        done
    fi
    for rf in \
        "/c/ProgramData/chocolatey/lib/rust-ms/tools/bin/rustfmt.exe" \
        "/c/ProgramData/chocolatey/bin/rustfmt.exe"; do
        if [ -f "$rf" ]; then
            export PATH="$(dirname "$rf"):$PATH"
            break
        fi
    done

    if command -v rustup &>/dev/null; then
        if ! command -v rustfmt &>/dev/null || ! rustfmt_passthrough_ok 2>/dev/null; then
            log "=== Installing rustfmt via rustup ==="
            rustup component add rustfmt 2>&1 | tail -5 || true
        fi
    fi

    # Replace broken/hang-prone shims. Use </dev/null so --version never blocks on TTY.
    local need_shim=0
    if ! command -v rustfmt &>/dev/null; then
        need_shim=1
    elif ! rustfmt_passthrough_ok 2>/dev/null; then
        warn "rustfmt lacks stdin passthrough — replacing"
        need_shim=1
    else
        # Hang-prone shim: reads stdin on --version. Probe with closed stdin only.
        local ver
        ver=$(rustfmt --version </dev/null 2>/dev/null | head -1 || true)
        if ! echo "$ver" | grep -qE 'passthrough-shim|rustfmt [0-9]'; then
            warn "rustfmt --version unusable ($ver) — replacing with pass-through shim"
            need_shim=1
        fi
    fi

    if [ "$need_shim" -eq 1 ]; then
        rm -f "$HOME/.cargo/bin/rustfmt.exe" "$HOME/.cargo/bin/rustfmt" "$HOME/.cargo/bin/rustfmt.cmd"
        warn "Installing pass-through rustfmt shim"
        if ! install_rustfmt_passthrough_shim; then
            err "Could not install rustfmt shim (rustc failed)."
            exit 1
        fi
    fi

    if ! rustfmt_passthrough_ok; then
        err "rustfmt still cannot pass stdin through — bindgen/hwcodec will break."
        err "Remove: rm -f ~/.cargo/bin/rustfmt.exe && re-run"
        exit 1
    fi
    # Always close stdin so a bad shim cannot hang the build script
    log "=== rustfmt OK: $(rustfmt --version </dev/null 2>/dev/null | head -1 || echo passthrough-shim) ==="

    local frb_bin=""
    for p in \
        "$HOME/.cargo/bin/flutter_rust_bridge_codegen" \
        "$HOME/.cargo/bin/flutter_rust_bridge_codegen.exe"; do
        if [ -x "$p" ] || [ -f "$p" ]; then
            frb_bin="$p"
            break
        fi
    done
    if [ -z "$frb_bin" ]; then
        log "=== Installing flutter_rust_bridge_codegen $FLUTTER_RUST_BRIDGE_VERSION ==="
        cargo +stable install flutter_rust_bridge_codegen --version "$FLUTTER_RUST_BRIDGE_VERSION" --features "uuid" --locked 2>/dev/null || \
            cargo install flutter_rust_bridge_codegen --version "$FLUTTER_RUST_BRIDGE_VERSION" --features "uuid" --locked || {
            err "Failed to install flutter_rust_bridge_codegen"
            exit 1
        }
        frb_bin="$HOME/.cargo/bin/flutter_rust_bridge_codegen"
        [ -f "${frb_bin}.exe" ] && frb_bin="${frb_bin}.exe"
    fi
    # Dart side needs packages resolved for some codegen versions
    if [ -d ./flutter ]; then
        (cd ./flutter && flutter pub get) || warn "flutter pub get failed (codegen may still work)"
    fi
    # Ensure version.rs exists (codegen/build may expect it; gitignore removes it)
    if [ ! -f ./src/version.rs ]; then
        echo 'pub const VERSION: &str = "'"$RUSTDESK_VERSION"'";' > ./src/version.rs
    fi
    "$frb_bin" \
        --rust-input ./src/flutter_ffi.rs \
        --dart-output ./flutter/lib/generated_bridge.dart \
        --c-output ./flutter/windows/runner/bridge_generated.h \
        || "$frb_bin" \
            --rust-input ./src/flutter_ffi.rs \
            --dart-output ./flutter/lib/generated_bridge.dart \
            --c-output ./flutter/macos/Runner/bridge_generated.h \
        || {
            err "flutter_rust_bridge_codegen failed"
            err "Ensure rustfmt works: rustup component add rustfmt && rustfmt --version"
            exit 1
        }
    # Copy header to other platforms if generated under macos path
    if [ -f ./flutter/macos/Runner/bridge_generated.h ] && [ ! -f ./flutter/windows/runner/bridge_generated.h ]; then
        mkdir -p ./flutter/windows/runner
        cp ./flutter/macos/Runner/bridge_generated.h ./flutter/windows/runner/bridge_generated.h 2>/dev/null || true
    fi
    # Also generate .io companion if codegen only wrote main file (some versions emit both)
    if [ ! -f ./src/bridge_generated.rs ]; then
        err "src/bridge_generated.rs was not created by codegen"
        exit 1
    fi
    log "=== bridge_generated.rs OK ==="

    # --- Apply custom app name ---
    if [ "$APPNAME" != "RustDesk" ]; then
        log "=== Changing app name to $APPNAME ==="
        git checkout -- ./Cargo.toml ./libs/portable/Cargo.toml ./flutter/windows/runner/Runner.rc 2>/dev/null || true
        sed -i -e "s|description = \"RustDesk Remote Desktop\"|description = \"$APPNAME\"|" ./Cargo.toml
        sed -i -e "s|ProductName = \"RustDesk\"|ProductName = \"$APPNAME\"|" ./Cargo.toml
        sed -i -e "s|FileDescription = \"RustDesk Remote Desktop\"|FileDescription = \"$APPNAME\"|" ./Cargo.toml
        sed -i -e "s|OriginalFilename = \"rustdesk.exe\"|OriginalFilename = \"$FILENAME.exe\"|" ./Cargo.toml
        sed -i -e "s|description = \"RustDesk Remote Desktop\"|description = \"$APPNAME\"|" ./libs/portable/Cargo.toml
        sed -i -e "s|ProductName = \"RustDesk\"|ProductName = \"$APPNAME\"|" ./libs/portable/Cargo.toml
        sed -i -e "s|FileDescription = \"RustDesk Remote Desktop\"|FileDescription = \"$APPNAME\"|" ./libs/portable/Cargo.toml
        sed -i -e "s|OriginalFilename = \"rustdesk.exe\"|OriginalFilename = \"$FILENAME.exe\"|" ./libs/portable/Cargo.toml
        sed -i -e "s|\"RustDesk Remote Desktop\"|\"$APPNAME\"|" ./flutter/windows/runner/Runner.rc
        sed -i -e "s|VALUE \"InternalName\", \"rustdesk\" \"\\\\0\"|VALUE \"InternalName\", \"$APPNAME\" \"\\\\0\"|" ./flutter/windows/runner/Runner.rc
        sed -i -e "s|\"rustdesk.exe\"|\"$FILENAME.exe\"|" ./flutter/windows/runner/Runner.rc
        sed -i -e "s|\"RustDesk\"|\"$APPNAME\"|" ./flutter/windows/runner/Runner.rc
        # Fix registry for app names with spaces
        if echo "$APPNAME" | grep -q " "; then
            sed -i -e 's|reg add {}|reg add \\\"{}\\\"|' ./src/platform/windows.rs
            sed -i -e 's|reg add HKEY_CLASSES_ROOT\\\\.{ext} /f|reg add \\\"HKEY_CLASSES_ROOT\\\\.{ext}\\\" /f|' ./src/platform/windows.rs
        fi
        # Update language files
        find ./src/lang -name "*.rs" -exec sed -i -e "s|RustDesk|$APPNAME|" {} \;
    fi

    # --- Apply custom company name ---
    if [ "$COMPNAME" != "Purslane Ltd" ]; then
        log "=== Changing company name to $COMPNAME ==="
        git checkout -- ./flutter/lib/desktop/pages/desktop_setting_page.dart ./res/msi/preprocess.py ./flutter/windows/runner/Runner.rc ./Cargo.toml ./libs/portable/Cargo.toml 2>/dev/null || true
        git checkout -- ./res/setup.nsi 2>/dev/null || true
        sed -i -e "s|Purslane Ltd|$COMPNAME|" ./flutter/lib/desktop/pages/desktop_setting_page.dart
        [ -f ./res/setup.nsi ] && sed -i -e "s|Purslane Ltd.|$COMPNAME|" ./res/setup.nsi || true
        [ -f ./res/msi/preprocess.py ] && sed -i -e "s|PURSLANE|$COMPNAME|" ./res/msi/preprocess.py || true
        [ -f ./res/msi/preprocess.py ] && sed -i -e "s|Purslane Ltd|$COMPNAME|" ./res/msi/preprocess.py || true
        sed -i -e "s|Purslane Ltd|$COMPNAME|" ./flutter/windows/runner/Runner.rc
        sed -i -e "s|Purslane Ltd|$COMPNAME|" ./Cargo.toml
        sed -i -e "s|Purslane Ltd|$COMPNAME|" ./libs/portable/Cargo.toml
    fi

    # --- Set server, key, and API server ---
    log "=== Setting server and key ==="
    git checkout -- ./src/common.rs ./src/lang/en.rs 2>/dev/null || true
    (cd ./libs/hbb_common && git checkout -- src/config.rs 2>/dev/null) || true
    sed -i -e "s|rs-ny.rustdesk.com|$RENDEZVOUS_SERVER|" ./libs/hbb_common/src/config.rs
    sed -i -e "s|OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=|$RS_PUB_KEY|" ./libs/hbb_common/src/config.rs
    sed -i -e 's|For faster connection, please set up your own server||' ./src/lang/en.rs
    sed -i -e '/const KEY:/,/};/d' ./src/common.rs
    sed -i -e '/let Ok(data) = sign::verify(&data, &pk)/,/};/d' ./src/common.rs
    sed -i -e "s|https://admin.rustdesk.com|$API_SERVER|" ./src/common.rs

    # --- Allow custom.txt (skip custom client signature check) ---
    log "=== Applying allowCustom patch ==="
    # Upstream allowCustom.py currently has merge-conflict markers — do not run it.
    # Prefer the .diff; fall back to in-place comment-out of the KEY verify block.
    wget -q https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/allowCustom.diff -O allowCustom.diff || true
    if [ -f allowCustom.diff ] && git apply --whitespace=nowarn allowCustom.diff 2>/dev/null; then
        log "=== allowCustom.diff applied ==="
    elif [ -f allowCustom.diff ] && git apply --3way --whitespace=nowarn allowCustom.diff 2>/dev/null; then
        log "=== allowCustom.diff applied (3-way) ==="
    else
        # Comment out custom-client KEY verification in read_custom_client (1.4.x)
        $PYTHON - <<'PY' || warn "allowCustom inline patch failed"
from pathlib import Path
p = Path("src/common.rs")
text = p.read_text(encoding="utf-8", errors="replace")
old = '''    const KEY: &str = "5Qbwsde3unUcJBtrx9ZkvUmwFNoExHzpryHuPUdqlWM=";
    let Some(pk) = get_rs_pk(KEY) else {
        log::error!("Failed to parse public key of custom client");
        return;
    };
    let Ok(data) = sign::verify(&data, &pk) else {
        log::error!("Failed to dec custom client config");
        return;
    };'''
new = '''    // const KEY: &str = "5Qbwsde3unUcJBtrx9ZkvUmwFNoExHzpryHuPUdqlWM=";
    // let Some(pk) = get_rs_pk(KEY) else {
    //     log::error!("Failed to parse public key of custom client");
    //     return;
    // };
    // let Ok(data) = sign::verify(&data, &pk) else {
    //     log::error!("Failed to dec custom client config");
    //     return;
    // };'''
if old in text:
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    print("allowCustom: commented KEY verify block")
elif "sign::verify(&data, &pk)" not in text or "Failed to parse public key of custom client" not in text:
    print("allowCustom: KEY verify already removed/applied")
else:
    print("allowCustom: pattern not found exactly — check src/common.rs manually")
PY
    fi
    wget -q https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/removeSetupServerTip.diff -O removeSetupServerTip.diff
    git apply --whitespace=nowarn removeSetupServerTip.diff 2>/dev/null || warn "removeSetupServerTip.diff failed"

    # --- Create custom.txt ---
    log "=== Creating custom.txt ==="
    if [ -n "$CUSTOM_B64" ]; then
        echo "$CUSTOM_B64" | base64 -d > ./custom.txt
    fi

    # --- Apply custom icon ---
    if [ "$ICON_URL" != "false" ]; then
        log "=== Applying custom icon ==="
        git checkout -- ./res/icon.ico ./res/icon.png ./res/tray-icon.ico ./res/32x32.png ./res/64x64.png ./res/128x128.png ./res/128x128@2x.png 2>/dev/null || true
        if [[ "$ICON_URL" == http* ]]; then
            wget -O ./res/icon.png "$ICON_URL"
        else
            cp "$ICON_URL" ./res/icon.png
        fi
        magick ./res/icon.png -define icon:auto-resize=256,64,48,32,16 ./res/icon.ico
        cp ./res/icon.ico ./res/tray-icon.ico
        magick ./res/icon.png -resize 32x32 ./res/32x32.png
        magick ./res/icon.png -resize 64x64 ./res/64x64.png
        magick ./res/icon.png -resize 128x128 ./res/128x128.png
        magick ./res/128x128.png -resize 200% ./res/128x128@2x.png
        # Replace embedded icon in ui.rs
        if [ -f "./src/ui.rs" ]; then
            cp ./src/ui.rs ./src/ui.rs.bak
            b64=$(base64 -w0 < ./res/icon.png 2>/dev/null || base64 < ./res/icon.png | tr -d '\n')
            sed -i -e "s|iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHL.*|$b64|" ./src/ui.rs 2>/dev/null || true
        fi
    fi

    # --- Apply custom logo ---
    if [ "$LOGO_URL" != "false" ]; then
        log "=== Applying custom logo ==="
        if [[ "$LOGO_URL" == http* ]]; then
            wget -O ./flutter/assets/logo.png "$LOGO_URL"
        else
            cp "$LOGO_URL" ./flutter/assets/logo.png
        fi
    fi

    # --- Optional patches ---
    if [ "$DELAY_FIX" == "true" ]; then
        log "=== Applying delay fix ==="
        git checkout -- ./src/client.rs 2>/dev/null || true
        sed -i -e 's|if !key.is_empty() && !token.is_empty()|if false /* Connection delay fix applied */|' ./src/client.rs
    fi

    if [ "$CYCLE_MONITOR" == "true" ]; then
        log "=== Applying cycle monitor patch ==="
        wget -q https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/cycle_monitor.diff
        git apply cycle_monitor.diff || warn "cycle_monitor.diff failed"
    fi

    if [ "$X_OFFLINE" == "true" ]; then
        log "=== Applying X offline patch ==="
        wget -q https://raw.githubusercontent.com/VenimK/creator/refs/heads/master/.github/patches/xoffline.diff
        git apply xoffline.diff || warn "xoffline.diff failed"
    fi

    if [ "$HIDE_CM" == "true" ]; then
        log "=== Applying hide-cm patch ==="
        git checkout -- flutter/lib/models/server_model.dart flutter/lib/main.dart flutter/lib/desktop/pages/desktop_setting_page.dart 2>/dev/null || true
        if [ -f "flutter/lib/models/server_model.dart" ]; then
            sed -i 's/bool hideCm = false;/bool _hideCm = false;/' flutter/lib/models/server_model.dart
            sed -i '/bool get clipboardOk => _clipboardOk;/a \
              bool get hideCm => _hideCm;\
              ' flutter/lib/models/server_model.dart
            sed -i 's/\/\*//g' flutter/lib/models/server_model.dart
            sed -i 's/\*\///g' flutter/lib/models/server_model.dart
        fi
        if [ -f "flutter/lib/main.dart" ]; then
            sed -i 's/gFFI.serverModel.hideCm = hide;/\/\/ gFFI.serverModel.hideCm = hide;/' flutter/lib/main.dart
        fi
        if [ -f "flutter/lib/desktop/pages/desktop_setting_page.dart" ]; then
            sed -i "s/\/\/ if (usePassword)/if (usePassword)/" flutter/lib/desktop/pages/desktop_setting_page.dart
            sed -i "s/\/\/   hide_cm(!locked).marginOnly(left: _kContentHSubMargin - 6),/  hide_cm(!locked).marginOnly(left: _kContentHSubMargin - 6),/" flutter/lib/desktop/pages/desktop_setting_page.dart
        fi
    fi

    if [ "$REMOVE_NEW_VERSION_NOTIF" == "true" ]; then
        log "=== Removing new version notification ==="
        git checkout -- ./flutter/lib/desktop/pages/desktop_home_page.dart ./src/common.rs 2>/dev/null || true
        sed -i -e 's|updateUrl.isNotEmpty|false|' ./flutter/lib/desktop/pages/desktop_home_page.dart
        sed -i '/let (request, url) =/,/Ok(())/{/Ok(())/!d}' ./src/common.rs
    fi

    if [ "$DISABLE_SETTINGS" == "true" ]; then
        log "=== Disabling settings UI ==="
        # Upstream disableSettings.diff is a corrupt placeholder — apply via sed
        local home_dart="./flutter/lib/desktop/pages/desktop_home_page.dart"
        local settings_dart="./flutter/lib/desktop/pages/desktop_setting_page.dart"
        if [ -f "$home_dart" ]; then
            # Prefer bind.isDisableSettings() if already present; else stub settings entry points
            if grep -q 'bind.isDisableSettings' "$home_dart" 2>/dev/null; then
                log "=== desktop_home_page already has isDisableSettings hooks ==="
            else
                # custom.txt disable-settings is handled by RustDesk if isDisableSettings works;
                # also force-hide the settings gear when method exists in generated bridge
                sed -i 's/updateUrl.isNotEmpty/false/' "$home_dart" 2>/dev/null || true
            fi
        fi
        if [ -f "$settings_dart" ]; then
            # Prepend early return in build() when possible via custom flag already in custom.txt
            if ! grep -q 'SETTINGS COMPLETELY DISABLED BY CUSTOM BUILD' "$settings_dart" 2>/dev/null; then
                $PYTHON - <<'PY' || warn "disableSettings inline patch failed"
from pathlib import Path
p = Path("flutter/lib/desktop/pages/desktop_setting_page.dart")
if not p.exists():
    raise SystemExit(0)
text = p.read_text(encoding="utf-8", errors="replace")
needle = "  Widget build(BuildContext context) {"
# find first build method in State class
idx = text.find(needle)
if idx < 0:
    needle = "  Widget build(BuildContext context) {"
    idx = text.find("Widget build(BuildContext context)")
if idx >= 0:
    # insert after opening brace of build
    brace = text.find("{", idx)
    if brace > 0 and "SETTINGS COMPLETELY DISABLED BY CUSTOM BUILD" not in text:
        insert = """
    // SETTINGS COMPLETELY DISABLED BY CUSTOM BUILD
    if (bind.isDisableSettings()) {
      return const Scaffold(body: Center(child: Text('Settings have been disabled by administrator')));
    }
"""
        text = text[: brace + 1] + insert + text[brace + 1 :]
        p.write_text(text, encoding="utf-8")
        print("disableSettings: patched desktop_setting_page.dart")
    else:
        print("disableSettings: could not locate build() brace")
else:
    print("disableSettings: build() not found")
PY
            fi
        fi
        # custom.txt already has disable-settings=Y from config loader when settingsN
    fi

    # --- Replace flutter launcher icons ---
    if [ "$ICON_URL" != "false" ]; then
        log "=== Running flutter_launcher_icons ==="
        cd ./flutter
        flutter pub get
        flutter pub run flutter_launcher_icons 2>/dev/null || dart run flutter_launcher_icons 2>/dev/null || warn "flutter_launcher_icons failed"
        cd ..
    fi

    # Force scrap/hwcodec to regenerate bindgen output with current LIBCLANG/rustfmt
    # - stale/opaque scrap bindings → "no field g_w"
    # - empty hwcodec ffi (bad rustfmt shim) → "no DataFormat in common"
    if [ -d ./target ]; then
        log "=== Cleaning scrap+hwcodec build artifacts for fresh bindgen ==="
        cargo clean -p scrap -p hwcodec 2>/dev/null \
            || rm -rf ./target/release/build/scrap-* ./target/release/build/hwcodec-* 2>/dev/null \
            || true
    fi
    # Also wipe any cached hwcodec OUT_DIR under cargo registry (git checkout builds)
    rm -rf "$HOME/.cargo/git/checkouts"/hwcodec-*/target 2>/dev/null || true

    # --- Replace Flutter engine with RustDesk custom engine ---
    log "=== Replacing Flutter engine with RustDesk custom engine ==="
    flutter precache --windows 2>/dev/null || true
    local engine_dir=""
    # Find the Flutter engine cache directory
    local flutter_bin=$(which flutter 2>/dev/null)
    if [ -n "$flutter_bin" ]; then
        local flutter_root=$(dirname "$(dirname "$flutter_bin")")
        engine_dir="$flutter_root/bin/cache/artifacts/engine/windows-x64-release"
    fi
    if [ -n "$engine_dir" ] && [ -d "$engine_dir" ]; then
        wget -q https://github.com/rustdesk/engine/releases/download/main/windows-x64-release.zip -O windows-x64-release.zip
        if [ -f windows-x64-release.zip ]; then
            unzip -o windows-x64-release.zip -d windows-x64-release 2>/dev/null || true
            cp -rf windows-x64-release/* "$engine_dir/" 2>/dev/null || true
            rm -rf windows-x64-release windows-x64-release.zip
            log "=== Flutter engine replaced ==="
        else
            warn "Failed to download RustDesk custom Flutter engine"
        fi
    else
        warn "Flutter engine cache directory not found, skipping engine replacement"
    fi

    # --- Build RustDesk ---
    log "=== Building RustDesk (this takes several minutes) ==="
    $PYTHON ./build.py --portable --hwcodec --flutter --skip-portable-pack || { err "build.py failed"; exit 1; }

    # Move Release output
    mv ./flutter/build/windows/x64/runner/Release ./rustdesk 2>/dev/null || { err "Build output not found"; exit 1; }

    # Download usbmmidd_v2
    log "=== Downloading usbmmidd_v2 ==="
    wget -q https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip -O usbmmidd_v2.zip
    unzip -o usbmmidd_v2.zip -d . 2>/dev/null || true
    rm -rf ./usbmmidd_v2/Win32 2>/dev/null || true
    rm -f ./usbmmidd_v2/deviceinstaller64.exe ./usbmmidd_v2/deviceinstaller.exe ./usbmmidd_v2/usbmmidd.bat 2>/dev/null || true
    mv -f ./usbmmidd_v2 ./rustdesk/ 2>/dev/null || true

    # Download printer driver
    log "=== Downloading printer driver ==="
    wget -q https://github.com/rustdesk/hbb_common/releases/download/driver/rustdesk_printer_driver_v4-1.4.zip -O rustdesk_printer_driver_v4-1.4.zip 2>/dev/null || true
    wget -q https://github.com/rustdesk/hbb_common/releases/download/driver/printer_driver_adapter.zip -O printer_driver_adapter.zip 2>/dev/null || true
    if [ -f rustdesk_printer_driver_v4-1.4.zip ]; then
        unzip -o rustdesk_printer_driver_v4-1.4.zip -d . 2>/dev/null || true
        mkdir -p ./rustdesk/drivers
        mv -f ./rustdesk_printer_driver_v4-1.4 ./rustdesk/drivers/RustDeskPrinterDriver 2>/dev/null || true
        unzip -o printer_driver_adapter.zip -d . 2>/dev/null || true
        mv -f ./printer_driver_adapter.dll ./rustdesk/ 2>/dev/null || true
    fi

    # Apply logo to built output
    if [ "$LOGO_URL" != "false" ]; then
        log "=== Applying logo to build output ==="
        if [[ "$LOGO_URL" == http* ]]; then
            wget -O ./rustdesk/data/flutter_assets/assets/logo.png "$LOGO_URL"
        else
            cp "$LOGO_URL" ./rustdesk/data/flutter_assets/assets/logo.png
        fi
    fi

    # Apply icon to built output
    if [ "$ICON_URL" != "false" ]; then
        log "=== Applying icon to build output ==="
        mv ./rustdesk/data/flutter_assets/assets/icon.svg ./rustdesk/data/flutter_assets/assets/icon.svg.bak 2>/dev/null || true
        magick ./res/icon.png ./rustdesk/data/flutter_assets/assets/icon.svg 2>/dev/null || true
    fi

    # Find and copy Runner.res
    log "=== Finding Runner.res ==="
    runner_res=$(find . -name "Runner.res" 2>/dev/null | head -1)
    if [ -n "$runner_res" ]; then
        cp "$runner_res" ./libs/portable/Runner.res
        log "Runner.res copied"
    else
        warn "Runner.res not found"
    fi

    # Create custom.txt in build output
    log "=== Creating custom.txt in build output ==="
    mkdir -p ./rustdesk
    if [ -n "$CUSTOM_B64" ]; then
        echo "$CUSTOM_B64" | base64 -d > ./rustdesk/custom.txt
    fi

    # --- Build self-extracted executable ---
    log "=== Building portable executable ==="
    # Prefer space-free name for the inner exe when possible; keep display APPNAME elsewhere
    local pack_exe_name="$FILENAME.exe"
    if [ -f "./rustdesk/rustdesk.exe" ]; then
        mv "./rustdesk/rustdesk.exe" "./rustdesk/$pack_exe_name"
    elif [ -f "./rustdesk/$APPNAME.exe" ]; then
        pack_exe_name="$APPNAME.exe"
    elif [ -f "./rustdesk/$FILENAME.exe" ]; then
        pack_exe_name="$FILENAME.exe"
    else
        # Fallback: first .exe in rustdesk output dir
        local found_exe
        found_exe=$(find ./rustdesk -maxdepth 1 -name '*.exe' 2>/dev/null | head -1)
        if [ -n "$found_exe" ]; then
            pack_exe_name="$(basename "$found_exe")"
        else
            warn "No rustdesk.exe in ./rustdesk/ — portable pack may fail"
        fi
    fi
    log "=== Packing entry exe: $pack_exe_name ==="
    sed -i '/dpiAware/d' res/manifest.xml 2>/dev/null || true
    pushd ./libs/portable >/dev/null
    pip3 install -r requirements.txt 2>/dev/null || pip install -r requirements.txt 2>/dev/null || true
    $PYTHON ./generate.py -f ../../rustdesk/ -o . -e "../../rustdesk/$pack_exe_name" || warn "Portable packer generate.py failed"
    popd >/dev/null

    mkdir -p ./SignOutput
    # Packer binary location depends on workspace vs crate-local target
    local packer_bin=""
    for p in \
        "./libs/portable/target/release/rustdesk-portable-packer.exe" \
        "./target/release/rustdesk-portable-packer.exe" \
        "./libs/portable/target/release/rustdesk-portable-packer" \
        "./target/release/rustdesk-portable-packer"; do
        if [ -f "$p" ]; then
            packer_bin="$p"
            break
        fi
    done
    if [ -z "$packer_bin" ]; then
        packer_bin=$(find ./libs/portable/target ./target -name 'rustdesk-portable-packer.exe' 2>/dev/null | head -1)
    fi
    if [ -n "$packer_bin" ] && [ -f "$packer_bin" ]; then
        cp -f "$packer_bin" "./SignOutput/${FILENAME}.exe"
        log "=== Portable EXE: ./SignOutput/${FILENAME}.exe (from $packer_bin) ==="
    else
        warn "Portable packer binary not found — copying unpackaged build as fallback"
        if [ -f "./rustdesk/$pack_exe_name" ]; then
            cp -f "./rustdesk/$pack_exe_name" "./SignOutput/${FILENAME}.exe"
            log "=== Fallback EXE copied (not self-extracting portable) ==="
        else
            warn "No EXE produced"
        fi
    fi

    # --- Build MSI (optional, may fail without WiX) ---
    log "=== Building MSI ==="
    if [ -d ./res/msi ]; then
        pushd ./res/msi >/dev/null
        $PYTHON preprocess.py --arp -d ../../rustdesk --version "$RUSTDESK_VERSION" 2>/dev/null || warn "preprocess.py failed"
        if [ ! -f "./Package/Config.wxi" ]; then
            log "Creating Config.wxi manually..."
            mkdir -p ./Package
            local product_lower
            product_lower=$(echo "$FILENAME" | tr '[:upper:]' '[:lower:]')
            cat > ./Package/Config.wxi << WXIEOF
<?xml version="1.0" encoding="utf-8"?>
<Include>
  <?define Version="$RUSTDESK_VERSION" ?>
  <?define Product="$APPNAME" ?>
  <?define Description="$APPNAME Remote Desktop" ?>
  <?define Manufacturer="$COMPNAME" ?>
  <?define ProductLower="$product_lower" ?>
  <?define RegKeyRoot="Software\\$APPNAME" ?>
  <?define BuildDir="../../rustdesk" ?>
  <?define UpgradeCode="{59C1BC08-0A9A-4A72-8BD4-7B28BD03C00A}" ?>
</Include>
WXIEOF
        fi
        nuget restore msi.sln 2>/dev/null || warn "nuget restore failed (MSI optional)"
        msbuild msi.sln -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10 2>/dev/null || warn "MSI build failed (optional — need WiX/MSBuild)"
        if [ -f "./Package/bin/x64/Release/en-us/Package.msi" ]; then
            mkdir -p ../../SignOutput
            cp -f ./Package/bin/x64/Release/en-us/Package.msi "../../SignOutput/${FILENAME}.msi"
            log "=== MSI build successful ==="
        else
            warn "MSI file was not generated (optional)"
        fi
        popd >/dev/null
    else
        warn "MSI directory not found, skipping MSI"
    fi

    # --- Move output files ---
    log "=== Moving output files ==="
    mkdir -p "$WIN_OUTPUT"
    local copied=0
    if ls ./SignOutput/*.exe >/dev/null 2>&1; then
        cp -f ./SignOutput/*.exe "$WIN_OUTPUT/" && copied=1
        log "=== EXE copied to $WIN_OUTPUT ==="
        ls -lh ./SignOutput/*.exe
    else
        warn "No EXE in SignOutput"
    fi
    if ls ./SignOutput/*.msi >/dev/null 2>&1; then
        cp -f ./SignOutput/*.msi "$WIN_OUTPUT/" && copied=1
        log "=== MSI copied to $WIN_OUTPUT ==="
    fi
    # Also keep a copy of the unpackaged Release folder for debugging
    if [ -d ./rustdesk ] && [ "$copied" -eq 0 ]; then
        warn "Packaging incomplete — rustdesk/ folder still at $(pwd)/rustdesk"
    fi

    # --- Upload to server ---
    if [ "$UPLOAD_TO_SERVER" == "true" ] && [ -n "$UPLOAD_TOKEN" ]; then
        log "=== Uploading to server ==="
        for f in "$WIN_OUTPUT"/*.exe "$WIN_OUTPUT"/*.msi; do
            if [ -f "$f" ]; then
                curl -i -X POST \
                    -H "Content-Type: multipart/form-data" \
                    -H "Authorization: Bearer $UPLOAD_TOKEN" \
                    -F "file=@$f" \
                    -F "uuid=$UPLOAD_UUID" \
                    "$UPLOAD_URL/save_custom_client" || warn "Upload of $(basename $f) failed"
            fi
        done
    fi

    local END_TIME=$(date +%s)
    local TOTAL=$(( END_TIME - START_TIME ))
    log "=== Windows build complete in $(( TOTAL / 60 )) min $(( TOTAL % 60 )) sec ==="
    log "=== Output files in $WIN_OUTPUT/ ==="
    if ls "$WIN_OUTPUT"/*.{exe,msi} >/dev/null 2>&1 || ls "$WIN_OUTPUT"/*.exe >/dev/null 2>&1; then
        ls -lh "$WIN_OUTPUT"/*.exe "$WIN_OUTPUT"/*.msi 2>/dev/null || ls -lh "$WIN_OUTPUT"/*.exe 2>/dev/null
        log "=== SUCCESS: custom Windows client is ready ==="
    else
        warn "No output files found in $WIN_OUTPUT"
    fi
}

# ============================ CONFIG LOADER ============================
# Load settings from a web UI JSON file (same format as creator.nas86.eu exports)
# Usage: ./buildlocal.sh --config MusicloverAndroid.json build-android
load_config() {
    local CONFIG_FILE="$1"
    if [ ! -f "$CONFIG_FILE" ]; then
        err "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    log "=== Loading config from $CONFIG_FILE ==="

    # Write Python parser to temp file to avoid heredoc-in-eval quoting issues
    local PY_SCRIPT=$(mktemp /tmp/buildlocal_config.XXXXXX.py)
    cat > "$PY_SCRIPT" << 'PYEOF'
import json, sys, base64, os, tempfile

with open(sys.argv[1]) as f:
    d = json.load(f)

def q(val):
    """Quote a value for shell assignment."""
    return str(val).replace('"', '\\"')

def b(val):
    """Convert boolean/on to true/false string."""
    if val == "on" or val is True:
        return "true"
    return "false"

# --- Shell variables ---
print('RUSTDESK_VERSION="' + q(d.get("version", "1.4.9")) + '"')
print('RENDEZVOUS_SERVER="' + q(d.get("serverIP", "rs-ny.rustdesk.com")) + '"')
print('RS_PUB_KEY="' + q(d.get("key", "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=")) + '"')

api = d.get("apiServer", "")
if not api:
    api = d.get("serverIP", "") + ":21114"
print('API_SERVER="' + q(api) + '"')

appname = d.get("appname", d.get("exename", "RustDesk"))
print('APPNAME="' + q(appname) + '"')
print('FILENAME="' + q(d.get("exename", appname)) + '"')
print('COMPNAME="' + q(d.get("compname", "")) + '"')

# Android app ID
androidappid = d.get("androidappid", "")
if androidappid:
    print('ANDROID_APP_ID="' + q(androidappid) + '"')

# Boolean flags
print('DELAY_FIX="' + b(d.get("delayFix", False)) + '"')
print('CYCLE_MONITOR="' + b(d.get("cycleMonitor", False)) + '"')
print('X_OFFLINE="' + b(d.get("xOffline", False)) + '"')

hidecm = d.get("hidecm", False)
print('HIDE_CM="' + b(hidecm) + '"')

print('REMOVE_NEW_VERSION_NOTIF="' + b(d.get("removeNewVersionNotif", False)) + '"')

settings = d.get("settings", "settingsY")
print('DISABLE_SETTINGS="' + ("true" if settings == "settingsN" else "false") + '"')

# --- Icon handling ---
# Use forward slashes so Git Bash eval/log never mangles \a \b \t in Windows paths
def shell_path(p):
    return p.replace("\\", "/")

iconfile = d.get("iconfile", "") or d.get("iconbase64", "")
if iconfile and iconfile.startswith("data:image"):
    header, b64data = iconfile.split(",", 1)
    icon_path = os.path.join(tempfile.gettempdir(), "buildlocal_icon.png")
    with open(icon_path, "wb") as f:
        f.write(base64.b64decode(b64data))
    print('ICON_URL="' + shell_path(icon_path) + '"')
else:
    print('ICON_URL="false"')

logofile = d.get("logofile", "") or d.get("logobase64", "")
if logofile and logofile.startswith("data:image"):
    header, b64data = logofile.split(",", 1)
    logo_path = os.path.join(tempfile.gettempdir(), "buildlocal_logo.png")
    with open(logo_path, "wb") as f:
        f.write(base64.b64decode(b64data))
    print('LOGO_URL="' + shell_path(logo_path) + '"')
else:
    print('LOGO_URL="false"')

# --- Generate custom.txt JSON (mirrors views.py) ---
custom = {}

direction = d.get("direction", "both")
if direction != "both" and direction != "Both":
    custom['conn-type'] = direction.lower()

installation = d.get("installation", "installationY")
if installation == "installationN":
    custom['disable-installation'] = 'Y'

if settings == "settingsN":
    custom['disable-settings'] = 'Y'

if appname.upper() != "RUSTDESK" and appname:
    custom['app-name'] = appname

custom['override-settings'] = {}
custom['default-settings'] = {}

permPass = d.get("permanentPassword", "")
if permPass:
    custom['password'] = permPass

theme = d.get("theme", "system")
themeDorO = d.get("themeDorO", "default")
platform = d.get("platform", "")
if theme != "system":
    if themeDorO == "default":
        if platform == "windows-x86":
            custom['default-settings']['allow-darktheme'] = 'Y' if theme == "dark" else 'N'
        else:
            custom['default-settings']['theme'] = theme
    elif themeDorO == "override":
        if platform == "windows-x86":
            custom['override-settings']['allow-darktheme'] = 'Y' if theme == "dark" else 'N'
        else:
            custom['override-settings']['theme'] = theme

denyLan = d.get("denyLan", False)
custom['enable-lan-discovery'] = 'N' if denyLan else 'Y'

autoClose = d.get("autoClose", False)
custom['allow-auto-disconnect'] = 'Y' if autoClose else 'N'

permissionsDorO = d.get("permissionsDorO", "default")
permissionsType = d.get("permissionsType", "custom")
passApproveMode = d.get("passApproveMode", "password-click")
enableDirectIP = d.get("enableDirectIP", False)
removeWallpaper = d.get("removeWallpaper", False)
enablePrinter = d.get("enablePrinter", False)
enableCamera = d.get("enableCamera", False)
enableTerminal = d.get("enableTerminal", False)

# Map enable* fields
perm_fields = {
    'enable-keyboard': d.get("enableKeyboard", False),
    'enable-clipboard': d.get("enableClipboard", False),
    'enable-file-transfer': d.get("enableFileTransfer", False),
    'enable-audio': d.get("enableAudio", False),
    'enable-tunnel': d.get("enableTCP", False),
    'enable-remote-restart': d.get("enableRemoteRestart", False),
    'enable-record-session': d.get("enableRecording", False),
    'enable-block-input': d.get("enableBlockingInput", False),
    'allow-remote-config-modification': d.get("enableRemoteModi", False),
    'direct-server': enableDirectIP,
    'verification-method': 'use-permanent-password' if hidecm else 'use-both-passwords',
    'approve-mode': passApproveMode,
    'allow-hide-cm': 'Y' if hidecm else 'N',
    'allow-remove-wallpaper': 'Y' if removeWallpaper else 'N',
    'enable-remote-printer': 'Y' if enablePrinter else 'N',
    'enable-camera': 'Y' if enableCamera else 'N',
    'enable-terminal': 'Y' if enableTerminal else 'N',
}

target = custom['default-settings'] if permissionsDorO == "default" else custom['override-settings']
target['access-mode'] = permissionsType
for k, v in perm_fields.items():
    if k in ('verification-method', 'approve-mode'):
        target[k] = v
    elif isinstance(v, bool):
        target[k] = 'Y' if v else 'N'
    else:
        target[k] = v

# Manual override lines
defaultManual = d.get("defaultManual", "")
for line in defaultManual.splitlines():
    line = line.strip()
    if not line or '=' not in line:
        continue
    k, value = line.split('=', 1)
    custom['default-settings'][k.strip()] = value.strip()

overrideManual = d.get("overrideManual", "")
for line in overrideManual.splitlines():
    line = line.strip()
    if not line or '=' not in line:
        continue
    k, value = line.split('=', 1)
    custom['override-settings'][k.strip()] = value.strip()

# Base64 encode
custom_json = json.dumps(custom)
custom_b64 = base64.b64encode(custom_json.encode("ascii")).decode("ascii")
print('CUSTOM_B64="' + custom_b64 + '"')
PYEOF

    # Run Python parser and eval the output as shell variable assignments
    eval "$($PYTHON "$PY_SCRIPT" "$CONFIG_FILE")"
    rm -f "$PY_SCRIPT"

    log "=== Config loaded: APPNAME=$APPNAME, VERSION=$RUSTDESK_VERSION, SERVER=$RENDEZVOUS_SERVER ==="
    log "=== Icon: $ICON_URL, Logo: $LOGO_URL ==="
}

# ============================ MAIN =============================
# Parse --config flag
CONFIG_FILE=""
if [ "${1:-}" == "--config" ]; then
    CONFIG_FILE="$2"
    shift 2
fi

if [ -n "$CONFIG_FILE" ]; then
    load_config "$CONFIG_FILE"
fi

case "${1:-build}" in
    setup)
        setup
        ;;
    build)
        build
        ;;
    rebuild)
        rebuild
        ;;
    setup-android)
        setup_android
        ;;
    build-android)
        build_android
        ;;
    build-android-aarch64)
        local_ORIG_TARGETS="$ANDROID_TARGETS"
        ANDROID_TARGETS="aarch64"
        build_android
        ANDROID_TARGETS="$local_ORIG_TARGETS"
        ;;
    build-android-armv7)
        local_ORIG_TARGETS="$ANDROID_TARGETS"
        ANDROID_TARGETS="armv7"
        build_android
        ANDROID_TARGETS="$local_ORIG_TARGETS"
        ;;
    build-android-x86_64)
        local_ORIG_TARGETS="$ANDROID_TARGETS"
        ANDROID_TARGETS="x86_64"
        build_android
        ANDROID_TARGETS="$local_ORIG_TARGETS"
        ;;
    build-android-all)
        ANDROID_TARGETS="aarch64 armv7 x86_64"
        build_android
        ;;
    setup-macos)
        setup_macos
        ;;
    build-macos)
        build_macos
        ;;
    setup-windows)
        setup_windows
        ;;
    build-windows)
        build_windows
        ;;
    *)
        echo "Usage: $0 [--config FILE.json] {setup|build|rebuild|setup-android|build-android|setup-macos|build-macos|setup-windows|build-windows}"
        echo ""
        echo "  --config FILE  - Load all settings from a web UI JSON file (same format as creator.nas86.eu)"
        echo "                    Overrides all CONFIG section variables. Place before the command."
        echo ""
        echo "  setup          - Install all Linux dependencies (run once)"
        echo "  build          - Full Linux build: deb + rpm + AppImage"
        echo "  rebuild        - Quick repackage with new custom.txt/name only"
        echo "  setup-android  - Install Android SDK/NDK + JDK + Rust targets"
        echo "  build-android  - Build APK for configured ANDROID_TARGETS (default: all)
  build-android-aarch64 - Build APK for arm64 only
  build-android-armv7   - Build APK for armv7 only
  build-android-x86_64  - Build APK for x86_64 only
  build-android-all     - Build APK for all targets"
        echo "  setup-macos    - Install macOS build deps via brew (run on Mac)"
        echo "  build-macos    - Build DMG for configured MACOS_TARGETS (run on Mac)"
        echo "  setup-windows  - Install Windows build deps via choco (run on Windows with Git Bash)"
        echo "  build-windows  - Build EXE + MSI (run on Windows with Git Bash)"
        echo ""
        echo "  Examples:"
        echo "    $0 --config MusicloverAndroid.json build-android"
        echo "    $0 --config MusicloverMacOS.json build-macos"
        echo "    $0 --config MusicloverWindows.json build-windows"
        echo "    $0 --config MySettings.json build"
        exit 1
        ;;
esac

