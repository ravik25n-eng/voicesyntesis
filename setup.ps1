# ─────────────────────────────────────────────────────────────────────────────
# VoiceModulation — First-time setup for Windows
# Run once from PowerShell (as your normal user, NOT Administrator):
#   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
#   .\setup.ps1
# ─────────────────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Stop"

function Info    { param($msg) Write-Host "[setup] $msg" -ForegroundColor Green }
function Warn    { param($msg) Write-Host "[warn]  $msg" -ForegroundColor Yellow }
function Section { param($msg) Write-Host "`n── $msg ──" -ForegroundColor Cyan }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# ── 1. Require winget ────────────────────────────────────────────────────────
Section "Checking winget"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "[error] winget not found." -ForegroundColor Red
    Write-Host "        Open the Microsoft Store, install 'App Installer', then re-run this script."
    exit 1
}
Info "winget found"

# ── 2. Install system dependencies via winget ─────────────────────────────────
Section "Installing Python 3.11, Node.js, ffmpeg, Ollama"

$packages = @(
    @{ Id = "Python.Python.3.11";  Name = "Python 3.11" },
    @{ Id = "OpenJS.NodeJS.LTS";   Name = "Node.js LTS" },
    @{ Id = "Gyan.FFmpeg";         Name = "ffmpeg" },
    @{ Id = "Ollama.Ollama";       Name = "Ollama" }
)

foreach ($pkg in $packages) {
    $installed = winget list --id $pkg.Id 2>$null | Select-String $pkg.Id
    if ($installed) {
        Info "$($pkg.Name) already installed"
    } else {
        Info "Installing $($pkg.Name)…"
        winget install --id $pkg.Id --silent --accept-package-agreements --accept-source-agreements
    }
}

# Refresh PATH so newly installed tools are available in this session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# ── 3. Python virtual environment ─────────────────────────────────────────────
Section "Python virtual environment"
if (-not (Test-Path ".venv")) {
    python -m venv .venv
    Info "Created .venv"
} else {
    Info ".venv already exists — skipping creation"
}

& .\.venv\Scripts\Activate.ps1

Section "Python dependencies"
python -m pip install --upgrade pip -q

# PyTorch: detect NVIDIA GPU and install CUDA build if available, else CPU build
Section "Detecting GPU for PyTorch"
$hasCuda = $false
try {
    $nvidiaSmi = Get-Command "nvidia-smi" -ErrorAction SilentlyContinue
    if ($nvidiaSmi) {
        $hasCuda = $true
        Warn "NVIDIA GPU detected — installing PyTorch with CUDA 12.1 support"
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 -q
    }
} catch {}

if (-not $hasCuda) {
    Info "No NVIDIA GPU detected — installing PyTorch CPU build"
    Info "(Synthesis will work but will be slow. Expected ~5-15 min per clip on CPU.)"
    pip install torch torchvision torchaudio -q
}

# Install remaining requirements (torch is already installed above, it will be skipped)
pip install -r backend/requirements.txt

# ── 4. Frontend dependencies ─────────────────────────────────────────────────
Section "Frontend dependencies (npm install)"
Set-Location frontend
npm install
Set-Location $ScriptDir

# ── 5. Pull Ollama model ──────────────────────────────────────────────────────
Section "Pulling Ollama model (mistral — ~4 GB, first-time only)"
Info "Starting Ollama temporarily for model download…"
$ollamaProc = Start-Process ollama -ArgumentList "serve" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3

ollama pull mistral

Stop-Process -Id $ollamaProc.Id -Force -ErrorAction SilentlyContinue

# ── 5. Download ML models ────────────────────────────────────────────────────
Section "Downloading ML models (Whisper ~3 GB + F5-TTS ~1.5 GB)"
Info "This may take 10-20 minutes on the first run…"
python backend\download_models.py

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Start the app any time with:  .\start.ps1"
Write-Host ""
