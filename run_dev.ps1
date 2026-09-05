# basetak dev runner: starts the already-built binary from the repo root so
# config.toml / style.css resolve. Its only job is: kill any running instance,
# then launch. Build first with .\build.ps1 (debug or -Release).
# Usage:
#   .\run_dev.ps1            # run the debug build
#   .\run_dev.ps1 -Release   # run the release build
param(
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
$exeName = 'basetak.exe'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$profileName = if ($Release) { 'release' } else { 'debug' }
$exe = Join-Path $projectRoot "target\$profileName\$exeName"

if (-not (Test-Path $exe)) {
    Write-Host "binary not found: $exe - build first with .\build.ps1" -ForegroundColor Red
    exit 1
}

# --- Kill existing instance ---------------------------------------------------
$procs = Get-Process -Name 'basetak' -ErrorAction SilentlyContinue
if ($procs) {
    Write-Host "basetak already running (PID $($procs.Id -join ', ')) - restarting..." -ForegroundColor Yellow
    $procs | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

# --- Run -----------------------------------------------------------------------
Write-Host "running $exe (cwd: $projectRoot)..." -ForegroundColor Green
$env:RUST_BACKTRACE = '1'
# Start via Start-Process so the console returns immediately and the bar owns
# its own process (Ctrl+C here won't kill it; use taskkill or re-run).
Start-Process -FilePath $exe -WorkingDirectory $projectRoot
Start-Sleep -Milliseconds 800
$running = Get-Process -Name 'basetak' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "basetak running (PID $($running.Id -join ', '))" -ForegroundColor Green
} else {
    Write-Host 'basetak exited immediately - check stderr output above' -ForegroundColor Red
    exit 1
}
