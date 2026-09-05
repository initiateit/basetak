# basetak build script: build (debug/release) with kill-if-running and env flags.
# Usage:
#   .\build.ps1              # debug build
#   .\build.ps1 -Release     # release build (LTO, codegen-units=1 from Cargo.toml)
#   .\build.ps1 -Tests       # run cargo test instead of building
#   .\build.ps1 -Clean       # clean before building
param(
    [switch]$Release,
    [switch]$Tests,
    [switch]$Clean,
    [switch]$NoKill   # skip killing a running instance
)

$ErrorActionPreference = 'Stop'
$exeName = 'basetak.exe'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

# --- Kill a running instance so the linker can overwrite the exe -------------
if (-not $NoKill) {
    $procs = Get-Process -Name 'basetak' -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "basetak is running (PID $($procs.Id -join ', ')) - killing..." -ForegroundColor Yellow
        $procs | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }
}

# --- Clean --------------------------------------------------------------------
if ($Clean) {
    Write-Host 'cargo clean...' -ForegroundColor Cyan
    cargo clean
}

# --- Build --------------------------------------------------------------------
$profileName = if ($Release) { 'release' } else { 'debug' }

# ENV flags for debug builds: backtraces on panic, no incremental-deps flakiness.
$env:RUST_BACKTRACE = '1'
$env:RUSTFLAGS = if ($Release) { $env:RUSTFLAGS } else { '-C debuginfo=1' }

if ($Tests) {
    Write-Host 'cargo test...' -ForegroundColor Cyan
    cargo test --all-targets
    if ($LASTEXITCODE -ne 0) { Write-Host 'TESTS FAILED' -ForegroundColor Red; exit 1 }
    Write-Host 'TESTS PASSED' -ForegroundColor Green
    exit 0
}

Write-Host "cargo build ($profileName)..." -ForegroundColor Cyan
if ($Release) {
    cargo build --release
} else {
    cargo build
}
if ($LASTEXITCODE -ne 0) { Write-Host 'BUILD FAILED' -ForegroundColor Red; exit 1 }

$exe = Join-Path $projectRoot "target\$profileName\$exeName"
if (-not (Test-Path $exe)) { Write-Host "expected binary not found: $exe" -ForegroundColor Red; exit 1 }

$size = [math]::Round((Get-Item $exe).Length / 1KB, 1)
Write-Host "BUILD OK: $exe (${size} KB)" -ForegroundColor Green
