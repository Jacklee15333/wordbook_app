"""
FSRS v5 算法实现（Python 版）
Free Spaced Repetition Scheduler - 间隔重复调度算法

基于 open-spaced-repetition/fsrs4anki 的核心逻辑
比 SM-2 更准确，参数可针对每个用户/单词独立调整
"""
import math
from datetime import datetime, timedelta, timezone
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Optional


class Rating(IntEnum):
    Again = 1   # 不认识
    Hard = 2    # 模糊
    Good = 3    # 认识
    Easy = 4    # 轻松


class State(IntEnum):
    New = 0
    Learning = 1
    Review = 2
    Relearning = 3


@dataclass
class Card:
    """单张卡片的 FSRS 状态"""
    due: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    stability: float = 0.0
    difficulty: float = 0.0
    elapsed_days: float = 0.0
    scheduled_days: float = 0.0
    reps: int = 0
    lapses: int = 0
    state: State = State.New
    last_review: Optional[datetime] = None


@dataclass
class ReviewResult:
    """一次评分后的结果"""
    card: Card
    review_log: dict


class FSRS:
    """
    FSRS v5 调度器
    
    默认参数基于大量 Anki 用户数据训练得出，适合大多数学习场景。
    后续可以根据用户个人数据进行参数优化。
    """

    def __init__(self, parameters: Optional[list[float]] = None):
        # FSRS v5 默认参数（19个）
        self.p = parameters or [
            0.40255, 1.18385, 3.173, 15.69105,     # w0-w3: 初始稳定性
            7.1949,  0.5345,  1.4604, 0.0046,       # w4-w7: 难度相关
            1.54575, 0.1192,  1.01925, 1.9395,       # w8-w11: 稳定性增长
            0.11,    0.29605, 2.2698, 0.2315,        # w12-w15: 遗忘相关
            2.9898,  0.51655, 0.6621,                # w16-w18: 其他
        ]
        self.decay = -0.5
        self.factor = 19 / 81  # 0.9^(1/decay) - 1

    def review(self, card: Card, rating: Rating, now: Optional[datetime] = None) -> ReviewResult:
        """
        对一张卡片进行评分，返回更新后的卡片状态
        
        Args:
            card: 当前卡片状态
            rating: 用户评分 (1-4)
            now: 当前时间（支持离线同步时传入客户端时间）
        
        Returns:
            ReviewResult: 包含更新后的卡片和复习日志
        """
        now = now or datetime.now(timezone.utc)
        
        # 计算自上次复习经过的天数
        elapsed_days = 0.0
        if card.last_review:
            elapsed_days = max(0, (now - card.last_review).total_seconds() / 86400)

        # 创建新卡片（不修改原始卡片）
        new_card = Card(
            due=card.due,
            stability=card.stability,
            difficulty=card.difficulty,
            elapsed_days=elapsed_days,
            scheduled_days=card.scheduled_days,
            reps=card.reps,
            lapses=card.lapses,
            state=card.state,
            last_review=card.last_review,
        )

        if new_card.state == State.New:
            new_card = self._handle_new(new_card, rating, now)
        elif new_card.state == State.Learning or new_card.state == State.Relearning:
            new_card = self._handle_learning(new_card, rating, now, elapsed_days)
        elif new_card.state == State.Review:
            new_card = self._handle_review(new_card, rating, now, elapsed_days)

        new_card.last_review = now
        new_card.reps += 1

        review_log = {
            "rating": int(rating),
            "reviewed_at": now.isoformat(),
            "elapsed_days": elapsed_days,
            "state_before": int(card.state),
            "state_after": int(new_card.state),
        }

        return ReviewResult(card=new_card, review_log=review_log)

    def _handle_new(self, card: Card, rating: Rating, now: datetime) -> Card:
        """处理新词的首次评分"""
        card.difficulty = self._init_difficulty(rating)
        card.stability = self._init_stability(rating)

        if rating == Rating.Again:
            card.state = State.Learning
            card.due = now + timedelta(minutes=1)
            card.scheduled_days = 0
        elif rating == Rating.Hard:
            card.state = State.Learning
            card.due = now + timedelta(minutes=5)
            card.scheduled_days = 0
        elif rating == Rating.Good:
            card.state = State.Learning
            card.due = now + timedelta(minutes=10)
            card.scheduled_days = 0
        else:  # Easy
            card.state = State.Review
            interval = self._next_interval(card.stability)
            card.scheduled_days = interval
            card.due = now + timedelta(days=interval)

        return card

    def _handle_learning(self, card: Card, rating: Rating, now: datetime, elapsed_days: float) -> Card:
        """处理学习中/重新学习的评分"""
        card.difficulty = self._next_difficulty(card.difficulty, rating)
        card.stability = self._short_term_stability(card.stability, rating)

        if rating == Rating.Again:
            card.state = State.Learning if card.state == State.Learning else State.Relearning
            card.due = now + timedelta(minutes=5)
            card.scheduled_days = 0
        elif rating == Rating.Hard:
            card.state = card.state  # 保持当前状态
            card.due = now + timedelta(minutes=10)
            card.scheduled_days = 0
        elif rating == Rating.Good:
            card.state = State.Review
            interval = self._next_interval(card.stability)
            card.scheduled_days = interval
            card.due = now + timedelta(days=interval)
        else:  # Easy
            card.state = State.Review
            interval = self._next_interval(card.stability)
            interval = max(interval, 1)  # 至少1天
            card.scheduled_days = interval
            card.due = now + timedelta(days=interval)

        return card

    def _handle_review(self, card: Card, rating: Rating, now: datetime, elapsed_days: float) -> Card:
        """处理复习阶段的评分"""
        retrievability = self._retrievability(elapsed_days, card.stability)
        card.difficulty = self._next_difficulty(card.difficulty, rating)

        if rating == Rating.Again:
            card.stability = self._next_forget_stability(
                card.difficulty, card.stability, retrievability
            )
            card.lapses += 1
            card.state = State.Relearning
            card.due = now + timedelta(minutes=5)
            card.scheduled_days = 0
        else:
            card.stability = self._next_recall_stability(
                card.difficulty, card.stability, retrievability, rating
            )
            card.state = State.Review
            interval = self._next_interval(card.stability)
            if rating == Rating.Hard:
                interval = min(interval, max(elapsed_days, 1))
            elif rating == Rating.Easy:
                interval = max(interval, elapsed_days + 1)
            interval = max(interval, 1)
            card.scheduled_days = interval
            card.due = now + timedelta(days=interval)

        return card

    # ---- FSRS 核心公式 ----

    def _init_stability(self, rating: Rating) -> float:
        """初始稳定性 S0"""
        return max(self.p[rating.value - 1], 0.1)

    def _init_difficulty(self, rating: Rating) -> float:
        """初始难度 D0"""
        d = self.p[4] - math.exp(self.p[5] * (rating.value - 1)) + 1
        return self._constrain_difficulty(d)

    def _next_difficulty(self, d: float, rating: Rating) -> float:
        """更新难度"""
        delta_d = -self.p[6] * (rating.value - 3)
        new_d = d + delta_d * self._mean_reversion(d)
        return self._constrain_difficulty(new_d)

    def _mean_reversion(self, d: float) -> float:
        """均值回归因子"""
        return self.p[7] * (self.p[4] - d) / self.p[4] + 1

    def _constrain_difficulty(self, d: float) -> float:
        return min(max(d, 1.0), 10.0)

    def _retrievability(self, elapsed_days: float, stability: float) -> float:
        """计算可提取性 R（记忆保留率）"""
        if stability <= 0:
            return 0
        return (1 + self.factor * elapsed_days / stability) ** self.decay

    def _next_interval(self, stability: float) -> float:
        """根据稳定性计算下次复习间隔（天）"""
        desired_retention = 0.9  # 目标记忆保留率 90%
        interval = stability / self.factor * (desired_retention ** (1 / self.decay) - 1)
        return max(round(interval), 1)

    def _next_recall_stability(self, d: float, s: float, r: float, rating: Rating) -> float:
        """回忆成功时的新稳定性"""
        hard_penalty = self.p[15] if rating == Rating.Hard else 1.0
        easy_bonus = self.p[16] if rating == Rating.Easy else 1.0
        new_s = s * (
            1
            + math.exp(self.p[8])
            * (11 - d)
            * s ** (-self.p[9])
            * (math.exp((1 - r) * self.p[10]) - 1)
            * hard_penalty
            * easy_bonus
        )
        return max(new_s, 0.1)

    def _next_forget_stability(self, d: float, s: float, r: float) -> float:
        """遗忘时的新稳定性"""
        new_s = (
            self.p[11]
            * d ** (-self.p[12])
            * ((s + 1) ** self.p[13] - 1)
            * math.exp((1 - r) * self.p[14])
        )
        return max(min(new_s, s), 0.1)

    def _short_term_stability(self, s: float, rating: Rating) -> float:
        """短期学习中的稳定性更新"""
        new_s = s * math.exp(self.p[17] * (rating.value - 3 + self.p[18]))
        return max(new_s, 0.1)


# ---- 便捷函数 ----

def card_from_db(progress: dict) -> Card:
    """从数据库记录构造 Card 对象"""
    return Card(
        due=progress.get("due_date") or datetime.now(timezone.utc),
        stability=progress.get("fsrs_stability", 0),
        difficulty=progress.get("fsrs_difficulty", 0),
        elapsed_days=progress.get("fsrs_elapsed_days", 0),
        scheduled_days=progress.get("fsrs_scheduled_days", 0),
        reps=progress.get("fsrs_reps", 0),
        lapses=progress.get("fsrs_lapses", 0),
        state=State(progress.get("fsrs_state", 0)),
        last_review=progress.get("last_review"),
    )


def card_to_db(card: Card) -> dict:
    """将 Card 对象转为数据库字段"""
    return {
        "fsrs_stability": card.stability,
        "fsrs_difficulty": card.difficulty,
        "fsrs_state": int(card.state),
        "fsrs_elapsed_days": card.elapsed_days,
        "fsrs_scheduled_days": card.scheduled_days,
        "fsrs_reps": card.reps,
        "fsrs_lapses": card.lapses,
        "due_date": card.due,
        "last_review": card.last_review,
    }
