"""Dispatch an incoming payload to the right modality ingester."""
from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from api.tribe.client import TribeInput

Modality = Literal["text", "image", "ui", "video"]


@dataclass
class IngestResult:
    tribe_input: TribeInput
    preview_path: Path | None   # what the user sees in the result page
    raw_hash: str               # stable id for caching + result URLs


def _hash_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()[:20]


def ingest_any(
    modality: Modality,
    *,
    text: str | None = None,
    image_bytes: bytes | None = None,
    video_bytes: bytes | None = None,
    workdir: Path,
) -> IngestResult:
    workdir.mkdir(parents=True, exist_ok=True)
    if modality == "text":
        assert text is not None, "text modality requires text"
        from api.ingest.text import ingest_text
        return ingest_text(text, workdir)
    if modality == "image":
        assert image_bytes is not None, "image modality requires bytes"
        from api.ingest.image import ingest_image
        return ingest_image(image_bytes, workdir)
    if modality == "ui":
        assert image_bytes is not None, "ui modality requires screenshot bytes"
        from api.ingest.ui import ingest_ui
        return ingest_ui(image_bytes, workdir)
    if modality == "video":
        assert video_bytes is not None, "video modality requires bytes"
        from api.ingest.video import ingest_video
        return ingest_video(video_bytes, workdir)
    raise ValueError(f"Unknown modality: {modality}")
