<#
.SYNOPSIS
    Start the VoiceSyntesis application.
.DESCRIPTION
    Starts Ollama (if not running), then launches the FastAPI backend which
    also serves the pre-built React frontend at http://localhost:8000.
    This script is invoked by launch.bat — run that instead of this directly.
#>

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $AppDir
$Host.UI.RawUI.WindowTitle = "VoiceSyntesis"

function Info { param($m) Write-Host "[VoiceSyntesis] $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "[VoiceSyntesis] WARNING: $m" -ForegroundColor Yellow }
function Err  { param($m) Write-Host "[VoiceSyntesis] ERROR: $m" -ForegroundColor Red }

# ── Add app-local tools (ffmpeg, ffprobe) to PATH ────────────────────────────
$toolsDir = Join-Path $AppDir "tools"
if ((Test-Path $toolsDir) -and ($env:Path -notlike "*$toolsDir*")) {
    $env:Path = "$toolsDir;$env:Path"
}

# ── Add Ollama to PATH if installed per-user ──────────────────────────────────
$ollamaLocalExe = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
if ((Test-Path $ollamaLocalExe) -and ($env:Path -notlike "*Programs\Ollama*")) {
    $env:Path = "$env:LOCALAPPDATA\Programs\Ollama;$env:Path"
}

# ── Verify virtual environment exists ────────────────────────────────────────
$venvPython = Join-Path $AppDir ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    Err "Virtual environment not found at: $AppDir\.venv"
    Err "Please re-run the installer or run install_deps.ps1 manually."
    Read-Host "Press Enter to close"
    exit 1
}

# ── Start Ollama service (if not already running) ─────────────────────────────
$ollamaRunning = Get-Process ollama -ErrorAction SilentlyContinue
if ($ollamaRunning) {
    Info "Ollama is already running."
} else {
    Info "Starting Ollama service ..."
    $ollamaExe = if (Test-Path $ollamaLocalExe) { $ollamaLocalExe } else { "ollama" }
    Start-Process $ollamaExe -ArgumentList "serve" -WindowStyle Hidden

    # Wait up to 16 seconds for Ollama API to become ready
    $ready = $false
    for ($i = 0; $i -lt 8; $i++) {
        Start-Sleep -Seconds 2
        try {
            Invoke-WebRequest -Uri "http://localhost:11434/api/tags" `
                -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop | Out-Null
            $ready = $true; break
        } catch {}
    }
    if ($ready) { Info "Ollama is ready." }
    else         { Warn "Ollama did not respond — transcript correction may not work." }
}

# ── Check if port 8000 is already occupied ────────────────────────────────────
$portInUse = $false
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect("127.0.0.1", 8000)
    $portInUse = $true
    $tcp.Close()
} catch {}

if ($portInUse) {
    Warn "Port 8000 is already in use — opening the existing instance."
    Start-Process "http://localhost:8000"
    exit 0
}

# ── Launch backend (serves app + pre-built frontend) ─────────────────────────
$env:OLLAMA_HOST = "http://localhost:11434"

Info "Starting VoiceSyntesis at http://localhost:8000 ..."
Start-Sleep -Seconds 1
Start-Process "http://localhost:8000"

# Keep uvicorn running in this window so the user can see logs / close the app
& $venvPython -m uvicorn backend.main:app --host 127.0.0.1 --port 8000

