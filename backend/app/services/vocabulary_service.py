"""
Vocabulary SQLite 词库服务
文件位置: app/services/vocabulary_service.py

管理 vocabulary.db（SQLite），提供快速匹配查询和入库功能。
vocabulary.db 和 main.py 同级，在 app/ 目录下。
"""
import sqlite3
import os
import threading
from typing import Optional, List, Dict, Any
from contextlib import contextmanager


class VocabularyService:
    """SQLite 基础词库管理服务"""

    def __init__(self, db_path: str = None):
        if db_path is None:
            # vocabulary.db 和 main.py 同级，在 app/ 目录下
            # services/ 的上级就是 app/
            db_path = os.path.join(
                os.path.dirname(os.path.dirname(__file__)),  # app/
                "vocabulary.db"
            )
        self.db_path = db_path
        self._local = threading.local()
        self._ensure_table()

    def _get_connection(self) -> sqlite3.Connection:
        """获取线程安全的数据库连接"""
        if not hasattr(self._local, 'conn') or self._local.conn is None:
            self._local.conn = sqlite3.connect(self.db_path, check_same_thread=False)
            self._local.conn.row_factory = sqlite3.Row
            self._local.conn.execute("PRAGMA journal_mode=WAL")
            self._local.conn.execute("PRAGMA busy_timeout=5000")
        return self._local.conn

    @contextmanager
    def _get_cursor(self):
        """获取游标的上下文管理器"""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            yield cursor
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            cursor.close()

    def _ensure_table(self):
        """确保表结构正确，如果需要则添加新字段"""
        conn = sqlite3.connect(self.db_path)
        try:
            # 检查现有列
            cursor = conn.execute("PRAGMA table_info(vocabulary)")
            columns = {row[1] for row in cursor.fetchall()}

            # 添加缺失的列
            new_columns = {
                "phonetic": "TEXT",
                "difficulty": "TEXT",
                "added_from": "TEXT DEFAULT 'manual'",
                "examples": "TEXT",
                "created_at": "TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
            }
            for col_name, col_type in new_columns.items():
                if col_name not in columns:
                    try:
                        conn.execute(f"ALTER TABLE vocabulary ADD COLUMN {col_name} {col_type}")
                    except sqlite3.OperationalError:
                        pass

            # 创建索引
            conn.execute("CREATE INDEX IF NOT EXISTS idx_vocabulary_word ON vocabulary(word)")
            conn.commit()
        finally:
            conn.close()

    def exact_match(self, word: str) -> Optional[Dict[str, Any]]:
        """精确匹配单词（不区分大小写）"""
        with self._get_cursor() as cursor:
            cursor.execute(
                "SELECT * FROM vocabulary WHERE LOWER(word) = LOWER(?)",
                (word.strip(),)
            )
            row = cursor.fetchone()
            if row:
                return dict(row)
            return None

    def batch_match(self, words: List[str]) -> Dict[str, Optional[Dict[str, Any]]]:
        """批量精确匹配"""
        results = {}
        for word in words:
            results[word] = self.exact_match(word)
        return results

    def add_word(self, word: str, meaning: str, phonetic: str = None,
                 difficulty: str = None, examples: str = None,
                 added_from: str = "manual") -> int:
        """添加单词到词库，返回ID"""
        with self._get_cursor() as cursor:
            # 先检查是否已存在
            cursor.execute(
                "SELECT id FROM vocabulary WHERE LOWER(word) = LOWER(?)",
                (word.strip(),)
            )
            existing = cursor.fetchone()
            if existing:
                # 更新
                cursor.execute(
                    """UPDATE vocabulary SET meaning=?, phonetic=?, difficulty=?,
                       examples=?, added_from=? WHERE id=?""",
                    (meaning, phonetic, difficulty, examples, added_from, existing["id"])
                )
                return existing["id"]
            else:
                # 插入
                cursor.execute(
                    """INSERT INTO vocabulary (word, meaning, phonetic, difficulty, examples, added_from)
                       VALUES (?, ?, ?, ?, ?, ?)""",
                    (word.strip(), meaning, phonetic, difficulty, examples, added_from)
                )
                return cursor.lastrowid

    def update_word(self, word_id: int, **kwargs) -> bool:
        """更新词库中的单词"""
        allowed_fields = {"word", "meaning", "phonetic", "difficulty", "examples", "added_from"}
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
        if not updates:
            return False

        set_clause = ", ".join(f"{k}=?" for k in updates.keys())
        values = list(updates.values()) + [word_id]

        with self._get_cursor() as cursor:
            cursor.execute(f"UPDATE vocabulary SET {set_clause} WHERE id=?", values)
            return cursor.rowcount > 0

    def delete_word(self, word_id: int) -> bool:
        """删除词库中的单词"""
        with self._get_cursor() as cursor:
            cursor.execute("DELETE FROM vocabulary WHERE id=?", (word_id,))
            return cursor.rowcount > 0

    def search(self, keyword: str, page: int = 1, page_size: int = 50) -> Dict[str, Any]:
        """搜索词库"""
        offset = (page - 1) * page_size
        with self._get_cursor() as cursor:
            cursor.execute(
                "SELECT COUNT(*) as cnt FROM vocabulary WHERE word LIKE ? OR meaning LIKE ?",
                (f"%{keyword}%", f"%{keyword}%")
            )
            total = cursor.fetchone()["cnt"]

            cursor.execute(
                """SELECT * FROM vocabulary WHERE word LIKE ? OR meaning LIKE ?
                   ORDER BY word ASC LIMIT ? OFFSET ?""",
                (f"%{keyword}%", f"%{keyword}%", page_size, offset)
            )
            items = [dict(row) for row in cursor.fetchall()]

            return {
                "items": items,
                "total": total,
                "page": page,
                "page_size": page_size,
                "total_pages": (total + page_size - 1) // page_size
            }

    def list_all(self, page: int = 1, page_size: int = 50) -> Dict[str, Any]:
        """分页列出所有词库"""
        offset = (page - 1) * page_size
        with self._get_cursor() as cursor:
            cursor.execute("SELECT COUNT(*) as cnt FROM vocabulary")
            total = cursor.fetchone()["cnt"]

            cursor.execute(
                "SELECT * FROM vocabulary ORDER BY word ASC LIMIT ? OFFSET ?",
                (page_size, offset)
            )
            items = [dict(row) for row in cursor.fetchall()]

            return {
                "items": items,
                "total": total,
                "page": page,
                "page_size": page_size,
                "total_pages": (total + page_size - 1) // page_size
            }

    def get_stats(self) -> Dict[str, Any]:
        """获取词库统计信息"""
        with self._get_cursor() as cursor:
            cursor.execute("SELECT COUNT(*) as total FROM vocabulary")
            total = cursor.fetchone()["total"]

            cursor.execute(
                "SELECT added_from, COUNT(*) as cnt FROM vocabulary GROUP BY added_from"
            )
            by_source = {row["added_from"] or "manual": row["cnt"] for row in cursor.fetchall()}

            return {
                "total": total,
                "by_source": by_source,
            }

    def get_by_id(self, word_id: int) -> Optional[Dict[str, Any]]:
        """根据ID获取词条"""
        with self._get_cursor() as cursor:
            cursor.execute("SELECT * FROM vocabulary WHERE id=?", (word_id,))
            row = cursor.fetchone()
            return dict(row) if row else None


# 全局单例
_vocabulary_service: Optional[VocabularyService] = None


def get_vocabulary_service(db_path: str = None) -> VocabularyService:
    """获取词库服务单例"""
    global _vocabulary_service
    if _vocabulary_service is None:
        _vocabulary_service = VocabularyService(db_path)
    return _vocabulary_service
