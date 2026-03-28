

Phase 1 — Project Foundation & Audio Recording
Goal: Working recorder with configurable duration

Set up Python 3.10+ virtual environment
Install sounddevice, soundfile, numpy
Implement AudioRecorder class:
Configurable duration: 30s → 120s (slider in UI)
Real-time waveform level indicator (CLI progress bar)
Save to recordings/ as .wav (16kHz mono — optimal for STT)
Auto-naming with timestamp
Basic CLI entrypoint to test recording


Phase 2 — Local Transcription with Whisper
Goal: Convert recorded voice to text locally

Install faster-whisper
Use large-v3 model (fits in 24GB RAM, best accuracy)
Implement Transcriber class:
Load model once, reuse across sessions
Return full transcript + word-level timestamps
Detect language automatically
Display transcript to user with confidence scores per segment
Deliverable: transcriber.py — input WAV → output text with segments

Note: faster-whisper runs via CoreML/Metal on Apple Silicon — expect ~2-5x real-time speed.



Phase 3 — Ollama LLM Transcript Correction
Goal: Use local LLM to clean/improve transcript before TTS

Install ollama Python SDK (pip install ollama)
Pull model: ollama pull llama3.2 (or mistral for faster inference)
Implement TranscriptCorrector class:
Send raw Whisper transcript + prompt to Ollama
Prompt: fix punctuation, grammar, remove filler words (uh, um), preserve meaning
Return suggested corrected transcript
User flow:
Show raw Whisper transcript
Show Ollama-suggested correction (diff highlighted)
User accepts / edits inline / rejects correction
Final transcript locked for TTS
Deliverable: corrector.py — raw transcript → polished transcript via Ollama


Phase 4 — Voice Cloning & Speech Synthesis
Goal: Generate new audio in the user's cloned voice

Install TTS (Coqui AI) — includes XTTS v2
XTTS v2 accepts 6-30s reference audio → your 30-120s recording is perfect (will be trimmed/sampled)
Implement VoiceCloner class:
Load XTTS v2 model (one-time, ~2GB)
Accept reference audio path + target transcript
Generate synthesized WAV
Save to outputs/ with timestamp
Quality tuning:
If reference > 30s, use the first clean 15-25s as clone reference
Keep sample rate at 24kHz for TTS output
Fallback option: If XTTS v2 quality is insufficient → try F5-TTS (diffusion-based, newer, often better naturalness)

Deliverable: voice_cloner.py — reference WAV + transcript → synthesized WAV


Phase 5 — Gradio Web Interface (Full Pipeline UI)
Goal: Unified browser-based UI tying all phases together

UI Components:
┌─────────────────────────────────────────────────┐
│  Duration Slider: [30s ──────────── 120s]       │
│  [▶ Start Recording]  [■ Stop]                  │
│  Waveform preview                               │
├─────────────────────────────────────────────────┤
│  [Generate Transcript]                          │
│  Raw Transcript: [editable textbox]             │
│  [✨ Improve with AI]                           │
│  Corrected Transcript: [editable textbox]       │
├─────────────────────────────────────────────────┤
│  [🎙 Clone Voice & Synthesize]                  │
│  Output Audio: [audio player]                  │
│  [⬇ Download]                                   │
└─────────────────────────────────────────────────┘
Built with gradio (gr.Blocks)
All steps sequential but each independently re-runnable
Audio playback inline
State management between steps
Deliverable: app.py — launch with python app.py, opens in browser


Phase 6 — Polish & Hardening
Goal: Make POC demo-ready

Add audio quality validation (min SNR, silence detection before accepting recording)
Progress indicators for each processing step (Whisper, Ollama, XTTS can all take 10-30s)
Session history: side-by-side original vs. synthesized audio player
Export: save full session (original recording + transcript + synthesized audio) as a zip
Logging for debugging model outputs