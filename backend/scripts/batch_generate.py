"""
批量生成词典数据脚本
使用本地 Ollama + Qwen2.5-14B 批量生成高中高频 500 词的词典数据

用法:
    python -m scripts.batch_generate --input words.txt --output generated_words.json
    python -m scripts.batch_generate --input words.txt --output generated_words.json --use-cloud
"""
import asyncio
import json
import argparse
import sys
from pathlib import Path

# 将项目根目录加入 path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.ai_generator import generate_word_data


async def main():
    parser = argparse.ArgumentParser(description="批量生成词典数据")
    parser.add_argument("--input", "-i", required=True, help="输入文件路径（每行一个单词）")
    parser.add_argument("--output", "-o", required=True, help="输出 JSON 文件路径")
    parser.add_argument("--use-cloud", action="store_true", help="使用云端 API（默认使用本地 Ollama）")
    parser.add_argument("--start", type=int, default=0, help="从第几个单词开始（断点续跑）")
    args = parser.parse_args()

    # 读取单词列表
    with open(args.input, "r", encoding="utf-8") as f:
        words = [line.strip().lower() for line in f if line.strip()]
    words = list(dict.fromkeys(words))  # 去重
    print(f"📖 共读取 {len(words)} 个单词")

    # 加载已有结果（支持断点续跑）
    results = {}
    output_path = Path(args.output)
    if output_path.exists():
        with open(output_path, "r", encoding="utf-8") as f:
            results = json.load(f)
        print(f"📂 已有 {len(results)} 个单词的数据，将跳过")

    prefer_local = not args.use_cloud
    success = 0
    failed = 0
    total = len(words)

    for i, word in enumerate(words[args.start:], start=args.start):
        # 跳过已生成的
        if word in results:
            continue

        print(f"\n[{i+1}/{total}] 正在生成: {word}")
        try:
            data = await generate_word_data(word, prefer_local=prefer_local)
            if data:
                results[word] = data
                success += 1
                print(f"  ✅ 成功 | 释义数: {len(data.get('definitions', []))} | 例句数: {len(data.get('examples', []))}")
            else:
                results[word] = None
                failed += 1
                print(f"  ❌ 生成失败")
        except Exception as e:
            results[word] = None
            failed += 1
            print(f"  ❌ 异常: {e}")

        # 每 10 个单词保存一次（防止中断丢失）
        if (i + 1) % 10 == 0:
            with open(output_path, "w", encoding="utf-8") as f:
                json.dump(results, f, ensure_ascii=False, indent=2)
            print(f"\n💾 已保存进度 ({success} 成功 / {failed} 失败)")

    # 最终保存
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    print(f"\n{'='*50}")
    print(f"✅ 完成! 成功: {success} | 失败: {failed} | 总计: {total}")
    print(f"📂 输出文件: {args.output}")


if __name__ == "__main__":
    asyncio.run(main())
