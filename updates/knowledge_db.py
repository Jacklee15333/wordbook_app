"""
★ v5.6: 可移植的单词知识库 (SQLite)
文件位置: backend/app/knowledge_db.py

独立的 SQLite 数据库，存储人工校验过的音节拆分和构词拆分数据。
特点：
  - 单个 .db 文件，可复制到其他机器/软件使用
  - 以单词文本为主键（不依赖 UUID），通用性强
  - 随着用户编辑数据越来越丰富
  - 新导入的单词自动从知识库获取已有数据
"""

import json
import sqlite3
import logging
import os
from datetime import datetime
from pathlib import Path

logger = logging.getLogger(__name__)

# 知识库文件路径：放在 backend/data/ 目录下
_DB_DIR = Path(__file__).parent.parent / "data"
_DB_PATH = _DB_DIR / "word_knowledge.db"


def get_db_path() -> Path:
    """返回知识库文件路径"""
    return _DB_PATH


def _get_conn() -> sqlite3.Connection:
    """获取 SQLite 连接（自动建表）"""
    _DB_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(_DB_PATH))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")  # 并发读性能更好
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS word_knowledge (
            word          TEXT PRIMARY KEY,
            syllables     TEXT,
            syllable_ipa  TEXT,
            morphemes     TEXT,
            source        TEXT DEFAULT 'manual',
            updated_at    TEXT
        )
    """)
    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_word_knowledge_updated
        ON word_knowledge(updated_at)
    """)
    conn.commit()
    return conn


# ═══════════════════════════════════════════════════════════
# 写入
# ═══════════════════════════════════════════════════════════

def save(word: str, syllables=None, syllable_ipa=None, morphemes=None, source="manual"):
    """保存/更新一个单词的知识数据"""
    word = word.strip().lower()
    if not word:
        return

    conn = _get_conn()
    try:
        now = datetime.utcnow().isoformat()
        conn.execute("""
            INSERT INTO word_knowledge (word, syllables, syllable_ipa, morphemes, source, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(word) DO UPDATE SET
                syllables    = COALESCE(excluded.syllables, word_knowledge.syllables),
                syllable_ipa = COALESCE(excluded.syllable_ipa, word_knowledge.syllable_ipa),
                morphemes    = COALESCE(excluded.morphemes, word_knowledge.morphemes),
                source       = excluded.source,
                updated_at   = excluded.updated_at
        """, (
            word,
            json.dumps(syllables, ensure_ascii=False) if syllables else None,
            json.dumps(syllable_ipa, ensure_ascii=False) if syllable_ipa else None,
            json.dumps(morphemes, ensure_ascii=False) if morphemes else None,
            source,
            now,
        ))
        conn.commit()
        logger.debug(f"[KNOWLEDGE] Saved: {word}")
    except Exception as e:
        logger.error(f"[KNOWLEDGE] Save error for '{word}': {e}")
    finally:
        conn.close()


def save_batch(items: list[dict]):
    """批量保存 [{word, syllables?, syllable_ipa?, morphemes?, source?}, ...]"""
    if not items:
        return 0

    conn = _get_conn()
    count = 0
    try:
        now = datetime.utcnow().isoformat()
        for item in items:
            word = item.get("word", "").strip().lower()
            if not word:
                continue
            conn.execute("""
                INSERT INTO word_knowledge (word, syllables, syllable_ipa, morphemes, source, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(word) DO UPDATE SET
                    syllables    = COALESCE(excluded.syllables, word_knowledge.syllables),
                    syllable_ipa = COALESCE(excluded.syllable_ipa, word_knowledge.syllable_ipa),
                    morphemes    = COALESCE(excluded.morphemes, word_knowledge.morphemes),
                    source       = excluded.source,
                    updated_at   = excluded.updated_at
            """, (
                word,
                json.dumps(item.get("syllables"), ensure_ascii=False) if item.get("syllables") else None,
                json.dumps(item.get("syllable_ipa"), ensure_ascii=False) if item.get("syllable_ipa") else None,
                json.dumps(item.get("morphemes"), ensure_ascii=False) if item.get("morphemes") else None,
                item.get("source", "manual"),
                now,
            ))
            count += 1
        conn.commit()
        logger.info(f"[KNOWLEDGE] Batch saved {count} words")
    except Exception as e:
        logger.error(f"[KNOWLEDGE] Batch save error: {e}")
    finally:
        conn.close()
    return count


# ═══════════════════════════════════════════════════════════
# 读取
# ═══════════════════════════════════════════════════════════

def get(word: str) -> dict | None:
    """获取单个单词的知识数据"""
    word = word.strip().lower()
    conn = _get_conn()
    try:
        row = conn.execute(
            "SELECT * FROM word_knowledge WHERE word = ?", (word,)
        ).fetchone()
        if not row:
            return None
        return _row_to_dict(row)
    finally:
        conn.close()


def get_batch(words: list[str]) -> dict[str, dict]:
    """批量查询，返回 {word: data, ...}"""
    if not words:
        return {}

    conn = _get_conn()
    try:
        placeholders = ",".join("?" * len(words))
        rows = conn.execute(
            f"SELECT * FROM word_knowledge WHERE word IN ({placeholders})",
            [w.strip().lower() for w in words]
        ).fetchall()
        return {row["word"]: _row_to_dict(row) for row in rows}
    finally:
        conn.close()


