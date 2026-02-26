"""
AI 词典生成服务
支持通义千问 API（云端）和 Ollama（本地）两种模式
"""
import json
import httpx
from typing import Optional
from app.core.config import get_settings

settings = get_settings()

# 生成词典数据的 Prompt 模板
WORD_GENERATION_PROMPT = """你是一个专业的英语词典编辑。请为以下英文单词生成完整的词典数据。

单词: {word}

请严格按照以下 JSON 格式返回，不要添加任何其他内容：
{{
    "word": "{word}",
    "phonetic_us": "美式音标，如 /ˈkʌmfərt/",
    "phonetic_uk": "英式音标，如 /ˈkʌmfət/",
    "definitions": [
        {{"pos": "词性缩写如 n./v./adj.", "cn": "中文释义", "en": "英文释义"}}
    ],
    "morphology": {{
        "prefix": "前缀（没有则为null）",
        "root": "词根",
        "suffix": "后缀（没有则为null）",
        "explanation": "词根词缀拆解说明，如 un-(否定) + comfort(舒适) + -able(能...的)"
    }},
    "word_family": ["同根词1", "同根词2"],
    "phrases": [
        {{"phrase": "常用短语搭配", "cn": "中文释义"}}
    ],
    "sentence_patterns": [
        {{"pattern": "句型结构如 make sb. do sth.", "cn": "中文说明"}}
    ],
    "examples": [
        {{"en": "英文例句（来自真实语境）", "cn": "中文翻译"}}
    ],
    "synonyms": ["近义词1", "近义词2"],
    "antonyms": ["反义词1", "反义词2"],
    "frequency_level": "高频/中频/低频",
    "difficulty_level": "初中/高中/四级/六级/考研"
}}

要求：
1. 释义精准，不要机翻，符合中国学生学习习惯
2. 至少提供 2 个释义（如果有多个词性）
3. 短语搭配至少 3 个，要是真正常用的
4. 例句至少 3 条，来自真实语境，难度适中
5. 词根词缀拆解要准确，没有明显词根词缀的简单词可以标注为 null
6. 只返回 JSON，不要有任何其他文字
"""


async def generate_word_data_qwen(word: str) -> Optional[dict]:
    """使用通义千问 API 生成词典数据"""
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                f"{settings.qwen_base_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {settings.qwen_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": settings.qwen_model,
                    "messages": [
                        {"role": "system", "content": "你是一个专业的英语词典编辑，只返回 JSON 格式数据。"},
                        {"role": "user", "content": WORD_GENERATION_PROMPT.format(word=word)},
                    ],
                    "temperature": 0.3,  # 低温度，保证输出稳定
                    "response_format": {"type": "json_object"},
                },
            )
            response.raise_for_status()
            data = response.json()
            content = data["choices"][0]["message"]["content"]
            return _parse_ai_response(content)
    except Exception as e:
        print(f"[Qwen API Error] {word}: {e}")
        return None


async def generate_word_data_ollama(word: str) -> Optional[dict]:
    """使用本地 Ollama 生成词典数据"""
    try:
        async with httpx.AsyncClient(timeout=120) as client:
            response = await client.post(
                f"{settings.ollama_base_url}/api/generate",
                json={
                    "model": settings.ollama_model,
                    "prompt": WORD_GENERATION_PROMPT.format(word=word),
                    "stream": False,
                    "format": "json",
                    "options": {
                        "temperature": 0.3,
                        "num_predict": 2000,
                    },
                },
            )
            response.raise_for_status()
            data = response.json()
            return _parse_ai_response(data.get("response", ""))
    except Exception as e:
        print(f"[Ollama Error] {word}: {e}")
        return None


async def generate_word_data(word: str, prefer_local: bool = True) -> Optional[dict]:
    """
    生成词典数据，优先使用本地模型，失败后回退到云端 API
    
    Args:
        word: 要生成的单词
        prefer_local: 是否优先使用本地 Ollama
    """
    if prefer_local:
        result = await generate_word_data_ollama(word)
        if result:
            return result
        # 本地失败，回退到云端
        print(f"[AI] 本地生成失败，回退到云端 API: {word}")

    return await generate_word_data_qwen(word)


async def batch_generate(words: list[str], prefer_local: bool = True) -> dict[str, Optional[dict]]:
    """
    批量生成词典数据
    
    Returns:
        {word: data_dict} 映射
    """
    results = {}
    for word in words:
        print(f"[AI] 正在生成: {word}")
        data = await generate_word_data(word, prefer_local)
        results[word] = data
    return results


def _parse_ai_response(content: str) -> Optional[dict]:
    """解析 AI 返回的 JSON 数据"""
    try:
        # 尝试直接解析
        data = json.loads(content)
        # 基本验证
        if "word" in data and "definitions" in data:
            return data
        return None
    except json.JSONDecodeError:
        # 尝试从文本中提取 JSON
        try:
            start = content.find("{")
            end = content.rfind("}") + 1
            if start >= 0 and end > start:
                data = json.loads(content[start:end])
                if "word" in data and "definitions" in data:
                    return data
        except (json.JSONDecodeError, ValueError):
            pass
        return None
