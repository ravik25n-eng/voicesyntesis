# VoiceSyntesis

> **Local voice cloning** — record your voice, transcribe it, clean it up with AI, and synthesise new speech that sounds like you. No cloud. No subscription. Runs 100% on your PC.

**Stack:** React + Vite · FastAPI · Whisper large-v3 · Ollama (Mistral) · F5-TTS

---

## Table of Contents

- [Windows — One-click Installer](#windows--one-click-installer)
- [What the Installer Downloads](#what-the-installer-downloads)
- [Using the App](#using-the-app)
- [Troubleshooting](#troubleshooting)
- [Developer — Build the Installer](#developer--build-the-installer)
- [Developer — Run in Dev Mode](#developer--run-in-dev-mode-maclinuxwindows)

---

## Windows — One-click Installer

> **Requirements:** Windows 10 (1809+) or Windows 11 · Internet connection · ~15 GB free disk space

### Step 1 — Download the installer

Go to the [**Releases**](../../releases) page and download **`VoiceSyntesis-Setup.exe`**.

### Step 2 — Run the installer

Double-click `VoiceSyntesis-Setup.exe`.

- Windows may show a **SmartScreen** warning — click **"More info" → "Run anyway"** (the file is safe but unsigned).
- Accept the default install directory (`%LocalAppData%\VoiceSyntesis`).
- On the **Components** page you can optionally tick **"Download AI models during install"** (~4.5 GB, recommended on a fast connection). If you skip this, models download automatically the first time you use transcription or synthesis.
- Click **Install**.

### Step 3 — Wait for dependencies

A **PowerShell window** opens automatically and installs everything step by step:

| Step | What is installed | Approx size |
|------|-------------------|-------------|
| 1 | Python 3.11 | 25 MB |
| 2 | Node.js LTS | 30 MB |
| 3 | FFmpeg | 90 MB |
| 4 | Ollama | 100 MB |
| 5 | Python virtual environment | — |
| 6 | PyTorch (CPU or CUDA) | 2–3 GB |
| 7 | FastAPI, Whisper, F5-TTS, etc. | ~500 MB |
| 8 | Mistral LLM model | ~4 GB |
| 9 | Whisper + F5-TTS weights *(if selected)* | ~4.5 GB |

> **Do NOT close** the PowerShell window. Total time is **20–60 minutes** depending on your internet speed.

When you see the green success banner the installation is complete.

### Step 4 — Launch

- Click **"Launch VoiceSyntesis now"** on the final installer page, **or**
- Double-click the **VoiceSyntesis** shortcut on your Desktop.

Your browser opens automatically at **http://localhost:8000**.

---

## What the Installer Downloads

Everything is downloaded from official sources — no third-party mirrors.

| Package | Source |
|---------|--------|
| Python 3.11 | python.org |
| Node.js LTS | nodejs.org |
| FFmpeg | gyan.dev (official FFmpeg Windows builds) |
| Ollama | ollama.com |
| PyTorch | pytorch.org |
| Python packages | PyPI (pip) |
| Mistral model | Ollama registry |
| Whisper large-v3 | Hugging Face (via faster-whisper) |
| F5-TTS | Hugging Face |

> If `winget` (App Installer) is present on your PC it is used first for Python, Node.js, FFmpeg, and Ollama — making those steps faster. If not, direct downloads are used automatically.

---

## Using the App

1. **Open the app** — double-click the Desktop shortcut. Your browser opens at http://localhost:8000.
2. **Create a project** — click **New Project**, enter a name, and click **Create**.
3. **Record** — click **Start Recording** and speak for 10–120 seconds. Click **Stop** when done.
4. **Transcribe** — click **Generate Transcript**. Whisper converts your speech to text (first run downloads the model if not done during install).
5. **Improve** — click **Improve with AI**. Mistral removes filler words and fixes punctuation. Accept, edit, or reject the suggestion.
6. **Synthesise** — choose a speaking style and click **Clone Voice & Synthesise**. F5-TTS generates a new WAV in your voice.
7. **Download** — click **Download** or play back the result in the browser.

---

## Troubleshooting

### Nothing opens after double-clicking the shortcut

Open PowerShell and run:
```powershell
cd "$env:LocalAppData\VoiceSyntesis"
.\install_deps.ps1 -InstallDir "$env:LocalAppData\VoiceSyntesis"
```
Check the log for errors:
```
%LocalAppData%\VoiceSyntesis\install.log
```

### "Ollama not found" / transcript correction fails

```powershell
ollama serve          # start the service
ollama pull mistral   # download the model if not present
```

### First transcription / synthesis is very slow

The AI models are downloading in the background — this only happens once. Whisper large-v3 is ~3 GB and F5-TTS is ~1.5 GB. Subsequent runs are fast.

### Port 8000 is already in use

Another process is using port 8000. Stop it or change the port:
```powershell
cd "$env:LocalAppData\VoiceSyntesis"
.\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 127.0.0.1 --port 8001
```
Then open http://localhost:8001.

### Re-run just the dependency installer

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
cd "$env:LocalAppData\VoiceSyntesis"
.\install_deps.ps1 -InstallDir "$env:LocalAppData\VoiceSyntesis" -DownloadModels
```

---

## Developer — Build the Installer

> Run this on your development machine (Windows).

**Prerequisites:**
- [Node.js 18+](https://nodejs.org)
- [Inno Setup 6](https://jrsoftware.org/isdl.php) (free, install with default options)
- Git

**Steps:**

```powershell
# 1. Clone the repository
git clone https://github.com/ravik25n-eng/voicesyntesis.git
cd voicesyntesis

# 2. Build the installer (builds frontend + compiles .exe in one command)
.\installer\build_installer.ps1
```

The output is at:
```
installer\dist\VoiceSyntesis-Setup.exe
```

Copy this single `.exe` file to any Windows 10/11 PC — it installs everything from scratch.

---

## Developer — Run in Dev Mode (Mac/Linux/Windows)

### Prerequisites

- Python 3.11+
- Node.js 18+
- ffmpeg (`brew install ffmpeg` / `apt install ffmpeg`)
- [Ollama](https://ollama.com) with `mistral` pulled: `ollama pull mistral`

### First-time setup

```bash
# Mac / Linux
bash setup.sh

# Windows (PowerShell)
.\setup.ps1
```

### Start all services

```bash
# Mac / Linux
bash start.sh

# Windows (PowerShell)
.\start.ps1
```

### Or start manually

```bash
# Terminal 1 — backend
source .venv/bin/activate          # Windows: .venv\Scripts\Activate.ps1
OLLAMA_HOST=http://localhost:11434 uvicorn backend.main:app --host 127.0.0.1 --port 8000 --reload

# Terminal 2 — frontend (dev with hot reload)
cd frontend
npm run dev
```

### Service URLs (dev mode)

| Service | URL |
|---------|-----|
| App (frontend) | http://localhost:5173 |
| Backend API | http://localhost:8000 |
| API Docs (Swagger) | http://localhost:8000/docs |
| Ollama | http://localhost:11434 |
