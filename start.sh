#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# VoiceModulation — Start all services (macOS / Linux)
# Run: bash start.sh
# Press Ctrl+C to stop everything.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${GREEN}[start]${NC} $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -d ".venv" ]] || { echo "Run setup.sh first."; exit 1; }
[[ -d "frontend/node_modules" ]] || { echo "Run setup.sh first (frontend/node_modules missing)."; exit 1; }

# ── Track child PIDs for clean shutdown ───────────────────────────────────────
PIDS=()
OLLAMA_STARTED=false

cleanup() {
  echo ""
  info "Shutting down…"
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  if $OLLAMA_STARTED; then
    pkill -x ollama 2>/dev/null || true
  fi
  info "Done. Bye!"
}
trap cleanup EXIT INT TERM

# ── 1. Ollama ─────────────────────────────────────────────────────────────────
if pgrep -x "ollama" &>/dev/null; then
  info "Ollama already running"
else
  info "Starting Ollama…"
  ollama serve &>/dev/null &
  OLLAMA_PID=$!
  PIDS+=("$OLLAMA_PID")
  OLLAMA_STARTED=true
  sleep 2
fi

# ── 2. Backend (FastAPI) ───────────────────────────────────────────────────────
info "Starting backend (FastAPI on port 8000)…"
source .venv/bin/activate
OLLAMA_HOST=http://localhost:11434 \
  uvicorn backend.main:app --host 127.0.0.1 --port 8000 \
  2>&1 | sed 's/^/[backend] /' &
BACKEND_PID=$!
PIDS+=("$BACKEND_PID")
sleep 2

# ── 3. Frontend (Vite) ────────────────────────────────────────────────────────
info "Starting frontend (Vite on port 5173)…"
cd frontend
npm run dev -- --host 127.0.0.1 2>&1 | sed 's/^/[frontend] /' &
FRONTEND_PID=$!
PIDS+=("$FRONTEND_PID")
cd "$SCRIPT_DIR"

# ── Ready ─────────────────────────────────────────────────────────────────────
sleep 2
echo ""
echo -e "${BOLD}${GREEN}All services running.${NC}  Press Ctrl+C to stop."
echo ""
echo -e "  ${CYAN}App${NC}      →  http://localhost:5173"
echo -e "  ${CYAN}API docs${NC} →  http://localhost:8000/docs"
echo -e "  ${CYAN}Ollama${NC}   →  http://localhost:11434"
echo ""

# Keep the script alive (wait for Ctrl+C)
wait
