"""数据库连接管理"""
import logging
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.core.config import get_settings


logger = logging.getLogger(__name__)

settings = get_settings()

engine = create_async_engine(
    settings.database_url,
    echo=settings.app_env == "development",
    pool_size=20,
    max_overflow=10,
    pool_pre_ping=True,
)

async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

# 别名，供后台任务（import_processor）使用
async_session_factory = async_session


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:
    """FastAPI 依赖注入：获取数据库 session"""
    async with async_session() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


# =====================================================
#  v4.7 新增：安全自动建表
#  只做 CREATE TABLE IF NOT EXISTS，绝不 DROP
#  这样无论怎么更新代码，用户的学习数据都不会丢失
# =====================================================

async def safe_auto_migrate():
    """启动时自动创建缺失的表，已有的表和数据不受影响"""
    # 确保所有 model 都被导入，这样 Base.metadata 才有完整的表定义
    try:
        import app.models  # noqa: F401
    except Exception as e:
        logger.warning(f"导入 models 时出错: {e}")

    async with engine.begin() as conn:
        # checkfirst=True → 只创建不存在的表，已有的表不动
        await conn.run_sync(Base.metadata.create_all, checkfirst=True)
        logger.info("[AUTO-MIGRATE] 数据库表检查完成（只创建缺失的表，已有数据不受影响）")
