"""Virality scoring head.

THIS FILE IS THE AUTORESEARCH TARGET. Claude (via `api.autoresearch.agent`)
will edit it to improve Spearman correlation against held-out views. Keep
the public surface — `score(pred) -> ViralityScore` — stable so the rest of
the stack does not break.

v0 (seed): a transparent hand-tuned linear head described in rubric.md.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from api.config import settings
from api.scoring.rois import ROI_NAMES, roi_means
from api.tribe.client import TribePrediction


@dataclass
class ViralityScore:
    score: float                                     # 0-100
    roi_breakdown: dict[str, float]                  # per-ROI 0-1
    engagement_timeline: list[float]                 # per-timestep 0-1
    dead_zones: list[tuple[float, float]]            # (start_s, end_s)
    hotspots: list[tuple[float, float]]              # (start_s, end_s)
    suggested_edits: list[str] = field(default_factory=list)
    meta: dict = field(default_factory=dict)


# Tunables — the agent will rewrite these (or the whole function) to search
# for better configurations.
WEIGHTS: dict[str, float] = {
    "reward":    0.30,
    "emotion":   0.25,
    "attention": 0.20,
    "language":  0.15,
    "visual":    0.10,
}
HOOK_SECONDS: float = 2.0
HOOK_BONUS: float = 0.25          # relative boost on reward+attention in the hook
DEAD_PCT: float = 25.0             # percentile below which a span counts as dead
HOT_PCT: float = 90.0              # percentile above which a span counts as hot
MIN_SPAN_S: float = 2.0            # minimum contiguous duration for a span callout
VARIANCE_GAIN: float = 0.4         # how strongly temporal variance boosts the score
CALIBRATION_GAIN: float = 3.5      # logistic steepness
CALIBRATION_BIAS: float = -1.2     # logistic offset -> median seed ~= 50


def _contiguous_spans(mask: np.ndarray, dt: float, min_s: float) -> list[tuple[float, float]]:
    """Return (start_s, end_s) tuples for runs of True at least min_s long."""
    out: list[tuple[float, float]] = []
    in_run = False
    start = 0
    for i, v in enumerate(mask):
        if v and not in_run:
            in_run = True
            start = i
        elif not v and in_run:
            in_run = False
            if (i - start) * dt >= min_s:
                out.append((start * dt, i * dt))
    if in_run and (len(mask) - start) * dt >= min_s:
        out.append((start * dt, len(mask) * dt))
    return out


def _logistic(x: float) -> float:
    return 1.0 / (1.0 + np.exp(-x))


def score(pred: TribePrediction) -> ViralityScore:
    per_roi = roi_means(pred.preds)  # dict[name] -> (T,)
    T = pred.n_timesteps
    dt = 1.0 / settings.sampling_hz

    # 1) Per-ROI peak response (90th percentile of its time series).
    peaks = {name: float(np.percentile(ts, 90)) for name, ts in per_roi.items()}

    # 2) Normalize peaks into 0-1 using a stable sigmoid around 0.
    norm_peaks = {name: float(_logistic(p)) for name, p in peaks.items()}

    # 3) Base linear combination.
    base = sum(WEIGHTS[name] * norm_peaks[name] for name in ROI_NAMES)

    # 4) Aggregate engagement time-series (weighted sum per timestep).
    agg = np.zeros(T, dtype=np.float32)
    for name in ROI_NAMES:
        agg += WEIGHTS[name] * per_roi[name]
    # Normalize agg to [0, 1] for plotting + dead/hot detection.
    amin, amax = float(agg.min()), float(agg.max())
    rng = max(1e-6, amax - amin)
    agg01 = (agg - amin) / rng
    timeline = [float(x) for x in agg01]

    # 5) Temporal variance multiplier.
    variance = float(np.std(agg01))
    var_mult = 1.0 + VARIANCE_GAIN * (variance - 0.2)   # 0.2 is a neutral std
    var_mult = max(0.7, min(1.4, var_mult))

    # 6) Hook boost: first HOOK_SECONDS weighted by reward+attention peak.
    hook_n = max(1, int(round(HOOK_SECONDS / dt)))
    hook_reward = float(per_roi["reward"][:hook_n].mean())
    hook_attn = float(per_roi["attention"][:hook_n].mean())
    hook_score = _logistic(0.5 * (hook_reward + hook_attn))
    hook_boost = 1.0 + HOOK_BONUS * (hook_score - 0.5)

    raw = base * var_mult * hook_boost
    # 7) Calibrate into 0-100 (median seed content ~= 50).
    final = 100.0 * _logistic(CALIBRATION_GAIN * (raw - 0.5) + CALIBRATION_BIAS * 0 + 0.0)

    # 8) Dead zones / hotspots on the aggregate timeline.
    lo = float(np.percentile(agg01, DEAD_PCT))
    hi = float(np.percentile(agg01, HOT_PCT))
    dead_zones = _contiguous_spans(agg01 <= lo, dt, MIN_SPAN_S)
    hotspots = _contiguous_spans(agg01 >= hi, dt, MIN_SPAN_S)

    # 9) Suggested edits.
    tips: list[str] = []
    if hotspots and hotspots[0][0] > 1.5:
        tips.append(
            f"Front-load the hotspot at {hotspots[0][0]:.1f}s-{hotspots[0][1]:.1f}s "
            f"to the opening."
        )
    for (s, e) in dead_zones[:2]:
        tips.append(f"Consider cutting the flat span at {s:.1f}s-{e:.1f}s.")
    if hook_score < 0.45:
        tips.append("Hook is weak in reward+attention — try a stronger opening line or cut.")
    if variance < 0.12:
        tips.append("Overall signal is flat — add a clear tonal shift or visual change.")
    if not tips:
        tips.append("Well-shaped engagement — no obvious edits.")

    return ViralityScore(
        score=float(final),
        roi_breakdown={name: norm_peaks[name] for name in ROI_NAMES},
        engagement_timeline=timeline,
        dead_zones=dead_zones,
        hotspots=hotspots,
        suggested_edits=tips,
        meta={
            "variance": variance,
            "hook_score": float(hook_score),
            "raw": float(raw),
            "weights": WEIGHTS,
            "hook_seconds": HOOK_SECONDS,
            "version": "v0-seed",
        },
    )
