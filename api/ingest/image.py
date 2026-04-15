"""Single image -> 5-second 'stare' video for TRIBE v2."""
from __future__ import annotations

from pathlib import Path

import numpy as np

from api.ingest.router import IngestResult, _hash_bytes
from api.tribe.client import TribeInput


STARE_SECONDS = 5.0
FPS = 10


def _stare_video(frame: np.ndarray, out: Path) -> None:
    """Write a tiny mp4 that shows `frame` for STARE_SECONDS seconds."""
    import imageio.v2 as imageio

    n_frames = int(STARE_SECONDS * FPS)
    writer = imageio.get_writer(
        out, fps=FPS, codec="libx264", quality=6, macro_block_size=1
    )
    try:
        for _ in range(n_frames):
            writer.append_data(frame)
    finally:
        writer.close()


def ingest_image(image_bytes: bytes, workdir: Path) -> IngestResult:
    from PIL import Image
    import io

    h = _hash_bytes(image_bytes)
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    # Resize so the longest side is 512 -- TRIBE's V-JEPA encoder is happy
    # with modest resolution and this keeps ffmpeg fast.
    img.thumbnail((512, 512))
    arr = np.array(img)
    preview_path = workdir / f"image_{h}.jpg"
    img.save(preview_path, quality=85)
    video_path = workdir / f"image_{h}.mp4"
    _stare_video(arr, video_path)

    tribe_input = TribeInput(
        modality="image",
        video_path=video_path,
        content_hash=h,
    )
    return IngestResult(tribe_input=tribe_input, preview_path=preview_path, raw_hash=h)
