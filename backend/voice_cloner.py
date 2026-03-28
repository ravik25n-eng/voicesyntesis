"""
F5-TTS voice cloning and synthesis.

F5-TTS requires:
  - ref_file:  path to the reference WAV (the user's recording)
  - gen_text:  the text to synthesise in the cloned voice (user's edited transcript)

ref_text is intentionally left empty so F5-TTS auto-transcribes its own
internal 12 s clip. This avoids the alignment mismatch that occurs when
the full recording transcript is used (F5-TTS clips ref audio to 12 s).

F5-TTS splits long gen_text into batches and runs them inside a
ThreadPoolExecutor. On Apple Silicon MPS the shared model/vocoder state is
NOT thread-safe; concurrent STFT calls produce mismatched tensor sizes.

Fix: we monkey-patch the ThreadPoolExecutor used by F5-TTS's
infer_batch_process with _SequentialExecutor — a drop-in replacement that
runs every submitted callable synchronously on the calling thread. This
makes all internal batches sequential without changing the public F5-TTS API
and works regardless of how many sub-batches F5-TTS decides to create.

The model is loaded once and reused across requests.
Device selection is automatic: CUDA (NVIDIA GPU) → MPS (Apple Silicon) → CPU.
"""

import concurrent.futures
import os
import threading
from collections.abc import Callable
from pathlib import Path

import torch

from utils import get_project_output_path, get_project_recording_path


def _detect_device() -> str:
    """Return the best available compute device: cuda → mps → cpu."""
    if torch.cuda.is_available():
        return "cuda"
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"


# ── Speaking style presets ───────────────────────────────────────────────────
# Each preset tunes F5-TTS infer() parameters that meaningfully change output:
#   speed        — speaking rate  (1.0 = natural, <1 = slower, >1 = faster)
#   cfg_strength — how strongly the diffusion model follows the voice reference
#                  (higher = more adherent / crisper enunciation)
# These produce distinct, audible differences while reusing the same cloned voice.

STYLE_PRESETS: dict[str, dict] = {
    # ── Neutral / utility ──────────────────────────────────────────────────
    "standard": {
        "label": "Standard",
        "speed": 1.0,
        "cfg_strength": 2.0,
        "description": "Natural pace, balanced tone",
        "group": "Utility",
    },
    "slow_clear": {
        "label": "Slow & Clear",
        "speed": 0.75,
        "cfg_strength": 2.0,
        "description": "Deliberate, easy to follow",
        "group": "Utility",
    },
    "fast_paced": {
        "label": "Fast Paced",
        "speed": 1.28,
        "cfg_strength": 2.3,
        "description": "Energetic, rapid delivery",
        "group": "Utility",
    },
    # ── English regional ───────────────────────────────────────────────────
    "american": {
        "label": "American",
        "speed": 1.1,
        "cfg_strength": 2.2,
        "description": "Upbeat, punchy cadence",
        "group": "English",
    },
    "british": {
        "label": "British (RP)",
        "speed": 0.88,
        "cfg_strength": 2.0,
        "description": "Crisp, measured enunciation",
        "group": "English",
    },
    "australian": {
        "label": "Australian",
        "speed": 0.93,
        "cfg_strength": 1.8,
        "description": "Relaxed, easy-going rhythm",
        "group": "English",
    },
    "irish": {
        "label": "Irish",
        "speed": 0.95,
        "cfg_strength": 1.9,
        "description": "Lilting, musical cadence",
        "group": "English",
    },
    "scottish": {
        "label": "Scottish",
        "speed": 0.9,
        "cfg_strength": 1.85,
        "description": "Rolling, rhythmic delivery",
        "group": "English",
    },
    "canadian": {
        "label": "Canadian",
        "speed": 1.05,
        "cfg_strength": 2.1,
        "description": "Clear, slightly measured pace",
        "group": "English",
    },
    "new_zealand": {
        "label": "New Zealand",
        "speed": 0.97,
        "cfg_strength": 1.85,
        "description": "Soft, unhurried delivery",
        "group": "English",
    },
    "south_african": {
        "label": "South African",
        "speed": 1.0,
        "cfg_strength": 1.95,
        "description": "Clipped, precise consonants",
        "group": "English",
    },
    # ── South Asian ────────────────────────────────────────────────────────
    "indian": {
        "label": "Indian",
        "speed": 0.92,
        "cfg_strength": 2.1,
        "description": "Rhythmic, syllable-even delivery",
        "group": "South Asian",
    },
    "indian_fast": {
        "label": "Indian (Expressive)",
        "speed": 1.08,
        "cfg_strength": 2.3,
        "description": "Lively, emphatic tone",
        "group": "South Asian",
    },
    # ── European ───────────────────────────────────────────────────────────
    "french": {
        "label": "French",
        "speed": 0.9,
        "cfg_strength": 1.9,
        "description": "Smooth, flowing phrasing",
        "group": "European",
    },
    "german": {
        "label": "German",
        "speed": 0.87,
        "cfg_strength": 2.1,
        "description": "Precise, deliberate articulation",
        "group": "European",
    },
    "spanish": {
        "label": "Spanish",
        "speed": 1.05,
        "cfg_strength": 1.95,
        "description": "Vibrant, rhythmic energy",
        "group": "European",
    },
    "italian": {
        "label": "Italian",
        "speed": 1.0,
        "cfg_strength": 1.9,
        "description": "Expressive, melodic flow",
        "group": "European",
    },
}

