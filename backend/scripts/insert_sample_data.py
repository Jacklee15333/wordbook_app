"""
Insert sample word data for testing.
Run this so the frontend has words to display immediately.

Usage:
    python -m scripts.insert_sample_data
"""
import asyncio
import sys
import uuid
from pathlib import Path
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).parent.parent))

import asyncpg
from app.core.config import get_settings
from scripts.init_db import parse_db_url

SAMPLE_WORDS = [
    {
        "word": "abandon",
        "phonetic_us": "/əˈbændən/",
        "phonetic_uk": "/əˈbændən/",
        "definitions": [{"pos": "v.", "cn": "放弃；抛弃", "en": "to leave completely and finally"}, {"pos": "n.", "cn": "放纵", "en": "a feeling of freedom"}],
        "morphology": {"prefix": "a-", "root": "bandon", "suffix": None, "explanation": "a-(to) + bandon(control) = give up control"},
        "word_family": ["abandonment", "abandoned"],
        "phrases": [{"phrase": "abandon hope", "cn": "放弃希望"}, {"phrase": "abandon ship", "cn": "弃船"}, {"phrase": "with abandon", "cn": "放纵地"}],
        "sentence_patterns": [{"pattern": "abandon sth./sb.", "cn": "放弃某事/抛弃某人"}],
        "examples": [{"en": "They had to abandon the car in the snow.", "cn": "他们不得不把车丢在雪地里。"}, {"en": "She abandoned her dream of becoming a dancer.", "cn": "她放弃了成为舞者的梦想。"}, {"en": "The children were dancing with abandon.", "cn": "孩子们尽情地跳舞。"}],
        "synonyms": ["give up", "desert", "forsake"],
        "antonyms": ["keep", "retain", "maintain"],
        "frequency_level": "high",
        "difficulty_level": "high school",
    },
    {
        "word": "ability",
        "phonetic_us": "/əˈbɪləti/",
        "phonetic_uk": "/əˈbɪlɪti/",
        "definitions": [{"pos": "n.", "cn": "能力；才能", "en": "the power or skill to do something"}],
        "morphology": {"prefix": None, "root": "abil", "suffix": "-ity", "explanation": "abil(able) + -ity(noun suffix) = state of being able"},
        "word_family": ["able", "unable", "disable", "enable"],
        "phrases": [{"phrase": "have the ability to", "cn": "有能力做"}, {"phrase": "to the best of one's ability", "cn": "尽某人所能"}, {"phrase": "natural ability", "cn": "天赋"}],
        "sentence_patterns": [{"pattern": "have the ability to do sth.", "cn": "有能力做某事"}],
        "examples": [{"en": "She has the ability to solve complex problems.", "cn": "她有解决复杂问题的能力。"}, {"en": "He performed to the best of his ability.", "cn": "他尽了最大努力表现。"}, {"en": "The test measures reading ability.", "cn": "这个测试衡量阅读能力。"}],
        "synonyms": ["capability", "capacity", "talent"],
        "antonyms": ["inability", "weakness"],
        "frequency_level": "high",
        "difficulty_level": "junior high",
    },
    {
        "word": "comfortable",
        "phonetic_us": "/ˈkʌmftəbl/",
        "phonetic_uk": "/ˈkʌmftəbl/",
        "definitions": [{"pos": "adj.", "cn": "舒适的；舒服的", "en": "providing physical ease and relaxation"}, {"pos": "adj.", "cn": "自在的；安逸的", "en": "free from stress or fear"}],
        "morphology": {"prefix": None, "root": "comfort", "suffix": "-able", "explanation": "comfort(comfort) + -able(able to) = able to give comfort"},
        "word_family": ["comfort", "uncomfortable", "comfortably", "discomfort"],
        "phrases": [{"phrase": "feel comfortable", "cn": "感到舒适"}, {"phrase": "comfortable with", "cn": "对...感到自在"}, {"phrase": "make yourself comfortable", "cn": "请随便坐"}],
        "sentence_patterns": [{"pattern": "be comfortable doing sth.", "cn": "做某事感到自在"}],
        "examples": [{"en": "This chair is very comfortable.", "cn": "这把椅子很舒服。"}, {"en": "I'm not comfortable speaking in public.", "cn": "我不太自在在公众面前讲话。"}, {"en": "Make yourself comfortable while I get some tea.", "cn": "我去泡茶，你随便坐。"}],
        "synonyms": ["cozy", "relaxed", "pleasant"],
        "antonyms": ["uncomfortable", "uneasy"],
        "frequency_level": "high",
        "difficulty_level": "junior high",
    },
    {
        "word": "determine",
        "phonetic_us": "/dɪˈtɜːrmɪn/",
        "phonetic_uk": "/dɪˈtɜːmɪn/",
        "definitions": [{"pos": "v.", "cn": "决定；确定", "en": "to decide or settle conclusively"}, {"pos": "v.", "cn": "查明；测定", "en": "to find out the facts about something"}],
        "morphology": {"prefix": "de-", "root": "termin", "suffix": "-e", "explanation": "de-(completely) + termin(limit/end) = to set limits completely, hence to decide"},
        "word_family": ["determination", "determined", "determinant"],
        "phrases": [{"phrase": "be determined to", "cn": "下定决心做"}, {"phrase": "determine the cause", "cn": "查明原因"}, {"phrase": "determine the outcome", "cn": "决定结果"}],
        "sentence_patterns": [{"pattern": "determine to do sth.", "cn": "决心做某事"}, {"pattern": "determine + wh-clause", "cn": "确定..."}],
        "examples": [{"en": "She determined to finish the project on time.", "cn": "她决心按时完成项目。"}, {"en": "The police are trying to determine the cause of the fire.", "cn": "警方正在试图查明火灾原因。"}, {"en": "Your attitude determines your altitude.", "cn": "你的态度决定你的高度。"}],
        "synonyms": ["decide", "establish", "ascertain"],
        "antonyms": ["hesitate", "waver"],
        "frequency_level": "high",
        "difficulty_level": "high school",
    },
    {
        "word": "environment",
        "phonetic_us": "/ɪnˈvaɪrənmənt/",
        "phonetic_uk": "/ɪnˈvaɪrənmənt/",
        "definitions": [{"pos": "n.", "cn": "环境；自然环境", "en": "the natural world around us"}, {"pos": "n.", "cn": "周围环境；氛围", "en": "the conditions that affect behavior and development"}],
        "morphology": {"prefix": "en-", "root": "viron", "suffix": "-ment", "explanation": "en-(in) + viron(circle) + -ment(noun suffix) = that which surrounds"},
        "word_family": ["environmental", "environmentalist", "environmentally"],
        "phrases": [{"phrase": "protect the environment", "cn": "保护环境"}, {"phrase": "working environment", "cn": "工作环境"}, {"phrase": "natural environment", "cn": "自然环境"}],
        "sentence_patterns": [{"pattern": "in a ... environment", "cn": "在...环境中"}],
        "examples": [{"en": "We must protect the environment for future generations.", "cn": "我们必须为后代保护环境。"}, {"en": "Children need a safe learning environment.", "cn": "孩子们需要一个安全的学习环境。"}, {"en": "The company provides a friendly working environment.", "cn": "公司提供友好的工作环境。"}],
        "synonyms": ["surroundings", "setting", "habitat"],
        "antonyms": [],
        "frequency_level": "high",
        "difficulty_level": "junior high",
    },
    {
        "word": "fundamental",
        "phonetic_us": "/ˌfʌndəˈmentl/",
        "phonetic_uk": "/ˌfʌndəˈmentl/",
        "definitions": [{"pos": "adj.", "cn": "基本的；根本的", "en": "forming a necessary base or core"}, {"pos": "n.", "cn": "基本原理；基础", "en": "a basic rule or principle"}],
        "morphology": {"prefix": None, "root": "fund", "suffix": "-ment-al", "explanation": "fund(foundation) + -ment(noun suffix) + -al(adj suffix) = relating to the foundation"},
        "word_family": ["fundamentally", "fundamentals", "fundamentalism"],
        "phrases": [{"phrase": "fundamental change", "cn": "根本性变化"}, {"phrase": "fundamental principle", "cn": "基本原则"}, {"phrase": "fundamental right", "cn": "基本权利"}],
        "sentence_patterns": [{"pattern": "be fundamental to sth.", "cn": "对某事是根本的"}],
        "examples": [{"en": "Education is a fundamental right.", "cn": "教育是一项基本权利。"}, {"en": "There are fundamental differences between the two approaches.", "cn": "两种方法之间有根本区别。"}, {"en": "Hard work is fundamental to success.", "cn": "努力工作是成功的基础。"}],
        "synonyms": ["basic", "essential", "core"],
        "antonyms": ["secondary", "minor", "superficial"],
        "frequency_level": "mid",
        "difficulty_level": "CET-4",
    },
    {
        "word": "generate",
        "phonetic_us": "/ˈdʒenəreɪt/",
        "phonetic_uk": "/ˈdʒenəreɪt/",
        "definitions": [{"pos": "v.", "cn": "产生；发生", "en": "to produce or create"}, {"pos": "v.", "cn": "引起；导致", "en": "to cause something to exist"}],
        "morphology": {"prefix": None, "root": "gener", "suffix": "-ate", "explanation": "gener(birth/produce) + -ate(verb suffix) = to produce or bring into being"},
        "word_family": ["generation", "generator", "generative", "regenerate"],
        "phrases": [{"phrase": "generate electricity", "cn": "发电"}, {"phrase": "generate income", "cn": "创收"}, {"phrase": "generate interest", "cn": "引起兴趣"}],
        "sentence_patterns": [{"pattern": "generate sth. from sth.", "cn": "从...产生..."}],
        "examples": [{"en": "The wind turbines generate clean electricity.", "cn": "风力涡轮机产生清洁电力。"}, {"en": "The new policy generated a lot of debate.", "cn": "新政策引发了大量讨论。"}, {"en": "We need to generate more revenue.", "cn": "我们需要创造更多收入。"}],
        "synonyms": ["produce", "create", "cause"],
        "antonyms": ["destroy", "eliminate"],
        "frequency_level": "high",
        "difficulty_level": "CET-4",
    },
    {
        "word": "hypothesis",
        "phonetic_us": "/haɪˈpɑːθəsɪs/",
        "phonetic_uk": "/haɪˈpɒθɪsɪs/",
        "definitions": [{"pos": "n.", "cn": "假设；假说", "en": "a proposed explanation made on limited evidence as a starting point"}],
        "morphology": {"prefix": "hypo-", "root": "thesis", "suffix": None, "explanation": "hypo-(under/below) + thesis(a placing/proposition) = a proposition placed under, i.e. assumed as a basis"},
        "word_family": ["hypothetical", "hypothesize", "hypothetically"],
        "phrases": [{"phrase": "test a hypothesis", "cn": "检验假设"}, {"phrase": "working hypothesis", "cn": "工作假说"}, {"phrase": "put forward a hypothesis", "cn": "提出假设"}],
        "sentence_patterns": [{"pattern": "the hypothesis that ...", "cn": "...的假设"}],
        "examples": [{"en": "The scientist tested her hypothesis through experiments.", "cn": "这位科学家通过实验检验了她的假说。"}, {"en": "We need more data to support this hypothesis.", "cn": "我们需要更多数据来支持这个假设。"}, {"en": "The hypothesis was proven correct.", "cn": "这个假说被证明是正确的。"}],
        "synonyms": ["theory", "assumption", "proposition"],
        "antonyms": ["fact", "proof", "certainty"],
        "frequency_level": "mid",
        "difficulty_level": "CET-6",
    },
    {
        "word": "illustrate",
        "phonetic_us": "/ˈɪləstreɪt/",
        "phonetic_uk": "/ˈɪləstreɪt/",
        "definitions": [{"pos": "v.", "cn": "说明；阐明", "en": "to explain or make something clear"}, {"pos": "v.", "cn": "加插图", "en": "to provide pictures for a book"}],
        "morphology": {"prefix": "il-", "root": "lustr", "suffix": "-ate", "explanation": "il-(in/into) + lustr(light) + -ate(verb suffix) = to throw light on, hence to make clear"},
        "word_family": ["illustration", "illustrative", "illustrator"],
        "phrases": [{"phrase": "illustrate a point", "cn": "说明一个观点"}, {"phrase": "as illustrated", "cn": "如图所示"}, {"phrase": "illustrate with examples", "cn": "用例子说明"}],
        "sentence_patterns": [{"pattern": "illustrate how/what/why ...", "cn": "说明如何/什么/为什么..."}],
        "examples": [{"en": "The diagram illustrates how the system works.", "cn": "这张图说明了系统如何运作。"}, {"en": "Let me illustrate my point with an example.", "cn": "让我用一个例子来说明我的观点。"}, {"en": "The book is beautifully illustrated.", "cn": "这本书插图精美。"}],
        "synonyms": ["demonstrate", "explain", "depict"],
        "antonyms": ["obscure", "confuse"],
        "frequency_level": "mid",
        "difficulty_level": "CET-4",
    },
    {
        "word": "justify",
        "phonetic_us": "/ˈdʒʌstɪfaɪ/",
        "phonetic_uk": "/ˈdʒʌstɪfaɪ/",
        "definitions": [{"pos": "v.", "cn": "证明...正当；为...辩护", "en": "to show that something is right or reasonable"}],
        "morphology": {"prefix": None, "root": "just", "suffix": "-ify", "explanation": "just(right/law) + -ify(to make) = to make right, to prove reasonable"},
        "word_family": ["justification", "justified", "unjustified", "justifiable"],
        "phrases": [{"phrase": "justify oneself", "cn": "为自己辩解"}, {"phrase": "justify the cost", "cn": "证明费用合理"}, {"phrase": "hard to justify", "cn": "难以辩护"}],
        "sentence_patterns": [{"pattern": "justify doing sth.", "cn": "证明做某事是正当的"}],
        "examples": [{"en": "How can you justify spending so much money?", "cn": "你怎么能证明花这么多钱是合理的？"}, {"en": "The end does not justify the means.", "cn": "目的不能为手段辩护。"}, {"en": "She tried to justify her decision to leave.", "cn": "她试图为自己的离开决定辩护。"}],
        "synonyms": ["defend", "validate", "warrant"],
        "antonyms": ["condemn", "criticize"],
        "frequency_level": "mid",
        "difficulty_level": "CET-4",
    },
]


