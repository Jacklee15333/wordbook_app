"""
背单词 App - 后端服务入口
v4.7: 新增单词图片接口 /media/{word_id}/image
v4.8: 修复音标问题 — 新增批量修复接口 /api/v1/admin/fix-phonetics
v5.0: 音节拆分 — pyphen 自动填充 syllables 字段 + 图片匹配标准化
v5.2: 词根词缀拆分 — morpheme_dict 引擎自动填充 morphemes 字段
"""
import os
import re
import glob
import json
import uuid as uuid_mod
import logging
import traceback
from fastapi import FastAPI, Depends, HTTPException, BackgroundTasks, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from sqlalchemy import select, func, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_db, safe_auto_migrate, engine, async_session
from app.core.security import get_current_user
from app.models.user import User
from app.models.word import Wordbook, Word, WordbookWord

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# ★ 降低 SQLAlchemy 日志噪音（只显示 WARNING 以上）
logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)

# ★ v5.2: 词根词缀引擎
try:
    from app.morpheme_dict import get_morphemes, MANUAL_MORPHEMES
    logger.info("[MORPHEMES] ✅ morpheme_dict module loaded successfully")
except ImportError as e:
    logger.warning(f"[MORPHEMES] ⚠️ morpheme_dict module not found: {e}")
    get_morphemes = None
    MANUAL_MORPHEMES = {}

settings = get_settings()

