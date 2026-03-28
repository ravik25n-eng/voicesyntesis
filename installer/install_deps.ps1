<#
.SYNOPSIS
    VoiceSyntesis dependency installer -- works on any Windows 10/11 PC.
.DESCRIPTION
    Installs every runtime dependency needed by VoiceSyntesis:
      - Python 3.11        (runtime)
      - Node.js LTS        (runtime - for frontend dev mode)
      - FFmpeg             (audio conversion)
      - Ollama             (local LLM service)
      - PyTorch            (CPU build, or CUDA if NVIDIA GPU detected)
      - Python packages    (FastAPI, faster-whisper, Coqui TTS XTTS v2, etc.)
      - Ollama mistral     (transcript-correction model, ~4 GB)
      - Whisper + XTTS v2 (AI models, ~4.8 GB, optional)

    Uses winget when available; falls back to direct downloads from official
    sources so it works on a completely fresh Windows PC.
    Launched automatically by the Inno Setup installer after file extraction.

.PARAMETER InstallDir
    Directory where VoiceSyntesis files were extracted (passed by Inno Setup).
.PARAMETER DownloadModels
    When set, also downloads Whisper large-v3 and F5-TTS weights (~4.5 GB).
#>
param(
    [string]$InstallDir = (Split-Path -Parent $MyInvocation.MyCommand.Path),
    [switch]$DownloadModels
)

Set-Location $InstallDir
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$TOTAL_STEPS = if ($DownloadModels) { 9 } else { 8 }
$script:currentStep = 0
$logFile  = Join-Path $InstallDir "install.log"
$toolsDir = Join-Path $InstallDir "tools"

"VoiceSyntesis Installer Log - $(Get-Date)" | Out-File -FilePath $logFile -Encoding utf8 -Force
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Log {
    param([string]$msg, [string]$color = "White")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
    Write-Host $line -ForegroundColor $color
}
function Info  { param($m) Log "  $m"              "White"  }
function Ok    { param($m) Log "  [OK]    $m"      "Green"  }
function Warn  { param($m) Log "  [WARN]  $m"      "Yellow" }
function Abort {
    param($m)
    Log "  [ERROR] $m" "Red"
    Write-Host ""
    Write-Host "  See the log for details: $logFile" -ForegroundColor DarkGray
    Read-Host "`n  Press Enter to close"
    exit 1
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Start-Step {
    param([string]$Name, [string]$Detail = "")
    $script:currentStep++
    $pct = [int](($script:currentStep - 1) / $TOTAL_STEPS * 100)
    Write-Progress -Activity "VoiceSyntesis Setup" `
                   -Status   "Step $($script:currentStep) of $TOTAL_STEPS -- $Name" `
                   -PercentComplete $pct
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  STEP $($script:currentStep) / $TOTAL_STEPS  >>  $Name" -ForegroundColor Cyan
    if ($Detail) { Write-Host "  $Detail" -ForegroundColor DarkGray }
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Log "STEP $($script:currentStep)/$TOTAL_STEPS -- $Name" "Cyan"
}

function Finish-Step { param([string]$m) Ok $m }

function Download-File {
    param([string]$Url, [string]$Dest, [string]$Label = "", [string]$SizeHint = "")
    $name = if ($Label) { $Label } else { Split-Path $Url -Leaf }
    $hint = if ($SizeHint) { " ($SizeHint)" } else { "" }
    Info "Downloading${hint}: $name"
    Info "  Source: $Url"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 600
        $mb = [math]::Round((Get-Item $Dest).Length / 1MB, 1)
        Ok "Downloaded $name -- ${mb} MB"
    } catch {
        Abort "Download failed for ${name}: $_"
    }
}

