"""词典 & 词书管理 API（含新版导入 V2）"""
import uuid as uuid_mod
import logging
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File, BackgroundTasks, Body
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession
from uuid import UUID

from app.core.database import get_db
from app.core.security import get_current_user, get_admin_user
from app.models.user import User
from app.models.word import Word, Wordbook, WordbookWord
from app.models.learning import UserWordbook
from app.schemas import (
    WordResponse, WordCreateRequest,
    WordbookResponse, WordbookCreateRequest,
)
from app.services.ai_generator import generate_word_data

logger = logging.getLogger(__name__)

router = APIRouter(tags=["词典与词书"])


# ============================================================
# 词典 API
# ============================================================

@router.get("/words/search", response_model=list[WordResponse])
async def search_words(
    q: str = Query(..., min_length=1, description="搜索关键词"),
    limit: int = Query(20, le=50),
    db: AsyncSession = Depends(get_db),
):
    """搜索单词"""
    result = await db.execute(
        select(Word)
        .where(Word.word.ilike(f"{q}%"))
        .order_by(Word.word)
        .limit(limit)
    )
    return result.scalars().all()


@router.get("/words/{word_id}", response_model=WordResponse)
async def get_word(word_id: UUID, db: AsyncSession = Depends(get_db)):
    """获取单词详情"""
    result = await db.execute(select(Word).where(Word.id == word_id))
    word = result.scalar_one_or_none()
    if not word:
        raise HTTPException(status_code=404, detail="单词不存在")
    return word


@router.post("/words", response_model=WordResponse)
async def create_word(
    req: WordCreateRequest,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_admin_user),
):
    """管理员手动添加单词"""
    existing = await db.execute(
        select(Word).where(func.lower(Word.word) == req.word.lower())
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="该单词已存在")

    word = Word(
        word=req.word,
        phonetic_us=req.phonetic_us,
        phonetic_uk=req.phonetic_uk,
        definitions=[d.model_dump() for d in req.definitions],
        morphology=req.morphology.model_dump() if req.morphology else {},
        word_family=req.word_family or [],
        phrases=[p.model_dump() for p in (req.phrases or [])],
        sentence_patterns=[s.model_dump() for s in (req.sentence_patterns or [])],
        examples=[e.model_dump() for e in (req.examples or [])],
        synonyms=req.synonyms or [],
        antonyms=req.antonyms or [],
        frequency_level=req.frequency_level,
        difficulty_level=req.difficulty_level,
        is_reviewed=True,
        review_status="approved",
    )
    db.add(word)
    await db.flush()
    return word


@router.post("/words/ai-generate")
async def ai_generate_word(
    word_text: str = Query(..., description="要生成的单词"),
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_admin_user),
):
    """AI 生成单词词典数据（管理员触发）"""
    existing = await db.execute(
        select(Word).where(func.lower(Word.word) == word_text.lower())
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="该单词已存在于词典中")

    data = await generate_word_data(word_text)
    if not data:
        raise HTTPException(status_code=500, detail="AI 生成失败，请稍后重试")

    word = Word(
        word=data.get("word", word_text),
        phonetic_us=data.get("phonetic_us"),
        phonetic_uk=data.get("phonetic_uk"),
        definitions=data.get("definitions", []),
        morphology=data.get("morphology", {}),
        word_family=data.get("word_family", []),
        phrases=data.get("phrases", []),
        sentence_patterns=data.get("sentence_patterns", []),
        examples=data.get("examples", []),
        synonyms=data.get("synonyms", []),
        antonyms=data.get("antonyms", []),
        frequency_level=data.get("frequency_level", "中频"),
        difficulty_level=data.get("difficulty_level"),
        is_reviewed=False,
        review_status="pending",
        ai_generated=True,
    )
    db.add(word)
    await db.flush()

    return {"message": "AI 生成成功，待审核", "word_id": str(word.id), "data": data}


@router.put("/words/{word_id}/approve")
async def approve_word(
    word_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_admin_user),
):
    """审核通过单词"""
    result = await db.execute(select(Word).where(Word.id == word_id))
    word = result.scalar_one_or_none()
    if not word:
        raise HTTPException(status_code=404, detail="单词不存在")

    word.is_reviewed = True
    word.review_status = "approved"
    return {"message": "审核通过"}


# ============================================================
# 词书 API
# ============================================================

