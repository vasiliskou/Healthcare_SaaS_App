# ---- Base image ----
  FROM python:3.12-slim AS base

  ENV PYTHONDONTWRITEBYTECODE=1 \
      PYTHONUNBUFFERED=1 \
      PIP_NO_CACHE_DIR=1
  
  # System deps (curl only if you want the HEALTHCHECK to work)
  RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
  
  # Non-root user
  RUN useradd -m appuser
  WORKDIR /app
  
  # ---- Dependencies ----
  # Leverage Docker layer caching: copy reqs first, install, then copy code
  COPY requirements.txt ./requirements.txt
  RUN pip install --upgrade pip && pip install -r requirements.txt
  
  # ---- App code ----
  COPY . .
  
  # ---- Runtime ----
  EXPOSE 8000
  USER appuser
  
  # Optional healthcheck (expects /health endpoint in your app)
  HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/health || exit 1
  
  # IMPORTANT: no --reload in production
  CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
  