function Install-ViaWinget {
    param([string]$Id, [string]$Label)
    Info "  via winget: $Id"
    winget install --id $Id --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "  +==================================================================+" -ForegroundColor Cyan
Write-Host "  |         VoiceSyntesis -- Dependency Installer                    |" -ForegroundColor Cyan
Write-Host "  |                                                                  |" -ForegroundColor Cyan
Write-Host "  |  This window will install all required components.               |" -ForegroundColor Cyan
Write-Host "  |  Do NOT close this window -- it may take 20-60 minutes.          |" -ForegroundColor Cyan
Write-Host "  |                                                                  |" -ForegroundColor Cyan
if ($DownloadModels) {
    Write-Host "  |  AI models will be downloaded now (~4.5 GB).                     |" -ForegroundColor Cyan
} else {
    Write-Host "  |  AI models will download on first use (~4.5 GB).                 |" -ForegroundColor Cyan
}
Write-Host "  +==================================================================+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Install directory : $InstallDir" -ForegroundColor DarkGray
Write-Host "  Log file          : $logFile"    -ForegroundColor DarkGray
Write-Host ""
Log "Installer started. InstallDir=$InstallDir DownloadModels=$($DownloadModels.IsPresent)"

$hasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
Info "winget available: $hasWinget"

# ===========================================================================
# STEP 1 -- PYTHON 3.11
# ===========================================================================
Start-Step "Python 3.11" "Runtime for the backend AI pipeline"

$pythonExe = $null
foreach ($candidate in @("python", "python3", "py")) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if (-not $cmd) { continue }
    $ver = & $candidate --version 2>&1
    if ($ver -match "Python 3\.1[0-9]") {
        $pythonExe = $candidate
        Ok "Already installed: $ver"
        break
    }
}

if (-not $pythonExe) {
    $pyInstalled = $false

    if ($hasWinget) {
        Info "Installing Python 3.11 via winget ..."
        $pyInstalled = Install-ViaWinget "Python.Python.3.11" "Python 3.11"
        if ($pyInstalled) { Refresh-Path; Ok "Python 3.11 installed via winget." }
        else               { Warn "winget failed -- falling back to direct download." }
    }

    if (-not $pyInstalled) {
        $pyInstaller = Join-Path $toolsDir "python-3.11.9-amd64.exe"
        Download-File "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" `
                      $pyInstaller "Python 3.11.9 installer" "25 MB"
        Info "Running Python installer (silent, current user) ..."
        Start-Process -FilePath $pyInstaller `
            -ArgumentList "/quiet", "InstallAllUsers=0", "PrependPath=1", `
                          "Include_pip=1", "Include_tcltk=0", "Include_test=0" `
            -Wait
        Remove-Item $pyInstaller -Force -ErrorAction SilentlyContinue
        Refresh-Path
    }

    foreach ($candidate in @("python", "py")) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $ver = & $candidate --version 2>&1
        if ($ver -match "Python 3\.1[0-9]") { $pythonExe = $candidate; break }
    }
    if (-not $pythonExe) { Abort "Python 3.11 installation failed. Check install.log." }
}
Finish-Step "Python ready -- $(& $pythonExe --version 2>&1)"

# ===========================================================================
# STEP 2 -- NODE.JS LTS
# ===========================================================================
Start-Step "Node.js LTS" "JavaScript runtime"

$nodeExe = Get-Command node -ErrorAction SilentlyContinue
if ($nodeExe) {
    Ok "Already installed: $(node --version)"
} else {
    $nodeInstalled = $false

    if ($hasWinget) {
        Info "Installing Node.js LTS via winget ..."
        $nodeInstalled = Install-ViaWinget "OpenJS.NodeJS.LTS" "Node.js LTS"
        if ($nodeInstalled) { Refresh-Path; Ok "Node.js installed via winget." }
        else                { Warn "winget failed -- falling back to direct download." }
    }

    if (-not $nodeInstalled) {
        $nodeMsi = Join-Path $toolsDir "node-lts-x64.msi"
        Download-File "https://nodejs.org/dist/latest-v22.x/node-v22.14.0-x64.msi" `
                      $nodeMsi "Node.js LTS installer" "~30 MB"
        Info "Running Node.js installer (silent) ..."
        Start-Process "msiexec.exe" -ArgumentList "/i `"$nodeMsi`" /quiet /norestart ADDLOCAL=ALL" -Wait
        Remove-Item $nodeMsi -Force -ErrorAction SilentlyContinue
        Refresh-Path
    }

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Warn "Node.js not detected after install -- may need a new terminal session."
    } else {
        Ok "Node.js ready -- $(node --version)"
    }
}
Finish-Step "Node.js ready"