app = FastAPI(
    title="WordBook API v3",
    description="WordBook API with batch import + word image + phonetics fix",
    version="4.8.0",
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
    return {"pong": True, "version": "4.8.0"}

# ★ v5.8: 数据版本号 — 每次后台编辑数据+1，前端检测到变化就刷新缓存
_DATA_VERSION_FILE = os.path.join(os.path.dirname(__file__), '..', 'data', 'data_version.txt')

def _get_data_version() -> int:
    try:
        with open(_DATA_VERSION_FILE, 'r') as f:
            return int(f.read().strip())
    except Exception:
        return 0

def _bump_data_version() -> int:
    v = _get_data_version() + 1
    try:
        os.makedirs(os.path.dirname(_DATA_VERSION_FILE), exist_ok=True)
        with open(_DATA_VERSION_FILE, 'w') as f:
            f.write(str(v))
    except Exception as e:
        logger.warning(f"[DATA-VERSION] bump failed: {e}")
    return v

@app.get("/api/v1/data-version")
async def get_data_version():
    """前端启动时检查此版本号，版本变化则刷新缓存"""
    return {"version": _get_data_version()}

@app.post("/api/v1/data-version/bump")
async def bump_data_version_endpoint():
    """手动递增数据版本号，触发前端刷新"""
    v = _bump_data_version()
    return {"version": v, "message": f"数据版本已更新到 v{v}"}

@app.get("/api/v1/media-test")
async def media_test():
    """Dead simple test - no imports, no DB"""
    return {"ok": True, "msg": "media-test works", "version": "4.8.0"}


# ★ v5.8: 数据管道自动体检
@app.post("/api/v1/system/health-check")
async def system_health_check():
    """启动时自动检查数据管道是否畅通，修复常见问题"""
    issues = []
    fixes = []

    # ── 检查1: 数据库列是否完整 ──
    expected_columns = ['syllables', 'syllable_ipa', 'morphemes', 'derivation']
    try:
        async with engine.begin() as conn:
            result = await conn.execute(text(
                "SELECT column_name FROM information_schema.columns WHERE table_name='words'"
            ))
            db_columns = {row[0] for row in result.all()}

            for col in expected_columns:
                if col not in db_columns:
                    col_type = 'VARCHAR(500)' if col == 'derivation' else 'JSONB'
                    await conn.execute(text(f"ALTER TABLE words ADD COLUMN {col} {col_type}"))
                    fixes.append(f"数据库: 自动添加 {col} 列")
                    logger.info(f"[HEALTH] ✅ Auto-added column: {col}")
    except Exception as e:
        issues.append(f"数据库列检查失败: {e}")

    # ── 检查2: Schema 字段是否完整 ──
    try:
        from app.schemas import WordResponse
        schema_fields = set(WordResponse.model_fields.keys())
        missing_in_schema = []
        for col in expected_columns:
            if col not in schema_fields:
                missing_in_schema.append(col)
        if missing_in_schema:
            issues.append(f"Schema缺少字段: {', '.join(missing_in_schema)} (需要手动更新 schemas/__init__.py)")
    except Exception as e:
        issues.append(f"Schema检查失败: {e}")

    # ── 检查3: API返回是否包含关键字段 ──
    try:
        async with async_session() as session:
            result = await session.execute(
                select(Word).where(Word.morphemes.isnot(None)).limit(1)
            )
            sample_word = result.scalars().first()
            if sample_word:
                from app.schemas import WordResponse
                response_data = WordResponse.model_validate(sample_word).model_dump()
                for col in expected_columns:
                    if col not in response_data:
                        issues.append(f"API返回缺少 {col} 字段 (Schema未声明)")
    except Exception as e:
        issues.append(f"API返回检查失败: {e}")

    # ── 检查4: 数据统计 ──
    stats = {}
    try:
        async with async_session() as session:
            total = (await session.execute(select(func.count(Word.id)))).scalar() or 0
            has_syl = (await session.execute(select(func.count(Word.id)).where(Word.syllables.isnot(None)))).scalar() or 0
            has_morph = (await session.execute(select(func.count(Word.id)).where(Word.morphemes.isnot(None)))).scalar() or 0
            has_deriv = (await session.execute(select(func.count(Word.id)).where(Word.derivation.isnot(None)))).scalar() or 0
            stats = {
                "total_words": total,
                "has_syllables": has_syl,
                "has_morphemes": has_morph,
                "has_derivation": has_deriv,
            }
    except Exception as e:
        issues.append(f"数据统计失败: {e}")

    # ── 检查5: 如果有更新，自动bumpt版本号 ──
    if fixes:
        _bump_data_version()
        fixes.append("数据版本号已更新，前端将自动刷新")

    healthy = len(issues) == 0
    return {
        "healthy": healthy,
        "issues": issues,
        "auto_fixes": fixes,
        "stats": stats,
    }


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


# ===== v4.7 单词图片接口 =====
# 图片存储目录: backend/media_storage/image/
# 文件命名: {word_text}.png  (如 ability.png, be able to do sth..png)

_IMAGE_DIR = os.path.join(
    os.path.dirname(os.path.dirname(__file__)),  # → backend/
    "media_storage", "image"
)


def _normalize_for_filename(text: str) -> str:
    """去掉 Windows 文件名不允许的字符，用于匹配比较。
    Windows 不允许: \\ / : * ? \" < > |
    """
    return re.sub(r'[\\/:*?"<>|]', '', text).strip().lower()


def _find_word_image(word_text: str) -> str | None:
    """在 media_storage/image/ 目录中查找单词对应的图片文件。
    支持 png/jpg/jpeg/gif/webp。
    ★ v4.8: 匹配时去掉 Windows 非法文件名字符（如 ? ! 等），
    解决数据库中 "what about doing sth.?" 匹配不到
    文件名 "What about doing sth..png" 的问题。
    """
    if not os.path.isdir(_IMAGE_DIR):
        return None

    exts = (".png", ".jpg", ".jpeg", ".gif", ".webp")

    # 1) 精确匹配（原始 word_text 直接拼文件名）
    for ext in exts:
        path = os.path.join(_IMAGE_DIR, f"{word_text}{ext}")
        if os.path.isfile(path):
            return path

    # 2) 标准化匹配：去掉非法字符 + case-insensitive
    normalized = _normalize_for_filename(word_text)
    try:
        for fname in os.listdir(_IMAGE_DIR):
            name_part, fext = os.path.splitext(fname)
            if fext.lower() in exts and _normalize_for_filename(name_part) == normalized:
                return os.path.join(_IMAGE_DIR, fname)
    except OSError:
        pass

    return None


_MIME_MAP = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
}


