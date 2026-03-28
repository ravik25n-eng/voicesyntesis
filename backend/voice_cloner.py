"""
Coqui XTTS v2 voice cloning and synthesis.

XTTS v2 clones a voice from a short reference recording (~6 s or more) and
synthesises any text in that voice. Unlike F5-TTS, XTTS v2:
  - Is licensed under MPL 2.0 (fully open-source, commercial use allowed)
  - Supports multiple languages natively
  - Does not require a reference transcript

The model is loaded once and reused across requests.
Device selection is automatic: CUDA (NVIDIA GPU) → CPU.
"""

import os
import re
import sys
import threading
from collections.abc import Callable
from pathlib import Path

import torch

from utils import get_project_output_path, get_project_recording_path


def _detect_device() -> str:
    """Return the best available compute device: cuda → cpu."""
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


# ── Speaking style presets ───────────────────────────────────────────────────
# speed < 1.0 = slower delivery, speed > 1.0 = faster delivery.
# XTTS v2 does not use cfg_strength; only speed meaningfully changes output.

STYLE_PRESETS: dict[str, dict] = {
    # ── Neutral / utility ──────────────────────────────────────────────────
    "standard": {
        "label": "Standard",
        "speed": 1.0,
        "description": "Natural pace, balanced tone",
        "group": "Utility",
    },
    "slow_clear": {
        "label": "Slow & Clear",
        "speed": 0.75,
        "description": "Deliberate, easy to follow",
        "group": "Utility",
    },
    "fast_paced": {
        "label": "Fast Paced",
        "speed": 1.28,
        "description": "Energetic, rapid delivery",
        "group": "Utility",
    },
    # ── English regional ───────────────────────────────────────────────────
    "american": {
        "label": "American",
        "speed": 1.1,
        "description": "Upbeat, punchy cadence",
        "group": "English",
    },
    "british": {
        "label": "British (RP)",
        "speed": 0.88,
        "description": "Crisp, measured enunciation",
        "group": "English",
    },
    "australian": {
        "label": "Australian",
        "speed": 0.93,
        "description": "Relaxed, easy-going rhythm",
        "group": "English",
    },
    "irish": {
        "label": "Irish",
        "speed": 0.95,
        "description": "Lilting, musical cadence",
        "group": "English",
    },
    "scottish": {
        "label": "Scottish",
        "speed": 0.9,
        "description": "Rolling, rhythmic delivery",
        "group": "English",
    },
    "canadian": {
        "label": "Canadian",
        "speed": 1.05,
        "description": "Clear, slightly measured pace",
        "group": "English",
    },
    "new_zealand": {
        "label": "New Zealand",
        "speed": 0.97,
        "description": "Soft, unhurried delivery",
        "group": "English",
    },
    "south_african": {
        "label": "South African",
        "speed": 1.0,
        "description": "Clipped, precise consonants",
        "group": "English",
    },
    # ── South Asian ────────────────────────────────────────────────────────
    "indian": {
        "label": "Indian",
        "speed": 0.92,
        "description": "Rhythmic, syllable-even delivery",
        "group": "South Asian",
    },
    "indian_fast": {
        "label": "Indian (Expressive)",
        "speed": 1.08,
        "description": "Lively, emphatic tone",
        "group": "South Asian",
    },
    # ── European ───────────────────────────────────────────────────────────
    "french": {
        "label": "French",
        "speed": 0.9,
        "description": "Smooth, flowing phrasing",
        "group": "European",
    },
    "german": {
        "label": "German",
        "speed": 0.87,
        "description": "Precise, deliberate articulation",
        "group": "European",
    },
    "spanish": {
        "label": "Spanish",
        "speed": 1.05,
        "description": "Vibrant, rhythmic energy",
        "group": "European",
    },
    "italian": {
        "label": "Italian",
        "speed": 1.0,
        "description": "Expressive, melodic flow",
        "group": "European",
    },
}

DEFAULT_STYLE = "standard"