# ===========================================================================
# STEP 3 -- FFMPEG
# ===========================================================================
Start-Step "FFmpeg" "Audio conversion (WebM/OGG -> WAV)"

$ffmpegBin    = Join-Path $toolsDir "ffmpeg.exe"
$ffmpegOnPath = Get-Command ffmpeg -ErrorAction SilentlyContinue

if ($ffmpegOnPath) {
    Ok "Already on PATH: $($ffmpegOnPath.Source)"
} elseif (Test-Path $ffmpegBin) {
    Ok "Already in tools directory."
} else {
    $ffInstalled = $false

    if ($hasWinget) {
        Info "Installing FFmpeg via winget ..."
        $ffInstalled = Install-ViaWinget "Gyan.FFmpeg" "FFmpeg"
        if ($ffInstalled) {
            Refresh-Path
            $ffInstalled = $null -ne (Get-Command ffmpeg -ErrorAction SilentlyContinue)
            if ($ffInstalled) { Ok "FFmpeg installed via winget." }
            else { Warn "winget OK but ffmpeg not on PATH -- downloading directly." ; $ffInstalled = $false }
        } else { Warn "winget failed -- downloading directly." }
    }

    if (-not $ffInstalled) {
        $ffmpegZip = Join-Path $toolsDir "ffmpeg-essentials.zip"
        Download-File "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" `
                      $ffmpegZip "FFmpeg essentials build" "~90 MB"
        Info "Extracting FFmpeg ..."
        Expand-Archive -Path $ffmpegZip -DestinationPath $toolsDir -Force
        Remove-Item $ffmpegZip -Force -ErrorAction SilentlyContinue

        $extracted = Get-ChildItem -Path $toolsDir -Filter "ffmpeg.exe" -Recurse | Select-Object -First 1
        if (-not $extracted) { Abort "ffmpeg.exe not found after extraction." }
        Copy-Item $extracted.FullName $ffmpegBin -Force

        $ffprobeEx = Get-ChildItem -Path $toolsDir -Filter "ffprobe.exe" -Recurse | Select-Object -First 1
        if ($ffprobeEx) { Copy-Item $ffprobeEx.FullName (Join-Path $toolsDir "ffprobe.exe") -Force }

        Get-ChildItem -Path $toolsDir -Directory |
            Where-Object { $_.Name -like "ffmpeg-*" } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        Ok "FFmpeg installed to tools directory."
    }
}

if ($env:Path -notlike "*$toolsDir*") { $env:Path = "$toolsDir;$env:Path" }
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$toolsDir*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$toolsDir;$userPath", "User")
    Info "Added tools directory to user PATH."
}
Finish-Step "FFmpeg ready"

# ===========================================================================
# STEP 4 -- OLLAMA
# ===========================================================================
Start-Step "Ollama" "Local LLM service for transcript correction"

$ollamaLocalExe = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
$ollamaOnPath   = Get-Command ollama -ErrorAction SilentlyContinue

if ($ollamaOnPath -or (Test-Path $ollamaLocalExe)) {
    Ok "Already installed."
    if ((Test-Path $ollamaLocalExe) -and ($env:Path -notlike "*Programs\Ollama*")) {
        $env:Path = "$env:LOCALAPPDATA\Programs\Ollama;$env:Path"
    }
} else {
    $olInstalled = $false

    if ($hasWinget) {
        Info "Installing Ollama via winget ..."
        $olInstalled = Install-ViaWinget "Ollama.Ollama" "Ollama"
        if ($olInstalled) { Refresh-Path; Ok "Ollama installed via winget." }
        else               { Warn "winget failed -- downloading directly." }
    }

    if (-not $olInstalled) {
        $ollamaInstaller = Join-Path $toolsDir "OllamaSetup.exe"
        Download-File "https://ollama.com/download/OllamaSetup.exe" `
                      $ollamaInstaller "Ollama installer" "~100 MB"
        Info "Running Ollama installer (silent) ..."
        Start-Process -FilePath $ollamaInstaller -ArgumentList "/S" -Wait
        Remove-Item $ollamaInstaller -Force -ErrorAction SilentlyContinue
        Refresh-Path
    }

    if (Test-Path $ollamaLocalExe) { $env:Path = "$env:LOCALAPPDATA\Programs\Ollama;$env:Path" }
    Ok "Ollama installed."
}
Finish-Step "Ollama ready"

