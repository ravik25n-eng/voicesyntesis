#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# VoiceModulation — First-time setup for macOS / Linux
# Run once: bash setup.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

info()    { echo -e "${GREEN}[setup]${NC} $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}── $* ──${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── 1. Homebrew (macOS only) ─────────────────────────────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
  section "Homebrew"
  if ! command -v brew &>/dev/null; then
    warn "Homebrew not found. Installing…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    info "Homebrew already installed"
  fi

  section "System dependencies (python, node, ffmpeg, ollama)"
  brew install python@3.11 node ffmpeg ollama 2>/dev/null || brew upgrade python@3.11 node ffmpeg ollama 2>/dev/null || true
else
  # Linux: check that required tools are present
  section "Checking system dependencies"
  for cmd in python3 node npm ffmpeg; do
    command -v "$cmd" &>/dev/null || error "'$cmd' not found. Install it via your package manager and re-run."
  done
  command -v ollama &>/dev/null || error "'ollama' not found. Install from https://ollama.com and re-run."
fi

# ── 2. Python virtual environment ────────────────────────────────────────────
section "Python virtual environment"
if [[ ! -d ".venv" ]]; then
  python3 -m venv .venv
  info "Created .venv"
else
  info ".venv already exists — skipping creation"
fi

source .venv/bin/activate

section "Python dependencies"
pip install --upgrade pip -q
pip install -r backend/requirements.txt

# ── 3. Frontend dependencies ─────────────────────────────────────────────────
section "Frontend dependencies (npm install)"
cd frontend
npm install
cd "$SCRIPT_DIR"

# ── 4. Pull Ollama model ─────────────────────────────────────────────────────
section "Pulling Ollama model (mistral — ~4 GB, first-time only)"
# Start ollama temporarily for the pull if it's not already running
OLLAMA_STARTED=false
if ! pgrep -x "ollama" &>/dev/null; then
  ollama serve &>/dev/null &
  OLLAMA_PID=$!
  OLLAMA_STARTED=true
  sleep 3  # give it a moment to start
fi

ollama pull mistral

if $OLLAMA_STARTED; then
  kill "$OLLAMA_PID" 2>/dev/null || true
fi

# ── 5. Download ML models ────────────────────────────────────────────────────
section "Downloading ML models (Whisper ~3 GB + F5-TTS ~1.5 GB)"
info "This may take 10–20 minutes on the first run…"
python backend/download_models.py

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ Setup complete!${NC}"
echo ""
echo "  Start the app any time with:  bash start.sh"
echo ""
