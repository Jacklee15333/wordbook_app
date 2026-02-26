"""词典数据模型"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import Boolean, Column, DateTime, Float, Integer, String, Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB, ARRAY
from app.core.database import Base


class Word(Base):
    __tablename__ = "words"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    word = Column(String(100), nullable=False)
    phonetic_us = Column(String(200))
    phonetic_uk = Column(String(200))
    audio_us_url = Column(Text)
    audio_uk_url = Column(Text)
    definitions = Column(JSONB, default=list)
    morphology = Column(JSONB, default=dict)
    word_family = Column(ARRAY(Text), default=list)
    phrases = Column(JSONB, default=list)
    sentence_patterns = Column(JSONB, default=list)
    examples = Column(JSONB, default=list)
    synonyms = Column(ARRAY(Text), default=list)
    antonyms = Column(ARRAY(Text), default=list)
    frequency_level = Column(String(20), default="中频")
    difficulty_level = Column(String(20))
    is_reviewed = Column(Boolean, default=False)
    review_status = Column(String(20), default="pending")
    ai_generated = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


class Wordbook(Base):
    __tablename__ = "wordbooks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(100), nullable=False)
    description = Column(Text)
    cover_url = Column(Text)
    word_count = Column(Integer, default=0)
    difficulty = Column(String(20))
    is_builtin = Column(Boolean, default=True)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    is_public = Column(Boolean, default=True)
    sort_order = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


class WordbookWord(Base):
    __tablename__ = "wordbook_words"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    wordbook_id = Column(UUID(as_uuid=True), ForeignKey("wordbooks.id", ondelete="CASCADE"), nullable=False)
    word_id = Column(UUID(as_uuid=True), ForeignKey("words.id", ondelete="CASCADE"), nullable=False)
    sort_order = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
