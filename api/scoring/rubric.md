# Virality Scoring Rubric — v0 (seed)

This rubric is the human-readable contract for `score.py`. The autoresearch
agent may edit both files as long as the output shape of `ViralityScore`
stays the same.

## Signal intuition

TRIBE v2 gives us a (T, 20484) matrix of predicted BOLD-like responses on
the fsaverage5 cortex at 2 Hz. We collapse that into five per-ROI time
series (`rois.py`) and turn those into a single 0-100 virality score plus
diagnostic feedback.

## Axes we score

| ROI         | What high activity here signals                   | Weight (v0) |
|-------------|---------------------------------------------------|-------------|
| reward      | dopaminergic "I want more of this"                | 0.30        |
| attention   | sustained focus, visual search                    | 0.20        |
| emotion     | arousal (awe, anger, humor, surprise)             | 0.25        |
| language    | semantic load — hook quality, readability         | 0.15        |
| visual      | raw visual pop — contrast, motion, faces          | 0.10        |

## Aggregation

1. **Per-ROI peak**: take the top-decile response within each ROI's time
   series. Peaks capture "spikes" better than means.
2. **Temporal variance**: boost content whose aggregate signal has high
   variance — flat curves flatline. Multiplicative factor in [0.8, 1.2].
3. **Hook boost**: within the first 2 seconds, weight reward + attention
   +25%. The first impression disproportionately drives share intent.
4. **Calibration**: map the weighted sum through a logistic so the score
   lives in [0, 100] and median seed content lands near 50.

## Diagnostic outputs

- **dead_zones**: contiguous spans (>= 2 s) where the aggregate engagement
  drops below the 25th percentile of the clip. Creator should cut these.
- **hotspots**: contiguous spans where engagement is in the top decile.
  Creator should front-load these.
- **suggested_edits**: short natural-language tips derived from the above.

## How the agent should iterate

The agent's one job is to maximise Spearman rank correlation between the
produced `ViralityScore.score` and the held-out actual-views labels in
`data/labeled/*.jsonl`. Every edit should be motivated by a concrete
hypothesis logged in `history.jsonl` (e.g. "emotion peak may underweight
anger-driven virality — try raising emotion weight from 0.25 to 0.35").
