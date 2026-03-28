import sys
import os

sys.path.insert(0, os.path.dirname(__file__))


def download_whisper():
    print("[models] Downloading Whisper large-v3 (~3 GB)...")
    from faster_whisper import WhisperModel
    WhisperModel("large-v3", device="cpu", compute_type="int8")
    print("[models] Whisper large-v3 ready.")


def download_f5tts():
    print("[models] Downloading F5-TTS model (~1.5 GB)...")
    import torch

    def _detect_device():
        if torch.cuda.is_available():
            return "cuda"
        if torch.backends.mps.is_available():
            return "mps"
        return "cpu"

    from f5_tts.api import F5TTS
    F5TTS(device=_detect_device())
    print("[models] F5-TTS model ready.")


if __name__ == "__main__":
    print("\n── Downloading ML models (first-time only) ──")
    print("This may take 10-20 minutes depending on your internet speed.\n")
    download_whisper()
    download_f5tts()
    print("\n[models] All models downloaded and cached.")
