"""Content-addressed cache for TRIBE predictions.

Keyed by (backend, fingerprint) so identical content never re-runs TRIBE.
Stores preds as float16 .npy (half the disk cost) plus a sidecar .json
holding segments + meta.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import TYPE_CHECKING

import numpy as np
import pandas as pd

from api.config import CACHE_DIR

if TYPE_CHECKING:
    from api.tribe.client import TribePrediction


def cache_key(backend: str, fingerprint: str) -> str:
    h = hashlib.sha256(f"{backend}|{fingerprint}".encode()).hexdigest()[:24]
    return f"{backend}_{h}"


def _paths(key: str) -> tuple[Path, Path]:
    return CACHE_DIR / f"{key}.npy", CACHE_DIR / f"{key}.json"


def load_cached(key: str) -> "TribePrediction | None":
    from api.tribe.client import TribePrediction

    npy, js = _paths(key)
    if not (npy.exists() and js.exists()):
        return None
    preds = np.load(npy).astype(np.float32)
    sidecar = json.loads(js.read_text())
    segments = pd.DataFrame(sidecar.get("segments", []))
    return TribePrediction(preds=preds, segments=segments, meta=sidecar.get("meta", {}))


def save_cached(key: str, pred: "TribePrediction") -> None:
    npy, js = _paths(key)
    np.save(npy, pred.preds.astype(np.float16))
    js.write_text(
        json.dumps(
            {
                "segments": pred.segments.to_dict(orient="records"),
                "meta": pred.meta,
            },
            default=str,
        )
    )