@app.get("/api/v1/media/{word_id}/image")
async def get_word_image(
    word_id: str,
    db: AsyncSession = Depends(get_db),
):
    """获取单词配图。根据 word_id 查词库得到 word_text，再从本地图片目录匹配。"""
    import uuid as _u
    try:
        wid = _u.UUID(str(word_id).strip())
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid word_id")

    result = await db.execute(select(Word.word).where(Word.id == wid))
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="word not found")

    word_text = row[0]
    img_path = _find_word_image(word_text)
    if not img_path:
        raise HTTPException(status_code=404, detail=f"no image for: {word_text}")

    ext = os.path.splitext(img_path)[1].lower()
    mime = _MIME_MAP.get(ext, "image/png")

    return FileResponse(
        img_path,
        media_type=mime,
        headers={
            "Cache-Control": "public, max-age=604800",
            "Access-Control-Allow-Origin": "*",
        },
    )


@app.get("/api/v1/media/{word_id}/image/check")
async def check_word_image(
    word_id: str,
    db: AsyncSession = Depends(get_db),
):
    """检查单词是否有配图（轻量接口，不返回图片内容）。"""
    import uuid as _u
    try:
        wid = _u.UUID(str(word_id).strip())
    except ValueError:
        return {"has_image": False}

    result = await db.execute(select(Word.word).where(Word.id == wid))
    row = result.first()
    if not row:
        return {"has_image": False}

    img_path = _find_word_image(row[0])
    return {"has_image": img_path is not None, "word": row[0]}


# ===== v4.7 图片管理接口 =====

@app.get("/api/v1/media-admin/image-status")
async def image_status(db: AsyncSession = Depends(get_db)):
    """图片库统计：总数、总大小、文件列表、每本词书的图片覆盖率"""
    import time as _time

    image_files = []
    total_size = 0
    image_names_lower = {}  # lowercase name -> original filename (for matching)

    exts = (".png", ".jpg", ".jpeg", ".gif", ".webp")

    if os.path.isdir(_IMAGE_DIR):
        try:
            for fname in os.listdir(_IMAGE_DIR):
                fpath = os.path.join(_IMAGE_DIR, fname)
                if not os.path.isfile(fpath):
                    continue
                name_part, fext = os.path.splitext(fname)
                if fext.lower() not in exts:
                    continue
                sz = os.path.getsize(fpath)
                mtime = os.path.getmtime(fpath)
                total_size += sz
                image_files.append({
                    "name": fname,
                    "size": sz,
                    "mtime": mtime,
                    "word": name_part,
                })
                image_names_lower[name_part.lower()] = fname
        except OSError as e:
            logger.warning(f"[IMAGE] 读取图片目录失败: {e}")

    # 按修改时间倒序
    image_files.sort(key=lambda x: x["mtime"], reverse=True)

    # 每本词书的图片覆盖率
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
            has_image_count = sum(
                1 for w in words if w.lower() in image_names_lower
            )
            wordbooks_info.append({
                "id": str(wb.id),
                "name": wb.name or "unnamed",
                "total": len(words),
                "has_image": has_image_count,
            })
    except Exception as e:
        logger.warning(f"[IMAGE] 词书查询失败: {e}")

    return _JSONResponse(content={
        "image_count": len(image_files),
        "total_size_bytes": total_size,
        "image_dir": _IMAGE_DIR,
        "images": [{"name": f["name"], "size": f["size"], "word": f["word"]} for f in image_files[:200]],
        "wordbooks": wordbooks_info,
    })


@app.get("/api/v1/media-admin/image-file/{filename}")
async def get_image_file(filename: str):
    """直接返回图片文件（管理面板预览用）"""
    if not os.path.isdir(_IMAGE_DIR):
        raise HTTPException(status_code=404, detail="image dir not found")

    safe_name = os.path.basename(filename)
    file_path = os.path.join(_IMAGE_DIR, safe_name)

    if not os.path.isfile(file_path):
        raise HTTPException(status_code=404, detail=f"file not found: {safe_name}")

    ext = os.path.splitext(safe_name)[1].lower()
    mime = _MIME_MAP.get(ext, "image/png")

    return FileResponse(
        file_path,
        media_type=mime,
        headers={
            "Cache-Control": "public, max-age=86400",
            "Access-Control-Allow-Origin": "*",
        },
    )


