"""UI screenshot -> saliency-driven scanpath video for TRIBE v2.

Screenshots are high-information but the visual system does not ingest
them as a single 'stare'. We simulate a natural UI scan by generating a
pan + zoom trajectory that visits a few salient regions. This gives TRIBE
a video-like signal that exercises both visual and language pathways.
"""
from __future__ import annotations

import io
from pathlib import Path

import cv2
import numpy as np

from api.ingest.router import IngestResult, _hash_bytes
from api.tribe.client import TribeInput


SCAN_SECONDS = 8.0
FPS = 10


def _saliency_points(img: np.ndarray, k: int = 4) -> list[tuple[int, int]]:
    """Pick k high-contrast regions in a rough F-pattern order."""
    gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
    edges = cv2.Canny(gray, 80, 180)
    h, w = edges.shape
    points: list[tuple[int, int]] = []
    # Divide into a 2x2 grid plus center; within each cell take the
    # densest-edge patch.
    cells = [
        (0, 0, w // 2, h // 2),
        (w // 2, 0, w, h // 2),
        (0, h // 2, w // 2, h),
        (w // 2, h // 2, w, h),
        (w // 4, h // 4, 3 * w // 4, 3 * h // 4),
    ]
    for (x0, y0, x1, y1) in cells[:k]:
        patch = edges[y0:y1, x0:x1]
        if patch.size == 0:
            continue
        ys, xs = np.where(patch > 0)
        if len(xs) == 0:
            points.append(((x0 + x1) // 2, (y0 + y1) // 2))
        else:
            cx = int(xs.mean()) + x0
            cy = int(ys.mean()) + y0
            points.append((cx, cy))
    return points


def _crop_at(img: np.ndarray, cx: int, cy: int, zoom: float, out_size: tuple[int, int]) -> np.ndarray:
    h, w = img.shape[:2]
    ow, oh = out_size
    cw = int(w / zoom)
    ch = int(h / zoom)
    x0 = max(0, min(w - cw, cx - cw // 2))
    y0 = max(0, min(h - ch, cy - ch // 2))
    patch = img[y0:y0 + ch, x0:x0 + cw]
    return cv2.resize(patch, (ow, oh), interpolation=cv2.INTER_LINEAR)


def ingest_ui(image_bytes: bytes, workdir: Path) -> IngestResult:
    from PIL import Image
    import imageio.v2 as imageio

    h = _hash_bytes(image_bytes)
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    img.thumbnail((1280, 1280))
    arr = np.array(img)
    preview_path = workdir / f"ui_{h}.png"
    img.save(preview_path)

    points = _saliency_points(arr)
    out_size = (640, 480)
    n_frames = int(SCAN_SECONDS * FPS)
    # Piecewise-linear path over the saliency points, interpolating cursor
    # position and zoom. Dwell at each point for ~1/(len(points)+1) of total.
    path_xy = []
    if not points:
        path_xy = [(arr.shape[1] // 2, arr.shape[0] // 2)] * n_frames
    else:
        segs = len(points)
        frames_per_seg = n_frames // segs
        for i, (cx, cy) in enumerate(points):
            nxt = points[(i + 1) % segs]
            for f in range(frames_per_seg):
                t = f / max(1, frames_per_seg - 1)
                x = int((1 - t) * cx + t * nxt[0])
                y = int((1 - t) * cy + t * nxt[1])
                path_xy.append((x, y))
        while len(path_xy) < n_frames:
            path_xy.append(points[-1])

    video_path = workdir / f"ui_{h}.mp4"
    writer = imageio.get_writer(video_path, fps=FPS, codec="libx264", quality=6, macro_block_size=1)
    try:
        for idx, (cx, cy) in enumerate(path_xy):
            # Zoom breathes 1.0 -> 1.8 -> 1.0 across the scan.
            phase = idx / max(1, len(path_xy) - 1)
            zoom = 1.0 + 0.8 * np.sin(np.pi * phase)
            frame = _crop_at(arr, cx, cy, zoom, out_size)
            writer.append_data(frame)
    finally:
        writer.close()

    tribe_input = TribeInput(
        modality="ui",
        video_path=video_path,
        content_hash=h,
    )
    return IngestResult(tribe_input=tribe_input, preview_path=preview_path, raw_hash=h)
