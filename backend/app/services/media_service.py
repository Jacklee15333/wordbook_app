"""
单词多媒体资源服务
──────────────────────────────────────────
- 有道词典优先（真人发音，单词质量好）
- Google TTS 兜底（短语/长文本都能读）
- 本地文件自动缓存

本地存储结构：
  backend/media_storage/
    audio/
      us/         ← 美音 (quality.mp3, take_a_vacation.mp3)
      uk/         ← 英音
      effect/     ← 特效音频（预留）
    images/       ← 图片（预留）
    videos/       ← 视频（预留）
──────────────────────────────────────────
"""
import os
import re
import logging
from urllib.parse import quote

import httpx

logger = logging.getLogger(__name__)

# 资源根目录（backend/media_storage/）
MEDIA_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "media_storage")


def _safe_filename(word_text: str) -> str:
    """将单词/短语转为安全的文件名"""
    name = word_text.strip().lower()
    name = name.replace(" ", "_").replace("/", "_")
    name = re.sub(r'[^a-z0-9_\-]', '', name)
    if len(name) > 80:
        name = name[:80]
    return name or "unknown"


def _get_media_dir(accent: str) -> str:
    """返回音频子目录"""
    return os.path.join(MEDIA_ROOT, "audio", accent)


def _get_youdao_url(word_text: str, accent: str = "us") -> str:
    """有道词典 TTS URL — 单词发音好，但部分短语没有"""
    type_param = 1 if accent == "us" else 2
    return f"https://dict.youdao.com/dictvoice?audio={quote(word_text)}&type={type_param}"


def _get_google_tts_url(word_text: str) -> str:
    """Google 翻译 TTS — 支持任意文本，短语兜底"""
    return f"https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en&q={quote(word_text)}"


async def _download_from_url(url: str) -> bytes | None:
    """从指定 URL 下载音频，返回字节或 None"""
    try:
        async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
            resp = await client.get(url, headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            })
            if resp.status_code == 200 and len(resp.content) > 500:
                return resp.content
    except Exception as e:
        logger.warning(f"[MEDIA] 下载失败: {url} → {e}")
    return None


async def get_audio_bytes(word_text: str, accent: str = "us") -> bytes | None:
    """
    获取单词/短语的音频。
    1. 查本地缓存
    2. 尝试有道词典
    3. 有道失败则用 Google TTS 兜底
    4. 成功后保存到本地缓存
    """
    # ── 1. 查本地文件 ──
    media_dir = _get_media_dir(accent)
    filename = f"{_safe_filename(word_text)}.mp3"
    file_path = os.path.join(media_dir, filename)

    if os.path.isfile(file_path) and os.path.getsize(file_path) > 500:
        logger.debug(f"[MEDIA] 缓存命中: '{word_text}'")
        with open(file_path, "rb") as f:
            return f.read()

    # ── 2. 尝试有道 ──
    logger.info(f"[MEDIA] 尝试有道: '{word_text}'")
    audio_bytes = await _download_from_url(_get_youdao_url(word_text, accent))

    # ── 3. 有道失败，尝试 Google TTS ──
    if not audio_bytes:
        logger.info(f"[MEDIA] 有道无音频，尝试 Google TTS: '{word_text}'")
        audio_bytes = await _download_from_url(_get_google_tts_url(word_text))

    if not audio_bytes:
        logger.error(f"[MEDIA] ❌ 所有源都失败: '{word_text}'")
        return None

    # ── 4. 保存到本地缓存 ──
    try:
        os.makedirs(media_dir, exist_ok=True)
        with open(file_path, "wb") as f:
            f.write(audio_bytes)
        logger.info(f"[MEDIA] ✅ 已缓存: {file_path} ({len(audio_bytes)} bytes)")
    except Exception as e:
        logger.warning(f"[MEDIA] 缓存写入失败: {e}")

    return audio_bytes