def _split_text(text: str, max_chars: int = 200) -> list[str]:
    """
    Split text into chunks at sentence boundaries, each at most max_chars.
    XTTS v2 handles longer inputs than F5-TTS so max_chars is set higher.
    """
    text = text.strip()
    if len(text) <= max_chars:
        return [text]

    sentences = re.split(r'(?<=[.!?])\s+', text)
    chunks: list[str] = []
    current = ""

    for sentence in sentences:
        sentence = sentence.strip()
        if not sentence:
            continue
        if len(current) + len(sentence) + 1 <= max_chars:
            current = (current + " " + sentence).strip() if current else sentence
        else:
            if current:
                chunks.append(current)
            while len(sentence) > max_chars:
                cut = sentence.rfind(" ", 0, max_chars)
                if cut == -1:
                    cut = max_chars
                chunks.append(sentence[:cut].strip())
                sentence = sentence[cut:].strip()
            current = sentence

    if current:
        chunks.append(current)

    return [c for c in chunks if c.strip()]


_tts = None
_lock = threading.Lock()

# Platform-aware cache path for XTTS v2 model weights (~1.8 GB)
if sys.platform == "win32":
    _XTTS_CACHE = os.path.join(
        os.environ.get("LOCALAPPDATA", os.path.expanduser("~")),
        "tts", "tts_models--multilingual--multi-dataset--xtts_v2",
    )
else:
    _XTTS_CACHE = os.path.expanduser(
        "~/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2"
    )


def _is_model_cached() -> bool:
    """Return True if XTTS v2 weights have already been downloaded."""
    return os.path.isdir(_XTTS_CACHE)


def _get_tts(status_callback: Callable | None = None):
    global _tts
    if _tts is None:
        with _lock:
            if _tts is None:
                cached = _is_model_cached()
                if status_callback:
                    if cached:
                        status_callback("loading_model", "Loading XTTS v2 model into memory...", 10)
                    else:
                        status_callback(
                            "loading_model",
                            "Downloading XTTS v2 model (~1.8 GB) -- first-run only, please wait...",
                            5,
                        )

                # Accept Coqui TOS non-interactively (required in server context)
                os.environ["COQUI_TOS_AGREED"] = "1"

                from TTS.api import TTS  # deferred import to avoid slow startup

                device = _detect_device()
                print(f"[voice_cloner] Using device: {device}")
                _tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)

                if status_callback:
                    status_callback("loading_model", "XTTS v2 model loaded.", 30)
    return _tts


def synthesize(
    file_id: str,
    gen_text: str,
    status_callback: Callable | None = None,
    style: str = DEFAULT_STYLE,
) -> Path:
    """
    Clone the voice from the reference recording and synthesise gen_text
    using Coqui XTTS v2 (MPL 2.0, commercial use allowed).

    For long texts the input is split into sentence-level chunks and each
    chunk synthesised independently, then concatenated with pydub. This
    gives the UI per-chunk progress updates and keeps memory usage flat.
    """
    def update(status: str, message: str, progress: int | None = None) -> None:
        if status_callback:
            status_callback(status, message, progress)

    reference_path = get_project_recording_path(file_id)
    if not reference_path.exists():
        raise FileNotFoundError(f"Reference recording not found for file_id: {file_id}")

    update("queued", "Starting synthesis pipeline...", 0)

    preset = STYLE_PRESETS.get(style, STYLE_PRESETS[DEFAULT_STYLE])
    speed = preset["speed"]

    tts = _get_tts(status_callback)

    update("preparing_audio", "Preprocessing reference audio...", 40)

    output_path = get_project_output_path(file_id)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    ref_file = str(reference_path)
    chunks = _split_text(gen_text)
    n = len(chunks)

    update("synthesizing", f"Generating speech in your cloned voice... ({n} segment{'s' if n > 1 else ''})", 55)

    if n == 1:
        tts.tts_to_file(
            text=chunks[0],
            speaker_wav=ref_file,
            language="en",
            file_path=str(output_path),
            speed=speed,
        )
    else:
        from pydub import AudioSegment
        part_paths: list[Path] = []
        for i, chunk in enumerate(chunks):
            update("synthesizing", f"Synthesising segment {i + 1}/{n}...", 55 + int(40 * i / n))
            part_path = output_path.parent / f"part{i}.wav"
            tts.tts_to_file(
                text=chunk,
                speaker_wav=ref_file,
                language="en",
                file_path=str(part_path),
                speed=speed,
            )
            part_paths.append(part_path)

        combined = AudioSegment.empty()
        for part_path in part_paths:
            combined += AudioSegment.from_wav(str(part_path))
            part_path.unlink()
        combined.export(str(output_path), format="wav")

    return output_path

