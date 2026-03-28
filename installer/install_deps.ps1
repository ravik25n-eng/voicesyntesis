param(
    [string]$InstallDir,
    [switch]$DownloadModels
)

$ErrorActionPreference = "Stop"
Set-Location $InstallDir

function Info    { param($m) Write-Host "[install] $m" -ForegroundColor Green }
function Section { param($m) Write-Host "`n== $m ==" -ForegroundColor Cyan }

$logFile = Join-Path $InstallDir "install.log"
Start-Transcript -Path $logFile -Append | Out-Null

Section "System dependencies"
$packages = @(
    @{ Id = "Python.Python.3.11"; Name = "Python 3.11" },
    @{ Id = "Gyan.FFmpeg";        Name = "ffmpeg" },
    @{ Id = "Ollama.Ollama";      Name = "Ollama" }
)
foreach ($pkg in $packages) {
    $installed = winget list --id $pkg.Id 2>$null | Select-String $pkg.Id
    if ($installed) {
        Info "$($pkg.Name) already installed"
    } else {
        Info "Installing $($pkg.Name)..."
        winget install --id $pkg.Id --silent --accept-package-agreements --accept-source-agreements
    }
}

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

Section "Python virtual environment"
python -m venv .venv
& .\.venv\Scripts\Activate.ps1

Section "Python packages"
python -m pip install --upgrade pip -q

$hasCuda = Get-Command "nvidia-smi" -ErrorAction SilentlyContinue
if ($hasCuda) {
    Info "NVIDIA GPU detected — installing PyTorch CUDA build"
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 -q
} else {
    Info "No GPU detected — installing PyTorch CPU build (synthesis will be slower)"
    pip install torch torchvision torchaudio -q
}

pip install -r backend\requirements.txt

Section "Ollama model (mistral)"
$ollamaProc = Start-Process ollama -ArgumentList "serve" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
ollama pull mistral
Stop-Process -Id $ollamaProc.Id -Force -ErrorAction SilentlyContinue

if ($DownloadModels) {
    Section "AI Models — Whisper + F5-TTS (~4.5 GB)"
    python backend\download_models.py
}

Stop-Transcript | Out-Null
Write-Host "`nInstallation complete." -ForegroundColor Green
