"""Entry point for `python -m openmumble` and the `openmumble` CLI command."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from openmumble.config import Config


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="openmumble",
        description="Local-first voice dictation with Whisper STT and optional Claude cleanup.",
    )
    parser.add_argument(
        "-c", "--config",
        type=Path,
        default=None,
        help="Path to config YAML (default: ./config.yaml or config.example.yaml)",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Override Whisper model size (e.g. tiny.en, small.en, medium, large-v3)",
    )
    parser.add_argument(
        "--hotkey",
        default=None,
        help="Override hotkey (e.g. ctrl, alt, shift, cmd, or a single character)",
    )
    parser.add_argument(
        "--no-cleanup",
        action="store_true",
        help="Disable Claude API cleanup pass (use raw Whisper output)",
    )
    args = parser.parse_args(argv)

    # Resolve config file
    config_path = args.config
    if config_path is None:
        for candidate in ("config.yaml", "config.example.yaml"):
            p = Path(candidate)
            if p.exists():
                config_path = p
                break

    cfg = Config.load(config_path)

    # CLI overrides
    if args.model:
        cfg.whisper.model_size = args.model
    if args.hotkey:
        cfg.hotkey = args.hotkey
    if args.no_cleanup:
        cfg.enable_cleanup = False

    from openmumble.app import App

    app = App(cfg)
    app.run()


if __name__ == "__main__":
    main()
