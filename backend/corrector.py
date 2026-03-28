"""
Ollama-based transcript correction.
Removes filler words, fixes punctuation/grammar while preserving speaker's intent.

Ollama host is read from the OLLAMA_HOST environment variable (default: http://localhost:11434).
Set OLLAMA_HOST=http://localhost:11434 when running Ollama inside Docker Desktop.
"""

import os

import ollama

# Docker Desktop exposes Ollama on localhost:11434 — same as a native install.
# Override with OLLAMA_HOST env var if your port differs.
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")

SYSTEM_PROMPT = """You are a professional transcript editor. Your task is to improve a speech-to-text transcript.

Rules:
- Fix punctuation and capitalization
- Remove filler words: um, uh, like, you know, kind of, sort of, basically, literally, right
- Fix grammatical errors while preserving the speaker's original meaning and vocabulary
- Do NOT add new content, opinions, or change facts
- Do NOT summarize — keep the full content
- Return ONLY the corrected transcript text with no commentary, no quotes, no prefix
"""


def correct_transcript(raw_transcript: str, model: str = "mistral:latest") -> dict:
    """
    Use a local Ollama model to clean and correct a raw Whisper transcript.
    Falls back to returning the original on error.
    """
    try:
        client = ollama.Client(host=OLLAMA_HOST)
        response = client.chat(
            model=model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": f"Please correct this transcript:\n\n{raw_transcript}",
                },
            ],
        )
        corrected = response["message"]["content"].strip()
        return {
            "corrected_text": corrected,
            "model_used": model,
            "success": True,
        }
    except Exception as exc:
        return {
            "corrected_text": raw_transcript,
            "model_used": model,
            "success": False,
            "error": str(exc),
        }
