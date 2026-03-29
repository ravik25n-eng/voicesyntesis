<#
.SYNOPSIS
    Start the VoiceSyntesis application silently in the background.
.DESCRIPTION
    Starts Ollama (if not running), then launches the FastAPI backend which
    also serves the pre-built React frontend at http://localhost:8000.
    Runs entirely hidden -- no console window is shown.
    This script is invoked by launch.bat -- run that instead of this directly.
#>

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $AppDir

$logFile = Join-Path $AppDir "voicesyntesis.log"

function Log { param($m) Add-Content -Path $logFile -Value "[$(Get-Date -Format 'HH:mm:ss')] $m" -ErrorAction SilentlyContinue }

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

# Suppress HuggingFace symlink warning
$env:HF_HUB_DISABLE_SYMLINKS_WARNING = "1"

# -- Verify virtual environment exists ----------------------------------------
$venvPython = Join-Path $AppDir ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    Log "ERROR: Virtual environment not found at $AppDir\.venv"
    exit 1
}

# -- Start Ollama service (if not already running) ----------------------------
$ollamaRunning = Get-Process ollama -ErrorAction SilentlyContinue
if (-not $ollamaRunning) {
    Log "Starting Ollama service ..."
    $ollamaExe = if (Test-Path $ollamaLocalExe) { $ollamaLocalExe } else { "ollama" }
    Start-Process $ollamaExe -ArgumentList "serve" -WindowStyle Hidden

    $ready = $false
    for ($i = 0; $i -lt 8; $i++) {
        Start-Sleep -Seconds 2
        try {
            Invoke-WebRequest -Uri "http://localhost:11434/api/tags" `
                -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop | Out-Null
            $ready = $true; break
        } catch {}
    }
    if ($ready) { Log "Ollama ready." }
    else         { Log "WARNING: Ollama did not respond -- transcript correction may not work." }
} else {
    Log "Ollama already running."
}

# -- Check if port 8000 is already occupied -----------------------------------
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect("127.0.0.1", 8000)
    $tcp.Close()
    Log "Port 8000 already in use -- VoiceSyntesis already running."
    exit 0
} catch {}

# -- Launch uvicorn hidden, with output redirected to log ---------------------
$env:OLLAMA_HOST = "http://localhost:11434"

Log "Starting VoiceSyntesis backend ..."

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $venvPython
$psi.Arguments = "-m uvicorn main:app --host 127.0.0.1 --port 8000 --app-dir `"$AppDir\backend`""
$psi.WorkingDirectory = $AppDir
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
$psi.EnvironmentVariables["OLLAMA_HOST"] = "http://localhost:11434"
$psi.EnvironmentVariables["COQUI_TOS_AGREED"] = "1"

$proc = [System.Diagnostics.Process]::Start($psi)

# Async-redirect stdout and stderr to the log file
$null = $proc.StandardOutput.BaseStream
$null = $proc.StandardError.BaseStream

$proc.BeginOutputReadLine()
$proc.BeginErrorReadLine()

$proc | Add-Member -MemberType ScriptMethod -Name HandleOutput -Value {
    param($s)
    if ($s) { Add-Content -Path $logFile -Value $s -ErrorAction SilentlyContinue }
}

$proc.add_OutputDataReceived({ param($s, $e) if ($e.Data) { Add-Content -Path $Using:logFile -Value $e.Data -ErrorAction SilentlyContinue } })
$proc.add_ErrorDataReceived({ param($s, $e) if ($e.Data) { Add-Content -Path $Using:logFile -Value $e.Data -ErrorAction SilentlyContinue } })

Log "Backend process started (PID $($proc.Id))."

Err "VoiceSyntesis backend has stopped. Close this window."
Read-Host "Press Enter to close"

