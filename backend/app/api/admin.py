"""
管理后台 API 路由
文件位置: app/api/admin.py

★★★ 关键：vocabulary_service 等重依赖在函数体内懒加载 ★★★
"""
import uuid
import logging
import traceback
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Body
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])


def _get_vocab_service():
    """懒加载 vocabulary_service"""
    from app.services.vocabulary_service import get_vocabulary_service
    return get_vocabulary_service()


def _get_models():
    """懒加载 models"""
    from app.models.word import Word, Wordbook
    from app.models.import_task import ImportTask, ImportItem
    return Word, Wordbook, ImportTask, ImportItem


# ==================== Dashboard ====================

@router.get("/dashboard")
async def get_dashboard_stats(db: AsyncSession = Depends(get_db)):
    """仪表盘统计数据"""
    try:
        Word, Wordbook, ImportTask, ImportItem = _get_models()
        vocab_service = _get_vocab_service()
    except Exception as e:
        logger.error(f"admin dashboard 依赖加载失败: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"依赖加载失败: {str(e)}")

    user_count = await db.scalar(select(func.count(User.id)))
    wordbook_count = await db.scalar(select(func.count(Wordbook.id)))
    word_count = await db.scalar(select(func.count(Word.id)))

    vocab_stats = vocab_service.get_stats()

    task_total = await db.scalar(select(func.count(ImportTask.id)))
    task_processing = await db.scalar(
        select(func.count(ImportTask.id)).where(ImportTask.status == "processing")
    )
    task_completed = await db.scalar(
        select(func.count(ImportTask.id)).where(ImportTask.status == "completed")
    )
    pending_review = await db.scalar(
        select(func.count(ImportItem.id)).where(ImportItem.status == "waiting_review")
    )

    return {
        "users": {"total": user_count or 0},
        "wordbooks": {"total": wordbook_count or 0},
        "words": {"total": word_count or 0},
        "vocabulary": vocab_stats,
        "import_tasks": {
            "total": task_total or 0,
            "processing": task_processing or 0,
            "completed": task_completed or 0,
        },
        "pending_review": pending_review or 0,
    }


# ==================== 用户管理 ====================

@router.get("/users")
async def list_users(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    search: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """用户列表"""
    query = select(User)
    count_query = select(func.count(User.id))

    if search:
        if hasattr(User, 'email'):
            search_filter = User.email.ilike(f"%{search}%")
        elif hasattr(User, 'nickname'):
            search_filter = User.nickname.ilike(f"%{search}%")
        else:
            search_filter = None
        if search_filter is not None:
            query = query.where(search_filter)
            count_query = count_query.where(search_filter)

    total = await db.scalar(count_query)

    if hasattr(User, 'created_at'):
        query = query.order_by(User.created_at.desc())

    result = await db.execute(
        query.offset((page - 1) * page_size).limit(page_size)
    )
    users = result.scalars().all()

    return {
        "items": [
            {
                "id": str(u.id),
                "email": getattr(u, 'email', ''),
                "nickname": getattr(u, 'nickname', ''),
                "role": getattr(u, 'role', 'user'),
                "is_active": getattr(u, 'is_active', True),
                "is_admin": getattr(u, 'is_admin', False),
                "created_at": u.created_at.isoformat() if hasattr(u, 'created_at') and u.created_at else None,
            }
            for u in users
        ],
        "total": total or 0,
        "page": page,
        "page_size": page_size,
    }


@router.put("/users/{user_id}")
async def update_user(
    user_id: str,
    data: dict = Body(...),
    db: AsyncSession = Depends(get_db)
):
    """更新用户信息"""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="用户不存在")

    if 'is_admin' in data and hasattr(user, 'is_admin'):
        user.is_admin = data['is_admin']
    if 'is_active' in data and hasattr(user, 'is_active'):
        user.is_active = data['is_active']

    await db.commit()
    return {"message": "更新成功"}


# ==================== 词库管理 ====================

@router.get("/vocabulary/list")
async def list_vocabulary(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    search: Optional[str] = None
):
    """词库列表"""
    try:
        vocab_service = _get_vocab_service()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"词库服务加载失败: {str(e)}")

    if search:
        return vocab_service.search(search, page, page_size)
    else:
        return vocab_service.list_all(page, page_size)


