"""Text insertion module — pastes text into the active window."""

from __future__ import annotations

import platform
import subprocess


def insert_text(text: str) -> None:
    """Copy *text* to clipboard and paste it into the currently focused window.

    macOS: uses pbcopy + AppleScript Cmd+V keystroke.
    Linux: uses xclip + xdotool Ctrl+V.
    """
    system = platform.system()

    if system == "Darwin":
        _insert_macos(text)
    elif system == "Linux":
        _insert_linux(text)
    else:
        # Fallback: just copy to clipboard via pyperclip
        import pyperclip
        pyperclip.copy(text)
        print("[inserter] Text copied to clipboard (auto-paste not supported "
              f"on {system}). Press Ctrl/Cmd+V to paste.")


def _insert_macos(text: str) -> None:
    """macOS: pbcopy → Cmd+V via AppleScript."""
    subprocess.run(["pbcopy"], input=text.encode(), check=True)
    subprocess.run(
        [
            "osascript",
            "-e",
            'tell application "System Events" to keystroke "v" using command down',
        ],
        check=True,
    )


def _insert_linux(text: str) -> None:
    """Linux/X11: xclip → xdotool Ctrl+V."""
    subprocess.run(
        ["xclip", "-selection", "clipboard"],
        input=text.encode(),
        check=True,
    )
    subprocess.run(["xdotool", "key", "ctrl+v"], check=True)
