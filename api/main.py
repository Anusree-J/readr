"""FastAPI service: scoring + autoresearch + history.

Endpoints:
  POST /score/text         body: {"text": "..."}                     -> ScoreResponse
  POST /score/image        multipart: file=<image>                   -> ScoreResponse
  POST /score/ui           multipart: file=<screenshot>              -> ScoreResponse
  POST /score/video        multipart: file=<mp4>                     -> ScoreResponse
  GET  /score/{id}                                                   -> cached ScoreResponse
  GET  /autoresearch/history                                         -> list of experiments
  POST /autoresearch/run?budget=5&offline=true                       -> SSE stream
  GET  /autoresearch/current                                         -> {score_py, rubric}
"""
from __future__ import annotations

import asyncio
import importlib
import json
import tempfile
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse

from api.autoresearch.runner import EXPERIMENTS_LOG, run_autoresearch
from api.config import DATA_DIR, SCORING_DIR, settings
from api.ingest import ingest_any
from api.scoring.score import ViralityScore
from api.tribe.client import get_client

app = FastAPI(title="CBT Virality API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.cors_origin, "http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

RESULTS_DIR = DATA_DIR / "results"
RESULTS_DIR.mkdir(exist_ok=True)


class TextIn(BaseModel):
    text: str


def _vs_to_dict(vs: ViralityScore, extra: dict) -> dict:
    return {
        "score": vs.score,
        "roi_breakdown": vs.roi_breakdown,
        "engagement_timeline": vs.engagement_timeline,
        "dead_zones": vs.dead_zones,
        "hotspots": vs.hotspots,
        "suggested_edits": vs.suggested_edits,
        "meta": vs.meta,
        **extra,
    }


def _run_pipeline(modality: str, workdir: Path, **kwargs) -> dict:
    # Fresh import so any recent autoresearch edit to score.py applies
    # without restarting the server.
    import sys
    if "api.scoring.score" in sys.modules:
        score_mod = importlib.reload(sys.modules["api.scoring.score"])
    else:
        score_mod = importlib.import_module("api.scoring.score")

    ing = ingest_any(modality, workdir=workdir, **kwargs)
    client = get_client()
    pred = client.predict_cached(ing.tribe_input)
    vs = score_mod.score(pred)

    result_id = ing.raw_hash
    payload = _vs_to_dict(
        vs,
        extra={
            "id": result_id,
            "modality": modality,
            "duration_s": pred.duration_s,
            "sampling_hz": settings.sampling_hz,
            "backend": pred.meta.get("backend"),
        },
    )
    (RESULTS_DIR / f"{result_id}.json").write_text(json.dumps(payload))
    return payload


@app.get("/healthz")
def health():
    return {"ok": True, "backend": settings.tribe_backend}


@app.post("/score/text")
def score_text(body: TextIn):
    if not body.text.strip():
        raise HTTPException(400, "empty text")
    with tempfile.TemporaryDirectory() as td:
        return _run_pipeline("text", Path(td), text=body.text)


@app.post("/score/image")
async def score_image(file: UploadFile = File(...)):
    data = await file.read()
    if not data:
        raise HTTPException(400, "empty upload")
    with tempfile.TemporaryDirectory() as td:
        return _run_pipeline("image", Path(td), image_bytes=data)


@app.post("/score/ui")
async def score_ui(file: UploadFile = File(...)):
    data = await file.read()
    if not data:
        raise HTTPException(400, "empty upload")
    with tempfile.TemporaryDirectory() as td:
        return _run_pipeline("ui", Path(td), image_bytes=data)


@app.post("/score/video")
async def score_video(file: UploadFile = File(...)):
    data = await file.read()
    if not data:
        raise HTTPException(400, "empty upload")
    with tempfile.TemporaryDirectory() as td:
        return _run_pipeline("video", Path(td), video_bytes=data)


@app.get("/score/{result_id}")
def get_result(result_id: str):
    fp = RESULTS_DIR / f"{result_id}.json"
    if not fp.exists():
        raise HTTPException(404, "unknown result id")
    return json.loads(fp.read_text())


# --- Autoresearch -----------------------------------------------------------


@app.get("/autoresearch/history")
def history():
    if not EXPERIMENTS_LOG.exists():
        return []
    out = []
    for line in EXPERIMENTS_LOG.read_text().splitlines():
        line = line.strip()
        if line:
            out.append(json.loads(line))
    return out


@app.get("/autoresearch/current")
def current_scoring():
    return {
        "score_py": (SCORING_DIR / "score.py").read_text(),
        "rubric": (SCORING_DIR / "rubric.md").read_text(),
    }


@app.post("/autoresearch/run")
async def run_experiments(budget: int = 5, offline: bool = False):
    async def event_stream():
        # run_autoresearch is sync/generator; push each entry as SSE.
        loop = asyncio.get_event_loop()
        gen = await loop.run_in_executor(
            None, lambda: list(run_autoresearch(budget=budget, offline=offline))
        )
        for entry in gen:
            yield {"event": "experiment", "data": json.dumps(entry)}
        yield {"event": "done", "data": "{}"}

    return EventSourceResponse(event_stream())
