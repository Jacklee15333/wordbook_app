"""
数据库初始化脚本
自动创建数据库和表结构，无需手动执行 SQL

用法:
    python -m scripts.init_db
    python -m scripts.init_db --drop   # 删除重建（危险！）
"""
import asyncio
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import asyncpg
from app.core.config import get_settings


# 从 DATABASE_URL 中解析连接信息
def parse_db_url(url: str) -> dict:
    """解析 postgresql+asyncpg://user:pass@host:port/dbname"""
    url = url.replace("postgresql+asyncpg://", "")
    user_pass, host_db = url.split("@")
    user, password = user_pass.split(":")
    host_port, dbname = host_db.split("/")
    if ":" in host_port:
        host, port = host_port.split(":")
        port = int(port)
    else:
        host = host_port
        port = 5432
    return {
        "user": user,
        "password": password,
        "host": host,
        "port": port,
        "database": dbname,
    }


async def create_database_if_not_exists(db_info: dict):
    """如果数据库不存在，则创建"""
    dbname = db_info["database"]
    # 连接到默认的 postgres 数据库
    conn = await asyncpg.connect(
        user=db_info["user"],
        password=db_info["password"],
        host=db_info["host"],
        port=db_info["port"],
        database="postgres",
    )
    try:
        exists = await conn.fetchval(
            "SELECT 1 FROM pg_database WHERE datname = $1", dbname
        )
        if not exists:
            # 需要在非事务模式下执行 CREATE DATABASE
            await conn.execute(f'CREATE DATABASE "{dbname}"')
            print(f"✅ 数据库 '{dbname}' 创建成功")
        else:
            print(f"📂 数据库 '{dbname}' 已存在")
    finally:
        await conn.close()


async def drop_database(db_info: dict):
    """删除数据库"""
    dbname = db_info["database"]
    conn = await asyncpg.connect(
        user=db_info["user"],
        password=db_info["password"],
        host=db_info["host"],
        port=db_info["port"],
        database="postgres",
    )
    try:
        # 断开其他连接
        await conn.execute(f"""
            SELECT pg_terminate_backend(pg_stat_activity.pid)
            FROM pg_stat_activity
            WHERE pg_stat_activity.datname = '{dbname}'
            AND pid <> pg_backend_pid()
        """)
        await conn.execute(f'DROP DATABASE IF EXISTS "{dbname}"')
        print(f"🗑️ 数据库 '{dbname}' 已删除")
    finally:
        await conn.close()


async def execute_schema(db_info: dict):
    """执行建表 SQL"""
    sql_file = Path(__file__).parent.parent.parent / "database" / "001_init_schema.sql"
    if not sql_file.exists():
        print(f"❌ 找不到 SQL 文件: {sql_file}")
        return False

    sql = sql_file.read_text(encoding="utf-8")

    conn = await asyncpg.connect(
        user=db_info["user"],
        password=db_info["password"],
        host=db_info["host"],
        port=db_info["port"],
        database=db_info["database"],
    )
    try:
        await conn.execute(sql)
        print("✅ 数据库表结构创建成功")
        
        # 验证表是否创建成功
        tables = await conn.fetch("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'public'
            ORDER BY table_name
        """)
        print(f"\n📋 已创建 {len(tables)} 张表:")
        for t in tables:
            print(f"   - {t['table_name']}")
        
        # 验证初始词书数据
        wordbooks = await conn.fetch("SELECT name, difficulty FROM wordbooks ORDER BY sort_order")
        print(f"\n📖 内置词书 ({len(wordbooks)} 本):")
        for wb in wordbooks:
            print(f"   - {wb['name']} ({wb['difficulty']})")
        
        return True
    except Exception as e:
        print(f"❌ 执行 SQL 失败: {e}")
        return False
    finally:
        await conn.close()


async def main():
    parser = argparse.ArgumentParser(description="数据库初始化")
    parser.add_argument("--drop", action="store_true", help="删除并重建数据库（危险！）")
    args = parser.parse_args()

    settings = get_settings()
    db_info = parse_db_url(settings.database_url)

    print(f"🔗 数据库连接: {db_info['host']}:{db_info['port']}/{db_info['database']}")
    print(f"👤 用户: {db_info['user']}")
    print()

    if args.drop:
        confirm = input("⚠️ 确认删除数据库？所有数据将丢失！(yes/no): ")
        if confirm.lower() != "yes":
            print("已取消")
            return
        await drop_database(db_info)

    await create_database_if_not_exists(db_info)
    await execute_schema(db_info)

    print("\n🎉 数据库初始化完成！")


if __name__ == "__main__":
    asyncio.run(main())
