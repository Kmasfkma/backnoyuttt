# 1. بايثون 3.11
FROM python:3.11-slim-bookworm

ENV ENV_MODE=production \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# 2. مكتبات النظام
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    redis-server \
    git \
    curl \
    libnss3 libnspr4 libasound2 libatk1.0-0 libc6 libcairo2 libcups2 \
    libdbus-1-3 libexpat1 libfontconfig1 libgbm1 libgcc1 libglib2.0-0 \
    libgtk-3-0 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxcursor1 \
    libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 \
    libxtst6 \
    && rm -rf /var/lib/apt/lists/*

# 3. الصلاحيات
RUN useradd -m -u 1000 user || true
RUN mkdir -p /var/lib/redis && chown -R 1000:1000 /var/lib/redis /app

# 4. تثبيت المكتبات (نحتفظ بملف requirements.txt الأخير كما هو)
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install -r requirements.txt && \
    pip install playwright

# 5. تثبيت الكروم
RUN python -m playwright install chromium

# 6. نسخ الكود
COPY --chown=1000:1000 . .

# --- التصحيح السحري: تعطيل Daytona في كل الملفات المسببة للمشاكل ---
# 1. إصلاح tool_base.py
RUN sed -i "s/from daytona_sdk import AsyncSandbox/class AsyncSandbox: pass # Mocked/" core/sandbox/tool_base.py || true
# 2. إصلاح resolver.py (السبب في الخطأ الأخير)
RUN sed -i "s/from daytona_sdk import AsyncSandbox/class AsyncSandbox: pass # Mocked/" core/sandbox/resolver.py || true

USER 1000
EXPOSE 8000

CMD ["sh", "-c", "redis-server --daemonize yes --maxmemory 40mb --maxmemory-policy allkeys-lru && uvicorn api:app --host 0.0.0.0 --port 8000 --workers 1"]
