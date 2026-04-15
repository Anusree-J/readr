"""Evaluation: score all items, compare to ground-truth views."""
from __future__ import annotations

import importlib
import math
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from api.autoresearch.dataset import LabeledItem, load_dataset, split
from api.ingest import ingest_any
from api.tribe.client import get_client


@dataclass
class EvalResult:
    spearman: float
    mae: float
    precision_at_topk: float   # fraction of top-k predicted that are in top-k actual
    n: int
    per_item: list[dict]

    def to_dict(self) -> dict:
        return {
            "spearman": self.spearman,
            "mae": self.mae,
            "precision_at_topk": self.precision_at_topk,
            "n": self.n,
        }


def _spearman(a: list[float], b: list[float]) -> float:
    """Simple Spearman rank correlation without SciPy import."""
    if len(a) < 2:
        return 0.0
    def rank(x):
        order = sorted(range(len(x)), key=lambda i: x[i])
        r = [0.0] * len(x)
        i = 0
        while i < len(x):
            j = i
            while j + 1 < len(x) and x[order[j + 1]] == x[order[i]]:
                j += 1
            avg = (i + j) / 2 + 1
            for k in range(i, j + 1):
                r[order[k]] = avg
            i = j + 1
        return r
    ra, rb = rank(a), rank(b)
    mean_a = sum(ra) / len(ra)
    mean_b = sum(rb) / len(rb)
    num = sum((ra[i] - mean_a) * (rb[i] - mean_b) for i in range(len(ra)))
    da = math.sqrt(sum((x - mean_a) ** 2 for x in ra))
    db = math.sqrt(sum((x - mean_b) ** 2 for x in rb))
    if da == 0 or db == 0:
        return 0.0
    return num / (da * db)


def _ingest_item(item: LabeledItem, workdir: Path):
    if item.modality == "text":
        return ingest_any("text", text=item.content or "", workdir=workdir)
    if item.modality in ("image", "ui"):
        assert item.asset is not None, f"{item.modality} item needs asset"
        return ingest_any(item.modality, image_bytes=item.asset.read_bytes(), workdir=workdir)
    if item.modality == "video":
        assert item.asset is not None, "video item needs asset"
        return ingest_any("video", video_bytes=item.asset.read_bytes(), workdir=workdir)
    raise ValueError(item.modality)


def run_eval(
    backend: str | None = None,
    split_name: str = "val",
    items: list[LabeledItem] | None = None,
) -> EvalResult:
    """Score every labeled item with the current scoring/score.py and report metrics.

    Force-reloads the scoring module so autoresearch edits take effect
    without restarting the process.
    """
    # Fresh import of scoring.score every call so edits apply immediately
    # (the autoresearch runner rewrites this file between experiments).
    import sys
    if "api.scoring.score" in sys.modules:
        score_mod = importlib.reload(sys.modules["api.scoring.score"])
    else:
        score_mod = importlib.import_module("api.scoring.score")

    if items is None:
        all_items = load_dataset()
        train, val = split(all_items)
        items = val if split_name == "val" else train

    client = get_client(backend)

    preds: list[float] = []
    truth: list[float] = []
    per: list[dict] = []
    with tempfile.TemporaryDirectory() as td:
        wd = Path(td)
        for it in items:
            ing = _ingest_item(it, wd)
            tp = client.predict_cached(ing.tribe_input)
            vs = score_mod.score(tp)
            preds.append(vs.score)
            truth.append(math.log1p(it.views))  # views are heavy-tailed
            per.append(
                {"id": it.id, "modality": it.modality, "pred": vs.score, "views": it.views}
            )

    if not preds:
        return EvalResult(spearman=0.0, mae=0.0, precision_at_topk=0.0, n=0, per_item=[])

    mae = float(np.mean(np.abs(np.array(preds) - np.array(truth) / max(truth) * 100)))
    rho = _spearman(preds, truth)

    k = max(1, len(preds) // 10)
    top_pred = set(sorted(range(len(preds)), key=lambda i: -preds[i])[:k])
    top_truth = set(sorted(range(len(truth)), key=lambda i: -truth[i])[:k])
    precision = len(top_pred & top_truth) / k

    return EvalResult(
        spearman=rho,
        mae=mae,
        precision_at_topk=precision,
        n=len(preds),
        per_item=per,
    )
