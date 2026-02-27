"""
单词生成服务
文件位置: app/services/word_generator_service.py

三级查询策略：
1. vocabulary.db 精确匹配（由调用方先执行）
2. 在线免费词典 API 查询（可靠）
3. Ollama AI 生成（兜底）
"""
import json
import logging
import re
from typing import Optional, Dict, Any

import httpx

logger = logging.getLogger(__name__)


class WordGeneratorService:
    """单词释义生成服务"""

    def __init__(self, ollama_base_url: str = "http://localhost:11434",
                 ollama_model: str = "gpt-oss:20b"):
        self.ollama_base_url = ollama_base_url.rstrip("/")
        self.ollama_model = ollama_model
        self.dict_api_url = "https://api.dictionaryapi.dev/api/v2/entries/en"

    async def lookup_online_dictionary(self, word: str) -> Optional[Dict[str, Any]]:
        """
        从免费在线词典 API 查询单词
        使用 dictionaryapi.dev（免费，无需API key）
        """
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(f"{self.dict_api_url}/{word.strip().lower()}")

                if response.status_code != 200:
                    logger.info(f"在线词典未找到: {word} (status={response.status_code})")
                    return None

                data = response.json()
                if not data or not isinstance(data, list):
                    return None

                entry = data[0]

                # 提取音标
                phonetic = ""
                if entry.get("phonetic"):
                    phonetic = entry["phonetic"]
                elif entry.get("phonetics"):
                    for p in entry["phonetics"]:
                        if p.get("text"):
                            phonetic = p["text"]
                            break

                # 提取释义 - 按词性组织
                meanings_parts = []
                definitions_list = []
                examples_list = []

                for meaning in entry.get("meanings", []):
                    part_of_speech = meaning.get("partOfSpeech", "")
                    pos_abbr = self._pos_abbreviation(part_of_speech)

                    for i, defn in enumerate(meaning.get("definitions", [])[:3]):
                        definition_text = defn.get("definition", "")
                        meanings_parts.append(f"{pos_abbr}{definition_text}")

                        definitions_list.append({
                            "pos": part_of_speech,
                            "definition": definition_text,
                            "definition_cn": "",
                        })

                        if defn.get("example"):
                            examples_list.append({
                                "sentence": defn["example"],
                                "translation": ""
                            })

                # 组合为简洁释义（给 vocabulary.db 用）
                meaning_text = "; ".join(meanings_parts[:5])

                return {
                    "source": "online_dictionary",
                    "word": word.strip().lower(),
                    "meaning": meaning_text,
                    "phonetic": phonetic,
                    "definitions": definitions_list,
                    "examples": examples_list[:3],
                    "difficulty": self._estimate_difficulty(word),
                }

        except httpx.TimeoutException:
            logger.warning(f"在线词典查询超时: {word}")
            return None
        except Exception as e:
            logger.error(f"在线词典查询异常: {word}, error={e}")
            return None

    async def generate_with_ollama(self, word: str) -> Optional[Dict[str, Any]]:
        """
        使用 Ollama 本地模型生成单词释义
        """
        prompt = f"""你是一个专业的英语词典编辑。请为以下英语单词生成详细的词典条目。

单词: {word}

请严格按照以下JSON格式输出，不要输出其他任何内容：
{{
    "word": "{word}",
    "phonetic": "音标，例如 /əˈbɪlɪti/",
    "meaning": "简洁的中文释义，格式如: n.能力；才能 / v.做某事",
    "definitions": [
        {{
            "pos": "词性英文，如 noun/verb/adjective",
            "definition": "英文释义",
            "definition_cn": "中文释义"
        }}
    ],
    "examples": [
        {{
            "sentence": "英文例句",
            "translation": "中文翻译"
        }}
    ],
    "difficulty": "A1/A2/B1/B2/C1/C2"
}}

要求：
1. 释义要准确，中文释义要自然流畅
2. 至少包含2个释义和2个例句
3. 音标使用国际音标格式
4. 难度等级参考CEFR标准
5. meaning字段要简洁，类似词典格式，如"n.(C)能力；才能"
6. 只输出JSON，不要有任何额外文字"""

        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    f"{self.ollama_base_url}/api/generate",
                    json={
                        "model": self.ollama_model,
                        "prompt": prompt,
                        "stream": False,
                        "options": {
                            "temperature": 0.3,
                            "top_p": 0.9,
                            "num_predict": 1024,
                        }
                    }
                )

                if response.status_code != 200:
                    logger.error(f"Ollama API 错误: status={response.status_code}")
                    return None

                result = response.json()
                raw_text = result.get("response", "").strip()

                # 尝试提取 JSON
                parsed = self._extract_json(raw_text)
                if parsed is None:
                    logger.error(f"Ollama 输出解析失败: {word}, raw={raw_text[:200]}")
                    return None

                # 验证必须字段
                if not parsed.get("word") or not parsed.get("meaning"):
                    logger.error(f"Ollama 输出缺少必须字段: {word}")
                    return None

                parsed["source"] = "ollama_ai"
                return parsed

        except httpx.TimeoutException:
            logger.warning(f"Ollama 生成超时: {word}")
            return None
        except Exception as e:
            logger.error(f"Ollama 生成异常: {word}, error={e}")
            return None

    async def generate_word_data(self, word: str) -> Optional[Dict[str, Any]]:
        """
        生成单词数据：先查在线词典，再用AI兜底
        """
        # 策略1: 在线免费词典
        result = await self.lookup_online_dictionary(word)
        if result:
            logger.info(f"在线词典查询成功: {word}")
            return result

        # 策略2: Ollama AI 生成
        logger.info(f"在线词典未找到 {word}，尝试 Ollama 生成")
        result = await self.generate_with_ollama(word)
        if result:
            logger.info(f"Ollama 生成成功: {word}")
            return result

        logger.warning(f"所有生成策略均失败: {word}")
        return None

    def _extract_json(self, text: str) -> Optional[Dict]:
        """从文本中提取JSON"""
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

        match = re.search(r'```(?:json)?\s*\n?(.*?)\n?\s*```', text, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(1))
            except json.JSONDecodeError:
                pass

        match = re.search(r'\{.*\}', text, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                pass

        return None

    @staticmethod
    def _pos_abbreviation(pos: str) -> str:
        """词性缩写"""
        mapping = {
            "noun": "n.",
            "verb": "v.",
            "adjective": "adj.",
            "adverb": "adv.",
            "preposition": "prep.",
            "conjunction": "conj.",
            "pronoun": "pron.",
            "interjection": "interj.",
            "determiner": "det.",
        }
        return mapping.get(pos.lower(), f"{pos}.")

    @staticmethod
    def _estimate_difficulty(word: str) -> str:
        """根据单词长度粗略估计难度"""
        length = len(word)
        if length <= 4:
            return "A1"
        elif length <= 6:
            return "A2"
        elif length <= 8:
            return "B1"
        elif length <= 10:
            return "B2"
        else:
            return "C1"
