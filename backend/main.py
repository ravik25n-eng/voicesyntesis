"""
FastAPI backend for VoiceModulation POC.
Serves audio upload, Whisper transcription, Ollama correction, and F5-TTS voice synthesis.
"""

import asyncio
import logging
import os
import sys
import threading
from pathlib import Path

# Ensure sibling modules (transcriber, corrector, voice_cloner, utils) are importable
# regardless of the working directory uvicorn is launched from.
sys.path.insert(0, os.path.dirname(__file__))

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

# ── Synthesis job tracker ────────────────────────────────────────────────────
# Keyed by file_id. Each entry: { status, message, progress, audio_url, error }
# Possible statuses: queued | loading_model | preparing_audio | synthesizing | done | error
synthesis_jobs: dict[str, dict] = {}

import corrector  # noqa: E402
import transcriber  # noqa: E402
import voice_cloner  # noqa: E402
from utils import (  # noqa: E402
    PROJECTS_DIR,
    create_project,
    get_project_output_path,
    get_project_recording_path,
    list_projects,
    save_uploaded_audio,
)
from voice_cloner import STYLE_PRESETS  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger(__name__)

app = FastAPI(title="VoiceModulation API", version="1.0.0")

# Allow requests from the React dev server
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Static file serving for audio playback in the browser
app.mount("/project-files", StaticFiles(directory=str(PROJECTS_DIR)), name="project-files")

# Serve pre-built frontend when running as installed app (no Vite/Node needed).
# Only mounted when frontend/dist exists — dev mode with Vite is unaffected.
_frontend_dist = Path(__file__).parent.parent / "frontend" / "dist"
if _frontend_dist.exists():
    app.mount("/", StaticFiles(directory=str(_frontend_dist), html=True), name="frontend")


# ── Request / Response models ────────────────────────────────────────────────

class CreateProjectRequest(BaseModel):
    name: str


class TranscribeRequest(BaseModel):
    file_id: str  # project_id


class CorrectTranscriptRequest(BaseModel):
    raw_transcript: str
    model: str = "mistral:latest"


class SynthesizeRequest(BaseModel):
    file_id: str  # project_id
    gen_text: str
    style: str = "standard"


# ── Endpoints ────────────────────────────────────────────────────────────────

@app.get("/api/health")
async def health():
    return {"status": "ok", "message": "VoiceModulation API is running"}


# ── Project endpoints ────────────────────────────────────────────────────────

@app.post("/api/projects")
async def create_project_endpoint(request: CreateProjectRequest):
    """Create a new named project folder and return its metadata."""
    if not request.name.strip():
        raise HTTPException(status_code=400, detail="Project name cannot be empty")
    try:
        meta = create_project(request.name.strip())
        logger.info("Project created: %s (%s)", meta['name'], meta['project_id'])
        return meta
    except Exception as exc:
        logger.error("Project creation failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/api/projects")
async def list_projects_endpoint():
    """Return all projects (newest first) with recording/output presence flags."""
    return list_projects()


@app.get("/api/style-presets")
async def get_style_presets():
    """Return available speaking style presets."""
    return [
        {"id": k, **{kk: vv for kk, vv in v.items()}}
        for k, v in STYLE_PRESETS.items()
    ]


@app.post("/api/upload-audio")
async def upload_audio(project_id: str, audio: UploadFile = File(...)):
    """
    Accept an audio blob from the browser, convert to 16 kHz mono WAV,
    and save it into the project folder.
    """
    project_path = PROJECTS_DIR / project_id
    if not project_path.exists():
        raise HTTPException(status_code=404, detail="Project not found")
    try:
        audio_bytes = await audio.read()
        content_type = audio.content_type or "audio/webm"
        wav_path = save_uploaded_audio(audio_bytes, project_id, content_type)
        logger.info("Audio uploaded for project %s: %d bytes", project_id, len(audio_bytes))
        return {
            "file_id": project_id,
            "audio_url": f"/project-files/{project_id}/recording.wav",
            "size_bytes": len(audio_bytes),
        }
    except Exception as exc:
        logger.error("Upload failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/api/transcribe")
async def transcribe_audio(request: TranscribeRequest):
    """Transcribe the uploaded WAV using faster-whisper large-v3."""
    wav_path = get_project_recording_path(request.file_id)
    if not wav_path.exists():
        raise HTTPException(status_code=404, detail="Recording not found")

    try:
        logger.info("Transcribing file_id=%s", request.file_id)
        result = transcriber.transcribe(wav_path)
        logger.info("Transcription complete: %d chars, lang=%s", len(result["text"]), result["language"])
        return result
    except Exception as exc:
        logger.error("Transcription failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/api/correct-transcript")