def _row_to_dict(row) -> dict:
    """将数据库行转为字典"""
    return {
        "word": row["word"],
        "syllables": json.loads(row["syllables"]) if row["syllables"] else None,
        "syllable_ipa": json.loads(row["syllable_ipa"]) if row["syllable_ipa"] else None,
        "morphemes": json.loads(row["morphemes"]) if row["morphemes"] else None,
        "source": row["source"],
        "updated_at": row["updated_at"],
    }


# ═══════════════════════════════════════════════════════════
# 统计 / 列表
# ═══════════════════════════════════════════════════════════

def stats() -> dict:
    """知识库统计"""
    conn = _get_conn()
    try:
        total = conn.execute("SELECT COUNT(*) FROM word_knowledge").fetchone()[0]
        has_syl = conn.execute("SELECT COUNT(*) FROM word_knowledge WHERE syllables IS NOT NULL").fetchone()[0]
        has_morph = conn.execute("SELECT COUNT(*) FROM word_knowledge WHERE morphemes IS NOT NULL").fetchone()[0]
        has_ipa = conn.execute("SELECT COUNT(*) FROM word_knowledge WHERE syllable_ipa IS NOT NULL").fetchone()[0]

        # 文件大小
        file_size = os.path.getsize(_DB_PATH) if _DB_PATH.exists() else 0

        return {
            "total": total,
            "has_syllables": has_syl,
            "has_morphemes": has_morph,
            "has_syllable_ipa": has_ipa,
            "file_size_bytes": file_size,
            "file_path": str(_DB_PATH),
        }
    finally:
        conn.close()


def list_all(limit=1000, offset=0) -> list[dict]:
    """列出所有记录"""
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM word_knowledge ORDER BY word LIMIT ? OFFSET ?",
            (limit, offset)
        ).fetchall()
        return [_row_to_dict(r) for r in rows]
    finally:
        conn.close()


def delete(word: str) -> bool:
    """删除一条记录"""
    word = word.strip().lower()
    conn = _get_conn()
    try:
        cursor = conn.execute("DELETE FROM word_knowledge WHERE word = ?", (word,))
        conn.commit()
        return cursor.rowcount > 0
    finally:
        conn.close()


# ═══════════════════════════════════════════════════════════
# 同步：从主数据库导出到知识库
# ═══════════════════════════════════════════════════════════

async def sync_from_main_db():
    """从 PostgreSQL 主库中已有数据同步到知识库（仅同步有数据的）"""
    try:
        from app.core.database import async_session
        from app.models.word import Word
        from sqlalchemy import select, or_

        async with async_session() as session:
            result = await session.execute(
                select(Word.word, Word.syllables, Word.syllable_ipa, Word.morphemes)
                .where(or_(
                    Word.syllables.isnot(None),
                    Word.morphemes.isnot(None),
                ))
            )
            rows = result.all()

        items = []
        for word_text, syllables, syllable_ipa, morphemes in rows:
            if syllables or morphemes:
                items.append({
                    "word": word_text,
                    "syllables": syllables,
                    "syllable_ipa": syllable_ipa,
                    "morphemes": morphemes,
                    "source": "sync",
                })

        count = save_batch(items)
        logger.info(f"[KNOWLEDGE] ✅ Synced {count} words from main DB to knowledge DB")
        return count
    except Exception as e:
        logger.error(f"[KNOWLEDGE] Sync error: {e}")
        return 0


async def apply_to_main_db():
    """将知识库数据应用到主数据库（填充缺失数据）"""
    try:
        from app.core.database import async_session
        from app.models.word import Word
        from sqlalchemy import select, update, or_

        # 获取主库中缺数据的单词
        async with async_session() as session:
            result = await session.execute(
                select(Word.id, Word.word, Word.syllables, Word.morphemes)
                .where(or_(
                    Word.syllables.is_(None),
                    Word.morphemes.is_(None),
                ))
            )
            words = result.all()

        if not words:
            logger.info("[KNOWLEDGE] No words need data from knowledge DB")
            return 0

        # 批量查知识库
        word_texts = [w.word.strip().lower() for w in words]
        knowledge = get_batch(word_texts)

        if not knowledge:
            logger.info("[KNOWLEDGE] No matching data in knowledge DB")
            return 0

        # 应用到主库
        count = 0
        async with async_session() as session:
            for word_id, word_text, cur_syl, cur_morph in words:
                k = knowledge.get(word_text.strip().lower())
                if not k:
                    continue

                updates = {}
                if cur_syl is None and k.get("syllables"):
                    updates["syllables"] = k["syllables"]
                if cur_morph is None and k.get("morphemes"):
                    updates["morphemes"] = k["morphemes"]
                if k.get("syllable_ipa") and cur_syl is None:
                    updates["syllable_ipa"] = k["syllable_ipa"]

                if updates:
                    await session.execute(
                        update(Word).where(Word.id == word_id).values(**updates)
                    )
                    count += 1

            await session.commit()

        logger.info(f"[KNOWLEDGE] ✅ Applied {count} words from knowledge DB to main DB")
        return count
    except Exception as e:
        logger.error(f"[KNOWLEDGE] Apply error: {e}")
        return 0
