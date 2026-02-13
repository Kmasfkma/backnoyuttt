from dotenv import load_dotenv
load_dotenv()

import sys
import os
import asyncio
import time
import uuid
import psutil
from collections import OrderedDict
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, Request, HTTPException, Response, Depends, APIRouter, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

# المكونات الأساسية فقط
from core.services import redis
from core.utils.openapi_config import configure_openapi
from core.services.supabase import DBConnection
from core.utils.config import config, EnvMode
from core.utils.logger import logger, structlog

# استيراد الـ Routers الأساسية
from core.versioning.api import router as versioning_router
from core.agents.api import router as agent_runs_router
from core.agents.agent_crud import router as agent_crud_router
from core.threads.api import router as threads_router
from core.sandbox import api as sandbox_api
from core.setup import router as setup_router, webhook_router
from core.notifications import api as notifications_api
from auth import api as auth_api
from core.utils.auth_utils import verify_and_get_user_id_from_jwt

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

db = DBConnection()
from core.utils.instance import INSTANCE_ID
instance_id = INSTANCE_ID

_is_shutting_down = False

@asynccontextmanager
async def lifespan(app: FastAPI):
    global _is_shutting_down
    # تقليل رسائل الـ Log لتوفير الـ CPU
    logger.info(f"Startup: Constrained Environment (512MB RAM)")
    try:
        # تشغيل الاتصالات الحيوية فقط
        await db.initialize()
        
        # تهيئة Redis (أساسي لتشغيل الـ Agent)
        from core.services import redis
        try:
            await redis.initialize_async()
            logger.debug("Redis initialized")
        except Exception as e:
            logger.error(f"Redis Init Failed: {e}")

        # ملاحظة: تم حذف مهام الـ Warm-up والـ Watchdog لتوفير الذاكرة
        
        from core.agents.pipeline.stateless import lifecycle
        await lifecycle.initialize()
        
        yield

        # Shutdown logic
        _is_shutting_down = True
        from core.agents.pipeline.stateless import lifecycle
        await lifecycle.shutdown()
        await db.disconnect()
        try: await redis.close()
        except: pass

    except Exception as e:
        logger.error(f"Critical Startup Error: {e}")
        raise

app = FastAPI(lifespan=lifespan)
configure_openapi(app)

# CORS
allowed_origins = ["https://www.kortix.com", "https://kortix.com"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

api_router = APIRouter()
# إضافة الـ Routers الأساسية فقط لتقليل حمل الذاكرة
api_router.include_router(versioning_router)
api_router.include_router(agent_runs_router)
api_router.include_router(threads_router)
api_router.include_router(sandbox_api.router)
api_router.include_router(auth_api.router)

@api_router.get("/health", tags=["system"])
async def health_check():
    if _is_shutting_down:
        raise HTTPException(status_code=503, detail="shutting_down")
    return {"status": "ok", "instance_id": instance_id}

app.include_router(api_router, prefix="/v1")

if __name__ == "__main__":
    import uvicorn
    # إجبار السيرفر على العمل بـ Worker واحد فقط لضمان عدم تجاوز 512MB
    uvicorn.run("api:app", host="0.0.0.0", port=7860, workers=1, loop="asyncio")
