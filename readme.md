# CBT — Brain-Predicted Virality

Score tweets, images, UI screenshots, and reels against **Meta FAIR's TRIBE v2**
(an open-source foundation model that predicts fMRI responses to video, audio,
and text), then let a **Karpathy-style autoresearch loop** improve the scoring
head overnight.

```
/CBT
├── api/              FastAPI + TRIBE wrapper + ingest + scoring + autoresearch
├── web/              Next.js 15 frontend (score UI + autoresearch dashboard)
├── data/             Labeled dataset, TRIBE prediction cache, result cache
└── infra/            Modal GPU deploy target
```

## Quick start (mock backend, no GPU, no secrets)

```bash
# Backend
cd api
python -m venv .venv && source .venv/bin/activate
pip install -e .
uvicorn api.main:app --reload --port 8000

# Frontend (separate terminal)
cd web
npm install
npm run dev
```

Open http://localhost:3000. The `mock` TRIBE backend produces deterministic
synthetic brain responses so you can exercise the full pipeline — ingest,
scoring, and autoresearch — without a GPU.

## Upgrading to real TRIBE v2

### Option A — Local CUDA
```bash
pip install -e '.[tribe]'
pip install git+https://github.com/facebookresearch/tribev2
export HF_TOKEN=hf_...    # needs Llama 3.2-3B access approved
export TRIBE_BACKEND=local
```

### Option B — Modal GPU endpoint
```bash
pip install modal
modal token new
modal secret create hf-token HF_TOKEN=hf_...
modal deploy api/tribe/modal_app.py
export MODAL_TRIBE_ENDPOINT=https://<your-modal-url>
export TRIBE_BACKEND=modal
```

Either way, predictions are content-addressed and cached under
`data/tribe_cache/`, so the autoresearch loop re-runs only the scoring head
(milliseconds per experiment) against pre-computed TRIBE outputs.

## Autoresearch

- `api/scoring/score.py` is the **agent-editable scoring head** (Karpathy's
  `train.py` analogue).
- `api/scoring/rubric.md` documents the scoring intent.
- `api/autoresearch/runner.py` is the keep-or-revert loop:
  ```
  python -m api.autoresearch.runner --budget 10 --offline     # no API key needed
  python -m api.autoresearch.runner --budget 50                # uses ANTHROPIC_API_KEY
  ```
- Metric: **Spearman rank correlation** between predicted `score` and
  `log1p(views)` on a held-out split of `data/labeled/*.jsonl`.
- Offline mode cycles through a deterministic set of tweaks so you can see
  the keep/revert mechanics without spending API credits.

## Endpoints

| method | path                              | purpose                      |
|--------|-----------------------------------|------------------------------|
| POST   | /score/text                       | JSON `{text}` → score        |
| POST   | /score/{image,ui,video}           | multipart `file` → score     |
| GET    | /score/{id}                       | cached result by id          |
| GET    | /autoresearch/history             | experiment log               |
| GET    | /autoresearch/current             | current `score.py` + rubric  |
| POST   | /autoresearch/run?budget=5        | SSE stream of experiments    |

## Seed dataset

`data/labeled/tweets.jsonl` ships with 20 seed tweets and their approximate
view counts. Drop more rows there (and assets for image/ui/video modalities
under `data/labeled/assets/`) to strengthen the autoresearch signal.

## Credits

- [TRIBE v2 paper](https://ai.meta.com/research/publications/a-foundation-model-of-vision-audition-and-language-for-in-silico-neuroscience)
- [Karpathy autoresearch](https://github.com/karpathy/autoresearch)
- Seed idea from @fuckgrowth on X.