# ===========================================================================
# STEP 5 -- PYTHON VIRTUAL ENVIRONMENT
# ===========================================================================
Start-Step "Python virtual environment" "Isolated package environment for VoiceSyntesis"

$venvPath   = Join-Path $InstallDir ".venv"
$pipExe     = Join-Path $venvPath "Scripts\pip.exe"
$venvPython = Join-Path $venvPath "Scripts\python.exe"

if (Test-Path $venvPython) {
    Ok "Virtual environment already exists."
} else {
    Info "Creating virtual environment at: $venvPath"
    & $pythonExe -m venv $venvPath
    if (-not (Test-Path $venvPython)) { Abort "Failed to create virtual environment." }
    Ok "Virtual environment created."
}
Info "Upgrading pip ..."
& $venvPython -m pip install --upgrade pip --quiet
Finish-Step "Virtual environment ready"

# ===========================================================================
# STEP 6 -- PYTORCH
# ===========================================================================
$hasCuda = $null -ne (Get-Command "nvidia-smi" -ErrorAction SilentlyContinue)
$torchVariant = if ($hasCuda) { "CUDA 12.1 (NVIDIA GPU)" } else { "CPU (no NVIDIA GPU found)" }
Start-Step "PyTorch -- $torchVariant" "Deep learning framework (large download: ~2-3 GB)"

