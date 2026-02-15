"""Main application orchestrator — ties recording, transcription, cleanup, and insertion together."""

from __future__ import annotations

import sys
import threading
import time

from pynput import keyboard

from openmumble.audio import Recorder
from openmumble.config import Config
from openmumble.inserter import insert_text
from openmumble.processor import Processor
from openmumble.transcriber import Transcriber

# Map config hotkey names → pynput Key objects
_SPECIAL_KEYS = {
    "ctrl": keyboard.Key.ctrl_l,
    "alt": keyboard.Key.alt_l,
    "shift": keyboard.Key.shift_l,
    "cmd": keyboard.Key.cmd_l,
    "option": keyboard.Key.alt_l,  # macOS alias
    "f1": keyboard.Key.f1,
    "f2": keyboard.Key.f2,
    "f3": keyboard.Key.f3,
    "f4": keyboard.Key.f4,
    "f5": keyboard.Key.f5,
    "f6": keyboard.Key.f6,
    "f7": keyboard.Key.f7,
    "f8": keyboard.Key.f8,
    "f9": keyboard.Key.f9,
    "f10": keyboard.Key.f10,
    "f11": keyboard.Key.f11,
    "f12": keyboard.Key.f12,
}


class App:
    """Push-to-talk dictation application."""

    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        self.recorder = Recorder(cfg.audio)
        self.transcriber = Transcriber(cfg.whisper)
        self.processor = Processor(cfg) if cfg.enable_cleanup else None
        self._recording = False
        self._hotkey = self._resolve_hotkey(cfg.hotkey)

    # ── public ────────────────────────────────────────────────────────

    def run(self) -> None:
        """Start listening for the hotkey. Blocks until Ctrl+C."""
        print(f"[openmumble] Ready — hold [{self.cfg.hotkey}] to dictate, "
              "release to transcribe. Ctrl+C to quit.")

        # Pre-load whisper model in background so first dictation is fast
        threading.Thread(target=self.transcriber.transcribe,
                         args=(__import__("numpy").array([], dtype="float32"),),
                         daemon=True).start()

        with keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release,
        ) as listener:
            try:
                listener.join()
            except KeyboardInterrupt:
                print("\n[openmumble] Bye.")

    # ── hotkey handling ───────────────────────────────────────────────

    @staticmethod
    def _resolve_hotkey(name: str):
        lower = name.lower()
        if lower in _SPECIAL_KEYS:
            return _SPECIAL_KEYS[lower]
        # Single character key
        if len(name) == 1:
            return keyboard.KeyCode.from_char(name)
        raise ValueError(f"Unknown hotkey: {name!r}. Use ctrl/alt/shift/cmd or a single character.")

    def _key_matches(self, key) -> bool:
        if isinstance(self._hotkey, keyboard.Key):
            # Also match the right-side variant (e.g. ctrl_r for ctrl_l)
            if isinstance(key, keyboard.Key):
                return key.name.rstrip("_lr") == self._hotkey.name.rstrip("_lr") or key == self._hotkey
            return False
        return key == self._hotkey

    def _on_press(self, key) -> None:
        if self._key_matches(key) and not self._recording:
            self._recording = True
            print("[openmumble] 🎙  Recording…")
            self.recorder.start()

    def _on_release(self, key) -> None:
        if self._key_matches(key) and self._recording:
            self._recording = False
            audio = self.recorder.stop()
            if audio.size == 0:
                print("[openmumble] No audio captured.")
                return
            duration = audio.size / self.cfg.audio.sample_rate
            print(f"[openmumble] Captured {duration:.1f}s of audio. Transcribing…")
            # Process in a thread so we don't block the hotkey listener
            threading.Thread(target=self._process, args=(audio,), daemon=True).start()

    # ── pipeline ──────────────────────────────────────────────────────

    def _process(self, audio) -> None:
        t0 = time.perf_counter()

        raw_text = self.transcriber.transcribe(audio)
        t_stt = time.perf_counter() - t0

        if not raw_text:
            print("[openmumble] (no speech detected)")
            return

        print(f"[openmumble] Raw ({t_stt:.2f}s): {raw_text}")

        final_text = raw_text
        if self.processor:
            t1 = time.perf_counter()
            final_text = self.processor.cleanup(raw_text)
            t_llm = time.perf_counter() - t1
            if final_text != raw_text:
                print(f"[openmumble] Cleaned ({t_llm:.2f}s): {final_text}")

        insert_text(final_text)
        total = time.perf_counter() - t0
        print(f"[openmumble] Done ({total:.2f}s total). Text inserted.")
