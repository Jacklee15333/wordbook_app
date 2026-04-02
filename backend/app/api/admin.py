"""
管理后台 API 路由
文件位置: app/api/admin.py

★★★ 关键：vocabulary_service 等重依赖在函数体内懒加载 ★★★

v4.8: 修复音标问题
  - approve_import_item 正确设置 phonetic_us / phonetic_uk
"""
import uuid
import logging
import traceback
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Body
from sqlalchemy import select, func, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.user import User
from app.models.word import Word

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
    """审核通过并入库 ★ v4.8: 正确设置 phonetic_us / phonetic_uk"""
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

    # ★ v4.8: 提取音标（支持 phonetic_us/phonetic_uk 和旧的 phonetic 字段）
    phonetic_us = generated_data.get("phonetic_us", "")
    phonetic_uk = generated_data.get("phonetic_uk", "")
    phonetic_generic = generated_data.get("phonetic", "")
    if not phonetic_us:
        phonetic_us = phonetic_generic
    if not phonetic_uk:
        phonetic_uk = phonetic_generic

    # 1. 写入 vocabulary.db
    vocab_service.add_word(
        word=word_text,
        meaning=meaning,
        phonetic=phonetic_us or phonetic_uk or phonetic_generic,
        difficulty=generated_data.get("difficulty", ""),
        examples=str(generated_data.get("examples", "")),
        added_from="ai_approved"
    )

    # 2. 创建/更新 PostgreSQL Word 记录
    word_result = await db.execute(select(Word).where(func.lower(Word.word) == word_text))
    existing_word = word_result.scalars().first()

    if existing_word:
        word_id = existing_word.id
        # ★ v4.8: 如果已有记录没有音标，补上
        if not existing_word.phonetic_us and phonetic_us:
            existing_word.phonetic_us = phonetic_us
        if not existing_word.phonetic_uk and phonetic_uk:
            existing_word.phonetic_uk = phonetic_uk
    else:
        word_id = uuid.uuid4()
        new_word = Word(
            id=word_id,
            word=word_text,
            phonetic_us=phonetic_us,     # ★ v4.8
            phonetic_uk=phonetic_uk,     # ★ v4.8
            definitions=generated_data.get("definitions", [{"pos": "", "cn": meaning}]),
            is_reviewed=True,
            review_status="approved",
            ai_generated=True,
        )
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


# ==================== ★ v5.5: 音节/词素 数据管理 ====================

@router.get("/word-data")
async def list_word_data(
    search: str = Query("", description="搜索单词"),
    page: int = Query(1, ge=1),
    page_size: int = Query(30, ge=1, le=100),
    filter: str = Query("all", description="all|has_syllables|no_syllables|has_morphemes|no_morphemes"),
    db: AsyncSession = Depends(get_db)
):
    """搜索/列表：单词的音节和词素数据"""
    query = select(
        Word.id, Word.word, Word.phonetic_us,
        Word.syllables, Word.syllable_ipa, Word.morphemes
    )
    count_query = select(func.count(Word.id))

    if search.strip():
        query = query.where(Word.word.ilike(f"%{search.strip()}%"))
        count_query = count_query.where(Word.word.ilike(f"%{search.strip()}%"))

    if filter == "has_syllables":
        query = query.where(Word.syllables.isnot(None))
        count_query = count_query.where(Word.syllables.isnot(None))
    elif filter == "no_syllables":
        query = query.where(Word.syllables.is_(None))
        count_query = count_query.where(Word.syllables.is_(None))
    elif filter == "has_morphemes":
        query = query.where(Word.morphemes.isnot(None))
        count_query = count_query.where(Word.morphemes.isnot(None))
    elif filter == "no_morphemes":
        query = query.where(Word.morphemes.is_(None))
        count_query = count_query.where(Word.morphemes.is_(None))

    total = (await db.execute(count_query)).scalar() or 0
    query = query.order_by(Word.word).offset((page - 1) * page_size).limit(page_size)
    rows = (await db.execute(query)).all()

    items = []
    for row in rows:
        items.append({
            "id": str(row.id),
            "word": row.word,
            "phonetic_us": row.phonetic_us,
            "syllables": row.syllables,
            "syllable_ipa": row.syllable_ipa,
            "morphemes": row.morphemes,
        })

    return {
        "items": items,
        "total": total,
        "page": page,
        "page_size": page_size,
        "total_pages": (total + page_size - 1) // page_size,
    }


