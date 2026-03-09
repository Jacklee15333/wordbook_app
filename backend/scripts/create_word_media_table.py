"""
创建 word_media 表 — 单词多媒体资源
──────────────────────────────────────────
运行方式：
  cd backend
  python -m scripts.create_word_media_table
──────────────────────────────────────────
"""
import asyncio
import logging
from sqlalchemy import text
from app.core.database import engine

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS word_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    word_id UUID NOT NULL REFERENCES words(id) ON DELETE CASCADE,
    media_type VARCHAR(50) NOT NULL,
    source VARCHAR(50) NOT NULL DEFAULT 'youdao',
    file_path TEXT NOT NULL,
    file_size INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引：按 word_id + media_type 快速查找
CREATE INDEX IF NOT EXISTS idx_word_media_word_id ON word_media(word_id);
CREATE INDEX IF NOT EXISTS idx_word_media_type ON word_media(media_type);
CREATE UNIQUE INDEX IF NOT EXISTS idx_word_media_unique ON word_media(word_id, media_type);
"""


async def main():
    logger.info("=" * 50)
    logger.info("创建 word_media 表...")
    logger.info("=" * 50)

    async with engine.begin() as conn:
        await conn.execute(text(CREATE_TABLE_SQL))

    logger.info("✅ word_media 表创建成功！")
    logger.info("")
    logger.info("本地资源目录结构：")
    logger.info("  media_storage/")
    logger.info("    audio/")
    logger.info("      us/         ← 美音 MP3")
    logger.info("      uk/         ← 英音 MP3")
    logger.info("      effect/     ← 特效音频（预留）")
    logger.info("    images/       ← 图片（预留）")
    logger.info("    videos/       ← 视频（预留）")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
