-- ============================================================
-- 背单词 App - 数据库初始化脚本
-- 数据库: PostgreSQL 14+
-- 部署: 阿里云 RDS
-- ============================================================

-- 启用 UUID 扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. 用户表
-- ============================================================
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,          -- bcrypt 加密
    nickname        VARCHAR(50),
    avatar_url      TEXT,
    is_active       BOOLEAN DEFAULT TRUE,
    is_admin        BOOLEAN DEFAULT FALSE,          -- 管理员标识
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);

-- ============================================================
-- 2. 词典数据表（所有用户共享）
-- ============================================================
CREATE TABLE words (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    word                VARCHAR(100) NOT NULL,
    word_lower          VARCHAR(100) GENERATED ALWAYS AS (LOWER(word)) STORED,  -- 小写索引用
    phonetic_us         VARCHAR(200),               -- 美式音标
    phonetic_uk         VARCHAR(200),               -- 英式音标
    audio_us_url        TEXT,                        -- 美式发音 OSS URL
    audio_uk_url        TEXT,                        -- 英式发音 OSS URL
    definitions         JSONB NOT NULL DEFAULT '[]', -- [{pos: "adj.", cn: "不舒服的", en: "not comfortable"}]
    morphology          JSONB DEFAULT '{}',          -- {prefix: "un-", root: "comfort", suffix: "-able", explanation: "..."}
    word_family         TEXT[] DEFAULT '{}',          -- 同根词族 ["comfort", "comfortable"]
    phrases             JSONB DEFAULT '[]',          -- [{phrase: "feel uncomfortable", cn: "感到不舒服"}]
    sentence_patterns   JSONB DEFAULT '[]',          -- [{pattern: "make sb. uncomfortable", cn: "使某人不舒服"}]
    examples            JSONB DEFAULT '[]',          -- [{en: "The chair was...", cn: "这把椅子..."}]
    synonyms            TEXT[] DEFAULT '{}',
    antonyms            TEXT[] DEFAULT '{}',
    frequency_level     VARCHAR(20) DEFAULT '中频',   -- 高频/中频/低频
    difficulty_level    VARCHAR(20),                  -- 初中/高中/四级/六级/考研
    is_reviewed         BOOLEAN DEFAULT FALSE,        -- 是否经过人工审核
    review_status       VARCHAR(20) DEFAULT 'pending', -- pending/approved/rejected
    ai_generated        BOOLEAN DEFAULT FALSE,        -- 是否 AI 生成
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 单词唯一约束（小写去重）
CREATE UNIQUE INDEX idx_words_word_lower ON words(word_lower);
CREATE INDEX idx_words_difficulty ON words(difficulty_level);
CREATE INDEX idx_words_review_status ON words(review_status);
CREATE INDEX idx_words_is_reviewed ON words(is_reviewed);

-- ============================================================
-- 3. 词书表
-- ============================================================
CREATE TABLE wordbooks (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(100) NOT NULL,           -- "高中英语词汇"
    description     TEXT,
    cover_url       TEXT,                             -- 封面图 URL
    word_count      INTEGER DEFAULT 0,                -- 冗余字段，定期更新
    difficulty      VARCHAR(20),                      -- 初中/高中/四级/六级/考研
    is_builtin      BOOLEAN DEFAULT TRUE,             -- 内置词书 vs 用户自定义
    created_by      UUID REFERENCES users(id),        -- 自定义词书的创建者
    is_public       BOOLEAN DEFAULT TRUE,             -- 内置词书公开，自定义词书仅本人可见
    sort_order      INTEGER DEFAULT 0,                -- 排序权重
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================
-- 4. 词书-单词关联表（词书只是"单词ID集合"）
-- ============================================================
CREATE TABLE wordbook_words (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wordbook_id     UUID NOT NULL REFERENCES wordbooks(id) ON DELETE CASCADE,
    word_id         UUID NOT NULL REFERENCES words(id) ON DELETE CASCADE,
    sort_order      INTEGER DEFAULT 0,                -- 单词在词书中的顺序
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_wordbook_words_unique ON wordbook_words(wordbook_id, word_id);
CREATE INDEX idx_wordbook_words_wordbook ON wordbook_words(wordbook_id);

-- ============================================================
-- 5. 用户-词书关联表（用户选择了哪些词书学习）
-- ============================================================
CREATE TABLE user_wordbooks (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wordbook_id     UUID NOT NULL REFERENCES wordbooks(id) ON DELETE CASCADE,
    daily_new_words INTEGER DEFAULT 20,               -- 每日新词数量
    is_active       BOOLEAN DEFAULT TRUE,             -- 当前是否在学习这本词书
    started_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_user_wordbooks_unique ON user_wordbooks(user_id, wordbook_id);

-- ============================================================
-- 6. 用户学习进度表（每人每词独立记录）
-- ============================================================
CREATE TABLE user_word_progress (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    word_id             UUID NOT NULL REFERENCES words(id) ON DELETE CASCADE,
    wordbook_id         UUID REFERENCES wordbooks(id),  -- 来源词书（可选）

    -- FSRS v5 核心参数
    fsrs_stability      FLOAT DEFAULT 0,                -- 稳定性 S
    fsrs_difficulty      FLOAT DEFAULT 0,                -- 难度 D
    fsrs_state          INTEGER DEFAULT 0,              -- 0=New, 1=Learning, 2=Review, 3=Relearning
    fsrs_elapsed_days   FLOAT DEFAULT 0,                -- 自上次复习经过的天数
    fsrs_scheduled_days FLOAT DEFAULT 0,                -- 计划间隔天数
    fsrs_reps           INTEGER DEFAULT 0,              -- 重复次数
    fsrs_lapses         INTEGER DEFAULT 0,              -- 遗忘次数
    due_date            TIMESTAMP WITH TIME ZONE,       -- 下次复习时间
    last_review         TIMESTAMP WITH TIME ZONE,       -- 最近复习时间（FSRS用）

    -- 统计字段
    review_count        INTEGER DEFAULT 0,              -- 总复习次数
    first_learned_at    TIMESTAMP WITH TIME ZONE,       -- 首次学习时间
    last_reviewed_at    TIMESTAMP WITH TIME ZONE,       -- 最近复习时间（显示用）

    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_user_word_progress_unique ON user_word_progress(user_id, word_id);
CREATE INDEX idx_user_word_progress_user ON user_word_progress(user_id);
CREATE INDEX idx_user_word_progress_due ON user_word_progress(user_id, due_date);
CREATE INDEX idx_user_word_progress_state ON user_word_progress(user_id, fsrs_state);

-- ============================================================
-- 7. 复习日志表（每次评分记录，用于冲突合并）
-- ============================================================
CREATE TABLE review_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    word_id         UUID NOT NULL REFERENCES words(id) ON DELETE CASCADE,
    rating          INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 4),
                    -- 1=Again(不认识), 2=Hard(模糊), 3=Good(认识), 4=Easy(轻松)
    reviewed_at     TIMESTAMP WITH TIME ZONE NOT NULL,  -- 精确到毫秒
    device_id       VARCHAR(100),                        -- 来源设备标识
    
    -- FSRS 快照（评分后的状态快照，方便调试和回溯）
    fsrs_stability_after  FLOAT,
    fsrs_difficulty_after FLOAT,
    fsrs_state_after      INTEGER,
    due_date_after        TIMESTAMP WITH TIME ZONE,

    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_review_logs_user_word ON review_logs(user_id, word_id);
CREATE INDEX idx_review_logs_user_time ON review_logs(user_id, reviewed_at);
CREATE INDEX idx_review_logs_device ON review_logs(device_id);

-- ============================================================
-- 8. 学习打卡表（每日统计）
-- ============================================================
CREATE TABLE daily_stats (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    study_date      DATE NOT NULL,
    new_words       INTEGER DEFAULT 0,          -- 当日新学单词数
    reviewed_words  INTEGER DEFAULT 0,          -- 当日复习单词数
    total_reviews   INTEGER DEFAULT 0,          -- 当日总评分次数
    study_minutes   INTEGER DEFAULT 0,          -- 学习时长（分钟）
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_daily_stats_unique ON daily_stats(user_id, study_date);

-- ============================================================
-- 9. 离线同步队列表（服务端存储，处理冲突用）
-- ============================================================
CREATE TABLE sync_queue (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action_type     VARCHAR(50) NOT NULL,        -- 'review', 'progress_update'
    payload         JSONB NOT NULL,              -- 具体数据
    device_id       VARCHAR(100),
    client_timestamp TIMESTAMP WITH TIME ZONE NOT NULL,  -- 客户端时间
    processed       BOOLEAN DEFAULT FALSE,
    processed_at    TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_sync_queue_user ON sync_queue(user_id, processed);

-- ============================================================
-- 10. 词典审核队列表
-- ============================================================
CREATE TABLE word_review_queue (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    word_id         UUID NOT NULL REFERENCES words(id) ON DELETE CASCADE,
    submitted_by    UUID REFERENCES users(id),    -- 谁触发的 AI 生成
    ai_model        VARCHAR(100),                  -- 生成用的模型名
    ai_raw_response TEXT,                          -- AI 原始返回（备查）
    status          VARCHAR(20) DEFAULT 'pending', -- pending/approved/modified/rejected
    reviewed_by     UUID REFERENCES users(id),     -- 审核人
    review_note     TEXT,                          -- 审核备注
    reviewed_at     TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_word_review_queue_status ON word_review_queue(status);

-- ============================================================
-- 辅助函数：自动更新 updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 为需要的表创建触发器
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_words_updated_at BEFORE UPDATE ON words
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_word_progress_updated_at BEFORE UPDATE ON user_word_progress
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_daily_stats_updated_at BEFORE UPDATE ON daily_stats
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 初始数据：创建内置词书
-- ============================================================
INSERT INTO wordbooks (name, description, difficulty, is_builtin, is_public, sort_order) VALUES
    ('初中英语词汇', '初中阶段核心词汇，约1600词', '初中', TRUE, TRUE, 1),
    ('高中英语词汇', '高中阶段核心词汇，约3500词', '高中', TRUE, TRUE, 2),
    ('大学英语四级', 'CET-4 核心词汇，约4500词', '四级', TRUE, TRUE, 3),
    ('大学英语六级', 'CET-6 核心词汇，约6000词', '六级', TRUE, TRUE, 4),
    ('考研英语词汇', '考研英语核心词汇，约5500词', '考研', TRUE, TRUE, 5);

-- ============================================================
-- 完成
-- ============================================================
-- 执行后请验证：
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