async def main():
    import json

    settings = get_settings()
    db_info = parse_db_url(settings.database_url)

    conn = await asyncpg.connect(
        user=db_info["user"],
        password=db_info["password"],
        host=db_info["host"],
        port=db_info["port"],
        database=db_info["database"],
    )

    try:
        # Get high school wordbook id
        wb_id = await conn.fetchval(
            "SELECT id FROM wordbooks WHERE difficulty = $1", "high school"
        )
        if not wb_id:
            # Try Chinese name
            wb_id = await conn.fetchval(
                "SELECT id FROM wordbooks WHERE name LIKE '%high%' OR name LIKE '%senior%'"
            )
        if not wb_id:
            # Just get the first one
            wb_id = await conn.fetchval(
                "SELECT id FROM wordbooks ORDER BY sort_order LIMIT 1"
            )

        print(f"Target wordbook ID: {wb_id}")

        inserted = 0
        linked = 0
        for w in SAMPLE_WORDS:
            # Check if word already exists
            existing = await conn.fetchval(
                "SELECT id FROM words WHERE LOWER(word) = $1", w["word"].lower()
            )
            if existing:
                word_id = existing
                print(f"  [skip] {w['word']} already exists")
            else:
                word_id = await conn.fetchval("""
                    INSERT INTO words (word, phonetic_us, phonetic_uk, definitions, morphology,
                        word_family, phrases, sentence_patterns, examples, synonyms, antonyms,
                        frequency_level, difficulty_level, is_reviewed, review_status, ai_generated)
                    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,TRUE,'approved',FALSE)
                    RETURNING id
                """,
                    w["word"], w["phonetic_us"], w["phonetic_uk"],
                    json.dumps(w["definitions"]), json.dumps(w["morphology"]),
                    w["word_family"], json.dumps(w["phrases"]),
                    json.dumps(w["sentence_patterns"]), json.dumps(w["examples"]),
                    w["synonyms"], w["antonyms"],
                    w["frequency_level"], w["difficulty_level"],
                )
                inserted += 1
                print(f"  [+] {w['word']} inserted")

            # Link to wordbook
            exists_link = await conn.fetchval(
                "SELECT 1 FROM wordbook_words WHERE wordbook_id=$1 AND word_id=$2",
                wb_id, word_id,
            )
            if not exists_link:
                await conn.execute(
                    "INSERT INTO wordbook_words (wordbook_id, word_id, sort_order) VALUES ($1,$2,$3)",
                    wb_id, word_id, linked,
                )
                linked += 1

        # Update wordbook word count
        count = await conn.fetchval(
            "SELECT count(*) FROM wordbook_words WHERE wordbook_id=$1", wb_id
        )
        await conn.execute(
            "UPDATE wordbooks SET word_count=$1 WHERE id=$2", count, wb_id
        )

        print(f"\nDone! Inserted: {inserted}, Linked to wordbook: {linked}")
        print(f"Wordbook now has {count} words")

    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main())