@router.get("/word-data/{word_id}")
async def get_word_data(word_id: str, db: AsyncSession = Depends(get_db)):
    """获取单个单词的完整数据"""
    result = await db.execute(
        select(Word).where(Word.id == word_id)
    )
    word = result.scalars().first()
    if not word:
        raise HTTPException(status_code=404, detail="单词不存在")

    definitions = word.definitions or []
    meaning = ""
    for d in definitions[:2]:
        pos = (d.get("pos") or "").strip()
        cn = (d.get("cn") or d.get("meaning") or "").strip()
        if cn:
            meaning += f"{pos} {cn}；" if pos else f"{cn}；"

    return {
        "id": str(word.id),
        "word": word.word,
        "phonetic_us": word.phonetic_us,
        "phonetic_uk": word.phonetic_uk,
        "meaning": meaning.rstrip("；"),
        "syllables": word.syllables,
        "syllable_ipa": word.syllable_ipa,
        "morphemes": word.morphemes,
    }


@router.put("/word-data/{word_id}")
async def update_word_data(
    word_id: str,
    data: dict = Body(...),
    db: AsyncSession = Depends(get_db)
):
    """更新单词的音节/词素数据"""
    result = await db.execute(select(Word).where(Word.id == word_id))
    word = result.scalars().first()
    if not word:
        raise HTTPException(status_code=404, detail="单词不存在")

    updated_fields = []

    if "syllables" in data:
        word.syllables = data["syllables"]  # list[str] or None
        updated_fields.append("syllables")

    if "syllable_ipa" in data:
        word.syllable_ipa = data["syllable_ipa"]  # list[str] or None
        updated_fields.append("syllable_ipa")

    if "morphemes" in data:
        word.morphemes = data["morphemes"]  # list[dict] or None
        updated_fields.append("morphemes")

    if not updated_fields:
        raise HTTPException(status_code=400, detail="没有需要更新的字段")

    word.updated_at = datetime.utcnow()
    await db.commit()
    logger.info(f"[WORD-DATA] ✅ Updated {word.word}: {', '.join(updated_fields)}")
    return {"message": f"已更新: {', '.join(updated_fields)}", "word": word.word}


@router.post("/word-data/{word_id}/regenerate")
async def regenerate_word_data(
    word_id: str,
    db: AsyncSession = Depends(get_db)
):
    """重新用引擎生成单词的音节/词素数据"""
    result = await db.execute(select(Word).where(Word.id == word_id))
    word = result.scalars().first()
    if not word:
        raise HTTPException(status_code=404, detail="单词不存在")

    word_text = word.word.strip()
    changes = []

    # 重新生成音节
    try:
        import pyphen
        dic = pyphen.Pyphen(lang='en_US')
        if ' ' not in word_text and word_text.isalpha():
            parts = dic.inserted(word_text.lower()).split('-')
            if len(parts) > 1:
                word.syllables = parts
                changes.append(f"syllables={parts}")
    except Exception as e:
        logger.warning(f"[WORD-DATA] syllable regen failed: {e}")

    # 重新生成音节音标
    try:
        from app.main import _get_syllable_ipa
        if word.syllables and word.phonetic_us:
            ipa_list = _get_syllable_ipa(word.syllables, word.phonetic_us)
            if ipa_list:
                word.syllable_ipa = ipa_list
                changes.append(f"syllable_ipa={ipa_list}")
    except Exception as e:
        logger.warning(f"[WORD-DATA] syllable_ipa regen failed: {e}")

    # 重新生成词素
    try:
        from app.morpheme_dict import get_morphemes, MANUAL_MORPHEMES
        w = word_text.lower()
        if w in MANUAL_MORPHEMES:
            word.morphemes = MANUAL_MORPHEMES[w]
            changes.append("morphemes=MANUAL")
        else:
            morphemes = get_morphemes(word_text)
            if morphemes:
                word.morphemes = morphemes
                changes.append(f"morphemes(auto)={len(morphemes)} parts")
    except Exception as e:
        logger.warning(f"[WORD-DATA] morpheme regen failed: {e}")

    if changes:
        word.updated_at = datetime.utcnow()
        await db.commit()
        logger.info(f"[WORD-DATA] ✅ Regenerated {word.word}: {', '.join(changes)}")
        return {"message": f"已重新生成: {', '.join(changes)}", "word": word.word}
    else:
        return {"message": "无法自动生成数据，请手动编辑", "word": word.word}


@router.get("/word-data-stats")
async def word_data_stats(db: AsyncSession = Depends(get_db)):
    """音节/词素数据统计"""
    total = (await db.execute(select(func.count(Word.id)))).scalar() or 0
    has_syl = (await db.execute(
        select(func.count(Word.id)).where(Word.syllables.isnot(None))
    )).scalar() or 0
    has_morph = (await db.execute(
        select(func.count(Word.id)).where(Word.morphemes.isnot(None))
    )).scalar() or 0
    has_syl_ipa = (await db.execute(
        select(func.count(Word.id)).where(Word.syllable_ipa.isnot(None))
    )).scalar() or 0

    return {
        "total_words": total,
        "has_syllables": has_syl,
        "no_syllables": total - has_syl,
        "has_morphemes": has_morph,
        "no_morphemes": total - has_morph,
        "has_syllable_ipa": has_syl_ipa,
    }
