# RustDesk Custom Builder - Windows Bootstrap Script
# Run this FIRST in PowerShell as Administrator before using buildlocal.sh
# This installs Chocolatey and Git (which includes Git Bash)
#
# Usage: Right-click → Run with PowerShell (as Administrator)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RustDesk Custom Builder - Windows Bootstrap" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Check Administrator ---
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Write-Host "Right-click PowerShell → 'Run as Administrator'" -ForegroundColor Yellow
    Write-Host "Then run: .\setup-windows.ps1" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# --- Install Chocolatey ---
Write-Host "[1/3] Checking Chocolatey..." -ForegroundColor Yellow
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Host "  Chocolatey is already installed." -ForegroundColor Green
} else {
    Write-Host "  Installing Chocolatey..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    try {
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Host "  Chocolatey installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "  ERROR: Failed to install Chocolatey." -ForegroundColor Red
        Write-Host "  Please install manually from: https://chocolatey.org/install" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Refresh PATH for current session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# --- Install Git (includes Git Bash) ---
Write-Host ""
Write-Host "[2/3] Checking Git for Windows (includes Git Bash)..." -ForegroundColor Yellow
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "  Git is already installed." -ForegroundColor Green
} else {
    Write-Host "  Installing Git for Windows..." -ForegroundColor Yellow
    choco install -y git --no-progress
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to install Git." -ForegroundColor Red
        Write-Host "  Please install manually from: https://git-scm.com/download/win" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "  Git installed successfully." -ForegroundColor Green
}

# Refresh PATH again
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# --- Verify Git Bash exists ---
Write-Host ""
Write-Host "[3/3] Verifying Git Bash installation..." -ForegroundColor Yellow
$gitBashPath = "C:\Program Files\Git\bin\bash.exe"
if (-not (Test-Path $gitBashPath)) {
    $gitBashPath = "C:\Program Files (x86)\Git\bin\bash.exe"
}
if (-not (Test-Path $gitBashPath)) {
    # Try to find it via git --exec-path
    $gitPath = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($gitPath) {
        $gitDir = Split-Path (Split-Path $gitPath)
        $gitBashPath = Join-Path $gitDir "bin\bash.exe"
    }
}

if (Test-Path $gitBashPath) {
    Write-Host "  Git Bash found at: $gitBashPath" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Could not locate bash.exe automatically." -ForegroundColor Yellow
    Write-Host "  Git Bash should still be available via Start Menu." -ForegroundColor Yellow
    $gitBashPath = "Git Bash (via Start Menu)"
}

# --- Done ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Bootstrap Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host ""
Write-Host "  1. Open Git Bash (from Start Menu or: $gitBashPath)" -ForegroundColor White
Write-Host "  2. Navigate to the creator folder:" -ForegroundColor White
Write-Host "     cd /c/path/to/creator" -ForegroundColor Gray
Write-Host "  3. Run the full setup:" -ForegroundColor White
Write-Host "     ./buildlocal.sh setup-windows" -ForegroundColor Gray
Write-Host "  4. Build with your config:" -ForegroundColor White
Write-Host "     ./buildlocal.sh --config MusicloverWindows.json build-windows" -ForegroundColor Gray
Write-Host ""
Write-Host "Note: setup-windows will install the remaining dependencies" -ForegroundColor DarkGray
Write-Host "      (Rust, Flutter, vcpkg, LLVM, ImageMagick, VS Build Tools)" -ForegroundColor DarkGray
Write-Host ""
Read-Host "Press Enter to exit"
