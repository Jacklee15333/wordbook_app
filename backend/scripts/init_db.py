"""
数据库初始化脚本 — 安全版
★ 默认只创建缺失的表，绝不删除已有数据
★ --drop 需要二次确认，并自动备份用户数据

用法:
    python -m scripts.init_db                  # 安全模式：只创建缺失的表
    python -m scripts.init_db --drop           # 删除重建（需二次确认+自动备份）
    python -m scripts.init_db --backup         # 仅备份用户数据
    python -m scripts.init_db --restore        # 从最新备份恢复用户数据
    python -m scripts.init_db --status         # 查看各表数据量
"""
import asyncio
import argparse
import sys
import json
import os
from pathlib import Path
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent.parent))

import asyncpg
from app.core.config import get_settings

BACKUP_DIR = Path(__file__).parent.parent / "backups"

# 用户数据表 — 这些表的数据必须保护
USER_DATA_TABLES = [
    "users",
    "user_word_progress",
    "review_logs",
    "daily_stats",
    "user_wordbooks",
]


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
        print(f"   将使用 SQLAlchemy 自动建表...")
        return await safe_create_tables(db_info)

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


# =====================================================
#  ★ 新增：安全建表（只创建缺失的表）
# =====================================================

async def safe_create_tables(db_info: dict):
    """使用 SQLAlchemy create_all(checkfirst=True)，只建缺失的表"""
    from sqlalchemy.ext.asyncio import create_async_engine
    from sqlalchemy import text
    from app.core.database import Base
    import app.models  # noqa: 确保所有 model 被注册

    settings = get_settings()
    engine = create_async_engine(settings.database_url)

    async with engine.begin() as conn:
        # 查看当前表
        result = await conn.execute(text(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'public'"
        ))
        before = {row[0] for row in result.fetchall()}
        print(f"\n📋 当前已有 {len(before)} 张表")

        # 只创建缺失的表
        await conn.run_sync(Base.metadata.create_all, checkfirst=True)

        # 查看创建后的表
        result2 = await conn.execute(text(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'public'"
        ))
        after = {row[0] for row in result2.fetchall()}
        new_tables = after - before

        if new_tables:
            print(f"✅ 新创建了 {len(new_tables)} 张表: {new_tables}")
        else:
            print("✅ 所有表已存在，无需创建")

        # 打印各表的数据量
        print(f"\n📊 各表数据量:")
        for table in sorted(after):
            try:
                count_result = await conn.execute(text(f"SELECT COUNT(*) FROM {table}"))
                count = count_result.scalar()
                icon = "🔒" if table in USER_DATA_TABLES else "📦"
                print(f"  {icon} {table}: {count} 条")
            except Exception:
                print(f"  ❓ {table}: 无法读取")

    await engine.dispose()
    return True


# =====================================================
#  ★ 新增：备份用户数据
# =====================================================

async def backup_user_data(db_info: dict) -> str:
    """备份用户数据到 JSON 文件"""
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = BACKUP_DIR / f"userdata_{timestamp}.json"

    conn = await asyncpg.connect(
        user=db_info["user"],
        password=db_info["password"],
        host=db_info["host"],
        port=db_info["port"],
        database=db_info["database"],
    )

    backup_data = {"version": "1", "timestamp": datetime.now().isoformat(), "tables": {}}

    try:
        # 检查哪些表存在
        existing = await conn.fetch(
            "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"
        )
        existing_set = {row['table_name'] for row in existing}

        for table in USER_DATA_TABLES:
            if table not in existing_set:
                print(f"  ⏭️ {table} — 不存在，跳过")
                continue

            rows = await conn.fetch(f"SELECT * FROM {table}")
            table_data = []
            for row in rows:
                row_dict = {}
                for key, value in dict(row).items():
                    if isinstance(value, datetime):
                        row_dict[key] = value.isoformat()
                    elif hasattr(value, 'hex'):  # UUID
                        row_dict[key] = str(value)
                    else:
                        row_dict[key] = value
                table_data.append(row_dict)

            backup_data["tables"][table] = table_data
            print(f"  ✅ {table} — {len(table_data)} 条记录")

    finally:
        await conn.close()

    with open(backup_path, 'w', encoding='utf-8') as f:
        json.dump(backup_data, f, ensure_ascii=False, indent=2)

    size_kb = backup_path.stat().st_size / 1024
    print(f"\n💾 备份已保存: {backup_path}  ({size_kb:.1f} KB)")
    return str(backup_path)


# =====================================================
#  ★ 新增：恢复用户数据
# =====================================================

