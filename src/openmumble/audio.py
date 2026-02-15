"""Audio recording module — captures microphone input into a NumPy buffer."""

from __future__ import annotations

import threading
from typing import TYPE_CHECKING

import numpy as np
import sounddevice as sd

if TYPE_CHECKING:
    from openmumble.config import AudioConfig


class Recorder:
    """Records audio from the default input device while ``recording`` is True."""

    def __init__(self, audio_cfg: AudioConfig) -> None:
        self.sample_rate = audio_cfg.sample_rate
        self.channels = audio_cfg.channels
        self._frames: list[np.ndarray] = []
        self._stream: sd.InputStream | None = None
        self._lock = threading.Lock()

    def start(self) -> None:
        """Begin recording."""
        with self._lock:
            self._frames.clear()
            self._stream = sd.InputStream(
                samplerate=self.sample_rate,
                channels=self.channels,
                dtype="float32",
                callback=self._callback,
            )
            self._stream.start()

    def stop(self) -> np.ndarray:
        """Stop recording and return captured audio as a float32 numpy array."""
        with self._lock:
            if self._stream is not None:
                self._stream.stop()
                self._stream.close()
                self._stream = None
            if not self._frames:
                return np.array([], dtype=np.float32)
            audio = np.concatenate(self._frames, axis=0)
            self._frames.clear()
        # Flatten to mono 1-D array
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        return audio

    def _callback(
        self,
        indata: np.ndarray,
        frames: int,
        time_info: object,
        status: sd.CallbackFlags,
    ) -> None:
        if status:
            print(f"[audio] {status}")
        self._frames.append(indata.copy())
