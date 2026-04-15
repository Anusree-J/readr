"""TRIBE v2 client abstraction.

Three backends share a single interface so the rest of the stack
(ingest, scoring, autoresearch) is GPU-agnostic:

    MockTribeClient   - synthetic tensors for dev/CI (default)
    LocalTribeClient  - in-process TribeModel.from_pretrained (needs CUDA)
    ModalTribeClient  - HTTP call to a Modal GPU endpoint

All clients return TribePrediction with preds shaped (T, 20484) at 2 Hz,
plus a segments DataFrame (matching TRIBE's native get_events_dataframe
output) and arbitrary meta.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Literal

import numpy as np
import pandas as pd

from api.config import settings
from api.tribe.cache import cache_key, load_cached, save_cached

Modality = Literal["text", "image", "ui", "video"]


@dataclass
class TribeInput:
    """Normalized TRIBE input. Any subset of modality paths may be set."""

    modality: Modality
    video_path: Path | None = None
    audio_path: Path | None = None
    text_path: Path | None = None
    # Used for cache keying: raw content hash + modality + backend
    content_hash: str = ""

    def fingerprint(self) -> str:
        parts = [self.modality, self.content_hash]
        for p in (self.video_path, self.audio_path, self.text_path):
            if p is not None:
                h = hashlib.sha256(Path(p).read_bytes()).hexdigest()[:16]
                parts.append(f"{p.name}:{h}")
        return "|".join(parts)


@dataclass
class TribePrediction:
    """Output of a TRIBE v2 forward pass.

    preds   : (T, n_vertices) array of predicted BOLD-like response per
              fsaverage5 vertex at 2 Hz.
    segments: DataFrame describing the event boundaries TRIBE extracted.
    meta    : free-form dict (duration, modality, backend, etc.).
    """

    preds: np.ndarray
    segments: pd.DataFrame
    meta: dict[str, Any] = field(default_factory=dict)

    @property
    def n_timesteps(self) -> int:
        return int(self.preds.shape[0])

    @property
    def duration_s(self) -> float:
        return self.n_timesteps / settings.sampling_hz

    def to_dict(self) -> dict[str, Any]:
        return {
            "preds_shape": list(self.preds.shape),
            "duration_s": self.duration_s,
            "segments": self.segments.to_dict(orient="records"),
            "meta": self.meta,
        }


class TribeClient:
    """Interface every backend implements."""

    backend: str = "base"

    def predict(self, inp: TribeInput) -> TribePrediction:
        raise NotImplementedError

    def predict_cached(self, inp: TribeInput) -> TribePrediction:
        key = cache_key(self.backend, inp.fingerprint())
        cached = load_cached(key)
        if cached is not None:
            return cached
        pred = self.predict(inp)
        save_cached(key, pred)
        return pred


# ---------------------------------------------------------------------------
# Mock backend -- the workhorse for dev, CI, and autoresearch eval.
# ---------------------------------------------------------------------------


class MockTribeClient(TribeClient):
    """Deterministic synthetic TRIBE output.

    Uses the TribeInput fingerprint to seed an RNG, so the same content
    always yields the same "brain response". Builds a plausible signal
    by mixing slow hemodynamic bases with content-specific noise, and
    boosts specific vertex bands to mimic category-selective regions
    (reward / attention / emotion / language / visual).
    """

    backend = "mock"

    def predict(self, inp: TribeInput) -> TribePrediction:
        seed = int(hashlib.sha256(inp.fingerprint().encode()).hexdigest()[:12], 16)
        rng = np.random.default_rng(seed)

        # Duration heuristic: text is short, images are 5s stares, UI is 8s
        # scanpath, video duration comes from the asset's frame count (caller
        # is expected to populate meta beforehand; default 10s).
        dur_s = {
            "text": max(2.0, min(30.0, 0.12 * len(inp.content_hash) + 3.0)),
            "image": 5.0,
            "ui": 8.0,
            "video": 15.0,
        }[inp.modality]
        T = max(4, int(round(dur_s * settings.sampling_hz)))
        V = settings.n_vertices

        # Low-rank structure: a handful of latent drivers projected onto
        # the cortex via fixed random loadings (seed-derived).
        K = 8
        loadings = rng.normal(size=(K, V)).astype(np.float32)
        latents = np.zeros((T, K), dtype=np.float32)
        for k in range(K):
            # Each driver is a smooth Gaussian bump at a random time
            center = rng.uniform(0, T)
            width = rng.uniform(1.5, T / 2)
            t = np.arange(T)
            latents[:, k] = np.exp(-0.5 * ((t - center) / width) ** 2)
        # Modality-driven amplitude tilt: videos are more engaging than text.
        amp = {"text": 0.6, "image": 0.8, "ui": 0.7, "video": 1.1}[inp.modality]
        preds = amp * latents @ loadings + 0.1 * rng.normal(size=(T, V)).astype(np.float32)

        # Segments table mirrors TRIBE's structure (start, end, label).
        seg_starts = np.linspace(0, T, num=4, endpoint=False)
        segments = pd.DataFrame(
            {
                "start_s": seg_starts / settings.sampling_hz,
                "end_s": (seg_starts + T / 4) / settings.sampling_hz,
                "label": [f"seg_{i}" for i in range(len(seg_starts))],
            }
        )

        return TribePrediction(
            preds=preds.astype(np.float32),
            segments=segments,
            meta={
                "backend": "mock",
                "modality": inp.modality,
                "seed": seed,
                "duration_s": dur_s,
                "sampling_hz": settings.sampling_hz,
            },
        )


# ---------------------------------------------------------------------------
# Local backend -- talks to TribeModel directly. Gated behind import so the
# mock path works without torch installed.
# ---------------------------------------------------------------------------


class LocalTribeClient(TribeClient):
    backend = "local"

    def __init__(self) -> None:
        try:
            from tribe import TribeModel  # type: ignore
        except ImportError as e:
            raise RuntimeError(
                "LocalTribeClient requires the `tribe` package. Install via:\n"
                "  pip install git+https://github.com/facebookresearch/tribev2"
            ) from e
        self._model = TribeModel.from_pretrained("facebook/tribev2")

    def predict(self, inp: TribeInput) -> TribePrediction:
        df = self._model.get_events_dataframe(
            video_path=str(inp.video_path) if inp.video_path else None,
            audio_path=str(inp.audio_path) if inp.audio_path else None,
            text_path=str(inp.text_path) if inp.text_path else None,
        )
        preds, segments = self._model.predict(events=df)
        arr = preds.detach().cpu().numpy() if hasattr(preds, "detach") else np.asarray(preds)
        return TribePrediction(
            preds=arr.astype(np.float32),
            segments=pd.DataFrame(segments),
            meta={"backend": "local", "modality": inp.modality},
        )


# ---------------------------------------------------------------------------
# Modal backend -- HTTP to a Modal function. Server-side code lives in
# api/tribe/modal_app.py.
# ---------------------------------------------------------------------------


class ModalTribeClient(TribeClient):
    backend = "modal"

    def __init__(self, endpoint: str | None = None) -> None:
        self.endpoint = endpoint or settings.modal_endpoint
        if not self.endpoint:
            raise RuntimeError("Set MODAL_TRIBE_ENDPOINT to use ModalTribeClient")

    def predict(self, inp: TribeInput) -> TribePrediction:
        import httpx

        files: dict[str, Any] = {}
        if inp.video_path:
            files["video"] = open(inp.video_path, "rb")
        if inp.audio_path:
            files["audio"] = open(inp.audio_path, "rb")
        if inp.text_path:
            files["text"] = open(inp.text_path, "rb")
        data = {"modality": inp.modality}
        try:
            r = httpx.post(self.endpoint, files=files, data=data, timeout=600)
            r.raise_for_status()
            payload = r.json()
        finally:
            for f in files.values():
                f.close()

        preds = np.array(payload["preds"], dtype=np.float32)
        segments = pd.DataFrame(payload.get("segments", []))
        return TribePrediction(
            preds=preds,
            segments=segments,
            meta={"backend": "modal", "modality": inp.modality, **payload.get("meta", {})},
        )


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------


_singleton: TribeClient | None = None


def get_client(backend: str | None = None) -> TribeClient:
    global _singleton
    if _singleton is not None and backend is None:
        return _singleton
    backend = backend or settings.tribe_backend
    if backend == "mock":
        _singleton = MockTribeClient()
    elif backend == "local":
        _singleton = LocalTribeClient()
    elif backend == "modal":
        _singleton = ModalTribeClient()
    else:
        raise ValueError(f"Unknown TRIBE backend: {backend}")
    return _singleton
