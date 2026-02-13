# 1. Python 3.11 (عشان نتفادى مشاكل الـ Logging والتوافق)
FROM python:3.11-slim-bookworm

ENV ENV_MODE=production \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# 2. تثبيت التبعات (Redis + Git + مكتبات تشغيل الكروم الضرورية)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    redis-server \
    git \
    curl \
    # مكتبات الكروم عشان Playwright يشتغل
    libnss3 libnspr4 libasound2 libatk1.0-0 libc6 libcairo2 libcups2 \
    libdbus-1-3 libexpat1 libfontconfig1 libgbm1 libgcc1 libglib2.0-0 \
    libgtk-3-0 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxcursor1 \
    libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 \
    libxtst6 \
    && rm -rf /var/lib/apt/lists/*

# 3. إعداد المستخدم والصلاحيات (مهم جداً لـ Hugging Face)
RUN useradd -m -u 1000 user || true
RUN mkdir -p /var/lib/redis && chown -R 1000:1000 /var/lib/redis /app

# 4. تثبيت المكتبات (تثبيت كل النواقص يدوياً هنا)
COPY requirements.txt .
# هنا ضفت daytona-sdk و tavily-python وأي حاجة ممكن تكون ناقصة
RUN pip install --upgrade pip && \
    pip install playwright tavily-python daytona-sdk && \
    pip install -r requirements.txt

# 5. تثبيت الكروم (داخل مسار بايثون)
RUN python -m playwright install chromium

# نسخ الكود مع ضبط الملكية
USER 1000
COPY --chown=1000:1000 . .

EXPOSE 8000

# 6. التشغيل (Redis مقيد بـ 40MB + تشغيل التطبيق بـ Worker واحد)
CMD ["sh", "-c", "redis-server --daemonize yes --maxmemory 40mb --maxmemory-policy allkeys-lru && uvicorn api:app --host 0.0.0.0 --port 8000 --workers 1"]
