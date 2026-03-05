"""
★★★ 一次性数据库修复脚本 ★★★
修复 words 表中 definitions 字段的格式问题：
  旧格式: [{"pos": "", "meaning": "n. 桌子", "examples": []}]
  新格式: [{"pos": "n.", "cn": "桌子"}]

使用方法：
  1. 先 cd 到 D:\wordbook_app\backend 目录
  2. 运行: python fix_definitions.py
  3. 脚本会自动读取 .env 中的数据库连接信息
"""

import os
import re
import json
import sys

# ── 加载 .env 文件 ──
def load_env(env_path=".env"):
    """手动加载 .env 文件"""
    env_vars = {}
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, _, value = line.partition("=")
                    env_vars[key.strip()] = value.strip()
    return env_vars


def parse_database_url(url):
    """从 DATABASE_URL 解析出 psycopg2 连接参数"""
    url = url.replace("postgresql+asyncpg://", "").replace("postgresql://", "")
    user_pass, _, host_db = url.partition("@")
    user, _, password = user_pass.partition(":")
    host_port, _, dbname = host_db.partition("/")
    host, _, port = host_port.partition(":")
    port = int(port) if port else 5432
    return {
        "host": host,
        "port": port,
        "dbname": dbname,
        "user": user,
        "password": password,
    }


# ── 词性解析 ──
POS_PATTERN = re.compile(
    r'^(n\.|v\.|vt\.|vi\.|adj\.|adv\.|prep\.|conj\.|pron\.|int\.|aux\.|art\.|num\.|det\.|abbr\.|pl\.)\s*'
)


def parse_meaning_to_definitions(meaning: str) -> list:
    """
    将旧格式的 meaning 字符串解析为标准 definitions。
    例如:
      "n. 桌子;v. 用...设圈套"
      → [{"pos": "n.", "cn": "桌子"}, {"pos": "v.", "cn": "用...设圈套"}]
    """
    if not meaning or not meaning.strip():
        return []

    definitions = []
    parts = re.split(r'[;；]', meaning)

    for part in parts:
        part = part.strip()
        if not part:
            continue
        m = POS_PATTERN.match(part)
        if m:
            pos = m.group(1)
            cn = part[m.end():].strip()
        else:
            pos = ""
            cn = part
        if cn:
            definitions.append({"pos": pos, "cn": cn})

    return definitions if definitions else [{"pos": "", "cn": meaning.strip()}]


def needs_fix(definitions: list) -> bool:
    """判断 definitions 是否需要修复"""
    if not definitions:
        return False
    for d in definitions:
        if not isinstance(d, dict):
            continue
        # 情况1: 有 "meaning" 键但没有 "cn" 键 → 需要修复
        if "meaning" in d and "cn" not in d:
            return True
        # 情况2: 有 "cn" 键但 pos 为空，且 cn 里嵌有词性前缀 → 需要修复
        if "cn" in d and (d.get("pos") or "") == "":
            cn_val = d.get("cn", "")
            if cn_val and POS_PATTERN.match(cn_val):
                return True
    return False


def fix_single_definition(definitions: list) -> list:
    """修复单条 word 的 definitions"""
    new_defs = []
    for d in definitions:
        if not isinstance(d, dict):
            continue
        pos = d.get("pos", "") or ""
        # 优先取 cn，然后 meaning，然后 definition_cn
        cn = d.get("cn") or d.get("meaning") or d.get("definition_cn") or ""

        if not cn:
            continue

        # 如果 pos 为空，尝试从 cn 中解析
        if not pos:
            m = POS_PATTERN.match(cn)
            if m:
                pos = m.group(1)
                cn = cn[m.end():].strip()

        new_def = {"pos": pos, "cn": cn}
        # 保留 en 字段（如果有）
        if d.get("en"):
            new_def["en"] = d["en"]
        new_defs.append(new_def)

    return new_defs if new_defs else definitions


def main():
    print("=" * 60)
    print("  数据库 definitions 格式修复工具")
    print("=" * 60)

    # 加载配置
    env = load_env(".env")
    db_url = env.get("DATABASE_URL", os.environ.get("DATABASE_URL", ""))
    if not db_url:
        print("\n❌ 错误: 找不到 DATABASE_URL!")
        print("   请确保在 D:\\wordbook_app\\backend 目录下运行此脚本")
        print("   且 .env 文件中配置了 DATABASE_URL")
        sys.exit(1)

    # 隐藏密码显示
    display_url = db_url.split("@")[-1] if "@" in db_url else db_url
    print(f"\n📡 数据库: {display_url}")

    # 连接数据库
    try:
        import psycopg2
        import psycopg2.extras
    except ImportError:
        print("\n⚠️  需要安装 psycopg2，正在安装...")
        os.system(f"{sys.executable} -m pip install psycopg2-binary")
        import psycopg2
        import psycopg2.extras

    conn_params = parse_database_url(db_url)
    print(f"📡 连接: {conn_params['host']}:{conn_params['port']}/{conn_params['dbname']}")

    try:
        conn = psycopg2.connect(**conn_params)
        conn.autocommit = False
        cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    except Exception as e:
        print(f"\n❌ 数据库连接失败: {e}")
        sys.exit(1)

    print("✅ 数据库连接成功\n")

    # 查询所有 words
    cur.execute("SELECT id, word, definitions FROM words")
    rows = cur.fetchall()
    print(f"📊 总词数: {len(rows)}")

    fixed_count = 0
    skipped_count = 0
    error_count = 0

    for row in rows:
        word_id = row["id"]
        word_text = row["word"]
        definitions = row["definitions"]

        if not definitions:
            skipped_count += 1
            continue

        # 确保 definitions 是 list
        if isinstance(definitions, str):
            try:
                definitions = json.loads(definitions)
            except Exception:
                skipped_count += 1
                continue

        if not isinstance(definitions, list):
            skipped_count += 1
            continue

        if not needs_fix(definitions):
            skipped_count += 1
            continue

        # 修复
        try:
            new_defs = fix_single_definition(definitions)
            cur.execute(
                "UPDATE words SET definitions = %s::jsonb WHERE id = %s",
                (json.dumps(new_defs, ensure_ascii=False), word_id)
            )
            fixed_count += 1
            if fixed_count <= 15:
                print(f"  🔧 {word_text}")
                print(f"     旧: {json.dumps(definitions, ensure_ascii=False)[:100]}")
                print(f"     新: {json.dumps(new_defs, ensure_ascii=False)[:100]}")
        except Exception as e:
            error_count += 1
            print(f"  ❌ {word_text}: {e}")

    # 提交
    if fixed_count > 0:
        conn.commit()
        print(f"\n✅ 修复完成!")
    else:
        print(f"\n✅ 所有数据格式正确，无需修复!")

    print(f"\n   📊 统计:")
    print(f"   已修复: {fixed_count} 条")
    print(f"   无需修复: {skipped_count} 条")
    if error_count:
        print(f"   失败: {error_count} 条")

    cur.close()
    conn.close()
    print("\n🎉 脚本执行完毕")
    print("   接下来请重启后端 (Ctrl+C 再启动) 和前端 (按 R 热重载)")


if __name__ == "__main__":
    main()