@app.get("/api/v1/media-admin/audio-by-word/{word_text}")
async def get_audio_by_word(word_text: str):
    """根据单词文本直接返回音频文件（管理面板用）"""
    from app.services.media_service import _safe_filename, _get_media_dir

    filename = f"{_safe_filename(word_text)}.mp3"
    file_path = os.path.join(_get_media_dir("us"), filename)

    if not os.path.isfile(file_path) or os.path.getsize(file_path) < 500:
        raise HTTPException(status_code=404, detail=f"no audio for: {word_text}")

    return FileResponse(
        file_path,
        media_type="audio/mpeg",
        headers={
            "Cache-Control": "public, max-age=604800",
            "Access-Control-Allow-Origin": "*",
        },
    )


@app.get("/api/v1/media-admin/image-by-word/{word_text}")
async def get_image_by_word(word_text: str):
    """根据单词文本直接返回图片文件（管理面板用，自动匹配扩展名）"""
    img_path = _find_word_image(word_text)
    if not img_path:
        raise HTTPException(status_code=404, detail=f"no image for: {word_text}")

    ext = os.path.splitext(img_path)[1].lower()
    mime = _MIME_MAP.get(ext, "image/png")

    return FileResponse(
        img_path,
        media_type=mime,
        headers={
            "Cache-Control": "public, max-age=86400",
            "Access-Control-Allow-Origin": "*",
        },
    )


@app.post("/api/v1/media-admin/word-media-batch")
async def word_media_batch(data: dict = MainBody(...)):
    """批量检查一组单词的音频/图片状态"""
    from app.services.media_service import has_cached_audio

    words = data.get("words", [])
    if not words or not isinstance(words, list):
        return {"results": {}}

    results = {}
    for w in words[:200]:  # 限制200个
        w = str(w).strip()
        if not w:
            continue
        results[w] = {
            "has_audio": has_cached_audio(w, "us"),
            "has_image": _find_word_image(w) is not None,
        }
    return {"results": results}


# ===== v4.8 批量修复音标接口 =====

