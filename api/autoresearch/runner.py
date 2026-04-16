"""Orchestrates the Karpathy keep/discard loop.

for i in range(budget):
    checkpoint = current score.py
    edit       = agent.propose(history)
    apply(edit)
    result     = eval.run()
    if result.spearman > best.spearman: keep
    else: revert
    log(experiment)
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from dataclasses import asdict
from pathlib import Path
from typing import Iterable, Iterator

from api.autoresearch.agent import AgentProposal, propose
from api.autoresearch.eval import EvalResult, run_eval
from api.config import AUTORESEARCH_DIR, SCORING_DIR

SCORE_PY = SCORING_DIR / "score.py"
EXPERIMENTS_LOG = AUTORESEARCH_DIR / "experiments.jsonl"


def _read_history(n: int = 20) -> list[dict]:
    if not EXPERIMENTS_LOG.exists():
        return []
    lines = EXPERIMENTS_LOG.read_text().splitlines()[-n:]
    return [json.loads(l) for l in lines if l.strip()]


def _append_history(entry: dict) -> None:
    EXPERIMENTS_LOG.parent.mkdir(parents=True, exist_ok=True)
    with EXPERIMENTS_LOG.open("a") as f:
        f.write(json.dumps(entry) + "\n")


def _apply(proposal: AgentProposal) -> None:
    SCORE_PY.write_text(proposal.score_py)


def _checkpoint() -> str:
    return SCORE_PY.read_text()


def _revert(snapshot: str) -> None:
    SCORE_PY.write_text(snapshot)


def _best_so_far() -> float:
    best = -1.0
    for entry in _read_history(1000):
        if entry.get("kept") and entry.get("spearman") is not None:
            best = max(best, float(entry["spearman"]))
    return best


def run_autoresearch(
    budget: int = 5,
    backend: str | None = None,
    offline: bool = False,
) -> Iterator[dict]:
    """Generator that yields each experiment result as it finishes.

    Callers can stream these (e.g. via SSE) or exhaust them for a batch job.
    """
    # Establish baseline if we have no prior history.
    if not _read_history(1):
        baseline = run_eval(backend=backend)
        entry = {
            "t": time.time(),
            "experiment": 0,
            "hypothesis": "baseline (seed score.py)",
            "spearman": baseline.spearman,
            "mae": baseline.mae,
            "precision_at_topk": baseline.precision_at_topk,
            "n": baseline.n,
            "kept": True,
        }
        _append_history(entry)
        yield entry

    best = _best_so_far()
    for i in range(1, budget + 1):
        history = _read_history(20)
        snapshot = _checkpoint()

        # Phase 1: agent is thinking. Emit a status event so the UI can
        # show a live "thinking" row before the eval completes. This is
        # purely cosmetic -- nothing gets written to history.jsonl here.
        yield {
            "t": time.time(),
            "experiment": i,
            "phase": "thinking",
            "kept": False,
        }

        try:
            proposal = propose(history, offline=offline)
        except Exception as e:
            err = {
                "t": time.time(),
                "experiment": i,
                "phase": "error",
                "error": f"agent: {e!r}",
                "kept": False,
            }
            _append_history(err)
            yield err
            continue

        # Phase 2: agent proposed; show the hypothesis and the file-level
        # diff size so the UI can stream the idea before the eval runs.
        yield {
            "t": time.time(),
            "experiment": i,
            "phase": "proposed",
            "hypothesis": proposal.hypothesis,
            "diff_bytes": max(0, len(proposal.score_py) - len(snapshot)),
            "kept": False,
        }

        _apply(proposal)
        try:
            result = run_eval(backend=backend)
        except Exception as e:
            _revert(snapshot)
            err = {
                "t": time.time(),
                "experiment": i,
                "phase": "error",
                "hypothesis": proposal.hypothesis,
                "error": f"eval: {e!r}",
                "kept": False,
            }
            _append_history(err)
            yield err
            continue

        kept = result.spearman > best
        if not kept:
            _revert(snapshot)
        else:
            best = result.spearman

        entry = {
            "t": time.time(),
            "experiment": i,
            "phase": "done",
            "hypothesis": proposal.hypothesis,
            "spearman": result.spearman,
            "mae": result.mae,
            "precision_at_topk": result.precision_at_topk,
            "n": result.n,
            "kept": kept,
            "best_so_far": best,
        }
        _append_history(entry)
        yield entry


def _cli(argv: list[str]) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--budget", type=int, default=5)
    p.add_argument("--backend", default=None)
    p.add_argument("--offline", action="store_true", help="use deterministic offline proposer")
    args = p.parse_args(argv)

    for entry in run_autoresearch(
        budget=args.budget, backend=args.backend, offline=args.offline
    ):
        print(json.dumps(entry, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
