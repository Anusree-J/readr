"""Labeled dataset loader for autoresearch.

data/labeled/*.jsonl is the ground truth: each line is
    {"modality": "text|image|ui|video",
     "content": "<tweet text>" | null,
     "asset": "relative/path/under/labeled/assets" | null,
     "views": 123456,
     "label": "free-text description for the agent"}

We deterministically split by hash of the id into train/val so the agent
always evaluates on the same held-out split.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from api.config import LABELED_DIR


@dataclass
class LabeledItem:
    id: str
    modality: str
    content: str | None
    asset: Path | None
    views: float
    label: str


def _iter_jsonl(path: Path) -> Iterable[dict]:
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            yield json.loads(line)


def load_dataset() -> list[LabeledItem]:
    items: list[LabeledItem] = []
    for jf in sorted(LABELED_DIR.glob("*.jsonl")):
        for row in _iter_jsonl(jf):
            asset = LABELED_DIR / "assets" / row["asset"] if row.get("asset") else None
            id_ = hashlib.sha256(
                f"{row['modality']}|{row.get('content','')}|{row.get('asset','')}".encode()
            ).hexdigest()[:16]
            items.append(
                LabeledItem(
                    id=id_,
                    modality=row["modality"],
                    content=row.get("content"),
                    asset=asset,
                    views=float(row["views"]),
                    label=row.get("label", ""),
                )
            )
    return items


def split(items: list[LabeledItem], val_frac: float = 0.3) -> tuple[list[LabeledItem], list[LabeledItem]]:
    train: list[LabeledItem] = []
    val: list[LabeledItem] = []
    for it in items:
        h = int(hashlib.sha256(it.id.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF
        (val if h < val_frac else train).append(it)
    return train, val
