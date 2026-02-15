"""Configuration management for OpenMumble."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

import yaml


@dataclass
class WhisperConfig:
    model_size: str = "small.en"
    device: str = "auto"
    compute_type: str = "int8"


@dataclass
class AudioConfig:
    sample_rate: int = 16000
    channels: int = 1


@dataclass
class Config:
    anthropic_api_key: str = ""
    claude_model: str = "claude-sonnet-4-20250514"
    whisper: WhisperConfig = field(default_factory=WhisperConfig)
    audio: AudioConfig = field(default_factory=AudioConfig)
    hotkey: str = "ctrl"
    enable_cleanup: bool = True

    @classmethod
    def load(cls, path: str | Path | None = None) -> Config:
        """Load config from YAML file, falling back to defaults.

        Settings are overridden by environment variables where applicable:
          - ANTHROPIC_API_KEY overrides anthropic_api_key
          - OPENMUMBLE_MODEL overrides whisper.model_size
          - OPENMUMBLE_HOTKEY overrides hotkey
        """
        cfg = cls()

        if path is not None:
            p = Path(path)
            if p.exists():
                with open(p) as f:
                    data = yaml.safe_load(f) or {}
                cfg = _merge(cfg, data)

        # Environment variable overrides
        env_key = os.environ.get("ANTHROPIC_API_KEY")
        if env_key:
            cfg.anthropic_api_key = env_key

        env_model = os.environ.get("OPENMUMBLE_MODEL")
        if env_model:
            cfg.whisper.model_size = env_model

        env_hotkey = os.environ.get("OPENMUMBLE_HOTKEY")
        if env_hotkey:
            cfg.hotkey = env_hotkey

        return cfg


def _merge(cfg: Config, data: dict) -> Config:
    """Merge a raw YAML dict into a Config instance."""
    if "anthropic_api_key" in data:
        cfg.anthropic_api_key = str(data["anthropic_api_key"])
    if "claude_model" in data:
        cfg.claude_model = str(data["claude_model"])
    if "hotkey" in data:
        cfg.hotkey = str(data["hotkey"])
    if "enable_cleanup" in data:
        cfg.enable_cleanup = bool(data["enable_cleanup"])

    whisper_data = data.get("whisper", {})
    if isinstance(whisper_data, dict):
        for key in ("model_size", "device", "compute_type"):
            if key in whisper_data:
                setattr(cfg.whisper, key, str(whisper_data[key]))

    audio_data = data.get("audio", {})
    if isinstance(audio_data, dict):
        if "sample_rate" in audio_data:
            cfg.audio.sample_rate = int(audio_data["sample_rate"])
        if "channels" in audio_data:
            cfg.audio.channels = int(audio_data["channels"])

    return cfg
