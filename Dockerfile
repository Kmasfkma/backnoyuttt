# 1. استخدام نسخة Debian بدلاً من Alpine (ضروري للمتصفحات)
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim

ENV ENV_MODE production
WORKDIR /app

# 2. تثبيت مكتبات النظام (WeasyPrint + Git + Curl)
# بنستخدم apt-get بدلاً من apk
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    python3-dev \
    # متطلبات WeasyPrint (PDF)
    libpango-1.0-0 \
    libpangoft2-1.0-0 \
    libcairo2 \
    libgdk-pixbuf-2.0-0 \
    libffi-dev \
    shared-mime-info \
    # تنظيف الكاش لتقليل الحجم
    && rm -rf /var/lib/apt/lists/*

# 3. إعداد UV وتثبيت المكتبات
COPY pyproject.toml uv.lock ./
ENV UV_LINK_MODE=copy
RUN --mount=type=cache,target=/root/.cache/uv uv sync --locked --quiet

# 4. تثبيت متصفحات Playwright (مهم جداً للـ Agent)
# لازم نفعل البيئة الوهمية عشان نسطب المتصفح جواها
RUN . .venv/bin/activate && pip install playwright && playwright install chromium --with-deps

# 5. نسخ باقي الكود
COPY . .

# 6. إعداد المستخدم (أمان لـ Hugging Face)
RUN useradd -m -u 1000 user
RUN chown -R user:user /app
USER user

# 7. ضبط البورت الصحيح (7860) ومسار البايثون
ENV PYTHONPATH=/app
ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 7860

# 8. أمر التشغيل (مع تعديل البورت لـ 7860)
CMD ["sh", "-c", "uv run gunicorn backend.api:app -w ${WORKERS:-4} -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:7860 --timeout ${TIMEOUT:-75} --graceful-timeout 30 --keep-alive 65"]