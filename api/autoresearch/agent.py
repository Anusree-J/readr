"""Claude agent that proposes edits to scoring/score.py.

Design mirrors Karpathy's autoresearch program.md:
  - One experiment = one focused edit + hypothesis.
  - Agent sees the last N experiments and the current score.py + rubric.md.
  - Agent returns a whole-file replacement of score.py plus a natural-
    language hypothesis. The runner applies the file, evaluates, keeps or
    reverts.

We intentionally keep the agent's action space tight (one file, whole-file
rewrite) because (a) mock/real TRIBE predictions are pre-cached so evals are
seconds, and (b) constrained edits converge faster than free-form.
"""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path

from api.config import SCORING_DIR, settings


SYSTEM_PROMPT = """You are an autoresearch agent optimising a virality scoring head.

Setup:
- TRIBE v2 (frozen) predicts fMRI responses on the fsaverage5 cortex (~20k \
vertices, 2 Hz) for any video/audio/text input.
- `api/scoring/rois.py` (frozen) splits those vertices into 5 ROIs: \
visual, attention, language, emotion, reward.
- `api/scoring/score.py` (your target) takes a TribePrediction and returns \
a ViralityScore with score, roi_breakdown, engagement_timeline, dead_zones, \
hotspots, suggested_edits.

Your objective: maximise Spearman rank correlation between score.score and \
log-transformed actual-views on a held-out labeled dataset.

Rules:
1. Output MUST be valid Python that keeps the public signature \
`def score(pred: TribePrediction) -> ViralityScore`.
2. Do NOT change imports that other modules rely on. Keep `from \
api.scoring.rois import roi_means, ROI_NAMES` and \
`from api.tribe.client import TribePrediction`.
3. One focused change per experiment. Prefer small tweaks (re-weight ROIs, \
change percentile thresholds, add/remove a term) over rewrites.
4. Explain your hypothesis in one sentence. Always log what you changed.

Return format: emit a JSON object between <EDIT> tags:

<EDIT>
{"hypothesis": "one-sentence why this might help",
 "score_py": "<full file contents>"}
</EDIT>

Nothing else."""


@dataclass
class AgentProposal:
    hypothesis: str
    score_py: str


def _read_text(p: Path) -> str:
    return p.read_text() if p.exists() else ""


def propose_next(last_n_experiments: list[dict]) -> AgentProposal:
    """Call the Claude API with full context. Raises if API key missing."""
    if not settings.anthropic_api_key:
        raise RuntimeError(
            "ANTHROPIC_API_KEY not set. The autoresearch agent needs it."
        )
    from anthropic import Anthropic

    client = Anthropic(api_key=settings.anthropic_api_key)

    score_py = _read_text(SCORING_DIR / "score.py")
    rubric = _read_text(SCORING_DIR / "rubric.md")
    history_snippet = json.dumps(last_n_experiments[-10:], indent=2)

    user = f"""Current scoring/score.py:
```python
{score_py}
```

Current rubric.md:
```markdown
{rubric}
```

Recent experiments (most recent last):
```json
{history_snippet}
```

Propose your next experiment. Return the full replacement score.py and your hypothesis in the required <EDIT> JSON format."""

    resp = client.messages.create(
        model=settings.agent_model,
        max_tokens=8000,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user}],
    )
    text = "".join(block.text for block in resp.content if getattr(block, "text", None))
    return _parse_edit(text)


def _parse_edit(text: str) -> AgentProposal:
    m = re.search(r"<EDIT>\s*(\{.*?\})\s*</EDIT>", text, re.DOTALL)
    if not m:
        raise ValueError(f"Agent did not return <EDIT>...</EDIT> block:\n{text[:400]}")
    try:
        obj = json.loads(m.group(1))
    except json.JSONDecodeError as e:
        raise ValueError(f"Agent <EDIT> block was not valid JSON: {e}\n{m.group(1)[:400]}")
    hypothesis = obj.get("hypothesis", "(no hypothesis)")
    score_py = obj.get("score_py")
    if not score_py or "def score(" not in score_py:
        raise ValueError("Agent score_py missing or has no `def score(`")
    return AgentProposal(hypothesis=hypothesis, score_py=score_py)


# ---------------------------------------------------------------------------
# Offline fallback: used when ANTHROPIC_API_KEY is absent (e.g. CI smoke).
# Cycles a handful of deterministic tweaks so the runner can still demonstrate
# the keep/revert mechanics without a real model.
# ---------------------------------------------------------------------------

OFFLINE_VARIANTS = [
    {
        "hypothesis": "Boost emotion weight, high-arousal content shares faster.",
        "subs": [("\"emotion\":   0.25", "\"emotion\":   0.32"),
                 ("\"reward\":    0.30", "\"reward\":    0.26")],
    },
    {
        "hypothesis": "Tighten hook window to first 1.5s.",
        "subs": [("HOOK_SECONDS: float = 2.0", "HOOK_SECONDS: float = 1.5")],
    },
    {
        "hypothesis": "Use 95th percentile for peak response instead of 90th.",
        "subs": [("np.percentile(ts, 90)", "np.percentile(ts, 95)")],
    },
    {
        "hypothesis": "Increase variance gain to favour dynamic content.",
        "subs": [("VARIANCE_GAIN: float = 0.4", "VARIANCE_GAIN: float = 0.6")],
    },
    {
        "hypothesis": "Re-weight reward up, visual down.",
        "subs": [("\"reward\":    0.30", "\"reward\":    0.36"),
                 ("\"visual\":    0.10", "\"visual\":    0.04")],
    },
]


def propose_offline(last_n_experiments: list[dict]) -> AgentProposal:
    current = _read_text(SCORING_DIR / "score.py")
    i = len(last_n_experiments) % len(OFFLINE_VARIANTS)
    variant = OFFLINE_VARIANTS[i]
    new = current
    applied = False
    for (old, repl) in variant["subs"]:
        if old in new:
            new = new.replace(old, repl, 1)
            applied = True
    if not applied:
        # Fallback: nudge CALIBRATION_GAIN a bit so we still log an experiment.
        new = re.sub(r"CALIBRATION_GAIN: float = [\d.]+",
                     f"CALIBRATION_GAIN: float = {3.0 + 0.1 * (i + 1):.2f}",
                     new)
    return AgentProposal(hypothesis=variant["hypothesis"], score_py=new)


def propose(last_n_experiments: list[dict], *, offline: bool = False) -> AgentProposal:
    if offline or not settings.anthropic_api_key:
        return propose_offline(last_n_experiments)
    return propose_next(last_n_experiments)