@router.get("/wordbooks", response_model=list[WordbookResponse])
async def list_wordbooks(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取词书列表（内置 + 用户自定义）"""
    result = await db.execute(
        select(Wordbook)
        .where(
            (Wordbook.is_public == True) |
            (Wordbook.created_by == current_user.id)
        )
        .order_by(Wordbook.sort_order)
    )
    wordbooks = result.scalars().all()

    # ★★★ 关键修复：每次获取词书列表时，从 wordbook_words 表重新统计真实数量 ★★★
    for wb in wordbooks:
        actual_count = await db.scalar(
            select(func.count()).select_from(WordbookWord).where(
                WordbookWord.wordbook_id == wb.id
            )
        )
        if wb.word_count != (actual_count or 0):
            wb.word_count = actual_count or 0

    return wordbooks


@router.get("/wordbooks/{wordbook_id}/words", response_model=list[WordResponse])
async def get_wordbook_words(
    wordbook_id: UUID,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db),
):
    """获取词书中的单词列表"""
    offset = (page - 1) * page_size
    result = await db.execute(
        select(Word)
        .join(WordbookWord, Word.id == WordbookWord.word_id)
        .where(WordbookWord.wordbook_id == wordbook_id)
        .order_by(WordbookWord.sort_order)
        .offset(offset)
        .limit(page_size)
    )
    return result.scalars().all()


@router.post("/wordbooks", response_model=WordbookResponse)
async def create_wordbook(
    req: WordbookCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """用户创建自定义词书"""
    wordbook = Wordbook(
        name=req.name,
        description=req.description,
        difficulty=req.difficulty,
        is_builtin=False,
        created_by=current_user.id,
        is_public=False,
    )
    db.add(wordbook)
    await db.flush()
    return wordbook


@router.post("/wordbooks/{wordbook_id}/import")
async def import_words_to_wordbook(
    wordbook_id: UUID,
    file: UploadFile = File(..., description="txt 或 csv 文件，每行一个单词"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """导入单词到词书（txt/csv 格式）- 旧版"""
    wb_result = await db.execute(select(Wordbook).where(Wordbook.id == wordbook_id))
    wordbook = wb_result.scalar_one_or_none()
    if not wordbook:
        raise HTTPException(status_code=404, detail="词书不存在")
    if not wordbook.is_builtin and wordbook.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="无权操作此词书")

    content = await file.read()
    text = content.decode("utf-8").strip()
    word_list = [line.strip().lower() for line in text.splitlines() if line.strip()]
    word_list = list(dict.fromkeys(word_list))

    found = 0
    not_found = []
    added = 0

    for word_text in word_list:
        result = await db.execute(
            select(Word).where(func.lower(Word.word) == word_text)
        )
        word = result.scalar_one_or_none()

        if not word:
            not_found.append(word_text)
            continue

        found += 1

        existing = await db.execute(
            select(WordbookWord).where(
                and_(
                    WordbookWord.wordbook_id == wordbook_id,
                    WordbookWord.word_id == word.id,
                )
            )
        )
        if not existing.scalar_one_or_none():
            db.add(WordbookWord(
                wordbook_id=wordbook_id,
                word_id=word.id,
                sort_order=added,
            ))
            added += 1

    count_result = await db.execute(
        select(func.count()).select_from(WordbookWord).where(
            WordbookWord.wordbook_id == wordbook_id
        )
    )
    wordbook.word_count = count_result.scalar() or 0

    return {
        "message": f"导入完成：{found} 个单词已匹配，{added} 个新增到词书",
        "total_in_file": len(word_list),
        "found": found,
        "added": added,
        "not_found": not_found,
        "not_found_count": len(not_found),
    }


# ============================================================
# ★★★ 新版导入 V2 — 异步处理 + 词库匹配 + AI生成 ★★★
# ============================================================

@router.post("/wordbooks/{wordbook_id}/import-v2")
async def import_words_v2(
    wordbook_id: UUID,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    data: dict = Body(...),
):
    """
    新版导入接口（异步处理）
    Body: {"words": ["apple", "banana", ...]}
    """
    logger.info(f"=== import-v2 called === wordbook_id={wordbook_id}, user={current_user.id}")

    # 懒加载重依赖，避免模块级导入失败
    try:
        from app.core.database import async_session_factory
        from app.core.config import get_settings
        from app.models.import_task import ImportTask
        from app.services.import_processor import ImportProcessor
    except Exception as e:
        logger.error(f"import-v2 lazy import failed: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"服务依赖加载失败: {str(e)}")

    settings = get_settings()

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

    logger.info(f"Creating import task: {len(word_list)} words")

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


@router.get("/import-tasks/{task_id}/progress")
async def get_task_progress(
    task_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取导入任务进度"""
    from app.models.import_task import ImportTask

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


@router.get("/import-tasks/{task_id}/results")
async def get_task_results(
    task_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取导入任务的最终结果"""
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


@router.post("/wordbooks/{wordbook_id}/select")
async def select_wordbook(
    wordbook_id: UUID,
    daily_new_words: int = Query(20, ge=5, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """用户选择学习某本词书"""
    result = await db.execute(
        select(UserWordbook).where(
            and_(
                UserWordbook.user_id == current_user.id,
                UserWordbook.wordbook_id == wordbook_id,
            )
        )
    )
    uw = result.scalar_one_or_none()
    if uw:
        uw.is_active = True
        uw.daily_new_words = daily_new_words
    else:
        uw = UserWordbook(
            user_id=current_user.id,
            wordbook_id=wordbook_id,
            daily_new_words=daily_new_words,
        )
        db.add(uw)

    return {"message": "已选择词书", "daily_new_words": daily_new_words}
