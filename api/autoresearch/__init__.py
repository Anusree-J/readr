"""Autoresearch: Karpathy-style loop that rewrites scoring/score.py."""
from .dataset import load_dataset, LabeledItem
from .eval import run_eval, EvalResult
from .runner import run_autoresearch

__all__ = ["load_dataset", "LabeledItem", "run_eval", "EvalResult", "run_autoresearch"]
