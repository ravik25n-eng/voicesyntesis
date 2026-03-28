# VoiceSyntesis

A local voice cloning app — record your voice, transcribe it, correct the transcript, and synthesise new speech in your cloned voice.

**Stack:** React + Vite · FastAPI · Whisper · Ollama (Mistral) · F5-TTS

---

## Windows — Install via Setup Wizard

Download `VoiceModulation-Setup.exe` from the [Releases](../../releases) page and run it.

The installer will:
- Install Python, ffmpeg, and Ollama automatically
- Set up all Python dependencies
- Optionally download AI models (~4.5 GB) during setup

After install, double-click the **VoiceModulation** shortcut on your Desktop.

**If nothing happens after install**, open PowerShell and run the dependency installer manually:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
cd "$env:LocalAppData\VoiceModulation"
.\install_deps.ps1 -InstallDir "$env:LocalAppData\VoiceModulation" -DownloadModels
```

Then check the log:
```
%LocalAppData%\VoiceModulation\install.log
```

---

## Mac / Linux — Setup

**Requirements:** Python 3.10+, Node.js, ffmpeg, Ollama

### First-time setup (installs everything)

```bash
bash setup.sh
```

### Start the app

```bash
bash start.sh
```

---

## Manual Setup (Mac/Linux)

### Python virtual environment + dependencies

```bash
cd /path/to/VoiceModulation
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
```

### Frontend dependencies

```bash
cd frontend
npm install
```

### Download AI models (first time only, ~4.5 GB)

```bash
source .venv/bin/activate
python backend/download_models.py
```

---

## Running (Mac/Linux — dev mode)

### Backend

```bash
source .venv/bin/activate
OLLAMA_HOST=http://localhost:11434 uvicorn backend.main:app --host 127.0.0.1 --port 8000 --reload
```

### Frontend

```bash
cd frontend
npm run dev
```

---

## Services

| Service  | URL                        |
|----------|----------------------------|
| Frontend | http://localhost:5173      |
| Backend  | http://localhost:8000      |
| API Docs | http://localhost:8000/docs |
| Ollama   | http://localhost:11434     |

---

## Requirements

- Python 3.10+
- Node.js 18+
- ffmpeg
- Ollama with `mistral` model (`ollama pull mistral`)
- ~10 GB free disk space (models + dependencies)
- Fast internet connection for first-time model downloads
