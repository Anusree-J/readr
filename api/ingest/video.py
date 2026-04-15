"""Short-form video (Reels/TikTok) -> TRIBE v2 video + audio inputs."""
from __future__ import annotations

import subprocess
from pathlib import Path

from api.ingest.router import IngestResult, _hash_bytes
from api.tribe.client import TribeInput


def _extract_audio(video_path: Path, audio_path: Path) -> bool:
    """Extract audio to wav. Returns True on success, False if no audio."""
    try:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        ffmpeg = "ffmpeg"
    try:
        subprocess.run(
            [
                ffmpeg,
                "-y",
                "-i",
                str(video_path),
                "-vn",
                "-ac",
                "1",
                "-ar",
                "16000",
                "-f",
                "wav",
                str(audio_path),
            ],
            check=True,
            capture_output=True,
        )
        return audio_path.exists() and audio_path.stat().st_size > 128
    except Exception:
        return False


def ingest_video(video_bytes: bytes, workdir: Path) -> IngestResult:
    h = _hash_bytes(video_bytes)
    video_path = workdir / f"reel_{h}.mp4"
    video_path.write_bytes(video_bytes)
    audio_path = workdir / f"reel_{h}.wav"
    has_audio = _extract_audio(video_path, audio_path)

    tribe_input = TribeInput(
        modality="video",
        video_path=video_path,
        audio_path=audio_path if has_audio else None,
        content_hash=h,
    )
    return IngestResult(tribe_input=tribe_input, preview_path=video_path, raw_hash=h)