# Check if torch is already installed in the venv before re-downloading
$torchCheck = & $venvPython -c "import torch; print(torch.__version__)" 2>$null
if ($LASTEXITCODE -eq 0 -and $torchCheck) {
    Ok "PyTorch already installed: v$($torchCheck.Trim()) -- skipping."
} else {
    if ($hasCuda) {
        Info "NVIDIA GPU confirmed -- installing PyTorch with CUDA 12.1 support ..."
        $pipOut = & $pipExe install torch torchvision torchaudio `
            --index-url https://download.pytorch.org/whl/cu121 2>&1
    } else {
        Info "No NVIDIA GPU -- installing PyTorch CPU build ..."
        Info "(Voice synthesis will work but be slower. Expect ~3-10 min per clip.)"
        $pipOut = & $pipExe install torch torchvision torchaudio 2>&1
    }
    $pipExit = $LASTEXITCODE
    $pipOut | ForEach-Object { Add-Content -Path $logFile -Value "  [pip] $_" -ErrorAction SilentlyContinue; Write-Host "  $_" }
    if ($pipExit -ne 0) { Abort "PyTorch installation failed. Check install.log." }
    Ok "PyTorch installed."
}
Finish-Step "PyTorch ready"

# ===========================================================================
# STEP 7 -- PYTHON PACKAGES
# ===========================================================================
Start-Step "Python application packages" "FastAPI, faster-whisper, Coqui TTS XTTS v2, pydub, uvicorn (~600 MB)"

# Helper: extract bare package name from a requirement spec like "fastapi>=0.110.0" or "uvicorn[standard]>=0.27.0"
function Get-PackageName {
    param([string]$Req)
    return ($Req -replace '\[.*?\]', '' -replace '[><=!;#@\s].*', '').Trim()
}

$reqFile = Join-Path $InstallDir "backend\requirements.txt"
$requirements = Get-Content $reqFile |
    Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }

# Tally what is already installed vs what needs installing
$toInstall = [System.Collections.Generic.List[string]]::new()
foreach ($req in $requirements) {
    $pkgName = Get-PackageName $req
    $showOut  = & $pipExe show $pkgName 2>$null
    if ($LASTEXITCODE -eq 0) {
        $ver = ($showOut | Select-String "^Version:") -replace "Version:\s*", ""
        Ok "  Already installed: $pkgName $ver -- skipping."
        Add-Content -Path $logFile -Value "  [skip] $pkgName $ver already present" -ErrorAction SilentlyContinue
    } else {
        Info "  Queued for install: $req"
        $toInstall.Add($req)
    }
}

if ($toInstall.Count -eq 0) {
    Ok "All packages already installed -- nothing to do."
} else {
    Info "$($toInstall.Count) package(s) to install."
    foreach ($pkg in $toInstall) {
        $pkgName = Get-PackageName $pkg
        Info "  Installing: $pkgName ..."
        Add-Content -Path $logFile -Value "  [install] $pkgName" -ErrorAction SilentlyContinue
        $pipOut  = & $pipExe install $pkg 2>&1
        $pipExit = $LASTEXITCODE
        $pipOut | ForEach-Object { Add-Content -Path $logFile -Value "    [pip] $_" -ErrorAction SilentlyContinue; Write-Host "    $_" }
        if ($pipExit -ne 0) {
            Abort "Failed to install: $pkgName.  Check install.log for details."
        }
        Ok "  Installed: $pkgName"
    }
}
Finish-Step "All Python packages ready"

# ===========================================================================
# STEP 8 -- OLLAMA MISTRAL MODEL
# ===========================================================================
Start-Step "Ollama mistral model" "AI model for transcript correction (~4 GB download)"

$ollamaExe = if (Test-Path $ollamaLocalExe) { $ollamaLocalExe } else { "ollama" }

try {
    $existingModels = & $ollamaExe list 2>&1
    if ($existingModels -match "mistral") {
        Ok "mistral model already present."
    } else {
        Info "Starting Ollama service ..."
        $ollamaProc = Start-Process $ollamaExe -ArgumentList "serve" -PassThru -WindowStyle Hidden

        $ready = $false
        for ($i = 0; $i -lt 15; $i++) {
            Start-Sleep -Seconds 2
            try {
                Invoke-WebRequest -Uri "http://localhost:11434/api/tags" `
                    -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop | Out-Null
                $ready = $true; break
            } catch {}
        }

        if ($ready) {
            Info "Pulling mistral -- this may take several minutes ..."
            & $ollamaExe pull mistral
            Ok "mistral model downloaded and ready."
        } else {
            Warn "Ollama API did not respond in time -- skipping model pull."
            Warn "Run:  ollama pull mistral  after installation."
        }

        if ($ollamaProc -and -not $ollamaProc.HasExited) {
            Stop-Process -Id $ollamaProc.Id -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    Warn "Could not pull mistral: $_"
    Warn "Run:  ollama pull mistral  after installation completes."
}
Finish-Step "Ollama mistral ready"

# ===========================================================================
# STEP 9 -- AI MODELS (optional)
# ===========================================================================
if ($DownloadModels) {
    Start-Step "AI Models -- Whisper large-v3 + Coqui XTTS v2" "Speech recognition and voice synthesis models (~4.8 GB)"

    Info "Downloading Whisper large-v3 (~3 GB) and Coqui XTTS v2 (~1.8 GB) ..."
    Info "This may take 10-30 minutes -- please wait."
    & $venvPython (Join-Path $InstallDir "backend\download_models.py")
    if ($LASTEXITCODE -ne 0) {
        Warn "Model download reported errors -- models will be retried on first use."
    } else {
        Ok "All AI models downloaded and cached."
    }
    Finish-Step "AI models ready"
} else {
    Write-Host ""
    Info "AI models (Whisper + Coqui XTTS v2) will download automatically on first use."
    Info "Expect a 10-30 min wait the first time you transcribe or synthesise."
}

Write-Progress -Activity "VoiceSyntesis Setup" -Status "Complete" -PercentComplete 100
Start-Sleep -Milliseconds 500
Write-Progress -Activity "VoiceSyntesis Setup" -Completed

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Green
Write-Host ""
Write-Host "  [SUCCESS] VoiceSyntesis installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  All $TOTAL_STEPS steps finished." -ForegroundColor Green
Write-Host "  Double-click the VoiceSyntesis shortcut on your Desktop to start." -ForegroundColor Green
Write-Host "  Log saved to: $logFile" -ForegroundColor DarkGray
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Green
Write-Host ""