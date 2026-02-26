"""学习 API 路由 - 背单词核心流程"""
from datetime import datetime, date, timezone
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession
from uuid import UUID

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.models.word import Word, WordbookWord
from app.models.learning import UserWordProgress, ReviewLog, DailyStat, UserWordbook
from app.schemas import (
    ReviewRequest, BatchReviewRequest, ReviewResultResponse,
    TodayTaskResponse, StudyCardResponse, WordResponse,
)
from app.services.fsrs import FSRS, Card, Rating, State, card_from_db, card_to_db

router = APIRouter(prefix="/study", tags=["学习"])
fsrs = FSRS()


@router.get("/today", response_model=TodayTaskResponse)
async def get_today_task(
    wordbook_id: UUID = Query(..., description="词书 ID"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取今日学习任务：到期复习词 + 新词"""
    now = datetime.now(timezone.utc)

    # 获取用户在该词书的设置
    uw_result = await db.execute(
        select(UserWordbook).where(
            and_(
                UserWordbook.user_id == current_user.id,
                UserWordbook.wordbook_id == wordbook_id,
            )
        )
    )
    user_wordbook = uw_result.scalar_one_or_none()
    daily_new_limit = user_wordbook.daily_new_words if user_wordbook else 20

    # 1. 获取到期需要复习的单词
    review_result = await db.execute(
        select(UserWordProgress, Word)
        .join(Word, UserWordProgress.word_id == Word.id)
        .where(
            and_(
                UserWordProgress.user_id == current_user.id,
                UserWordProgress.wordbook_id == wordbook_id,
                UserWordProgress.due_date <= now,
                UserWordProgress.fsrs_state != State.New,
            )
        )
        .order_by(UserWordProgress.due_date)
    )
    review_items = review_result.all()

    # 2. 获取新词（还没学过的）
    # 先找出该词书中用户已学过的单词 ID
    learned_ids_result = await db.execute(
        select(UserWordProgress.word_id).where(
            and_(
                UserWordProgress.user_id == current_user.id,
                UserWordProgress.wordbook_id == wordbook_id,
            )
        )
    )
    learned_word_ids = {row[0] for row in learned_ids_result.all()}

    # 从词书中取出未学过的新词
    new_words_query = (
        select(Word)
        .join(WordbookWord, Word.id == WordbookWord.word_id)
        .where(WordbookWord.wordbook_id == wordbook_id)
    )
    if learned_word_ids:
        new_words_query = new_words_query.where(Word.id.notin_(learned_word_ids))
    new_words_query = new_words_query.order_by(WordbookWord.sort_order).limit(daily_new_limit)

    new_result = await db.execute(new_words_query)
    new_words = new_result.scalars().all()

    # 3. 计算连续打卡天数
    streak = await _calculate_streak(db, current_user.id)

    # 组装响应
    review_cards = []
    for progress, word in review_items:
        review_cards.append(StudyCardResponse(
            word=WordResponse.model_validate(word),
            progress={
                "fsrs_state": progress.fsrs_state,
                "due_date": progress.due_date.isoformat() if progress.due_date else None,
                "review_count": progress.review_count,
                "stability": progress.fsrs_stability,
                "difficulty": progress.fsrs_difficulty,
            },
            is_new=False,
        ))

    new_cards = [
        StudyCardResponse(word=WordResponse.model_validate(w), is_new=True)
        for w in new_words
    ]

    return TodayTaskResponse(
        new_words=new_cards,
        review_words=review_cards,
        new_count=len(new_cards),
        review_count=len(review_cards),
        streak_days=streak,
    )


@router.post("/review", response_model=ReviewResultResponse)
async def submit_review(
    req: ReviewRequest,
    wordbook_id: UUID = Query(..., description="词书 ID"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """提交一次评分 - 每次评分立即同步到云端"""
    # 查找或创建学习进度
    result = await db.execute(
        select(UserWordProgress).where(
            and_(
                UserWordProgress.user_id == current_user.id,
                UserWordProgress.word_id == req.word_id,
            )
        )
    )
    progress = result.scalar_one_or_none()

    if progress:
        # 已有进度，从数据库恢复 Card
        card = card_from_db({
            "due_date": progress.due_date,
            "fsrs_stability": progress.fsrs_stability,
            "fsrs_difficulty": progress.fsrs_difficulty,
            "fsrs_elapsed_days": progress.fsrs_elapsed_days,
            "fsrs_scheduled_days": progress.fsrs_scheduled_days,
            "fsrs_reps": progress.fsrs_reps,
            "fsrs_lapses": progress.fsrs_lapses,
            "fsrs_state": progress.fsrs_state,
            "last_review": progress.last_review,
        })
    else:
        # 新词，创建进度记录
        card = Card()
        progress = UserWordProgress(
            user_id=current_user.id,
            word_id=req.word_id,
            wordbook_id=wordbook_id,
            first_learned_at=req.reviewed_at,
        )
        db.add(progress)

    # FSRS 计算
    review_result = fsrs.review(card, Rating(req.rating), now=req.reviewed_at)
    new_card = review_result.card

    # 更新进度
    card_data = card_to_db(new_card)
    for key, value in card_data.items():
        setattr(progress, key, value)
    progress.review_count = (progress.review_count or 0) + 1
    progress.last_reviewed_at = req.reviewed_at

    # 写入复习日志
    review_log = ReviewLog(
        user_id=current_user.id,
        word_id=req.word_id,
        rating=req.rating,
        reviewed_at=req.reviewed_at,
        device_id=req.device_id,
        fsrs_stability_after=new_card.stability,
        fsrs_difficulty_after=new_card.difficulty,
        fsrs_state_after=int(new_card.state),
        due_date_after=new_card.due,
    )
    db.add(review_log)

    # 更新当日统计
    await _update_daily_stat(db, current_user.id, card.state == State.New)

    return ReviewResultResponse(
        word_id=req.word_id,
        fsrs_state=int(new_card.state),
        due_date=new_card.due,
        stability=new_card.stability,
        difficulty=new_card.difficulty,
    )


@router.post("/sync", response_model=list[ReviewResultResponse])
async def batch_sync(
    req: BatchReviewRequest,
    wordbook_id: UUID = Query(..., description="词书 ID"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """离线批量同步 - 按时间戳顺序 replay 所有评分"""
    # 按时间排序
    sorted_reviews = sorted(req.reviews, key=lambda r: r.reviewed_at)

    results = []
    for review in sorted_reviews:
        result = await submit_review(review, wordbook_id, db, current_user)
        results.append(result)

    return results


@router.get("/progress")
async def get_wordbook_progress(
    wordbook_id: UUID = Query(..., description="词书 ID"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取词书学习进度概览"""
    # 总词数
    total_result = await db.execute(
        select(func.count()).select_from(WordbookWord).where(
            WordbookWord.wordbook_id == wordbook_id
        )
    )
    total = total_result.scalar() or 0

    # 各状态统计
    stats = {}
    for state in [State.New, State.Learning, State.Review, State.Relearning]:
        if state == State.New:
            # 未学 = 词书总词数 - 有进度记录的词数
            learned_result = await db.execute(
                select(func.count()).select_from(UserWordProgress).where(
                    and_(
                        UserWordProgress.user_id == current_user.id,
                        UserWordProgress.wordbook_id == wordbook_id,
                    )
                )
            )
            learned = learned_result.scalar() or 0
            stats["new"] = total - learned
        else:
            count_result = await db.execute(
                select(func.count()).select_from(UserWordProgress).where(
                    and_(
                        UserWordProgress.user_id == current_user.id,
                        UserWordProgress.wordbook_id == wordbook_id,
                        UserWordProgress.fsrs_state == state,
                    )
                )
            )
            state_name = {1: "learning", 2: "review", 3: "relearning"}[state]
            stats[state_name] = count_result.scalar() or 0

    return {
        "total_words": total,
        "stats": stats,
        "mastered": stats.get("review", 0),
        "progress_percent": round((stats.get("review", 0) / total * 100) if total > 0 else 0, 1),
    }


# ---- 辅助函数 ----

async def _calculate_streak(db: AsyncSession, user_id: UUID) -> int:
    """计算连续打卡天数"""
    result = await db.execute(
        select(DailyStat.study_date)
        .where(DailyStat.user_id == user_id)
        .order_by(DailyStat.study_date.desc())
        .limit(365)
    )
    dates = [row[0] for row in result.all()]
    if not dates:
        return 0

    streak = 0
    today = date.today()
    expected = today
    for d in dates:
        if d == expected:
            streak += 1
            expected = expected - __import__("datetime").timedelta(days=1)
        elif d < expected:
            break
    return streak


async def _update_daily_stat(db: AsyncSession, user_id: UUID, is_new: bool):
    """更新当日学习统计"""
    today = date.today()
    result = await db.execute(
        select(DailyStat).where(
            and_(DailyStat.user_id == user_id, DailyStat.study_date == today)
        )
    )
    stat = result.scalar_one_or_none()
    if not stat:
        stat = DailyStat(user_id=user_id, study_date=today)
        db.add(stat)

    stat.total_reviews = (stat.total_reviews or 0) + 1
    if is_new:
        stat.new_words = (stat.new_words or 0) + 1
    else:
        stat.reviewed_words = (stat.reviewed_words or 0) + 1
