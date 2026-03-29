<#
.SYNOPSIS
    Start the VoiceSyntesis application.
.DESCRIPTION
    Starts Ollama (if not running), then launches the FastAPI backend which
    also serves the pre-built React frontend at http://localhost:8000.
    This script is invoked by launch.bat -- run that instead of this directly.
#>

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $AppDir
$Host.UI.RawUI.WindowTitle = "VoiceSyntesis"

# Suppress HuggingFace symlink warning on Windows (cache works fine without symlinks)
$env:HF_HUB_DISABLE_SYMLINKS_WARNING = "1"

function Info { param($m) Write-Host "[VoiceSyntesis] $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "[VoiceSyntesis] WARNING: $m" -ForegroundColor Yellow }
function Err  { param($m) Write-Host "[VoiceSyntesis] ERROR: $m" -ForegroundColor Red }

# -- Add app-local tools (ffmpeg, ffprobe) to PATH ---------------------------
$toolsDir = Join-Path $AppDir "tools"
if ((Test-Path $toolsDir) -and ($env:Path -notlike "*$toolsDir*")) {
    $env:Path = "$toolsDir;$env:Path"
}

# -- Add Ollama to PATH if installed per-user ---------------------------------
$ollamaLocalExe = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
if ((Test-Path $ollamaLocalExe) -and ($env:Path -notlike "*Programs\Ollama*")) {
    $env:Path = "$env:LOCALAPPDATA\Programs\Ollama;$env:Path"
}

# -- Verify virtual environment exists ----------------------------------------
$venvPython = Join-Path $AppDir ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    Err "Virtual environment not found at: $AppDir\.venv"
    Err "Please re-run the installer or run install_deps.ps1 manually."
    Read-Host "Press Enter to close"
    exit 1
}

# -- Start Ollama service (if not already running) ----------------------------
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
    else         { Warn "Ollama did not respond -- transcript correction may not work." }
}

# -- Check if port 8000 is already occupied -----------------------------------
$portInUse = $false
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect("127.0.0.1", 8000)
    $portInUse = $true
    $tcp.Close()
} catch {}

if ($portInUse) {
    Info "Port 8000 is already in use -- VoiceSyntesis is already running."
    exit 0
}

# -- Launch backend in background, wait for it to be ready, then open browser -
$env:OLLAMA_HOST = "http://localhost:11434"

Info "Starting VoiceSyntesis backend ..."

# Start uvicorn as a background job so we can poll for readiness
$uvicornJob = Start-Job -ScriptBlock {
    param($python, $appDir)
    Set-Location $appDir
    & $python -m uvicorn main:app --host 127.0.0.1 --port 8000 --app-dir "$appDir\backend"
} -ArgumentList $venvPython, $AppDir

# Poll port 8000 until the backend is accepting connections (up to 30 s)
$backendReady = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 2
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect("127.0.0.1", 8000)
        $tcp.Close()
        $backendReady = $true
        break
    } catch {}
}

if ($backendReady) {
    Info "Backend ready at http://localhost:8000"
} else {
    Warn "Backend did not respond after 30 seconds."
    Warn "Check this window for error messages. You can try http://localhost:8000 manually."
}

Info "VoiceSyntesis is running. Close this window to stop the app."

# Stream job output to this window so the user can see backend logs
while ($true) {
    $out = Receive-Job -Job $uvicornJob 2>&1
    if ($out) { Write-Host $out }
    if ($uvicornJob.State -in @("Completed", "Failed", "Stopped")) { break }
    Start-Sleep -Seconds 1
}

Err "VoiceSyntesis backend has stopped. Close this window."
Read-Host "Press Enter to close"

