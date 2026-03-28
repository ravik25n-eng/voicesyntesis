import sys
import os

# Suppress HuggingFace symlink warning on Windows
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

sys.path.insert(0, os.path.dirname(__file__))


def download_whisper():
    print("[models] Downloading Whisper large-v3 (~3 GB)...")
    from faster_whisper import WhisperModel
    WhisperModel("large-v3", device="cpu", compute_type="int8")
    print("[models] Whisper large-v3 ready.")


def download_xtts():
    print("[models] Downloading Coqui XTTS v2 model (~1.8 GB)...")
    import os
    import torch
    os.environ["COQUI_TOS_AGREED"] = "1"
    from TTS.api import TTS
    device = "cuda" if torch.cuda.is_available() else "cpu"
    TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)
    print("[models] XTTS v2 model ready.")


if __name__ == "__main__":
    print("\n-- Downloading ML models (first-time only) --")
    print("This may take 10-20 minutes depending on your internet speed.\n")
    download_whisper()
    download_xtts()
    print("\n[models] All models downloaded and cached.")
