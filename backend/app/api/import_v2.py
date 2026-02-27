"""
新版导入 API（v2）
文件位置: app/api/import_v2.py

★★★ 关键：所有重依赖（ImportProcessor, vocabulary_service）都在函数体内懒加载 ★★★
★★★ 这样即使依赖有问题，路由也能注册成功，错误会在请求时暴露为 500 而非 404 ★★★
"""
import uuid as uuid_mod
import logging
import traceback
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, Body
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User

logger = logging.getLogger(__name__)

# 不设 prefix，由 main.py 统一加 /api/v1
router = APIRouter(tags=["import-v2"])


# ============================================================
# 测试端点 — 验证路由是否注册成功（零依赖）
# ============================================================
@router.get("/import-v2/test")
async def import_v2_test():
    """测试端点，如果能访问说明路由注册成功"""
    return {"status": "ok", "message": "import-v2 router is working!"}


# ============================================================
# 导入接口
# ============================================================
@router.post("/wordbooks/{wordbook_id}/import-v2")
async def import_words_v2(
    wordbook_id: UUID,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    data: dict = Body(...),
):
    """新版导入接口（异步处理）"""
    logger.info(f"=== import-v2 called === wordbook_id={wordbook_id}, user={current_user.id}")

    # ---- 懒加载重依赖 ----
    try:
        from app.core.database import async_session_factory
        from app.core.config import get_settings
        from app.models.import_task import ImportTask
        from app.models.word import Wordbook
        from app.services.import_processor import ImportProcessor
    except Exception as e:
        logger.error(f"import-v2 依赖加载失败: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"服务内部依赖加载失败: {str(e)}")

    settings = get_settings()

    words = data.get("words", [])
    if not words or not isinstance(words, list):
        raise HTTPException(status_code=400, detail="请提供 words 列表")

    # 验证词书存在
    result = await db.execute(select(Wordbook).where(Wordbook.id == wordbook_id))
    wordbook = result.scalars().first()
    if not wordbook:
        raise HTTPException(status_code=404, detail="词书不存在")

    # 去重去空
    word_list = list(dict.fromkeys([w.strip() for w in words if isinstance(w, str) and w.strip()]))
    if not word_list:
        raise HTTPException(status_code=400, detail="单词列表为空")

    logger.info(f"Creating import task: {len(word_list)} words")

    # 创建任务
    task_id = uuid_mod.uuid4()
    task = ImportTask(
        id=task_id,
        user_id=current_user.id,
        wordbook_id=wordbook_id,
        total_words=len(word_list),
        status="pending",
    )
    db.add(task)
    await db.commit()

    logger.info(f"Task created: {task_id}")

    # 启动后台处理
    processor = ImportProcessor(
        db_session_factory=async_session_factory,
        ollama_base_url=settings.ollama_base_url,
        ollama_model=settings.ollama_model,
    )
    background_tasks.add_task(processor.process_import, str(task_id), word_list)

    return {
        "task_id": str(task_id),
        "message": f"导入任务已创建，共 {len(word_list)} 个单词正在后台处理",
        "total_words": len(word_list),
    }


# ============================================================
# 进度查询
# ============================================================
@router.get("/import-tasks/{task_id}/progress")
async def get_task_progress(
    task_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取导入任务进度"""
    try:
        from app.models.import_task import ImportTask
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"依赖加载失败: {str(e)}")

    result = await db.execute(select(ImportTask).where(ImportTask.id == task_id))
    task = result.scalars().first()
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")

    processed = task.matched_count + task.ai_generated_count + task.ai_failed_count
    progress = (processed / max(task.total_words, 1)) * 100

    return {
        "id": str(task.id),
        "status": task.status,
        "total_words": task.total_words,
        "matched_count": task.matched_count,
        "ai_generated_count": task.ai_generated_count,
        "ai_failed_count": task.ai_failed_count,
        "approved_count": task.approved_count,
        "progress": round(progress, 1),
        "error_message": task.error_message,
    }


# ============================================================
# 结果查询
# ============================================================
@router.get("/import-tasks/{task_id}/results")
async def get_task_results(
    task_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取导入任务的最终结果"""
    try:
        from app.models.import_task import ImportTask, ImportItem
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"依赖加载失败: {str(e)}")

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