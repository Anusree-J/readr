"""Text tweet -> TRIBE text input."""
from __future__ import annotations

from pathlib import Path

from api.ingest.router import IngestResult, _hash_bytes
from api.tribe.client import TribeInput


def ingest_text(text: str, workdir: Path) -> IngestResult:
    h = _hash_bytes(text.encode("utf-8"))
    text_path = workdir / f"text_{h}.txt"
    text_path.write_text(text, encoding="utf-8")
    tribe_input = TribeInput(
        modality="text",
        text_path=text_path,
        content_hash=h,
    )
    return IngestResult(tribe_input=tribe_input, preview_path=None, raw_hash=h)
