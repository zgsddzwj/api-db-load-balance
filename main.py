"""
FastAPI 应用：健康检查、读（从库）/写（主库）示例路由。
"""
from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from database import get_db_primary, get_db_replica

app = FastAPI(title="API DB Load Balance Demo")

# 示例表：首次写请求时在主库创建（若不存在），避免启动时强依赖 MySQL
_CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
"""


@app.get("/health")
def health():
    """健康检查，供 Nginx 或监控使用。"""
    return {"status": "ok"}


class ItemCreate(BaseModel):
    name: str


class ItemResponse(BaseModel):
    id: int
    name: str

    class Config:
        from_attributes = True


@app.get("/items", response_model=list[ItemResponse])
def list_items(db: Session = Depends(get_db_replica)):
    """读操作：从库查询。"""
    rows = db.execute(text("SELECT id, name FROM items ORDER BY id")).mappings().all()
    return [ItemResponse(id=r["id"], name=r["name"]) for r in rows]


@app.post("/items", response_model=ItemResponse)
def create_item(item: ItemCreate, db: Session = Depends(get_db_primary)):
    """写操作：主库写入。"""
    db.execute(text(_CREATE_TABLE_SQL))
    db.commit()
    db.execute(
        text("INSERT INTO items (name) VALUES (:name)"),
        {"name": item.name},
    )
    db.commit()
    row = db.execute(text("SELECT LAST_INSERT_ID() AS id")).mappings().first()
    row_id = row["id"] if row else None
    if not row_id:
        raise HTTPException(status_code=500, detail="Insert failed")
    return ItemResponse(id=row_id, name=item.name)
