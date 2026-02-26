"""学习进度与复习日志模型"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, DateTime, Float, Integer, String, Boolean, Date, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from app.core.database import Base


class UserWordProgress(Base):
    __tablename__ = "user_word_progress"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    word_id = Column(UUID(as_uuid=True), ForeignKey("words.id", ondelete="CASCADE"), nullable=False)
    wordbook_id = Column(UUID(as_uuid=True), ForeignKey("wordbooks.id"))

    # FSRS v5 参数
    fsrs_stability = Column(Float, default=0)
    fsrs_difficulty = Column(Float, default=0)
    fsrs_state = Column(Integer, default=0)  # 0=New, 1=Learning, 2=Review, 3=Relearning
    fsrs_elapsed_days = Column(Float, default=0)
    fsrs_scheduled_days = Column(Float, default=0)
    fsrs_reps = Column(Integer, default=0)
    fsrs_lapses = Column(Integer, default=0)
    due_date = Column(DateTime(timezone=True))
    last_review = Column(DateTime(timezone=True))

    # 统计
    review_count = Column(Integer, default=0)
    first_learned_at = Column(DateTime(timezone=True))
    last_reviewed_at = Column(DateTime(timezone=True))

    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


class ReviewLog(Base):
    __tablename__ = "review_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    word_id = Column(UUID(as_uuid=True), ForeignKey("words.id", ondelete="CASCADE"), nullable=False)
    rating = Column(Integer, nullable=False)  # 1-4
    reviewed_at = Column(DateTime(timezone=True), nullable=False)
    device_id = Column(String(100))

    # FSRS 快照
    fsrs_stability_after = Column(Float)
    fsrs_difficulty_after = Column(Float)
    fsrs_state_after = Column(Integer)
    due_date_after = Column(DateTime(timezone=True))

    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class DailyStat(Base):
    __tablename__ = "daily_stats"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    study_date = Column(Date, nullable=False)
    new_words = Column(Integer, default=0)
    reviewed_words = Column(Integer, default=0)
    total_reviews = Column(Integer, default=0)
    study_minutes = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


class UserWordbook(Base):
    __tablename__ = "user_wordbooks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    wordbook_id = Column(UUID(as_uuid=True), ForeignKey("wordbooks.id", ondelete="CASCADE"), nullable=False)
    daily_new_words = Column(Integer, default=20)
    is_active = Column(Boolean, default=True)
    started_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
