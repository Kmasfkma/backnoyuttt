# 1. استخدام صورة مايكروسوفت الجاهزة (لتجنب استهلاك موارد المعالج في التسطيب)
FROM mcr.microsoft.com/playwright/python:v1.41.0-jammy

# إعدادات البيئة لتقليل استهلاك الذاكرة
ENV ENV_MODE=production \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PATH="/home/user/.local/bin:$PATH" \
    # تعطيل الـ Cache الخاص بـ PIP لتوفير المساحة
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# 2. تثبيت Redis و Git كـ Root
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    redis-server \
    git \
    && rm -rf /var/lib/apt/lists/*

# 3. إعداد صلاحيات المستخدم 1000
RUN mkdir -p /var/lib/redis /etc/redis /var/log/redis /app && \
    chown -R 1000:1000 /var/lib/redis /etc/redis /var/log/redis /app

# التبديل للمستخدم الافتراضي
USER 1000

# 4. تثبيت المكتبات (pip المباشر أسرع في هذه المواصفات)
COPY --chown=1000:1000 requirements.txt ./
RUN pip install --upgrade pip && \
    pip install --user -r requirements.txt

# 5. نسخ الكود
COPY --chown=1000:1000 . .

EXPOSE 7860

# 6. التشغيل (تقييد Redis بـ 50MB فقط من الرامات + 1 Worker للتطبيق)
CMD ["sh", "-c", "redis-server --daemonize yes --maxmemory 50mb --maxmemory-policy allkeys-lru && python3 -m uvicorn api:app --host 0.0.0.0 --port 7860 --workers 1 --timeout-keep-alive 60"]
