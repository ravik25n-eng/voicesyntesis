<#
.SYNOPSIS
    Build the VoiceSyntesis Windows installer (.exe).

.DESCRIPTION
    Run this script on your developer machine to produce VoiceSyntesis-Setup.exe.

    Steps performed:
      1. Checks that Node.js and Inno Setup 6 are installed.
      2. Runs  npm install + npm run build  inside  frontend/  to produce
         frontend/dist/ (the pre-built static React files bundled into the installer).
      3. Compiles  installer/setup.iss  with ISCC.exe to produce
         installer/dist/VoiceSyntesis-Setup.exe.

.REQUIREMENTS
    - Node.js 18+  : https://nodejs.org  (only needed on the BUILD machine)
    - Inno Setup 6 : https://jrsoftware.org/isdl.php  (free, install with defaults)

.EXAMPLE
    cd d:\voice_project\voicesyntesis
    .\installer\build_installer.ps1
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir

function Info  { param($m) Write-Host "[build] $m"          -ForegroundColor Green }
function Step  { param($m) Write-Host "`n[build] ── $m ──"   -ForegroundColor Cyan  }
function Abort { param($m) Write-Host "[build] ERROR: $m"   -ForegroundColor Red; exit 1 }

Step "Checking prerequisites"

# ── Node.js ──────────────────────────────────────────────────────────────────
# Node.js is needed on THIS (developer) machine to build the React frontend.
# The installer also installs Node.js on the target machine automatically.
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Abort "Node.js not found.`nInstall it from https://nodejs.org then re-run this script."
}
Info "Node.js : $(node --version)"
Info "npm     : $(npm --version)"

# ── Inno Setup 6 ─────────────────────────────────────────────────────────────
$isccExe = $null
$isccCandidates = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
)
# Also check if ISCC is on PATH (e.g. via scoop or chocolatey)
$isccOnPath = Get-Command ISCC -ErrorAction SilentlyContinue
if ($isccOnPath) { $isccCandidates = @($isccOnPath.Source) + $isccCandidates }

foreach ($p in $isccCandidates) {
    if (Test-Path $p) { $isccExe = $p; break }
}
if (-not $isccExe) {
    Abort "Inno Setup 6 not found.`nDownload the installer from https://jrsoftware.org/isdl.php, install it, then re-run."
}
Info "ISCC    : $isccExe"

# ── 1. Build frontend ─────────────────────────────────────────────────────────
Step "Building React frontend"

$frontendDir = Join-Path $RootDir "frontend"
Set-Location $frontendDir

Info "npm install ..."
npm install
if ($LASTEXITCODE -ne 0) { Abort "npm install failed." }

Info "npm run build ..."
npm run build
if ($LASTEXITCODE -ne 0) { Abort "npm run build failed." }

$distPath = Join-Path $frontendDir "dist"
if (-not (Test-Path $distPath)) { Abort "frontend\dist not found after build." }
$distCount = (Get-ChildItem $distPath -Recurse -File).Count
Info "Frontend built: $distCount files in frontend\dist\"

# ── 2. Compile Inno Setup script ─────────────────────────────────────────────
Step "Compiling Inno Setup installer"

Set-Location $ScriptDir

# Ensure output dir exists (ISCC creates it, but be explicit)
$outDir = Join-Path $ScriptDir "dist"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Info "Running ISCC ..."
& $isccExe "setup.iss"
if ($LASTEXITCODE -ne 0) { Abort "ISCC compilation failed (exit code $LASTEXITCODE)." }

$exePath = Join-Path $outDir "VoiceSyntesis-Setup.exe"
if (-not (Test-Path $exePath)) { Abort "Installer not found at expected path: $exePath" }

$sizeMB = [math]::Round((Get-Item $exePath).Length / 1MB, 1)

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║   VoiceSyntesis-Setup.exe is ready!                          ║" -ForegroundColor Green
Write-Host "  ║                                                              ║" -ForegroundColor Green
Write-Host "  ║   Location : installer\dist\VoiceSyntesis-Setup.exe         ║" -ForegroundColor Green
Write-Host "  ║   Size     : ${sizeMB} MB                                         ║" -ForegroundColor Green
Write-Host "  ║                                                              ║" -ForegroundColor Green
Write-Host "  ║   Copy this file to any Windows 10/11 PC and run it.        ║" -ForegroundColor Green
Write-Host "  ║   The installer downloads all dependencies automatically.    ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
