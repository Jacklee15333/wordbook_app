"""
导入处理后台任务服务
文件位置: app/services/import_processor.py

异步处理用户导入的单词列表：
1. vocabulary.db 精确匹配
2. 未匹配的走在线词典 + AI 生成
3. 匹配的自动导入，生成的等待审核
"""
import logging
import uuid
from datetime import datetime
from typing import List

from sqlalchemy import select, update, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.import_task import ImportTask, ImportItem
from app.models.word import Word, Wordbook, WordbookWord
from app.services.vocabulary_service import get_vocabulary_service
from app.services.word_generator_service import WordGeneratorService

logger = logging.getLogger(__name__)


class ImportProcessor:
    """导入处理器"""

    def __init__(self, db_session_factory, ollama_base_url: str = "http://localhost:11434",
                 ollama_model: str = "gpt-oss:20b"):
        self.db_session_factory = db_session_factory
        self.vocab_service = get_vocabulary_service()
        self.word_generator = WordGeneratorService(
            ollama_base_url=ollama_base_url,
            ollama_model=ollama_model
        )

    async def process_import(self, task_id: str, word_list: List[str]):
        """
        处理导入任务的主流程（作为后台任务运行）
        """
        logger.info(f"开始处理导入任务: {task_id}, 单词数: {len(word_list)}")

        async with self.db_session_factory() as session:
            try:
                # 获取任务信息（需要 wordbook_id）
                task_result = await session.execute(
                    select(ImportTask).where(ImportTask.id == task_id)
                )
                task_obj = task_result.scalars().first()
                wordbook_id = str(task_obj.wordbook_id) if task_obj else None

                # 更新任务状态为 processing
                await session.execute(
                    update(ImportTask).where(ImportTask.id == task_id).values(
                        status="processing",
                        total_words=len(word_list),
                        updated_at=datetime.utcnow()
                    )
                )
                await session.commit()

                matched_count = 0
                ai_generated_count = 0
                ai_failed_count = 0

                # 去重
                unique_words = list(dict.fromkeys([w.strip().lower() for w in word_list if w.strip()]))

                for word_text in unique_words:
                    try:
                        result = await self._process_single_word(
                            session, task_id, word_text, wordbook_id
                        )
                        if result == "matched":
                            matched_count += 1
                        elif result == "generated":
                            ai_generated_count += 1
                        else:
                            ai_failed_count += 1
                    except Exception as e:
                        logger.error(f"处理单词异常: {word_text}, error={e}")
                        ai_failed_count += 1
                        item = ImportItem(
                            id=uuid.uuid4(),
                            task_id=task_id,
                            word_text=word_text,
                            match_type="ai_failed",
                            status="pending",
                            generated_data={"error": str(e)}
                        )
                        session.add(item)

                    # 每处理一个词就提交一次，更新进度
                    await session.execute(
                        update(ImportTask).where(ImportTask.id == task_id).values(
                            matched_count=matched_count,
                            ai_generated_count=ai_generated_count,
                            ai_failed_count=ai_failed_count,
                            updated_at=datetime.utcnow()
                        )
                    )
                    await session.commit()

                # 标记任务完成
                await session.execute(
                    update(ImportTask).where(ImportTask.id == task_id).values(
                        status="completed",
                        total_words=len(unique_words),
                        matched_count=matched_count,
                        ai_generated_count=ai_generated_count,
                        ai_failed_count=ai_failed_count,
                        completed_at=datetime.utcnow(),
                        updated_at=datetime.utcnow()
                    )
                )

                # ★★★ 关键修复：更新词书的 word_count ★★★
                if wordbook_id:
                    actual_count = await session.scalar(
                        select(func.count(WordbookWord.id)).where(
                            WordbookWord.wordbook_id == wordbook_id
                        )
                    )
                    await session.execute(
                        update(Wordbook).where(Wordbook.id == wordbook_id).values(
                            word_count=actual_count or 0,
                            updated_at=datetime.utcnow()
                        )
                    )
                    logger.info(f"★ 词书 {wordbook_id} word_count 已更新为 {actual_count}")

                await session.commit()

                logger.info(
                    f"导入任务完成: {task_id}, "
                    f"匹配={matched_count}, AI生成={ai_generated_count}, 失败={ai_failed_count}"
                )

            except Exception as e:
                logger.error(f"导入任务异常: {task_id}, error={e}")
                try:
                    await session.rollback()
                    await session.execute(
                        update(ImportTask).where(ImportTask.id == task_id).values(
                            status="failed",
                            error_message=str(e),
                            updated_at=datetime.utcnow()
                        )
                    )
                    await session.commit()
                except Exception:
                    pass

    async def _process_single_word(self, session: AsyncSession, task_id: str,
                                    word_text: str, wordbook_id: str = None) -> str:
        """
        处理单个单词
        返回: "matched" | "generated" | "failed"
        """
        word_lower = word_text.strip().lower()

        # ===== 第一步：在 vocabulary.db 精确匹配 =====
        vocab_result = self.vocab_service.exact_match(word_lower)

        if vocab_result:
            logger.info(f"词库匹配: {word_text} -> {vocab_result.get('meaning', '')[:50]}")

            # 查找或创建 PostgreSQL Word 记录
            word_id = await self._find_or_create_word(
                session, word_lower, vocab_result.get("meaning", "")
            )

            # 把单词加入词书
            if wordbook_id and word_id:
                await self._add_to_wordbook(session, wordbook_id, word_id)

            # 创建导入明细
            item = ImportItem(
                id=uuid.uuid4(),
                task_id=task_id,
                word_text=word_text,
                match_type="exact_match",
                vocabulary_meaning=vocab_result.get("meaning", ""),
                word_id=word_id,
                status="auto_imported",
            )
            session.add(item)
            return "matched"

        # ===== 第二步：先查 PostgreSQL 词典 =====
        pg_result = await session.execute(
            select(Word).where(func.lower(Word.word) == word_lower)
        )
        pg_word = pg_result.scalars().first()

        if pg_word:
            logger.info(f"PostgreSQL词典匹配: {word_text}")

            if wordbook_id:
                await self._add_to_wordbook(session, wordbook_id, pg_word.id)

            item = ImportItem(
                id=uuid.uuid4(),
                task_id=task_id,
                word_text=word_text,
                match_type="exact_match",
                vocabulary_meaning="已存在于词典",
                word_id=pg_word.id,
                status="auto_imported",
            )
            session.add(item)
            return "matched"

        # ===== 第三步：在线词典 + AI 生成 =====
        logger.info(f"词库未匹配，开始生成: {word_text}")
        generated = await self.word_generator.generate_word_data(word_lower)

        if generated:
            source = generated.get("source", "unknown")
            match_type = "dict_generated" if source == "online_dictionary" else "ai_generated"

            item = ImportItem(
                id=uuid.uuid4(),
                task_id=task_id,
                word_text=word_text,
                match_type=match_type,
                vocabulary_meaning=generated.get("meaning", ""),
                generated_data=generated,
                status="waiting_review",
            )
            session.add(item)
            return "generated"
        else:
            item = ImportItem(
                id=uuid.uuid4(),
                task_id=task_id,
                word_text=word_text,
                match_type="ai_failed",
                status="pending",
                generated_data={"error": "所有生成策略均失败"}
            )
            session.add(item)
            return "failed"

    async def _find_or_create_word(self, session: AsyncSession,
                                    word_text: str, meaning: str) -> uuid.UUID:
        """在 PostgreSQL 中查找或创建 Word 记录"""
        result = await session.execute(
            select(Word).where(func.lower(Word.word) == word_text.lower())
        )
        existing = result.scalars().first()

        if existing:
            return existing.id

        # 创建新的 Word 记录（对齐你的 Word 模型字段）
        new_word = Word(
            id=uuid.uuid4(),
            word=word_text,
            definitions=[{"pos": "", "meaning": meaning, "examples": []}],
            is_reviewed=True,
            review_status="approved",
            ai_generated=False,
        )
        session.add(new_word)
        await session.flush()
        return new_word.id

    async def _add_to_wordbook(self, session: AsyncSession,
                                wordbook_id: str, word_id) -> None:
        """把单词加入词书（如果还没在里面的话）"""
        try:
            existing = await session.execute(
                select(WordbookWord).where(
                    and_(
                        WordbookWord.wordbook_id == wordbook_id,
                        WordbookWord.word_id == word_id,
                    )
                )
            )
            if not existing.scalars().first():
                # 获取当前最大排序号
                max_order = await session.scalar(
                    select(func.max(WordbookWord.sort_order)).where(
                        WordbookWord.wordbook_id == wordbook_id
                    )
                )
                session.add(WordbookWord(
                    wordbook_id=wordbook_id,
                    word_id=word_id,
                    sort_order=(max_order or 0) + 1,
                ))
        except Exception as e:
            logger.warning(f"添加单词到词书失败: {word_id} -> {wordbook_id}, error={e}")
