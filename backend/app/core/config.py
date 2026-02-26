"""应用配置 - 从环境变量加载"""
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # 数据库
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/wordbook_db"

    # JWT
    jwt_secret_key: str = "dev-secret-change-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 10080  # 7天

    # 阿里云 OSS
    oss_access_key_id: str = ""
    oss_access_key_secret: str = ""
    oss_bucket_name: str = "wordbook-audio"
    oss_endpoint: str = "https://oss-cn-shanghai.aliyuncs.com"
    oss_domain: str = ""

    # 通义千问
    qwen_api_key: str = ""
    qwen_model: str = "qwen-plus"
    qwen_base_url: str = "https://dashscope.aliyuncs.com/compatible-mode/v1"

    # Ollama
    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = "qwen2.5:14b"

    # 有道 TTS
    youdao_app_key: str = ""
    youdao_app_secret: str = ""

    # 应用
    app_env: str = "development"
    app_host: str = "0.0.0.0"
    app_port: int = 8000
    cors_origins: str = "http://localhost:3000,http://localhost:8080"

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",")]

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache
def get_settings() -> Settings:
    return Settings()
