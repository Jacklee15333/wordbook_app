"""
创建管理员账号

用法:
    python -m scripts.create_admin
    python -m scripts.create_admin --email admin@test.com --password admin123
"""
import asyncio
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import asyncpg
from app.core.config import get_settings
from app.core.security import hash_password
from scripts.init_db import parse_db_url


async def main():
    parser = argparse.ArgumentParser(description="创建管理员账号")
    parser.add_argument("--email", default="admin@wordbook.local", help="管理员邮箱")
    parser.add_argument("--password", default="admin123", help="管理员密码")
    parser.add_argument("--nickname", default="管理员", help="昵称")
    args = parser.parse_args()

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
        # 检查是否已存在
        existing = await conn.fetchval(
            "SELECT id FROM users WHERE email = $1", args.email
        )
        if existing:
            print(f"⚠️ 管理员账号 {args.email} 已存在")
            return

        pw_hash = hash_password(args.password)
        await conn.execute("""
            INSERT INTO users (email, password_hash, nickname, is_admin, is_active)
            VALUES ($1, $2, $3, TRUE, TRUE)
        """, args.email, pw_hash, args.nickname)

        print(f"✅ 管理员账号创建成功!")
        print(f"   邮箱: {args.email}")
        print(f"   密码: {args.password}")
        print(f"   昵称: {args.nickname}")

    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main())
