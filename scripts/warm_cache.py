"""Warm the TRIBE prediction cache over the labeled dataset.

Run this ONCE after deploying (or after adding new labeled rows). It iterates
every labeled item, ingests it, and calls predict_cached -- which hits the
configured TRIBE backend on first touch and persists the (T, 20484) tensor
to data/tribe_cache/. After this completes, the autoresearch loop runs
CPU-only because every eval reads from the cache.

Usage:
    TRIBE_BACKEND=modal MODAL_TRIBE_ENDPOINT=https://... \\
      python scripts/warm_cache.py

    # or (local CUDA box):
    TRIBE_BACKEND=local HF_TOKEN=hf_... python scripts/warm_cache.py

    # or (smoke test, no GPU):
    TRIBE_BACKEND=mock python scripts/warm_cache.py
"""
from __future__ import annotations

import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from api.autoresearch.dataset import load_dataset
from api.config import CACHE_DIR, settings
from api.ingest import ingest_any
from api.tribe.client import get_client


def main() -> int:
    items = load_dataset()
    if not items:
        print("No labeled items found. Seed data/labeled/*.jsonl first.")
        return 1

    client = get_client()
    print(f"Backend: {settings.tribe_backend}")
    print(f"Cache:   {CACHE_DIR}")
    print(f"Items:   {len(items)}")
    print()

    hits = 0
    misses = 0
    t0 = time.time()
    with tempfile.TemporaryDirectory() as td:
        wd = Path(td)
        for i, it in enumerate(items):
            # Ingest -> TribeInput.
            if it.modality == "text":
                ing = ingest_any("text", text=it.content or "", workdir=wd)
            elif it.modality in ("image", "ui"):
                assert it.asset is not None, f"{it.modality} item missing asset"
                ing = ingest_any(it.modality, image_bytes=it.asset.read_bytes(), workdir=wd)
            else:
                assert it.asset is not None
                ing = ingest_any("video", video_bytes=it.asset.read_bytes(), workdir=wd)

            # Cache probe: build the key, check if the file exists already.
            from api.tribe.cache import cache_key, load_cached
            key = cache_key(client.backend, ing.tribe_input.fingerprint())
            was_cached = load_cached(key) is not None

            t1 = time.time()
            pred = client.predict_cached(ing.tribe_input)
            dt = time.time() - t1

            if was_cached:
                hits += 1
                print(f"[{i + 1:>3}/{len(items)}] {it.modality:<5}  cache hit   ({dt * 1000:.0f} ms)")
            else:
                misses += 1
                print(f"[{i + 1:>3}/{len(items)}] {it.modality:<5}  TRIBE call  ({dt:.1f} s)  shape={pred.preds.shape}")

    total = time.time() - t0
    print()
    print(f"Done in {total:.1f}s — hits: {hits}, misses: {misses}")
    if settings.tribe_backend == "mock":
        print("Note: mock backend produces synthetic tensors. Switch to 'local' or 'modal' for real TRIBE predictions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
