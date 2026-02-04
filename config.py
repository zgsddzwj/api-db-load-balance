"""
从环境变量读取主库/从库 DB 配置，供 SQLAlchemy 使用。
优先使用 DB_PRIMARY_URL / DB_REPLICA_URL；未设置时由 HOST/PORT/USER/PASSWORD/DATABASE 拼接。
"""
import os
from urllib.parse import quote_plus

from dotenv import load_dotenv

load_dotenv()


def _build_mysql_url(host: str, port: str, user: str, password: str, database: str) -> str:
    safe_password = quote_plus(password) if password else ""
    return f"mysql+pymysql://{user}:{safe_password}@{host}:{port}/{database}"


def get_primary_url() -> str:
    url = os.getenv("DB_PRIMARY_URL")
    if url:
        return url
    return _build_mysql_url(
        host=os.getenv("DB_PRIMARY_HOST", "127.0.0.1"),
        port=os.getenv("DB_PRIMARY_PORT", "3306"),
        user=os.getenv("DB_PRIMARY_USER", "root"),
        password=os.getenv("DB_PRIMARY_PASSWORD", ""),
        database=os.getenv("DB_PRIMARY_DATABASE", "app_db"),
    )


def get_replica_url() -> str:
    url = os.getenv("DB_REPLICA_URL")
    if url:
        return url
    return _build_mysql_url(
        host=os.getenv("DB_REPLICA_HOST", "127.0.0.1"),
        port=os.getenv("DB_REPLICA_PORT", "3306"),
        user=os.getenv("DB_REPLICA_USER", "root"),
        password=os.getenv("DB_REPLICA_PASSWORD", ""),
        database=os.getenv("DB_REPLICA_DATABASE", "app_db"),
    )
