
### Backend (FastAPI)

cd /Users/raikumar/Documents/Development/VoiceModulation
source .venv/bin/activate
OLLAMA_HOST=http://localhost:11434 uvicorn backend.main:app --host 127.0.0.1 --port 8000 --reload
 

### Frontend (React + Vite)

 
cd /Users/raikumar/Documents/Development/VoiceModulation/frontend
npm run dev
 

---

## Setup (first time only)

### Python virtual environment + dependencies

cd /Users/raikumar/Documents/Development/VoiceModulation
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
 

### Frontend dependencies

cd /Users/raikumar/Documents/Development/VoiceModulation/frontend
npm install
 


| Service  | URL                        |
|----------|----------------------------|
| Frontend | http://localhost:5173      |
| Backend  | http://localhost:8000      |
| API Docs | http://localhost:8000/docs |
| Ollama   | http://localhost:11434     |
