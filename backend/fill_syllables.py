"""
★ v5.0 音节拆分批量填充脚本
──────────────────────────────────────
用法: cd backend && python fill_syllables.py

依赖: pip install pyphen asyncpg sqlalchemy[asyncio]
作用: 为 words 表中所有单个英文单词填充 syllables 字段
      短语/词缀/句型 不会被处理
"""
import re
import asyncio
import pyphen
from sqlalchemy import select, update, text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

# ── 请根据你的实际配置修改 ──
DATABASE_URL = "postgresql+asyncpg://postgres:postgres@localhost:5432/wordbook"


dic = pyphen.Pyphen(lang='en_US')


def get_syllables(word_text: str) -> list[str] | None:
    """只处理纯英文单词，跳过短语/词缀/特殊字符"""
    if ' ' in word_text or word_text.startswith('-') or word_text.endswith('-'):
        return None
    if not re.match(r'^[a-zA-Z]+$', word_text):
        return None
    parts = dic.inserted(word_text.lower()).split('-')
    return parts if len(parts) > 1 else None


async def main():
    engine = create_async_engine(DATABASE_URL)
    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    # 确保 syllables 列存在
    async with engine.begin() as conn:
        result = await conn.execute(text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name='words' AND column_name='syllables'"
        ))
        if result.first() is None:
            await conn.execute(text("ALTER TABLE words ADD COLUMN syllables JSONB"))
            print("✅ 已添加 syllables 列")

    async with session_factory() as session:
        result = await session.execute(text(
            "SELECT id, word FROM words WHERE syllables IS NULL"
        ))
        words = result.all()
        print(f"📊 共 {len(words)} 个单词需要处理")

        count = 0
        skipped = 0
        for word_id, word_text in words:
            syllables = get_syllables(word_text)
            if syllables:
                await session.execute(text(
                    "UPDATE words SET syllables = :syl WHERE id = :wid"
                ), {"syl": str(syllables).replace("'", '"'), "wid": word_id})
                count += 1
                if count <= 10:
                    print(f"  ✅ {word_text} → {syllables}")
            else:
                skipped += 1

        await session.commit()
        print(f"\n🎉 完成！已填充 {count} 个单词，跳过 {skipped} 个（短语/词缀/单音节）")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
