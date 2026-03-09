"""
背单词 App - 后端服务入口
"""
import os
import json
import uuid as uuid_mod
import logging
import traceback
from fastapi import FastAPI, Depends, HTTPException, BackgroundTasks, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.models.word import Wordbook, Word, WordbookWord

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

settings = get_settings()

app = FastAPI(
    title="WordBook API v3",
    description="WordBook API with batch import",
    version="4.6.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ===== 诊断端点（直接在 app 上） =====
@app.get("/ping")
async def ping():
    return {"pong": True, "version": "4.6.0"}

@app.get("/api/v1/media-test")
async def media_test():
    """Dead simple test - no imports, no DB"""
    return {"ok": True, "msg": "media-test works", "version": "4.6.0"}


@app.get("/test/{some_id}/action")
async def test_path_param(some_id: str):
    return {"matched": True, "some_id": some_id}


# ===== 验证文件是否更新 — 无需登录，在浏览器直接访问 =====
@app.get("/api/v1/rename-check")
async def rename_check():
    """访问 http://localhost:8000/api/v1/rename-check 验证后端是否更新"""
    return {
        "status": "main.py已更新",
        "version": "rename-debug-v3",
        "rename_route": "POST /api/v1/wordbooks/{id}/rename",
    }


# ===== ★★★ 重命名词书 — 直接注册，绕过 router 加载问题 ★★★ =====
from fastapi import Body as MainBody

@app.post("/api/v1/wordbooks/{wordbook_id}/rename")
async def rename_wordbook_direct(
    wordbook_id: str,
    data: dict = MainBody(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """重命名词书 — 直接注册在 main.py"""
    print(f"\n{'='*60}")
    print(f"[RENAME] ★ 收到重命名请求!")
    print(f"[RENAME] wordbook_id = {wordbook_id!r}")
    print(f"[RENAME] data        = {data!r}")
    print(f"[RENAME] user_id     = {current_user.id!r}")
    print(f"{'='*60}\n")
    logger.info(f"[RENAME] wordbook_id={wordbook_id} data={data} user={current_user.id}")

    import uuid as _uuid
    try:
        wb_uuid = _uuid.UUID(str(wordbook_id).strip())
    except ValueError as ve:
        print(f"[RENAME] ❌ UUID解析失败: {ve}")
        raise HTTPException(status_code=400, detail=f"无效的词书ID格式: {wordbook_id!r}")

    result = await db.execute(select(Wordbook).where(Wordbook.id == wb_uuid))
    wordbook = result.scalars().first()

    if not wordbook:
        print(f"[RENAME] ❌ 词书不存在 uuid={wb_uuid}")
        raise HTTPException(status_code=404, detail=f"词书不存在 (id={wordbook_id})")

    print(f"[RENAME] ✅ 找到词书: name={wordbook.name!r} is_builtin={wordbook.is_builtin} created_by={wordbook.created_by!r}")

    if wordbook.is_builtin:
        print(f"[RENAME] ❌ 是内置词书，不可重命名")
        raise HTTPException(status_code=403, detail="内置词书不可重命名")
    if wordbook.created_by is not None and wordbook.created_by != current_user.id:
        print(f"[RENAME] ❌ 非创建者: created_by={wordbook.created_by} user={current_user.id}")
        raise HTTPException(status_code=403, detail="无权操作此词书（非创建者）")

    new_name = (data.get("name") or "").strip()
    if not new_name:
        raise HTTPException(status_code=400, detail="词书名称不能为空")

    old_name = wordbook.name
    wordbook.name = new_name
    await db.commit()
    print(f"[RENAME] ✅ 成功: {old_name!r} → {new_name!r}")
    return {"message": "重命名成功", "name": new_name}


# ===== ★★★ 导入 V2 端点 — 直接在 app 上注册，不通过 router ★★★ =====

@app.get("/api/v1/wordbooks/{wordbook_id}/batch-import")
async def batch_import_check(wordbook_id: str):
    """GET 测试端点"""
    return {"status": "route_ok", "wordbook_id": wordbook_id}


@app.post("/api/v1/wordbooks/{wordbook_id}/batch-import")
async def batch_import_words(
    wordbook_id: str,
    request: Request,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """新版导入接口"""
    logger.info(f"=== batch-import called === wordbook_id={wordbook_id}")

    try:
        body_bytes = await request.body()
        data = json.loads(body_bytes)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Body 解析失败: {str(e)}")

    try:
        from app.core.database import async_session_factory
        from app.models.import_task import ImportTask
        from app.services.import_processor import ImportProcessor
    except Exception as e:
        logger.error(f"Dependency error: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"依赖加载失败: {str(e)}")

    words = data.get("words", [])
    if not words or not isinstance(words, list):
        raise HTTPException(status_code=400, detail="请提供 words 列表")

    result = await db.execute(select(Wordbook).where(Wordbook.id == wordbook_id))
    wordbook = result.scalars().first()
    if not wordbook:
        raise HTTPException(status_code=404, detail="词书不存在")

    word_list = list(dict.fromkeys([w.strip() for w in words if isinstance(w, str) and w.strip()]))
    if not word_list:
        raise HTTPException(status_code=400, detail="单词列表为空")

    task_id = uuid_mod.uuid4()
    task = ImportTask(
        id=task_id, user_id=current_user.id, wordbook_id=wordbook_id,
        total_words=len(word_list), status="pending",
    )
    db.add(task)
    await db.commit()

    processor = ImportProcessor(
        db_session_factory=async_session_factory,
        ollama_base_url=settings.ollama_base_url,
        ollama_model=settings.ollama_model,
    )
    background_tasks.add_task(processor.process_import, str(task_id), word_list)

    return {
        "task_id": str(task_id),
        "message": f"导入任务已创建，共 {len(word_list)} 个单词",
        "total_words": len(word_list),
    }


@app.get("/api/v1/import-tasks/{task_id}/progress")
async def get_task_progress_direct(
    task_id: str, db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.models.import_task import ImportTask
    result = await db.execute(select(ImportTask).where(ImportTask.id == task_id))
    task = result.scalars().first()
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")
    processed = task.matched_count + task.ai_generated_count + task.ai_failed_count
    progress = (processed / max(task.total_words, 1)) * 100
    return {
        "id": str(task.id), "status": task.status, "total_words": task.total_words,
        "matched_count": task.matched_count, "ai_generated_count": task.ai_generated_count,
        "ai_failed_count": task.ai_failed_count, "approved_count": task.approved_count,
        "progress": round(progress, 1), "error_message": task.error_message,
    }


@app.get("/api/v1/import-tasks/{task_id}/results")
async def get_task_results_direct(
    task_id: str, db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.models.import_task import ImportTask, ImportItem
    result = await db.execute(select(ImportTask).where(ImportTask.id == task_id))
    task = result.scalars().first()
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")
    items_result = await db.execute(
        select(ImportItem).where(ImportItem.task_id == task_id)
        .order_by(ImportItem.match_type, ImportItem.word_text)
    )
    items = items_result.scalars().all()
    return {
        "task": task.to_dict(),
        "matched": [i.to_dict() for i in items if i.match_type == "exact_match"],
        "generated": [i.to_dict() for i in items if i.match_type in ("ai_generated", "dict_generated")],
        "failed": [i.to_dict() for i in items if i.match_type == "ai_failed"],
    }


# ===== 原有路由注册 =====

try:
    from app.api.auth import router as auth_router
    app.include_router(auth_router, prefix="/api/v1")
    logger.info("OK auth")
except Exception as e:
    logger.error(f"FAIL auth: {e}")
    traceback.print_exc()

try:
    from app.api.study import router as study_router
    app.include_router(study_router, prefix="/api/v1")
    logger.info("OK study")
except Exception as e:
    logger.error(f"FAIL study: {e}")
    traceback.print_exc()

try:
    from app.api.words import router as words_router
    app.include_router(words_router, prefix="/api/v1")
    logger.info("OK words")
except Exception as e:
    logger.error(f"FAIL words: {e}")
    traceback.print_exc()

try:
    from app.api.admin import router as admin_router
    app.include_router(admin_router)
    logger.info("OK admin")
except Exception as e:
    logger.error(f"FAIL admin: {e}")
    traceback.print_exc()

# NOTE: media router kept for /media/{word_id}/audio only
try:
    from app.api.media import router as media_router
    app.include_router(media_router, prefix="/api/v1")
    logger.info("OK media (audio endpoint)")
except Exception as e:
    logger.warning(f"media router skipped: {e}")

# ===== v4.6 media-admin endpoints (separate path, no router conflict) =====
from fastapi.responses import JSONResponse as _JSONResponse, Response as _Response

@app.get("/api/v1/media-admin/status")
async def media_status_v45(db: AsyncSession = Depends(get_db)):
    """media status - v4.6"""
    logger.info("[MEDIA-v4.6] === /media-admin/status called ===")
    try:
        from app.services.media_service import get_cache_stats, get_preload_status, has_cached_audio
        logger.info("[MEDIA-v4.6] imports OK")
        stats = get_cache_stats()
        preload = get_preload_status()
        logger.info(f"[MEDIA-v4.6] stats={stats['audio_us_count']} files, preload={preload.get('status')}")

        wordbooks_info = []
        try:
            wb_result = await db.execute(select(Wordbook).order_by(Wordbook.name))
            for wb in wb_result.scalars().all():
                words_result = await db.execute(
                    select(Word.word)
                    .join(WordbookWord, Word.id == WordbookWord.word_id)
                    .where(WordbookWord.wordbook_id == wb.id)
                )
                words = [r[0] for r in words_result.all()]
                cached = sum(1 for w in words if has_cached_audio(w))
                wordbooks_info.append({
                    "id": str(wb.id), "name": wb.name or "unnamed",
                    "total": len(words), "cached": cached,
                })
        except Exception as e:
            logger.warning(f"[MEDIA-v4.6] wordbook query: {e}")
            import traceback as _tb
            _tb.print_exc()

        # Calculate elapsed time if running
        elapsed_seconds = 0
        if preload.get("start_time"):
            import time
            elapsed_seconds = int(time.time() - preload["start_time"])

        result = {
            **stats,
            "preload_status": preload.get("status", "idle"),
            "preload_progress": preload.get("progress", ""),
            "preload_total": preload.get("total", 0),
            "preload_done": preload.get("done", 0),
            "preload_failed": preload.get("failed", 0),
            "preload_skipped": preload.get("skipped", 0),
            "preload_current_word": preload.get("current_word", ""),
            "preload_wordbook_name": preload.get("wordbook_name", ""),
            "preload_elapsed_seconds": elapsed_seconds,
            "preload_failed_words": preload.get("failed_words", []),
            "wordbooks": wordbooks_info,
        }
        logger.info(f"[MEDIA-v4.6] returning {len(wordbooks_info)} wordbooks")
        return _JSONResponse(content=result)
    except Exception as e:
        logger.error(f"[MEDIA-v4.6] status error: {e}")
        import traceback as _tb
        _tb.print_exc()
        return _JSONResponse(content={
            "audio_us_count": 0, "audio_uk_count": 0, "total_size_bytes": 0,
            "recent_files": [], "preload_status": "error",
            "preload_progress": str(e), "wordbooks": [],
            "preload_total": 0, "preload_done": 0, "preload_failed": 0,
            "preload_skipped": 0, "preload_current_word": "",
            "preload_wordbook_name": "", "preload_elapsed_seconds": 0,
            "preload_failed_words": [],
        })

@app.post("/api/v1/media-admin/preload/{wordbook_id}")
async def media_preload_v45(
    wordbook_id: str,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """media preload - v4.6"""
    logger.info(f"[MEDIA-v4.6] === /media-admin/preload called: {wordbook_id} ===")
    try:
        from app.services.media_service import preload_wordbook_audio, get_preload_status
        import uuid as _u

        # Check if already running
        current_status = get_preload_status()
        if current_status.get("status") == "running":
            return {"message": "已有下载任务正在进行中，请等待完成", "total_words": 0, "version": "v4.6", "already_running": True}

        wb_uuid = _u.UUID(str(wordbook_id).strip())

        # Get wordbook name
        wb_result = await db.execute(select(Wordbook).where(Wordbook.id == wb_uuid))
        wb = wb_result.scalars().first()
        wb_name = wb.name if wb else "unknown"

        result = await db.execute(
            select(Word.word)
            .join(WordbookWord, Word.id == WordbookWord.word_id)
            .where(WordbookWord.wordbook_id == wb_uuid)
        )
        words = [r[0] for r in result.all()]
        logger.info(f"[MEDIA-v4.6] preload: {len(words)} words found")
        if words:
            background_tasks.add_task(preload_wordbook_audio, words, "us", wb_name)
        return {"message": "preload started", "total_words": len(words), "version": "v4.6", "wordbook_name": wb_name}
    except Exception as e:
        logger.error(f"[MEDIA-v4.6] preload error: {e}")
        import traceback as _tb
        _tb.print_exc()
        return {"message": str(e), "total_words": 0}


# ===== 固定端点 =====
@app.get("/admin", include_in_schema=False)
async def admin_page():
    admin_html = os.path.join(os.path.dirname(__file__), "static", "admin.html")
    if os.path.exists(admin_html):
        return FileResponse(admin_html, media_type="text/html")
    return {"error": "admin.html not found"}


@app.get("/")
async def root():
    return {"app": "WordBook API", "version": "4.6.0"}


@app.get("/health")
async def health_check():
    return {"status": "ok"}


@app.on_event("startup")
async def startup_event():
    logger.info("=" * 50)
    logger.info("ROUTE LIST v4.6.0 (media-direct):")
    for route in app.routes:
        if hasattr(route, 'methods') and hasattr(route, 'path'):
            methods = ','.join(route.methods)
            logger.info(f"  {methods:8s} {route.path}")
    logger.info("=" * 50)