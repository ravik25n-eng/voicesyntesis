"""
Whisper-based transcription using faster-whisper.
Model is loaded once and reused across requests.
Uses 'large-v3' for best accuracy on M-series Macs (runs on CPU with int8 — fast).
"""

import threading
from pathlib import Path

from faster_whisper import WhisperModel

_model: WhisperModel | None = None
_lock = threading.Lock()

MODEL_SIZE = "large-v3"


def get_model() -> WhisperModel:
    global _model
    if _model is None:
        with _lock:
            if _model is None:
                _model = WhisperModel(MODEL_SIZE, device="cpu", compute_type="int8")
    return _model


def transcribe(audio_path: Path) -> dict:
    """
    Transcribe a WAV file.
    Returns:
        text: full transcript string
        segments: list of {start, end, text, avg_logprob}
        language: detected language code
        language_probability: confidence [0, 1]
        duration: audio duration in seconds
    """
    model = get_model()
    segments_iter, info = model.transcribe(
        str(audio_path),
        beam_size=5,
        language=None,           # auto-detect
        vad_filter=True,
        vad_parameters={"min_silence_duration_ms": 500},
    )

    segment_list = []
    full_text_parts = []

    for seg in segments_iter:
        segment_list.append(
            {
                "start": round(seg.start, 2),
                "end": round(seg.end, 2),
                "text": seg.text.strip(),
                "avg_logprob": round(seg.avg_logprob, 3),
            }
        )
        full_text_parts.append(seg.text.strip())

    return {
        "text": " ".join(full_text_parts),
        "segments": segment_list,
        "language": info.language,
        "language_probability": round(info.language_probability, 3),
        "duration": round(info.duration, 2),
    }
