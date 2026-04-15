"""Modal deployment for TRIBE v2 GPU inference.

Deploy with:
    modal deploy api/tribe/modal_app.py

The deployed URL goes into MODAL_TRIBE_ENDPOINT for ModalTribeClient.
"""
from __future__ import annotations

try:
    import modal  # type: ignore
except ImportError:  # modal is an optional dep
    modal = None  # type: ignore


if modal is not None:
    image = (
        modal.Image.debian_slim(python_version="3.11")
        .apt_install("ffmpeg", "git")
        .pip_install(
            "torch>=2.4",
            "transformers>=4.45",
            "huggingface-hub>=0.25",
            "fastapi",
            "numpy",
            "pandas",
            "git+https://github.com/facebookresearch/tribev2",
        )
    )

    app = modal.App("cbt-tribe", image=image)
    hf_secret = modal.Secret.from_name("hf-token")

    @app.function(gpu="T4", timeout=600, secrets=[hf_secret])
    @modal.web_endpoint(method="POST", docs=True)
    def predict(video: bytes | None = None, audio: bytes | None = None,
                text: bytes | None = None, modality: str = "video") -> dict:
        import tempfile, json
        from pathlib import Path
        from tribe import TribeModel  # type: ignore
        import numpy as np

        model = TribeModel.from_pretrained("facebook/tribev2")
        tmp = Path(tempfile.mkdtemp())
        kwargs = {}
        if video:
            p = tmp / "in.mp4"; p.write_bytes(video); kwargs["video_path"] = str(p)
        if audio:
            p = tmp / "in.wav"; p.write_bytes(audio); kwargs["audio_path"] = str(p)
        if text:
            p = tmp / "in.txt"; p.write_bytes(text); kwargs["text_path"] = str(p)

        df = model.get_events_dataframe(**kwargs)
        preds, segments = model.predict(events=df)
        arr = preds.detach().cpu().numpy() if hasattr(preds, "detach") else np.asarray(preds)
        return {
            "preds": arr.astype("float16").tolist(),
            "segments": segments if isinstance(segments, list) else segments.to_dict(orient="records"),
            "meta": {"modality": modality, "shape": list(arr.shape)},
        }