DEFAULT_STYLE = "standard"


# ── Sequential executor patch ────────────────────────────────────────────────

class _SequentialExecutor:
    """
    Drop-in replacement for ThreadPoolExecutor.
    Runs every submitted callable synchronously on the calling thread,
    eliminating MPS thread-safety issues in F5-TTS batch processing.
    """
    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def submit(self, fn, *args, **kwargs):
        f = concurrent.futures.Future()
        try:
            f.set_result(fn(*args, **kwargs))
        except Exception as exc:
            f.set_exception(exc)
        return f


def _patch_f5_executor():
    """Replace ThreadPoolExecutor in F5-TTS's infer_batch_process with
    _SequentialExecutor. Called once after the module is first imported."""
    try:
        import f5_tts.infer.utils_infer as _u
        _u.ThreadPoolExecutor = _SequentialExecutor
    except Exception:
        pass  # If the internal structure changes, fall through gracefully


# ─────────────────────────────────────────────────────────────────────────────


def _split_text(text: str, max_chars: int = 120) -> list[str]:
    """
    Split *text* into chunks of at most *max_chars* characters, preferring
    sentence boundaries (. ! ?) then clause boundaries (, ;) over hard cuts.
    Each chunk will be a complete, speakable unit for one tts.infer() call.

    Note: with _SequentialExecutor patched in, F5-TTS's internal re-batching
    is already safe. This split keeps individual calls short to give the UI
    meaningful progress updates on long texts.
    """
    import re
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
            # Sentence itself longer than max_chars — hard split at word boundary
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

_HF_MODEL_CACHE = os.path.expanduser(
    "~/.cache/huggingface/hub/models--SWivid--F5-TTS"
)


def _is_model_cached() -> bool:
    """Return True if the F5-TTS model weights have already been downloaded."""
    return os.path.isdir(_HF_MODEL_CACHE)


def _get_tts(status_callback: Callable | None = None):
    global _tts
    if _tts is None:
        with _lock:
            if _tts is None:
                cached = _is_model_cached()
                if status_callback:
                    if cached:
                        status_callback("loading_model", "Loading F5-TTS model into memory…", 10)
                    else:
                        status_callback(
                            "loading_model",
                            "Downloading F5-TTS model (~1.5 GB from HuggingFace) — first-run only, please wait…",
                            5,
                        )

                from f5_tts.api import F5TTS  # deferred to avoid slow startup
                device = _detect_device()
                print(f"[voice_cloner] Using device: {device}")
                _tts = F5TTS(device=device)

                # Apply the sequential executor patch now that F5-TTS is imported
                _patch_f5_executor()

                if status_callback:
                    status_callback("loading_model", "F5-TTS model loaded ✓", 30)
    return _tts


def synthesize(
    file_id: str,
    gen_text: str,
    status_callback: Callable | None = None,
    style: str = DEFAULT_STYLE,
) -> Path:
    """
    Clone the voice from the reference recording and synthesise gen_text.

    ref_text is passed as "" so F5-TTS auto-transcribes its internal 12 s
    clip (result is cached per reference file). This avoids alignment
    mismatch caused by passing the full recording transcript against a
    12 s audio clip.

    F5-TTS's ThreadPoolExecutor is patched to _SequentialExecutor so all
    internal batches run on the same thread, eliminating MPS tensor-size
    mismatches.

    For long texts we pre-split into sentence-level chunks and synthesise
    each independently, then concatenate with pydub, giving the UI
    per-chunk progress updates.
    """
    def update(status: str, message: str, progress: int | None = None) -> None:
        if status_callback:
            status_callback(status, message, progress)

    reference_path = get_project_recording_path(file_id)
    if not reference_path.exists():
        raise FileNotFoundError(f"Reference recording not found for file_id: {file_id}")

    update("queued", "Starting synthesis pipeline…", 0)

    preset = STYLE_PRESETS.get(style, STYLE_PRESETS[DEFAULT_STYLE])
    speed = preset["speed"]
    cfg_strength = preset["cfg_strength"]

    tts = _get_tts(status_callback)

    update("preparing_audio", "Preprocessing reference audio…", 40)

    output_path = get_project_output_path(file_id)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    ref_file = str(reference_path)
    chunks = _split_text(gen_text)
    n = len(chunks)

    update("synthesizing", f"Generating speech in your cloned voice… ({n} segment{'s' if n > 1 else ''})", 55)

    if n == 1:
        tts.infer(
            ref_file=ref_file,
            ref_text="",
            gen_text=chunks[0],
            file_wave=str(output_path),
            remove_silence=False,
            speed=speed,
            cfg_strength=cfg_strength,
        )
    else:
        from pydub import AudioSegment
        part_paths: list[Path] = []
        for i, chunk in enumerate(chunks):
            update("synthesizing", f"Synthesising segment {i + 1}/{n}…", 55 + int(40 * i / n))
            part_path = output_path.parent / f"part{i}.wav"
            tts.infer(
                ref_file=ref_file,
                ref_text="",
                gen_text=chunk,
                file_wave=str(part_path),
                remove_silence=False,
                speed=speed,
                cfg_strength=cfg_strength,
            )
            part_paths.append(part_path)

        combined = AudioSegment.empty()
        for part_path in part_paths:
            combined += AudioSegment.from_wav(str(part_path))
            part_path.unlink()
        combined.export(str(output_path), format="wav")

    return output_path

