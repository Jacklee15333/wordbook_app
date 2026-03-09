"""
Media Resource API - v2 robust
"""
import logging
import traceback
from uuid import UUID
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from fastapi.responses import Response, JSONResponse
from sqlalchemy import select, func, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.word import Word, Wordbook, WordbookWord
from app.services.media_service import (
    get_audio_bytes, has_cached_audio, preload_wordbook_audio,
    get_preload_status, get_cache_stats,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/media", tags=["media"])


# ══════════════════════════════════════════════════════════════
# GET /status — no DB needed for basic stats, DB optional for wordbooks
# ══════════════════════════════════════════════════════════════

@router.get("/status")
async def media_status(db: AsyncSession = Depends(get_db)):
    """Cache stats + preload status + per-wordbook coverage."""
    logger.info("[MEDIA-API] /status called")
    try:
        stats = get_cache_stats()
        preload = get_preload_status()
        logger.info(f"[MEDIA-API] stats: us={stats['audio_us_count']}, uk={stats['audio_uk_count']}")

        wordbooks_info = []
        try:
            # Simple query: just get wordbooks
            wb_result = await db.execute(
                select(Wordbook.id, Wordbook.name, Wordbook.word_count)
            )
            wordbooks = wb_result.all()
            logger.info(f"[MEDIA-API] found {len(wordbooks)} wordbooks")

            for wb_id, wb_name, wb_count in wordbooks:
                try:
                    # Get words in this wordbook
                    words_result = await db.execute(
                        select(Word.word)
                        .join(WordbookWord, Word.id == WordbookWord.word_id)
                        .where(WordbookWord.wordbook_id == wb_id)
                    )
                    words = [r[0] for r in words_result.all()]
                    total = len(words)
                    cached = sum(1 for w in words if has_cached_audio(w))
                    wordbooks_info.append({
                        "id": str(wb_id),
                        "name": wb_name or "unnamed",
                        "total": total,
                        "cached": cached,
                    })
                except Exception as e:
                    logger.warning(f"[MEDIA-API] error checking wordbook {wb_name}: {e}")
                    wordbooks_info.append({
                        "id": str(wb_id),
                        "name": wb_name or "unnamed",
                        "total": wb_count or 0,
                        "cached": 0,
                    })
        except Exception as e:
            logger.warning(f"[MEDIA-API] wordbook query failed: {e}")

        result = {
            **stats,
            "preload_status": preload.get("status", "idle"),
            "preload_progress": preload.get("progress", ""),
            "wordbooks": wordbooks_info,
        }
        logger.info(f"[MEDIA-API] /status returning {len(wordbooks_info)} wordbooks")
        return JSONResponse(content=result)

    except Exception as e:
        logger.error(f"[MEDIA-API] /status error: {e}\n{traceback.format_exc()}")
        return JSONResponse(content={
            "audio_us_count": 0,
            "audio_uk_count": 0,
            "total_size_bytes": 0,
            "recent_files": [],
            "preload_status": "error",
            "preload_progress": str(e),
            "wordbooks": [],
        })


# ══════════════════════════════════════════════════════════════
# GET /{word_id}/audio
# ══════════════════════════════════════════════════════════════

@router.get("/{word_id}/audio")
async def get_word_audio(
    word_id: UUID,
    accent: str = Query("us", regex="^(us|uk)$"),
    db: AsyncSession = Depends(get_db),
):
    """Get word audio."""
    logger.debug(f"[MEDIA-API] /audio called: word_id={word_id}, accent={accent}")
    result = await db.execute(select(Word.word).where(Word.id == word_id))
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="word not found")

    audio_data = await get_audio_bytes(row[0], accent)
    if not audio_data:
        raise HTTPException(status_code=404, detail=f"audio unavailable: {row[0]}")

    return Response(
        content=audio_data,
        media_type="audio/mpeg",
        headers={
            "Cache-Control": "public, max-age=604800",
            "Access-Control-Allow-Origin": "*",
        },
    )


# ══════════════════════════════════════════════════════════════
# POST /preload/{wordbook_id}
# ══════════════════════════════════════════════════════════════

@router.post("/preload/{wordbook_id}")
async def preload_wordbook(
    wordbook_id: UUID,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """Start background preload."""
    logger.info(f"[MEDIA-API] /preload called: wordbook_id={wordbook_id}")
    try:
        result = await db.execute(
            select(Word.word)
            .join(WordbookWord, Word.id == WordbookWord.word_id)
            .where(WordbookWord.wordbook_id == wordbook_id)
            .order_by(WordbookWord.sort_order)
        )
        words = [row[0] for row in result.all()]
        logger.info(f"[MEDIA-API] preload: found {len(words)} words")

        if not words:
            return JSONResponse(
                status_code=200,
                content={"message": "wordbook empty", "total_words": 0}
            )

        background_tasks.add_task(preload_wordbook_audio, words, "us")
        return {"message": "preload started", "total_words": len(words)}

    except Exception as e:
        logger.error(f"[MEDIA-API] preload error: {e}\n{traceback.format_exc()}")
        return JSONResponse(
            status_code=200,
            content={"message": f"preload error: {str(e)}", "total_words": 0}
        )