@app.post("/api/v1/admin/fix-phonetics")
async def fix_phonetics_batch(
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """
    ★ v4.8: 批量修复数据库中缺失音标的单词
    策略：
    1. 先从本地 vocabulary.db (SQLite) 读取音标（无需网络）
    2. 再从在线词典 API 查询剩余的（需要网络）
    """
    from sqlalchemy import or_
    result = await db.execute(
        select(Word.id, Word.word).where(
            or_(
                Word.phonetic_us == None,
                Word.phonetic_us == "",
            )
        ).order_by(Word.word)
    )
    words_to_fix = [(str(row[0]), row[1]) for row in result.all()]

    if not words_to_fix:
        return {
            "message": "所有单词都已有音标，无需修复",
            "total": 0,
        }

    logger.info(f"[FIX-PHONETICS] 发现 {len(words_to_fix)} 个单词缺少音标，启动后台修复...")

    async def _do_fix():
        """后台修复任务"""
        from app.core.database import async_session_factory
        from app.services.word_generator_service import WordGeneratorService
        from app.services.vocabulary_service import get_vocabulary_service
        import asyncio
        import re

        generator = WordGeneratorService()
        vocab_service = get_vocabulary_service()

        # ★ eng_to_ipa 库（纯离线）
        ipa_convert = None
        try:
            import eng_to_ipa as ipa
            ipa_convert = ipa.convert
            logger.info("[FIX-PHONETICS] eng_to_ipa 库加载成功")
        except ImportError:
            logger.warning("[FIX-PHONETICS] eng_to_ipa 未安装")

        fixed = 0
        failed = 0
        skipped = 0
        fixed_local = 0
        fixed_ipa = 0
        fixed_online = 0
        failed_words = []

        def _is_single_word(w):
            """判断是否为单个英文单词（不是短语/句型）"""
            w = w.strip()
            # 包含空格 → 短语/句型，跳过
            if ' ' in w:
                return False
            # 包含中文 → 跳过
            if re.search(r'[\u4e00-\u9fff]', w):
                return False
            # 包含特殊符号（除了连字符）→ 跳过
            if re.search(r'[^a-zA-Z\-]', w):
                return False
            # 太短（1个字母）→ 跳过
            if len(w) <= 1:
                return False
            return True

        async with async_session_factory() as session:
            for word_id_str, word_text in words_to_fix:
                # ★ 跳过短语、句型、非单词
                if not _is_single_word(word_text):
                    skipped += 1
                    continue

                try:
                    phonetic_us = ""
                    phonetic_uk = ""

                    # 策略1: 从本地 vocabulary.db 读取
                    vocab_result = vocab_service.exact_match(word_text)
                    if vocab_result and vocab_result.get("phonetic"):
                        raw_phonetic = vocab_result["phonetic"].strip()
                        if raw_phonetic and len(raw_phonetic) > 1:
                            phonetic_us = WordGeneratorService._clean_phonetic(raw_phonetic)
                            phonetic_uk = phonetic_us
                            fixed_local += 1

                    # 策略2: eng_to_ipa 本地生成
                    if not phonetic_us and ipa_convert:
                        try:
                            clean_word = word_text.strip().lower()
                            ipa_result = ipa_convert(clean_word)
                            if ipa_result and '*' not in ipa_result and ipa_result != clean_word:
                                phonetic_us = f"/{ipa_result}/"
                                phonetic_uk = phonetic_us
                                fixed_ipa += 1
                        except Exception:
                            pass

                    # 策略3: 在线词典 API
                    if not phonetic_us:
                        try:
                            phonetic_data = await generator.fetch_phonetic_only(word_text)
                            if phonetic_data:
                                phonetic_us = phonetic_data.get("phonetic_us", "")
                                phonetic_uk = phonetic_data.get("phonetic_uk", "")
                                if phonetic_us:
                                    fixed_online += 1
                        except Exception:
                            pass

                    # 写入数据库
                    if phonetic_us or phonetic_uk:
                        word_result = await session.execute(
                            select(Word).where(Word.id == word_id_str)
                        )
                        word_obj = word_result.scalars().first()
                        if word_obj:
                            if not word_obj.phonetic_us:
                                word_obj.phonetic_us = phonetic_us
                            if not word_obj.phonetic_uk:
                                word_obj.phonetic_uk = phonetic_uk or phonetic_us
                            fixed += 1
                    else:
                        failed += 1
                        failed_words.append(word_text)

                    # 每 50 个提交一次
                    if (fixed + failed) % 50 == 0 and (fixed + failed) > 0:
                        await session.commit()
                        logger.info(
                            f"[FIX-PHONETICS] 进度: {fixed + failed + skipped}/{len(words_to_fix)} "
                            f"(IPA={fixed_ipa} 词库={fixed_local} 跳过短语={skipped} 失败={failed})"
                        )

                except Exception as e:
                    logger.debug(f"[FIX-PHONETICS] 修复失败: {word_text}, error={e}")
                    failed += 1
                    failed_words.append(word_text)

            await session.commit()
            logger.info(
                f"[FIX-PHONETICS] ★ 修复完成! "
                f"IPA生成={fixed_ipa} 词库={fixed_local} 在线={fixed_online} "
                f"跳过短语={skipped} 失败={failed} 总计={len(words_to_fix)}"
            )
            if failed_words:
                logger.info(f"[FIX-PHONETICS] ★ 失败的单词列表 ({len(failed_words)}个):")
                for i in range(0, len(failed_words), 10):
                    batch = failed_words[i:i+10]
                    logger.info(f"[FIX-PHONETICS]   {', '.join(batch)}")

    background_tasks.add_task(_do_fix)

    return {
        "message": f"后台修复任务已启动，共 {len(words_to_fix)} 个单词需要修复音标",
        "total": len(words_to_fix),
        "words_preview": [w[1] for w in words_to_fix[:20]],
    }


@app.get("/api/v1/admin/phonetics-status")
async def phonetics_status(db: AsyncSession = Depends(get_db)):
    """
    ★ v4.8: 查看音标覆盖状况
    """
    from sqlalchemy import or_

    total = await db.scalar(select(func.count(Word.id)))
    missing = await db.scalar(
        select(func.count(Word.id)).where(
            or_(Word.phonetic_us == None, Word.phonetic_us == "")
        )
    )
    has_phonetic = (total or 0) - (missing or 0)

    # 抽样显示一些缺少音标的单词
    sample_result = await db.execute(
        select(Word.word).where(
            or_(Word.phonetic_us == None, Word.phonetic_us == "")
        ).order_by(Word.word).limit(30)
    )
    sample_words = [r[0] for r in sample_result.all()]

    return {
        "total_words": total or 0,
        "has_phonetic": has_phonetic,
        "missing_phonetic": missing or 0,
        "coverage_percent": round(has_phonetic / max(total, 1) * 100, 1),
        "sample_missing": sample_words,
    }


# ===== 固定端点 =====
@app.get("/admin", include_in_schema=False)
async def admin_page():
    admin_html = os.path.join(os.path.dirname(__file__), "static", "admin.html")
    if os.path.exists(admin_html):
        return FileResponse(
            admin_html,
            media_type="text/html",
            headers={
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "Pragma": "no-cache",
                "Expires": "0",
            },
        )
    return {"error": "admin.html not found"}


@app.get("/")
async def root():
    return {"app": "WordBook API", "version": "5.0.0"}


@app.get("/health")
async def health_check():
    return {"status": "ok"}


# ═══════════════════════════════════════════════════════════════
# ★ v5.0: 音节拆分 — pyphen 自动填充
# ═══════════════════════════════════════════════════════════════

def _get_syllables(word_text: str) -> list[str] | None:
    """用 pyphen 获取单词的音节拆分，仅对单个英文单词有效"""
    # 跳过短语、词缀、句型
    if ' ' in word_text or word_text.startswith('-') or word_text.endswith('-'):
        return None
    # 跳过包含特殊字符的
    if not re.match(r'^[a-zA-Z]+$', word_text):
        return None
    try:
        import pyphen
        dic = pyphen.Pyphen(lang='en_US')
        parts = dic.inserted(word_text.lower()).split('-')
        return parts if len(parts) > 1 else None
    except ImportError:
        return None
    except Exception as e:
        logger.warning(f"[SYLLABLES] pyphen error for '{word_text}': {e}")
        return None


async def _ensure_syllables_column():
    """启动时自动添加 syllables 列（如果不存在）"""
    try:
        async with engine.begin() as conn:
            result = await conn.execute(text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name='words' AND column_name='syllables'"
            ))
            if result.first() is None:
                await conn.execute(text(
                    "ALTER TABLE words ADD COLUMN syllables JSONB"
                ))
                logger.info("[MIGRATE] ✅ Added syllables column to words table")
            else:
                logger.info("[MIGRATE] syllables column already exists")
    except Exception as e:
        logger.warning(f"[MIGRATE] syllables column check/add failed: {e}")


