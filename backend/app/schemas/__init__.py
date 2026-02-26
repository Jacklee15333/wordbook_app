"""API request/response models"""
from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel, Field


# ============================================================
# Auth
# ============================================================
class RegisterRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=6, max_length=128)
    nickname: Optional[str] = None


class LoginRequest(BaseModel):
    email: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    email: str
    nickname: Optional[str] = None


class UserResponse(BaseModel):
    id: UUID
    email: str
    nickname: Optional[str]
    is_admin: bool
    created_at: datetime

    class Config:
        from_attributes = True


# ============================================================
# 词典相关
# ============================================================
class DefinitionItem(BaseModel):
    pos: str            # 词性: "adj.", "n.", "v." 等
    cn: str             # 中文释义
    en: Optional[str] = None  # 英文释义


class MorphologyData(BaseModel):
    prefix: Optional[str] = None
    root: Optional[str] = None
    suffix: Optional[str] = None
    explanation: Optional[str] = None  # 拆解说明


class PhraseItem(BaseModel):
    phrase: str
    cn: str


class ExampleItem(BaseModel):
    en: str
    cn: str


class WordResponse(BaseModel):
    id: UUID
    word: str
    phonetic_us: Optional[str]
    phonetic_uk: Optional[str]
    audio_us_url: Optional[str]
    audio_uk_url: Optional[str]
    definitions: list
    morphology: Optional[dict]
    word_family: Optional[list[str]]
    phrases: Optional[list]
    sentence_patterns: Optional[list]
    examples: Optional[list]
    synonyms: Optional[list[str]]
    antonyms: Optional[list[str]]
    frequency_level: Optional[str]
    difficulty_level: Optional[str]
    is_reviewed: bool

    class Config:
        from_attributes = True


class WordCreateRequest(BaseModel):
    """管理员手动添加单词"""
    word: str
    phonetic_us: Optional[str] = None
    phonetic_uk: Optional[str] = None
    definitions: list[DefinitionItem]
    morphology: Optional[MorphologyData] = None
    word_family: Optional[list[str]] = None
    phrases: Optional[list[PhraseItem]] = None
    sentence_patterns: Optional[list[PhraseItem]] = None
    examples: Optional[list[ExampleItem]] = None
    synonyms: Optional[list[str]] = None
    antonyms: Optional[list[str]] = None
    frequency_level: Optional[str] = "中频"
    difficulty_level: Optional[str] = None


# ============================================================
# 词书相关
# ============================================================
class WordbookResponse(BaseModel):
    id: UUID
    name: str
    description: Optional[str]
    word_count: int
    difficulty: Optional[str]
    is_builtin: bool
    sort_order: int

    class Config:
        from_attributes = True


class WordbookCreateRequest(BaseModel):
    name: str = Field(max_length=100)
    description: Optional[str] = None
    difficulty: Optional[str] = None


# ============================================================
# 学习相关
# ============================================================
class ReviewRequest(BaseModel):
    """用户评分请求"""
    word_id: UUID
    rating: int = Field(ge=1, le=4)  # 1=Again, 2=Hard, 3=Good, 4=Easy
    reviewed_at: datetime             # 客户端时间戳（毫秒精度）
    device_id: Optional[str] = None


class BatchReviewRequest(BaseModel):
    """离线批量同步"""
    reviews: list[ReviewRequest]


class StudyCardResponse(BaseModel):
    """学习卡片数据"""
    word: WordResponse
    progress: Optional[dict] = None  # FSRS 状态，新词为 None
    is_new: bool = True


class TodayTaskResponse(BaseModel):
    """今日学习任务"""
    new_words: list[StudyCardResponse]
    review_words: list[StudyCardResponse]
    new_count: int
    review_count: int
    streak_days: int  # 连续打卡天数


class ReviewResultResponse(BaseModel):
    """评分后返回更新的 FSRS 状态"""
    word_id: UUID
    fsrs_state: int
    due_date: datetime
    stability: float
    difficulty: float


# ============================================================
# 统计相关
# ============================================================
class DailyStatResponse(BaseModel):
    study_date: str  # YYYY-MM-DD
    new_words: int
    reviewed_words: int
    total_reviews: int

    class Config:
        from_attributes = True