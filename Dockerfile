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

# 4. تثبيت المكتبات (نحتفظ بملف requirements.txt الأخير)
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install -r requirements.txt && \
    pip install playwright

# 5. تثبيت الكروم
RUN python -m playwright install chromium

# 6. نسخ الكود
COPY --chown=1000:1000 . .

# --- الخطوة السحرية: إنشاء ملف محاكاة (Mock) ذكي ---
# ننشئ ملف بايثون يحتوي على كلاس يقبل أي شيء (Arguments, Context Managers, Awaitables)
RUN echo 'class Mock:\n\
    def __init__(self, *args, **kwargs): pass\n\
    def __call__(self, *args, **kwargs): return self\n\
    def __getattr__(self, name): return self\n\
    def __await__(self): yield None\n\
    async def __aenter__(self): return self\n\
    async def __aexit__(self, *args): pass\n\
\n\
# تعيين كل الأسماء المطلوبة لهذا الكلاس\n\
AsyncDaytona=DaytonaConfig=CreateSandboxFromSnapshotParams=AsyncSandbox=SessionExecuteRequest=Resources=SandboxState=WorkspaceState=Mock' > /app/mock_daytona.py

# --- توجيه الكود لاستخدام الملف الوهمي بدلاً من المكتبة المفقودة ---
# نغير أي سطر يستورد من "daytona_sdk" ليستورد من "mock_daytona"
RUN find core -name "*.py" -print0 | xargs -0 sed -i 's/from daytona_sdk/from mock_daytona/g'

USER 1000
EXPOSE 8000

CMD ["sh", "-c", "redis-server --daemonize yes --maxmemory 40mb --maxmemory-policy allkeys-lru && uvicorn api:app --host 0.0.0.0 --port 8000 --workers 1"]