async def _fill_missing_syllables():
    """后台填充所有缺少音节数据的单词"""
    try:
        import pyphen
    except ImportError:
        logger.warning("[SYLLABLES] pyphen not installed, run: pip install pyphen")
        return

    try:
        dic = pyphen.Pyphen(lang='en_US')
        async with async_session() as session:
            result = await session.execute(
                select(Word.id, Word.word).where(Word.syllables.is_(None))
            )
            words = result.all()
            if not words:
                logger.info("[SYLLABLES] All words already have syllables data")
                return

            count = 0
            for word_id, word_text in words:
                syllables = _get_syllables(word_text)
                if syllables:
                    await session.execute(
                        update(Word).where(Word.id == word_id)
                        .values(syllables=syllables)
                    )
                    count += 1

            await session.commit()
            logger.info(f"[SYLLABLES] ✅ Filled {count}/{len(words)} words with syllable data")
    except Exception as e:
        logger.error(f"[SYLLABLES] fill error: {e}")


@app.post("/api/v1/admin/fill-syllables")
async def fill_syllables_endpoint(
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
):
    """手动触发音节数据填充（管理员接口）"""
    background_tasks.add_task(_fill_missing_syllables)
    return {"message": "syllables fill started in background"}


# ═══════════════════════════════════════════════════════════════
# ★ v5.2: 词根词缀拆分 — morpheme_dict 引擎自动填充
# ═══════════════════════════════════════════════════════════════

