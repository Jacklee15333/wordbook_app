"""
端到端测试脚本 - 验证整个系统是否正常工作

用法:
    python -m scripts.test_system

测试内容:
    1. 数据库连接
    2. 用户注册/登录
    3. 词书列表
    4. 词典搜索
    5. FSRS 算法
    6. Ollama 连接（可选）
"""
import asyncio
import sys
from pathlib import Path
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).parent.parent))

import httpx

BASE_URL = "http://localhost:8000"
TEST_EMAIL = "test@wordbook.local"
TEST_PASSWORD = "test123456"


async def test_health():
    """测试服务是否启动"""
    async with httpx.AsyncClient() as client:
        r = await client.get(f"{BASE_URL}/health")
        assert r.status_code == 200
        print("✅ [1/7] 后端服务正常运行")


async def test_register() -> str:
    """测试注册"""
    async with httpx.AsyncClient() as client:
        r = await client.post(f"{BASE_URL}/api/v1/auth/register", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
            "nickname": "测试用户",
        })
        if r.status_code == 400 and "已注册" in r.text:
            # 已注册就登录
            r = await client.post(f"{BASE_URL}/api/v1/auth/login", json={
                "email": TEST_EMAIL,
                "password": TEST_PASSWORD,
            })
        assert r.status_code == 200
        token = r.json()["access_token"]
        print(f"✅ [2/7] 用户认证正常 (token: {token[:20]}...)")
        return token


async def test_me(token: str):
    """测试获取当前用户"""
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{BASE_URL}/api/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 200
        data = r.json()
        print(f"✅ [3/7] 用户信息: {data['nickname']} ({data['email']})")


async def test_wordbooks(token: str) -> str:
    """测试词书列表"""
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{BASE_URL}/api/v1/wordbooks",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 200
        wordbooks = r.json()
        print(f"✅ [4/7] 词书列表: {len(wordbooks)} 本词书")
        for wb in wordbooks:
            print(f"       - {wb['name']} (词数: {wb['word_count']})")
        if wordbooks:
            return wordbooks[0]["id"]
        return None


async def test_word_search(token: str):
    """测试搜索单词"""
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{BASE_URL}/api/v1/words/search?q=comfortable",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 200
        words = r.json()
        if words:
            print(f"✅ [5/7] 单词搜索: 找到 {len(words)} 个结果")
            w = words[0]
            print(f"       - {w['word']}: {w.get('definitions', [])[:1]}")
        else:
            print(f"⚠️ [5/7] 单词搜索: 词典为空（需要先导入数据）")


async def test_fsrs():
    """测试 FSRS 算法"""
    from app.services.fsrs import FSRS, Card, Rating, State

    fsrs = FSRS()
    card = Card()

    # 模拟学习流程
    # 第一次：认识
    result = fsrs.review(card, Rating.Good)
    assert result.card.state == State.Learning
    
    # 第二次：轻松
    result2 = fsrs.review(result.card, Rating.Easy)
    assert result2.card.state == State.Review
    assert result2.card.stability > 0
    
    print(f"✅ [6/7] FSRS 算法正常")
    print(f"       - 评分 Good → 状态: Learning, 稳定性: {result.card.stability:.2f}")
    print(f"       - 评分 Easy → 状态: Review, 稳定性: {result2.card.stability:.2f}, 间隔: {result2.card.scheduled_days:.0f}天")


async def test_ollama():
    """测试 Ollama 连接"""
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            r = await client.get("http://localhost:11434/api/tags")
            if r.status_code == 200:
                models = r.json().get("models", [])
                model_names = [m["name"] for m in models]
                print(f"✅ [7/7] Ollama 连接正常, 已安装模型: {model_names}")
                if not any("qwen" in m for m in model_names):
                    print(f"       ⚠️ 未找到 Qwen 模型，请运行: ollama pull qwen2.5:14b")
            else:
                print(f"⚠️ [7/7] Ollama 返回异常: {r.status_code}")
    except Exception:
        print(f"⚠️ [7/7] Ollama 未运行（不影响基础功能，AI 生成词典时需要）")
        print(f"       启动方法: ollama serve")


async def main():
    print("=" * 55)
    print("  背单词 App - 系统测试")
    print("=" * 55)
    print()

    try:
        await test_health()
    except Exception as e:
        print(f"❌ 后端服务未启动！请先运行:")
        print(f"   cd backend")
        print(f"   uvicorn app.main:app --reload --port 8000")
        return

    token = await test_register()
    await test_me(token)
    await test_wordbooks(token)
    await test_word_search(token)
    await test_fsrs()
    await test_ollama()

    print()
    print("=" * 55)
    print("  测试完成! 🎉")
    print("=" * 55)
    print()
    print("📝 下一步:")
    print("  1. 如果词典为空，运行批量生成:")
    print("     python -m scripts.batch_generate -i scripts/high_freq_500.txt -o scripts/generated_words.json")
    print("  2. 导入数据库:")
    print('     python -m scripts.import_to_db -i scripts/generated_words.json -w "高中英语词汇"')


if __name__ == "__main__":
    asyncio.run(main())
