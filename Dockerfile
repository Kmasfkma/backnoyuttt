# 1. Base Image
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim

ENV ENV_MODE production
ENV PYTHONUNBUFFERED=1
ENV UV_LINK_MODE=copy
ENV PYTHONPATH=/app
ENV PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# ==============================================================================
# 🛠️ SYSTEM NETWORK FIX: Prefer IPv4 over IPv6
# هذا هو الحل الجذري لمشكلة الاتصال بـ Supabase من داخل Hugging Face
# يقوم بتعديل أولوية العناوين في النظام ليختار IPv4 دائماً
# ==============================================================================
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
# 🛠️ HOTFIX: إصلاح مشكلة الـ 500 Error وتعارض المكتبات
# نقوم بإجبار إعادة تثبيت SQLAlchemy و Greenlet لإصلاح مشاكل الـ Async
# ---------------------------------------------------------------------------
RUN . .venv/bin/activate && pip install --force-reinstall --no-cache-dir "sqlalchemy>=2.0.30" "greenlet>=3.0.3"

# 5. Install Playwright (Browsers)
RUN . .venv/bin/activate && pip install playwright && playwright install chromium --with-deps

# 6. Copy Application Code & Permissions
COPY . .
RUN useradd -m -u 1000 user
RUN mkdir -p /var/lib/redis && chown -R user:user /var/lib/redis /etc/redis /var/log/redis
RUN chown -R user:user /app

# Switch to non-root user
USER user

# Expose the port
EXPOSE 7860

# 7. Start Command (Redis + Gunicorn/Uvicorn)
# Using uvicorn worker class for proper async support
CMD ["sh", "-c", "redis-server --daemonize yes && uv run gunicorn backend.api:app -w ${WORKERS:-4} -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:7860 --timeout ${TIMEOUT:-120} --graceful-timeout 30 --keep-alive 65"]