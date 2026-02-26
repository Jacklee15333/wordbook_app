"""
背单词 App - 后端服务入口
启动: uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.api.auth import router as auth_router
from app.api.study import router as study_router
from app.api.words import router as words_router

settings = get_settings()

app = FastAPI(
    title="背单词 App API",
    description="背单词 App 后端服务 - Flutter Web + FastAPI + PostgreSQL + FSRS v5",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS 配置（开发环境允许所有来源）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
app.include_router(auth_router, prefix="/api/v1")
app.include_router(study_router, prefix="/api/v1")
app.include_router(words_router, prefix="/api/v1")


@app.get("/")
async def root():
    return {
        "app": "背单词 App API",
        "version": "1.0.0",
        "docs": "/docs",
    }


@app.get("/health")
async def health_check():
    return {"status": "ok"}