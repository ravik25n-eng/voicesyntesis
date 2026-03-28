$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $AppDir

function Info { param($m) Write-Host "[VoiceModulation] $m" -ForegroundColor Green }

$ollamaRunning = Get-Process ollama -ErrorAction SilentlyContinue
if (-not $ollamaRunning) {
    Info "Starting Ollama..."
    Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

Info "Starting app — opening http://localhost:8000 in your browser..."
Start-Sleep -Seconds 1
Start-Process "http://localhost:8000"

& .\.venv\Scripts\Activate.ps1
$env:OLLAMA_HOST = "http://localhost:11434"
python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