@router.get("/vocabulary/stats")
async def vocabulary_stats():
    """词库统计"""
    try:
        vocab_service = _get_vocab_service()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"词库服务加载失败: {str(e)}")
    return vocab_service.get_stats()


@router.get("/vocabulary/{word_id}")
async def get_vocabulary_item(word_id: int):
    """获取词库单条记录"""
    try:
        vocab_service = _get_vocab_service()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"词库服务加载失败: {str(e)}")
    item = vocab_service.get_by_id(word_id)
    if not item:
        raise HTTPException(status_code=404, detail="词条不存在")
    return item


@router.post("/vocabulary")
async def add_vocabulary(data: dict = Body(...)):
    """添加词条到词库"""
    try:
        vocab_service = _get_vocab_service()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"词库服务加载失败: {str(e)}")
    word_id = vocab_service.add_word(
        word=data.get("word", ""),
        meaning=data.get("meaning", ""),
        phonetic=data.get("phonetic", ""),
        difficulty=data.get("difficulty", ""),
        examples=data.get("examples", ""),
        added_from="manual"
    )
    return {"id": word_id, "message": "添加成功"}


@router.put("/vocabulary/{word_id}")
async def update_vocabulary(word_id: int, data: dict = Body(...)):
    """更新词库词条"""
    try:
        vocab_service = _get_vocab_service()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"词库服务加载失败: {str(e)}")
    allowed = {"word", "meaning", "phonetic", "difficulty", "examples"}
    updates = {k: v for k, v in data.items() if k in allowed and v is not None}
    if not updates:
        raise HTTPException(status_code=400, detail="没有需要更新的内容")

    success = vocab_service.update_word(word_id, **updates)
    if not success:
        raise HTTPException(status_code=404, detail="词条不存在")
    return {"message": "更新成功"}


@router.delete("/vocabulary/{word_id}")
async def delete_vocabulary(word_id: int):
    """删除词库词条"""
    try:
        vocab_service = _get_vocab_service()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"词库服务加载失败: {str(e)}")
    success = vocab_service.delete_word(word_id)
    if not success:
        raise HTTPException(status_code=404, detail="词条不存在")
    return {"message": "删除成功"}


# ==================== 处理日志 ====================