async def _ensure_morphemes_column():
    """启动时自动添加 morphemes 列（如果不存在）"""
    try:
        async with engine.begin() as conn:
            result = await conn.execute(text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name='words' AND column_name='morphemes'"
            ))
            if result.first() is None:
                await conn.execute(text(
                    "ALTER TABLE words ADD COLUMN morphemes JSONB"
                ))
                logger.info("[MIGRATE] ✅ Added morphemes column to words table")
            else:
                logger.info("[MIGRATE] morphemes column already exists")
    except Exception as e:
        logger.warning(f"[MIGRATE] morphemes column check/add failed: {e}")


async def _fill_missing_morphemes():
    """后台填充所有缺少词根词缀数据的单词"""
    if get_morphemes is None:
        logger.warning("[MORPHEMES] ⚠️ get_morphemes function not available, skipping fill")
        return

    try:
        async with async_session() as session:
            result = await session.execute(
                select(Word.id, Word.word).where(Word.morphemes.is_(None))
            )
            words = result.all()
            if not words:
                logger.info("[MORPHEMES] All words already have morphemes data")
                return

            count = 0
            for word_id, word_text in words:
                morphemes = get_morphemes(word_text)
                if morphemes:
                    await session.execute(
                        update(Word).where(Word.id == word_id)
                        .values(morphemes=morphemes)
                    )
                    count += 1

            await session.commit()
            logger.info(f"[MORPHEMES] ✅ Filled {count}/{len(words)} words with morpheme data")
    except Exception as e:
        logger.error(f"[MORPHEMES] fill error: {e}")


async def _apply_manual_morpheme_overrides():
    """★ v5.5: 用 MANUAL_MORPHEMES 手工标注覆盖低质量的自动解析结果"""
    if not MANUAL_MORPHEMES:
        return
    try:
        async with async_session() as session:
            result = await session.execute(
                select(Word.id, Word.word)
            )
            words = result.all()
            count = 0
            for word_id, word_text in words:
                w = word_text.strip().lower()
                if w in MANUAL_MORPHEMES:
                    await session.execute(
                        update(Word).where(Word.id == word_id)
                        .values(morphemes=MANUAL_MORPHEMES[w])
                    )
                    count += 1
            await session.commit()
            if count > 0:
                logger.info(f"[MORPHEMES] ✅ Applied {count} MANUAL_MORPHEMES overrides")
    except Exception as e:
        logger.error(f"[MORPHEMES] manual override error: {e}")


@app.post("/api/v1/admin/fill-morphemes")
async def fill_morphemes_endpoint(
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
):
    """手动触发词根词缀数据填充（管理员接口）"""
    background_tasks.add_task(_fill_missing_morphemes)
    return {"message": "morphemes fill started in background"}


@app.post("/api/v1/admin/refill-morphemes")
async def refill_morphemes_endpoint(
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
):
    """清空后重填词根词缀数据（用于更新 morpheme_dict 后刷新）"""
    try:
        async with async_session() as session:
            await session.execute(
                update(Word).values(morphemes=None)
            )
            await session.commit()
            logger.info("[MORPHEMES] 🗑️ Cleared all morphemes data for refill")
    except Exception as e:
        logger.error(f"[MORPHEMES] clear error: {e}")
        return {"message": f"clear failed: {e}"}

    background_tasks.add_task(_fill_missing_morphemes)
    return {"message": "morphemes cleared and refill started in background"}


