# 1. Base Image
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim

ENV ENV_MODE production
ENV PYTHONUNBUFFERED=1 
ENV UV_LINK_MODE=copy
ENV PYTHONPATH=/app
ENV PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# 2. Force IPv4 for Supabase connection (Network Fix)
# هذا السطر مهم جداً لحل مشكلة الاتصال بقاعدة البيانات
RUN echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf

# 3. Install System Dependencies + Redis
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    python3-dev \
    libpango-1.0-0 \
    libpangoft2-1.0-0 \
    libcairo2 \
    libgdk-pixbuf-2.0-0 \
    libffi-dev \
    shared-mime-info \
    redis-server \
    && rm -rf /var/lib/apt/lists/*

# 4. Setup UV and Install Dependencies
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --locked --quiet

# ---------------------------------------------------------------------------
# 🛠️ HOTFIX: Force Re-install libraries to prevent Async conflicts
# ---------------------------------------------------------------------------
RUN . .venv/bin/activate && pip install --force-reinstall --no-cache-dir "sqlalchemy>=2.0.30" "greenlet>=3.0.3"

# 5. Install Playwright
RUN . .venv/bin/activate && pip install playwright && playwright install chromium --with-deps

# 6. Copy Application Code
COPY . .

# Setup User Permissions
RUN useradd -m -u 1000 user
RUN mkdir -p /var/lib/redis && chown -R user:user /var/lib/redis /etc/redis /var/log/redis
RUN chown -R user:user /app

USER user

EXPOSE 7860

# 7. Start Command
# 🔴 FIX: Changed 'backend.api:app' to 'api:app' because api.py is in the root
CMD ["sh", "-c", "redis-server --daemonize yes && uv run gunicorn api:app -w ${WORKERS:-4} -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:7860 --timeout ${TIMEOUT:-120} --graceful-timeout 30 --keep-alive 65"]