async def correct_transcript(request: CorrectTranscriptRequest):
    """Clean up a raw transcript using the local Ollama model."""
    if not request.raw_transcript.strip():
        raise HTTPException(status_code=400, detail="Transcript cannot be empty")

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            lambda: corrector.correct_transcript(request.raw_transcript, request.model)
        )
        if not result.get("success"):
            error_msg = result.get("error", "Unknown error")
            logger.error("Correction failed: %s", error_msg)
            raise HTTPException(status_code=502, detail=f"Ollama error: {error_msg}")
        return result
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Correction failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


def _run_synthesis(file_id: str, gen_text: str, style: str = "standard") -> None:
    """Runs in a background thread. Updates synthesis_jobs[file_id] at each phase."""

    def on_status(status: str, message: str, progress: int | None = None) -> None:
        synthesis_jobs[file_id].update(
            {"status": status, "message": message, "progress": progress}
        )
        logger.info("[synthesis:%s] %s — %s", file_id[:8], status, message)

    try:
        output_path = voice_cloner.synthesize(
            file_id=file_id,
            gen_text=gen_text,
            status_callback=on_status,
            style=style,
        )
        synthesis_jobs[file_id].update(
            {
                "status": "done",
                "message": "Synthesis complete!",
                "progress": 100,
                "audio_url": f"/project-files/{file_id}/synthesized.wav",
            }
        )
        logger.info("Synthesis done: %s", output_path)
    except Exception as exc:
        synthesis_jobs[file_id].update(
            {"status": "error", "message": str(exc), "progress": None}
        )
        logger.error("Synthesis failed for %s: %s", file_id, exc)


@app.post("/api/synthesize")
async def synthesize_voice(request: SynthesizeRequest):
    """Start voice synthesis in a background thread and return immediately."""
    if not request.gen_text.strip():
        raise HTTPException(status_code=400, detail="Transcript cannot be empty")

    wav_path = get_project_recording_path(request.file_id)
    if not wav_path.exists():
        raise HTTPException(status_code=404, detail="Reference recording not found")

    # Register a new job
    synthesis_jobs[request.file_id] = {
        "status": "queued",
        "message": "Synthesis queued…",
        "progress": 0,
        "audio_url": None,
    }

    thread = threading.Thread(
        target=_run_synthesis,
        args=(request.file_id, request.gen_text, request.style),
        daemon=True,
    )
    thread.start()
    logger.info("Synthesis thread started for file_id=%s", request.file_id)
    return {"file_id": request.file_id, "status": "queued"}


@app.get("/api/synthesis-status/{file_id}")
async def synthesis_status(file_id: str):
    """Poll this endpoint to get live synthesis phase, message and progress."""
    job = synthesis_jobs.get(file_id)
    if not job:
        raise HTTPException(status_code=404, detail="No synthesis job found for this file_id")
    return job


@app.get("/api/audio/recording/{file_id}")
async def get_recording(file_id: str):
    path = get_project_recording_path(file_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Recording not found")
    return FileResponse(str(path), media_type="audio/wav")


@app.get("/api/audio/synthesized/{file_id}")
async def get_synthesized(file_id: str):
    path = get_project_output_path(file_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Synthesized audio not found")
    return FileResponse(str(path), media_type="audio/wav")


@app.get("/api/subtitle/{file_id}")
async def get_subtitle(file_id: str):
    """
    Transcribe the synthesized output WAV with Whisper and return timestamped segments.
    Use this to verify what was actually generated vs what was intended.
    """
    path = get_project_output_path(file_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Synthesized audio not found. Run synthesis first.")

    try:
        logger.info("Extracting subtitles for file_id=%s", file_id)
        result = transcriber.transcribe(path)
        return {
            "file_id": file_id,
            "text": result["text"],
            "segments": result["segments"],
            "language": result["language"],
            "language_probability": result["language_probability"],
            "duration": result["duration"],
        }
    except Exception as exc:
        logger.error("Subtitle extraction failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.delete("/api/projects/{project_id}")
async def delete_project_endpoint(project_id: str):
    """Permanently delete a project folder and all its files."""
    import shutil
    project_path = PROJECTS_DIR / project_id
    if not project_path.exists():
        raise HTTPException(status_code=404, detail="Project not found")
    try:
        shutil.rmtree(project_path)
        logger.info("Project deleted: %s", project_id)
        return {"deleted": project_id}
    except Exception as exc:
        logger.error("Project deletion failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))
