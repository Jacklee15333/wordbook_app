"""
导入任务和导入明细模型
文件位置: app/models/import_task.py
"""
import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship

from app.core.database import Base


class ImportTask(Base):
    __tablename__ = "import_tasks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    wordbook_id = Column(UUID(as_uuid=True), ForeignKey("wordbooks.id", ondelete="CASCADE"), nullable=False)
    total_words = Column(Integer, nullable=False, default=0)
    matched_count = Column(Integer, nullable=False, default=0)
    ai_generated_count = Column(Integer, nullable=False, default=0)
    ai_failed_count = Column(Integer, nullable=False, default=0)
    approved_count = Column(Integer, nullable=False, default=0)
    status = Column(String(20), nullable=False, default="pending")
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)
    completed_at = Column(DateTime(timezone=True), nullable=True)

    # Relationships
    items = relationship("ImportItem", back_populates="task", cascade="all, delete-orphan", lazy="selectin")
    user = relationship("User", backref="import_tasks", lazy="selectin")
    wordbook = relationship("Wordbook", backref="import_tasks", lazy="selectin")

    def to_dict(self):
        return {
            "id": str(self.id),
            "user_id": str(self.user_id),
            "wordbook_id": str(self.wordbook_id),
            "total_words": self.total_words,
            "matched_count": self.matched_count,
            "ai_generated_count": self.ai_generated_count,
            "ai_failed_count": self.ai_failed_count,
            "approved_count": self.approved_count,
            "status": self.status,
            "error_message": self.error_message,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }


class ImportItem(Base):
    __tablename__ = "import_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    task_id = Column(UUID(as_uuid=True), ForeignKey("import_tasks.id", ondelete="CASCADE"), nullable=False)
    word_text = Column(String(200), nullable=False)
    match_type = Column(String(20), nullable=False, default="pending")
    vocabulary_meaning = Column(Text, nullable=True)
    generated_data = Column(JSONB, nullable=True)
    word_id = Column(UUID(as_uuid=True), ForeignKey("words.id"), nullable=True)
    status = Column(String(20), nullable=False, default="pending")
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    task = relationship("ImportTask", back_populates="items")

    def to_dict(self):
        return {
            "id": str(self.id),
            "task_id": str(self.task_id),
            "word_text": self.word_text,
            "match_type": self.match_type,
            "vocabulary_meaning": self.vocabulary_meaning,
            "generated_data": self.generated_data,
            "word_id": str(self.word_id) if self.word_id else None,
            "status": self.status,
            "reviewed_by": str(self.reviewed_by) if self.reviewed_by else None,
            "reviewed_at": self.reviewed_at.isoformat() if self.reviewed_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
