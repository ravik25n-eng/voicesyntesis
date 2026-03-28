import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

from pydub import AudioSegment

# All project data lives under backend/projects/{project_id}/
#   recording.wav      — the reference voice sample
#   synthesized.wav    — the F5-TTS output (created after synthesis)
#   meta.json          — { project_id, name, created_at }
PROJECTS_DIR = Path(__file__).parent / "projects"
PROJECTS_DIR.mkdir(exist_ok=True)


# ── Project helpers ──────────────────────────────────────────────────────────

def _slugify(name: str) -> str:
    """Convert a human name to a safe directory slug."""
    slug = name.strip().lower()
    slug = re.sub(r"[^\w\s-]", "", slug)
    slug = re.sub(r"[\s_]+", "-", slug)
    slug = slug.strip("-") or "project"
    return slug[:48]  # cap length


def create_project(name: str) -> dict:
    """
    Create a new project directory, write meta.json, and return the project dict.
    Appends a short unique suffix to prevent folder collisions.
    """
    slug = _slugify(name)
    suffix = uuid.uuid4().hex[:6]
    project_id = f"{slug}-{suffix}"
    project_path = PROJECTS_DIR / project_id
    project_path.mkdir(parents=True, exist_ok=True)

    meta = {
        "project_id": project_id,
        "name": name,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    (project_path / "meta.json").write_text(json.dumps(meta, ensure_ascii=False))
    return meta


def get_project_recording_path(project_id: str) -> Path:
    return PROJECTS_DIR / project_id / "recording.wav"


def get_project_output_path(project_id: str) -> Path:
    return PROJECTS_DIR / project_id / "synthesized.wav"


def list_projects() -> list[dict]:
    """Return all projects sorted newest-first, each enriched with file presence flags."""
    projects = []
    for meta_file in PROJECTS_DIR.glob("*/meta.json"):
        try:
            meta = json.loads(meta_file.read_text())
            project_id = meta["project_id"]
            has_recording = get_project_recording_path(project_id).exists()
            has_output = get_project_output_path(project_id).exists()
            projects.append({
                **meta,
                "has_recording": has_recording,
                "has_output": has_output,
                "recording_url": f"/project-files/{project_id}/recording.wav" if has_recording else None,
                "output_url": f"/project-files/{project_id}/synthesized.wav" if has_output else None,
            })
        except Exception:
            continue
    projects.sort(key=lambda p: p.get("created_at", ""), reverse=True)
    return projects


# ── Audio helpers ────────────────────────────────────────────────────────────

def save_uploaded_audio(audio_bytes: bytes, project_id: str, content_type: str = "audio/webm") -> Path:
    """
    Save uploaded audio bytes into the project folder, convert to 16 kHz mono WAV,
    and return the wav_path.
    """
    ext_map = {
        "audio/webm": "webm",
        "audio/ogg": "ogg",
        "audio/mp4": "mp4",
        "audio/x-m4a": "m4a",
        "audio/mpeg": "mp3",
        "audio/mp3": "mp3",
        "audio/wav": "wav",
        "audio/x-wav": "wav",
        "audio/flac": "flac",
        "audio/x-flac": "flac",
    }
    ext = ext_map.get(content_type, "webm")

    project_path = PROJECTS_DIR / project_id
    project_path.mkdir(parents=True, exist_ok=True)

    raw_path = project_path / f"recording_raw.{ext}"
    wav_path = project_path / "recording.wav"

    with open(raw_path, "wb") as f:
        f.write(audio_bytes)

    audio = AudioSegment.from_file(str(raw_path))
    audio = audio.set_frame_rate(16000).set_channels(1)
    audio.export(str(wav_path), format="wav")

    if raw_path != wav_path:
        raw_path.unlink(missing_ok=True)

    return wav_path



