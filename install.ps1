# ─── Claude Multi-Account — One-line Installer (Windows) ─────────────────────
# irm https://raw.githubusercontent.com/ghackk/claude-multi-account/master/install.ps1 | iex

$ErrorActionPreference = "Stop"
$repo = "https://github.com/ghackk/claude-multi-account.git"
$installDir = "$HOME\claude-multi-account"

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Claude Multi-Account — Installer    " -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# ─── Download ────────────────────────────────────────────────────────────────

if (Test-Path "$installDir\.git") {
    Write-Host "Existing installation found. Updating..." -ForegroundColor Yellow
    git -C $installDir pull --quiet
    Write-Host "Updated!" -ForegroundColor Green
} elseif (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "Cloning repository..."
    git clone --quiet $repo $installDir
    Write-Host "Downloaded!" -ForegroundColor Green
} else {
    Write-Host "git not found — downloading as archive..."
    $zipUrl = "https://github.com/ghackk/claude-multi-account/archive/refs/heads/master.zip"
    $zipPath = "$env:TEMP\claude-multi-account.zip"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $HOME -Force
    if (Test-Path "$HOME\claude-multi-account-master") {
        if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
        Rename-Item "$HOME\claude-multi-account-master" $installDir
    }
    Remove-Item $zipPath -Force
    Write-Host "Downloaded!" -ForegroundColor Green
}

# ─── PATH integration ────────────────────────────────────────────────────────

$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*claude-multi-account*") {
    [Environment]::SetEnvironmentVariable("PATH", "$installDir;$currentPath", "User")
    $env:PATH = "$installDir;$env:PATH"
    Write-Host "Added to PATH" -ForegroundColor Green
} else {
    Write-Host "Already in PATH" -ForegroundColor DarkGray
}

# ─── Done ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "  Run " -NoNewline
Write-Host "claude-menu" -ForegroundColor Cyan -NoNewline
Write-Host " to start (open a new terminal first)"
Write-Host "  Update anytime: " -NoNewline
Write-Host "cd $installDir; git pull" -ForegroundColor DarkGray
Write-Host ""
