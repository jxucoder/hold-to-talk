"""Claude API text processor — cleans up raw transcription output."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from openmumble.config import Config

SYSTEM_PROMPT = """\
You are a dictation post-processor. You receive raw speech-to-text output and \
return a cleaned version. Rules:

1. Remove filler words (um, uh, like, you know) unless they're clearly intentional.
2. Fix grammar and punctuation.
3. Resolve self-corrections — e.g. "Tuesday no Wednesday" becomes "Wednesday".
4. Preserve the speaker's tone: casual stays casual, formal stays formal.
5. Do NOT add information, change meaning, or editorialize.
6. Return ONLY the cleaned text — no commentary, no quotes, no markdown."""


class Processor:
    """Sends raw transcription to Claude for cleanup."""

    def __init__(self, cfg: Config) -> None:
        self._cfg = cfg
        self._client = None  # lazy-loaded

    def _ensure_client(self):
        if self._client is not None:
            return
        import anthropic
        self._client = anthropic.Anthropic(api_key=self._cfg.anthropic_api_key)

    def cleanup(self, raw_text: str) -> str:
        """Clean up raw transcribed text via Claude. Returns cleaned text."""
        if not raw_text.strip():
            return raw_text

        if not self._cfg.anthropic_api_key:
            print("[processor] No API key — skipping Claude cleanup.")
            return raw_text

        self._ensure_client()

        try:
            response = self._client.messages.create(
                model=self._cfg.claude_model,
                max_tokens=4096,
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": raw_text}],
            )
            return response.content[0].text.strip()
        except Exception as exc:
            print(f"[processor] Claude cleanup failed: {exc}")
            return raw_text
