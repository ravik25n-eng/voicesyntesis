# ─────────────────────────────────────────────────────────────────────────────
# VoiceModulation — Start all services (Windows)
# Run: .\start.ps1
# Close this window (or press Ctrl+C) to stop everything.
# ─────────────────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Stop"

function Info { param($msg) Write-Host "[start] $msg" -ForegroundColor Green }
function Warn { param($msg) Write-Host "[warn]  $msg" -ForegroundColor Yellow }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# ── Sanity checks ─────────────────────────────────────────────────────────────
if (-not (Test-Path ".venv")) {
    Write-Host "[error] .venv not found. Run setup.ps1 first." -ForegroundColor Red; exit 1
}
if (-not (Test-Path "frontend\node_modules")) {
    Write-Host "[error] frontend\node_modules not found. Run setup.ps1 first." -ForegroundColor Red; exit 1
}

$Jobs = @()

function Stop-AllJobs {
    Info "Shutting down…"
    foreach ($job in $Jobs) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
    # Stop Ollama if we started it
    Get-Process ollama -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Info "Done. Bye!"
}

# ── 1. Ollama ─────────────────────────────────────────────────────────────────
$ollamaRunning = Get-Process ollama -ErrorAction SilentlyContinue
if ($ollamaRunning) {
    Info "Ollama already running"
} else {
    Info "Starting Ollama…"
    Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

# ── 2. Backend (FastAPI) ───────────────────────────────────────────────────────
Info "Starting backend (FastAPI on port 8000)…"
$backendJob = Start-Job -ScriptBlock {
    param($dir)
    Set-Location $dir
    & .\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 127.0.0.1 --port 8000 2>&1 |
        ForEach-Object { "[backend] $_" }
} -ArgumentList $ScriptDir
$Jobs += $backendJob
Start-Sleep -Seconds 3

# ── 3. Frontend (Vite) ────────────────────────────────────────────────────────
Info "Starting frontend (Vite on port 5173)…"
$frontendJob = Start-Job -ScriptBlock {
    param($dir)
    Set-Location (Join-Path $dir "frontend")
    npm run dev -- --host 127.0.0.1 2>&1 |
        ForEach-Object { "[frontend] $_" }
} -ArgumentList $ScriptDir
$Jobs += $frontendJob
Start-Sleep -Seconds 3

# ── Ready ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "All services running.  Close this window or press Ctrl+C to stop." -ForegroundColor Green
Write-Host ""
Write-Host "  App      ->  http://localhost:5173" -ForegroundColor Cyan
Write-Host "  API docs ->  http://localhost:8000/docs" -ForegroundColor Cyan
Write-Host "  Ollama   ->  http://localhost:11434" -ForegroundColor Cyan
Write-Host ""

# Stream output from background jobs and keep alive until Ctrl+C
try {
    while ($true) {
        foreach ($job in $Jobs) {
            $output = Receive-Job $job -ErrorAction SilentlyContinue
            if ($output) { $output | ForEach-Object { Write-Host $_ } }

            if ($job.State -eq "Failed") {
                Warn "A background job failed. Check the output above."
            }
        }
        Start-Sleep -Milliseconds 500
    }
} finally {
    Stop-AllJobs
}
