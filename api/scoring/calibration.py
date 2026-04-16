"""Calibrate predicted virality score -> expected view range.

Trains an isotonic regression on the labeled dataset so every time the
scoring head runs the result page can answer "how many views is that,
actually?". The fit is cached to disk and invalidated when the labeled
dataset changes.

Prediction format:
    predict_views(score) -> (low, mid, high)   # 80% bootstrap band

The model is monotone (higher score -> higher expected views) which keeps
it interpretable even as the autoresearch agent rewrites score.py.
"""
from __future__ import annotations

import hashlib
import importlib
import json
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np

from api.autoresearch.dataset import LabeledItem, load_dataset
from api.config import DATA_DIR
from api.ingest import ingest_any
from api.tribe.client import get_client

CALIB_DIR = DATA_DIR / "calibration"
CALIB_DIR.mkdir(exist_ok=True)
CALIB_FIT = CALIB_DIR / "fit.json"


@dataclass
class Calibration:
    dataset_hash: str
    # Arrays are stored as plain lists for JSON. x = sorted training scores,
    # y = isotonic-regressed log-views, residuals = per-point fit errors.
    x: list[float]
    y: list[float]
    residuals: list[float]
    n: int
    score_py_version: str

    def to_json(self) -> str:
        return json.dumps(asdict(self))

    @classmethod
    def from_json(cls, s: str) -> "Calibration":
        return cls(**json.loads(s))


def _dataset_hash(items: list[LabeledItem], score_py_text: str) -> str:
    """Hash labels + score.py so the fit invalidates when either changes."""
    h = hashlib.sha256()
    for it in sorted(items, key=lambda x: x.id):
        h.update(f"{it.id}|{it.views}".encode())
    h.update(score_py_text.encode())
    return h.hexdigest()[:16]


def _score_all(items: list[LabeledItem]) -> tuple[np.ndarray, np.ndarray]:
    """Run score() on every labeled item, paired with log1p(views)."""
    import sys
    if "api.scoring.score" in sys.modules:
        score_mod = importlib.reload(sys.modules["api.scoring.score"])
    else:
        score_mod = importlib.import_module("api.scoring.score")

    client = get_client()
    scores = np.zeros(len(items), dtype=np.float64)
    truth = np.zeros(len(items), dtype=np.float64)
    with tempfile.TemporaryDirectory() as td:
        wd = Path(td)
        for i, it in enumerate(items):
            if it.modality == "text":
                ing = ingest_any("text", text=it.content or "", workdir=wd)
            elif it.modality in ("image", "ui"):
                assert it.asset is not None
                ing = ingest_any(it.modality, image_bytes=it.asset.read_bytes(), workdir=wd)
            else:  # video
                assert it.asset is not None
                ing = ingest_any("video", video_bytes=it.asset.read_bytes(), workdir=wd)
            pred = client.predict_cached(ing.tribe_input)
            vs = score_mod.score(pred)
            scores[i] = vs.score
            truth[i] = np.log1p(it.views)
    return scores, truth


def _isotonic_fit(x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Pool-adjacent-violators isotonic regression. Returns sorted (x, y_hat)."""
    order = np.argsort(x)
    xs = x[order]
    ys = y[order]
    # Average duplicate x so PAV is well-defined.
    dedup_x: list[float] = []
    dedup_y: list[float] = []
    i = 0
    while i < len(xs):
        j = i
        while j + 1 < len(xs) and xs[j + 1] == xs[i]:
            j += 1
        dedup_x.append(float(xs[i]))
        dedup_y.append(float(np.mean(ys[i : j + 1])))
        i = j + 1
    # PAV
    n = len(dedup_y)
    w = [1.0] * n
    yh = list(dedup_y)
    stack_y: list[float] = []
    stack_w: list[float] = []
    stack_start: list[int] = []
    for k in range(n):
        cy, cw, cs = yh[k], w[k], k
        while stack_y and stack_y[-1] > cy:
            py, pw, ps = stack_y.pop(), stack_w.pop(), stack_start.pop()
            cy = (py * pw + cy * cw) / (pw + cw)
            cw = pw + cw
            cs = ps
        stack_y.append(cy)
        stack_w.append(cw)
        stack_start.append(cs)
    out = np.zeros(n, dtype=np.float64)
    for yv, wv, sv in zip(stack_y, stack_w, stack_start):
        end = int(sv + wv)
        out[int(sv):end] = yv
    return np.array(dedup_x), out


def fit_and_save() -> Calibration:
    items = load_dataset()
    from api.config import SCORING_DIR
    score_py_text = (SCORING_DIR / "score.py").read_text()
    ds_hash = _dataset_hash(items, score_py_text)

    scores, truth = _score_all(items)
    xs, ys_hat = _isotonic_fit(scores, truth)
    # Per-point residuals in original order — used for bootstrap CI width.
    yhat_full = np.interp(scores, xs, ys_hat)
    residuals = (truth - yhat_full).tolist()

    calib = Calibration(
        dataset_hash=ds_hash,
        x=xs.tolist(),
        y=ys_hat.tolist(),
        residuals=residuals,
        n=len(items),
        score_py_version=hashlib.sha256(score_py_text.encode()).hexdigest()[:12],
    )
    CALIB_FIT.write_text(calib.to_json())
    return calib


def load_calibration() -> Calibration | None:
    if not CALIB_FIT.exists():
        return None
    try:
        return Calibration.from_json(CALIB_FIT.read_text())
    except Exception:
        return None


def maybe_refit() -> Calibration:
    """Return a current calibration, refitting if the dataset or score.py
    have changed since the last fit."""
    items = load_dataset()
    from api.config import SCORING_DIR
    score_py_text = (SCORING_DIR / "score.py").read_text()
    ds_hash = _dataset_hash(items, score_py_text)
    cached = load_calibration()
    if cached and cached.dataset_hash == ds_hash:
        return cached
    return fit_and_save()


def predict_views(score: float, calib: Calibration | None = None) -> dict:
    """Map a 0-100 score onto (low, mid, high) view estimates plus metadata."""
    if calib is None:
        calib = maybe_refit()
    xs = np.array(calib.x)
    ys = np.array(calib.y)
    res = np.array(calib.residuals) if calib.residuals else np.array([0.0])
    if len(xs) == 0:
        return {"low": 0, "mid": 0, "high": 0, "n": 0}
    log_mid = float(np.interp(score, xs, ys))
    # 80% bootstrap band using empirical residual quantiles.
    q_lo = float(np.quantile(res, 0.10)) if len(res) > 1 else 0.0
    q_hi = float(np.quantile(res, 0.90)) if len(res) > 1 else 0.0
    mid = float(np.expm1(log_mid))
    low = float(np.expm1(log_mid + q_lo))
    high = float(np.expm1(log_mid + q_hi))
    return {
        "low": max(0.0, low),
        "mid": max(0.0, mid),
        "high": max(low, high),
        "n": calib.n,
    }
