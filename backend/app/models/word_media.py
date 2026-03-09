"""单词多媒体资源模型"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, DateTime, Integer, String, Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base


class WordMedia(Base):
    """
    单词多媒体资源表
    ──────────────────────────────────────────
    media_type 可选值:
      - audio_us    美音
      - audio_uk    英音
      - audio_effect_xxx  特效音频（如 audio_effect_kamen = 假面骑士）
      - image       图片
      - video       视频
    source 可选值:
      - youdao      有道词典自动抓取
      - custom      手动上传
      - 其他自定义来源
    ──────────────────────────────────────────
    """
    __tablename__ = "word_media"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    word_id = Column(UUID(as_uuid=True), ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)
    media_type = Column(String(50), nullable=False, index=True)  # audio_us / audio_uk / image / video ...
    source = Column(String(50), nullable=False, default="youdao")  # youdao / custom / ...
    file_path = Column(Text, nullable=False)  # 本地相对路径，以后换 OSS 改成完整 URL
    file_size = Column(Integer, default=0)  # 字节数
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
                        onupdate=lambda: datetime.now(timezone.utc))
