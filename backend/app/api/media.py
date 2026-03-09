"""
单词多媒体资源 API
  GET /api/v1/media/{word_id}/audio?accent=us
"""
import logging
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.word import Word
from app.services.media_service import get_audio_bytes

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/media", tags=["多媒体资源"])


@router.get("/{word_id}/audio")
async def get_word_audio(
    word_id: UUID,
    accent: str = Query("us", regex="^(us|uk)$"),
    db: AsyncSession = Depends(get_db),
):
    """获取单词音频（无需登录，后端代理+自动缓存）"""
    result = await db.execute(select(Word.word).where(Word.id == word_id))
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="单词不存在")

    audio_data = await get_audio_bytes(row[0], accent)
    if not audio_data:
        raise HTTPException(status_code=404, detail=f"无法获取音频: {row[0]}")

    return Response(
        content=audio_data,
        media_type="audio/mpeg",
        headers={
            "Cache-Control": "public, max-age=604800",
            "Access-Control-Allow-Origin": "*",
        },
    )
