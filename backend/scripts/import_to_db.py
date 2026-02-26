"""
将批量生成的词典数据导入数据库

用法:
    python -m scripts.import_to_db --input generated_words.json --wordbook "高中英语词汇"
"""
import asyncio
import json
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import select, func
from app.core.database import engine, async_session
from app.models.word import Word, Wordbook, WordbookWord


async def main():
    parser = argparse.ArgumentParser(description="导入词典数据到数据库")
    parser.add_argument("--input", "-i", required=True, help="生成的 JSON 文件路径")
    parser.add_argument("--wordbook", "-w", required=True, help="目标词书名称")
    parser.add_argument("--mark-reviewed", action="store_true", help="标记为已审核")
    args = parser.parse_args()

    # 读取数据
    with open(args.input, "r", encoding="utf-8") as f:
        data = json.load(f)

    valid_words = {k: v for k, v in data.items() if v is not None}
    print(f"📖 共 {len(valid_words)} 个有效单词数据")

    async with async_session() as session:
        # 查找目标词书
        result = await session.execute(
            select(Wordbook).where(Wordbook.name == args.wordbook)
        )
        wordbook = result.scalar_one_or_none()
        if not wordbook:
            print(f"❌ 词书 '{args.wordbook}' 不存在")
            return

        added = 0
        skipped = 0
        linked = 0

        for word_text, word_data in valid_words.items():
            # 检查是否已存在
            existing = await session.execute(
                select(Word).where(func.lower(Word.word) == word_text.lower())
            )
            word = existing.scalar_one_or_none()

            if word:
                skipped += 1
            else:
                # 创建新单词
                word = Word(
                    word=word_data.get("word", word_text),
                    phonetic_us=word_data.get("phonetic_us"),
                    phonetic_uk=word_data.get("phonetic_uk"),
                    definitions=word_data.get("definitions", []),
                    morphology=word_data.get("morphology", {}),
                    word_family=word_data.get("word_family", []),
                    phrases=word_data.get("phrases", []),
                    sentence_patterns=word_data.get("sentence_patterns", []),
                    examples=word_data.get("examples", []),
                    synonyms=word_data.get("synonyms", []),
                    antonyms=word_data.get("antonyms", []),
                    frequency_level=word_data.get("frequency_level", "中频"),
                    difficulty_level=word_data.get("difficulty_level"),
                    is_reviewed=args.mark_reviewed,
                    review_status="approved" if args.mark_reviewed else "pending",
                    ai_generated=True,
                )
                session.add(word)
                await session.flush()
                added += 1

            # 关联到词书（如果未关联）
            link_exists = await session.execute(
                select(WordbookWord).where(
                    WordbookWord.wordbook_id == wordbook.id,
                    WordbookWord.word_id == word.id,
                )
            )
            if not link_exists.scalar_one_or_none():
                session.add(WordbookWord(
                    wordbook_id=wordbook.id,
                    word_id=word.id,
                    sort_order=linked,
                ))
                linked += 1

        # 更新词书词数
        count_result = await session.execute(
            select(func.count()).select_from(WordbookWord).where(
                WordbookWord.wordbook_id == wordbook.id
            )
        )
        wordbook.word_count = count_result.scalar() or 0

        await session.commit()

    print(f"\n{'='*50}")
    print(f"✅ 导入完成!")
    print(f"  新增单词: {added}")
    print(f"  已存在跳过: {skipped}")
    print(f"  关联到词书: {linked}")
    print(f"  词书总词数: {wordbook.word_count}")


if __name__ == "__main__":
    asyncio.run(main())