@router.get("/import-tasks")
async def list_import_tasks(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    status: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """导入任务列表"""
    try:
        _, _, ImportTask, _ = _get_models()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"依赖加载失败: {str(e)}")

    query = select(ImportTask)
    count_query = select(func.count(ImportTask.id))

    if status:
        query = query.where(ImportTask.status == status)
        count_query = count_query.where(ImportTask.status == status)

    total = await db.scalar(count_query)
    result = await db.execute(
        query.order_by(ImportTask.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    tasks = result.scalars().all()

    return {
        "items": [t.to_dict() for t in tasks],
        "total": total or 0,
        "page": page,
        "page_size": page_size,
    }


@router.get("/import-tasks/{task_id}")
async def get_import_task_detail(task_id: str, db: AsyncSession = Depends(get_db)):
    """导入任务详情"""
    try:
        _, _, ImportTask, ImportItem = _get_models()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"依赖加载失败: {str(e)}")

    result = await db.execute(
        select(ImportTask).where(ImportTask.id == task_id)
    )
    task = result.scalars().first()
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")

    items_result = await db.execute(
        select(ImportItem).where(ImportItem.task_id == task_id)
        .order_by(ImportItem.match_type, ImportItem.word_text)
    )
    items = items_result.scalars().all()

    matched_items = [i.to_dict() for i in items if i.match_type == "exact_match"]
    generated_items = [i.to_dict() for i in items if i.match_type in ("ai_generated", "dict_generated")]
    failed_items = [i.to_dict() for i in items if i.match_type == "ai_failed"]

    task_dict = task.to_dict()
    task_dict["matched_items"] = matched_items
    task_dict["generated_items"] = generated_items
    task_dict["failed_items"] = failed_items
    return task_dict


@router.post("/import-items/{item_id}/approve")
async def approve_import_item(
    item_id: str,
    data: dict = Body(default={}),
    db: AsyncSession = Depends(get_db)
):
    """审核通过并入库"""
    try:
        Word, _, ImportTask, ImportItem = _get_models()
        vocab_service = _get_vocab_service()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"依赖加载失败: {str(e)}")

    result = await db.execute(
        select(ImportItem).where(ImportItem.id == item_id)
    )
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="导入项不存在")

    if item.status not in ("waiting_review", "pending"):
        raise HTTPException(status_code=400, detail=f"当前状态不允许审核: {item.status}")

    generated_data = data.get("generated_data") or item.generated_data or {}
    word_text = item.word_text.strip().lower()
    meaning = generated_data.get("meaning", item.vocabulary_meaning or "")

    # 1. 写入 vocabulary.db
    vocab_service.add_word(
        word=word_text,
        meaning=meaning,
        phonetic=generated_data.get("phonetic", ""),
        difficulty=generated_data.get("difficulty", ""),
        examples=str(generated_data.get("examples", "")),
        added_from="ai_approved"
    )

    # 2. 创建/更新 PostgreSQL Word 记录
    word_result = await db.execute(select(Word).where(func.lower(Word.word) == word_text))
    existing_word = word_result.scalars().first()

    if existing_word:
        word_id = existing_word.id
    else:
        word_id = uuid.uuid4()
        new_word = Word(
            id=word_id,
            word=word_text,
            definitions=generated_data.get("definitions", [{"pos": "", "meaning": meaning, "examples": []}]),
            is_reviewed=True,
            review_status="approved",
            ai_generated=True,
        )
        if generated_data.get("phonetic") and hasattr(new_word, 'phonetic_us'):
            new_word.phonetic_us = generated_data.get("phonetic")
        db.add(new_word)

    # 3. 更新导入项
    has_edit = bool(data.get("generated_data"))
    item.status = "edited_approved" if has_edit else "approved"
    item.word_id = word_id
    item.reviewed_at = datetime.utcnow()
    item.updated_at = datetime.utcnow()
    if has_edit:
        item.generated_data = data["generated_data"]

    # 4. 更新任务 approved_count
    task_result = await db.execute(
        select(ImportTask).where(ImportTask.id == item.task_id)
    )
    task = task_result.scalars().first()
    if task:
        task.approved_count = (task.approved_count or 0) + 1

    await db.commit()
    return {"message": "审核入库成功", "word_id": str(word_id)}


@router.post("/import-items/{item_id}/reject")
async def reject_import_item(item_id: str, db: AsyncSession = Depends(get_db)):
    """拒绝导入项"""
    try:
        _, _, _, ImportItem = _get_models()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"依赖加载失败: {str(e)}")

    result = await db.execute(
        select(ImportItem).where(ImportItem.id == item_id)
    )
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="导入项不存在")

    item.status = "rejected"
    item.reviewed_at = datetime.utcnow()
    item.updated_at = datetime.utcnow()
    await db.commit()
    return {"message": "已拒绝"}


@router.put("/import-items/{item_id}")
async def update_import_item(item_id: str, data: dict = Body(...), db: AsyncSession = Depends(get_db)):
    """编辑导入项的生成数据"""
    try:
        _, _, _, ImportItem = _get_models()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"依赖加载失败: {str(e)}")

    result = await db.execute(
        select(ImportItem).where(ImportItem.id == item_id)
    )
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="导入项不存在")

    item.generated_data = data
    item.updated_at = datetime.utcnow()
    await db.commit()
    return {"message": "更新成功"}