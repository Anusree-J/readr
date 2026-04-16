FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    TRIBE_BACKEND=mock

# System deps: ffmpeg for video, libgl for opencv, git for optional tribe install.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
        libgl1 \
        libglib2.0-0 \
        git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY api/pyproject.toml /app/api/pyproject.toml
COPY api/__init__.py /app/api/__init__.py
# Install only the base deps first so code changes don't bust the layer.
RUN pip install -e /app/api

# Now the rest of the source + the labeled seed dataset.
COPY api /app/api
COPY data/labeled /app/data/labeled
COPY scripts /app/scripts

EXPOSE 8000
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
