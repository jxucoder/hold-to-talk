"""Whisper transcription module — converts audio to text locally."""

from __future__ import annotations

from typing import TYPE_CHECKING

import numpy as np

if TYPE_CHECKING:
    from openmumble.config import WhisperConfig


class Transcriber:
    """Wraps faster-whisper for local speech-to-text."""

    def __init__(self, whisper_cfg: WhisperConfig) -> None:
        self._cfg = whisper_cfg
        self._model = None  # lazy-loaded

    def _load_model(self):
        from faster_whisper import WhisperModel

        device = self._cfg.device
        if device == "auto":
            device = "cpu"  # faster-whisper defaults; CUDA picked up automatically
        print(f"[transcriber] Loading Whisper model '{self._cfg.model_size}' "
              f"(device={device}, compute={self._cfg.compute_type}) …")
        self._model = WhisperModel(
            self._cfg.model_size,
            device=device,
            compute_type=self._cfg.compute_type,
        )
        print("[transcriber] Model loaded.")

    def transcribe(self, audio: np.ndarray) -> str:
        """Transcribe a float32 audio array and return the text."""
        if audio.size == 0:
            return ""
        if self._model is None:
            self._load_model()

        segments, _info = self._model.transcribe(
            audio,
            beam_size=5,
            language="en",
            vad_filter=True,
        )
        text = " ".join(seg.text.strip() for seg in segments)
        return text.strip()
