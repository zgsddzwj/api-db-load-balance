"""
双数据源：主库（写）、从库（读）。
提供 get_db_primary / get_db_replica 供 FastAPI 依赖注入，路由中写用 primary、读用 replica。
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from config import get_primary_url, get_replica_url

engine_primary = create_engine(
    get_primary_url(),
    pool_pre_ping=True,
    pool_recycle=300,
)
engine_replica = create_engine(
    get_replica_url(),
    pool_pre_ping=True,
    pool_recycle=300,
)

SessionPrimary = sessionmaker(autocommit=False, autoflush=False, bind=engine_primary)
SessionReplica = sessionmaker(autocommit=False, autoflush=False, bind=engine_replica)


def get_db_primary():
    """主库 Session，用于写操作（INSERT/UPDATE/DELETE）。"""
    db = SessionPrimary()
    try:
        yield db
    finally:
        db.close()


def get_db_replica():
    """从库 Session，用于读操作（SELECT）。"""
    db = SessionReplica()
    try:
        yield db
    finally:
        db.close()