@app.get("/api/v1/debug/morpheme-status")
async def morpheme_status():
    """诊断端点：检查 morphemes 数据状态（无需登录）"""
    try:
        async with async_session() as session:
            # 总词数
            total_result = await session.execute(select(func.count(Word.id)))
            total = total_result.scalar()

            # 有 morphemes 数据的词数
            filled_result = await session.execute(
                select(func.count(Word.id)).where(Word.morphemes.isnot(None))
            )
            filled = filled_result.scalar()

            # 抽样：取5个有数据的词看看
            sample_result = await session.execute(
                select(Word.word, Word.morphemes)
                .where(Word.morphemes.isnot(None))
                .limit(5)
            )
            samples = [{"word": r[0], "morphemes": r[1]} for r in sample_result.all()]

            # 检查 accidental 这个词
            test_result = await session.execute(
                select(Word.word, Word.morphemes, Word.syllables)
                .where(Word.word == 'accidental')
            )
            test_row = test_result.first()
            test_word = None
            if test_row:
                test_word = {
                    "word": test_row[0],
                    "morphemes": test_row[1],
                    "syllables": test_row[2],
                }

        return {
            "total_words": total,
            "words_with_morphemes": filled,
            "words_without_morphemes": total - filled,
            "morpheme_dict_loaded": get_morphemes is not None,
            "test_accidental": test_word,
            "samples": samples,
        }
    except Exception as e:
        return {"error": str(e), "morpheme_dict_loaded": get_morphemes is not None}


@app.on_event("startup")
async def startup_event():
    # ★★★ 超醒目启动标记 ★★★
    print("\n" + "★" * 60)
    print("★★★  main.py v5.2 (2026-04-01) 词根词缀版  ★★★")
    print("★★★  morpheme_dict loaded:", "YES ✅" if get_morphemes else "NO ❌", " ★★★")
    print("★" * 60 + "\n")

    # ★ 安全自动建表：只创建缺失的表，绝不删除已有数据
    try:
        await safe_auto_migrate()
    except Exception as e:
        logger.error(f"自动建表出错（不影响启动）: {e}")

    # ★ v5.0: 确保 syllables 列存在，并后台填充
    try:
        await _ensure_syllables_column()
    except Exception as e:
        logger.warning(f"syllables 列迁移失败: {e}")

    # ★ v5.2: 确保 morphemes 列存在，并后台填充
    try:
        await _ensure_morphemes_column()
    except Exception as e:
        logger.warning(f"morphemes 列迁移失败: {e}")

    # ★ v5.3: 确保 syllable_ipa 列存在
    try:
        async with engine.begin() as conn:
            result = await conn.execute(text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name='words' AND column_name='syllable_ipa'"
            ))
            if result.first() is None:
                await conn.execute(text(
                    "ALTER TABLE words ADD COLUMN syllable_ipa JSONB"
                ))
                logger.info("[MIGRATE] ✅ Added syllable_ipa column")
            else:
                logger.info("[MIGRATE] syllable_ipa column already exists")
    except Exception as e:
        logger.warning(f"syllable_ipa 列迁移失败: {e}")

    # ★ v5.8: 确保 derivation 列存在
    try:
        async with engine.begin() as conn:
            result = await conn.execute(text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name='words' AND column_name='derivation'"
            ))
            if result.first() is None:
                await conn.execute(text(
                    "ALTER TABLE words ADD COLUMN derivation VARCHAR(500)"
                ))
                logger.info("[MIGRATE] ✅ Added derivation column")
            else:
                logger.info("[MIGRATE] derivation column already exists")
    except Exception as e:
        logger.warning(f"derivation 列迁移失败: {e}")

    import asyncio
    asyncio.create_task(_fill_missing_syllables())
    asyncio.create_task(_fill_missing_morphemes())
    asyncio.create_task(_apply_manual_morpheme_overrides())

    print("\n" + "=" * 50)
    print("ROUTE LIST v5.2 (syllable + morpheme):")
    for route in app.routes:
        if hasattr(route, 'methods') and hasattr(route, 'path'):
            methods = ','.join(route.methods)
            print(f"  {methods:8s} {route.path}")
    print("=" * 50 + "\n")