async def restore_user_data(db_info: dict):
    """从最新备份恢复用户数据"""
    if not BACKUP_DIR.exists():
        print("❌ 没有找到备份目录")
        return False
    backups = sorted(BACKUP_DIR.glob("userdata_*.json"), reverse=True)
    if not backups:
        print("❌ 没有找到备份文件")
        return False

    backup_path = backups[0]
    print(f"📂 使用最新备份: {backup_path}")

    with open(backup_path, 'r', encoding='utf-8') as f:
        backup_data = json.load(f)

    print(f"📅 备份时间: {backup_data.get('timestamp')}")

    conn = await asyncpg.connect(
        user=db_info["user"],
        password=db_info["password"],
        host=db_info["host"],
        port=db_info["port"],
        database=db_info["database"],
    )

    try:
        existing = await conn.fetch(
            "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"
        )
        existing_set = {row['table_name'] for row in existing}

        # 按依赖顺序恢复
        restore_order = ["users", "user_wordbooks", "user_word_progress", "review_logs", "daily_stats"]

        for table in restore_order:
            if table not in backup_data.get("tables", {}):
                continue
            if table not in existing_set:
                print(f"  ⚠️ {table} — 表不存在，跳过（请先建表）")
                continue

            rows = backup_data["tables"][table]
            if not rows:
                print(f"  ⏭️ {table} — 备份中无数据")
                continue

            # 检查表中是否已有数据
            current_count = await conn.fetchval(f"SELECT COUNT(*) FROM {table}")
            if current_count > 0:
                print(f"  ⏭️ {table} — 已有 {current_count} 条数据，跳过（避免重复）")
                continue

            # 插入数据
            columns = list(rows[0].keys())
            placeholders = ", ".join(f"${i+1}" for i in range(len(columns)))
            column_names = ", ".join(columns)
            insert_sql = f"INSERT INTO {table} ({column_names}) VALUES ({placeholders}) ON CONFLICT DO NOTHING"

            success = 0
            for row in rows:
                try:
                    values = [row[col] for col in columns]
                    await conn.execute(insert_sql, *values)
                    success += 1
                except Exception:
                    pass

            print(f"  ✅ {table} — 恢复 {success}/{len(rows)} 条")

    finally:
        await conn.close()

    return True


# =====================================================
#  ★ 新增：查看数据库状态
# =====================================================

async def show_status(db_info: dict):
    """查看各表数据量"""
    conn = await asyncpg.connect(
        user=db_info["user"],
        password=db_info["password"],
        host=db_info["host"],
        port=db_info["port"],
        database=db_info["database"],
    )
    try:
        tables = await conn.fetch(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'public' ORDER BY table_name"
        )
        print(f"\n📊 数据库共 {len(tables)} 张表:")
        for t in tables:
            name = t['table_name']
            count = await conn.fetchval(f"SELECT COUNT(*) FROM {name}")
            icon = "🔒" if name in USER_DATA_TABLES else "📦"
            print(f"  {icon} {name}: {count} 条")
        print(f"\n  🔒 = 用户数据表（更新时必须保留）")
        print(f"  📦 = 应用内容表")
    finally:
        await conn.close()


# =====================================================
#  主函数
# =====================================================

async def main():
    parser = argparse.ArgumentParser(description="数据库初始化（安全版）")
    parser.add_argument("--drop", action="store_true", help="删除并重建数据库（需二次确认+自动备份）")
    parser.add_argument("--backup", action="store_true", help="备份用户数据")
    parser.add_argument("--restore", action="store_true", help="从最新备份恢复用户数据")
    parser.add_argument("--status", action="store_true", help="查看各表数据量")
    args = parser.parse_args()

    settings = get_settings()
    db_info = parse_db_url(settings.database_url)

    print(f"🔗 数据库连接: {db_info['host']}:{db_info['port']}/{db_info['database']}")
    print(f"👤 用户: {db_info['user']}")
    print()

    if args.status:
        await show_status(db_info)
        return

    if args.backup:
        print("📦 备份用户数据...")
        await backup_user_data(db_info)
        return

    if args.restore:
        print("📂 恢复用户数据...")
        await restore_user_data(db_info)
        return

    if args.drop:
        print("⚠️⚠️⚠️  警告：这会删除整个数据库，包括所有用户的学习进度！")
        confirm1 = input("确认删除？(yes/no): ")
        if confirm1.lower() != "yes":
            print("已取消")
            return
        confirm2 = input(f"再次确认，输入数据库名 '{db_info['database']}': ")
        if confirm2 != db_info["database"]:
            print("已取消")
            return

        # 自动备份
        print("\n📦 自动备份用户数据...")
        try:
            await backup_user_data(db_info)
            print("   （如需恢复，运行: python -m scripts.init_db --restore）")
        except Exception as e:
            print(f"   ⚠️ 备份失败: {e}")
            confirm3 = input("备份失败，仍要继续？(yes/no): ")
            if confirm3.lower() != "yes":
                print("已取消")
                return

        await drop_database(db_info)
        await create_database_if_not_exists(db_info)
        await execute_schema(db_info)

        print("\n🎉 数据库已重建！")
        print("💡 恢复用户数据: python -m scripts.init_db --restore")
        return

    # ★ 默认：安全模式 — 只创建缺失的表，不删除任何数据
    print("🔒 安全模式：只创建缺失的表，已有数据不受影响")
    await create_database_if_not_exists(db_info)
    await safe_create_tables(db_info)
    print("\n🎉 完成！")


if __name__ == "__main__":
    asyncio.run(main())
