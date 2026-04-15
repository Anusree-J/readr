"""Runtime configuration loaded from environment."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "data"
CACHE_DIR = DATA_DIR / "tribe_cache"
LABELED_DIR = DATA_DIR / "labeled"
ASSETS_DIR = LABELED_DIR / "assets"
SCORING_DIR = Path(__file__).resolve().parent / "scoring"
AUTORESEARCH_DIR = Path(__file__).resolve().parent / "autoresearch"

for _p in (DATA_DIR, CACHE_DIR, LABELED_DIR, ASSETS_DIR):
    _p.mkdir(parents=True, exist_ok=True)


@dataclass(frozen=True)
class Settings:
    tribe_backend: str = os.getenv("TRIBE_BACKEND", "mock")  # mock | local | modal
    modal_endpoint: str | None = os.getenv("MODAL_TRIBE_ENDPOINT")
    hf_token: str | None = os.getenv("HF_TOKEN")
    anthropic_api_key: str | None = os.getenv("ANTHROPIC_API_KEY")
    agent_model: str = os.getenv("AGENT_MODEL", "claude-opus-4-6")
    sampling_hz: float = 2.0  # TRIBE v2 native rate
    n_vertices: int = 20484   # fsaverage5 vertex count
    cors_origin: str = os.getenv("CORS_ORIGIN", "http://localhost:3000")


settings = Settings()
