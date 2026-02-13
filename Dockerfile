# استخدام بايثون 3.11 مباشرة لحل مشكلة الـ logging
FROM python:3.11-slim-bookworm

ENV ENV_MODE=production \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# تثبيت Redis وتبعيات المتصفح الضرورية فقط (بدون تحميل متصفحات ضخمة)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    redis-server \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# تثبيت المكتبات وتحديد إصدار Playwright
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# تثبيت الكروم فقط (بدون deps إضافية لتوفير الذاكرة)
RUN playwright install chromium

# إعدادات المستخدم 1000 لضمان الصلاحيات
RUN useradd -m -u 1000 user || true
RUN mkdir -p /var/lib/redis && chown -R 1000:1000 /var/lib/redis /app
USER 1000

COPY --chown=1000:1000 . .

EXPOSE 8000

# تقييد Redis بـ 40MB فقط لترك مساحة للتطبيق (512MB محدودة جداً)
CMD ["sh", "-c", "redis-server --daemonize yes --maxmemory 40mb --maxmemory-policy allkeys-lru && uvicorn api:app --host 0.0.0.0 --port 8000 --workers 1"]
