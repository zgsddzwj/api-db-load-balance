# 应用层读写分离配置

API 连接 2 台 DB 时：**写请求走主库，读请求走从库**，实现读的负载分担。

## 环境变量

复制 [.env.example](.env.example) 为 `.env`，填写实际主库/从库地址与账号。应用启动时读取这些变量，在代码或 ORM 中按读写选择数据源。

## 实现方式

### 方式一：应用内双数据源（推荐）

在 API 中配置两个数据源（主/从），根据操作类型选择：

- **写操作**（INSERT / UPDATE / DELETE / 带写的存储过程）→ 使用主库数据源。
- **读操作**（SELECT / 只读查询）→ 使用从库数据源。

示例（概念）：

- **Java/Spring**：使用 `AbstractRoutingDataSource` 或 Spring Boot 多数据源 + `@Transactional(readOnly = true)` 走从库。
- **Node (TypeORM/Sequelize)**：建两个 DataSource/Sequelize 实例（primary / replica），在 Repository 或 Service 层按读写选择。
- **Go (GORM)**：`db.Set("gorm:query_option", "/* replica */")` 或两个 `*gorm.DB` 实例，读用 replica、写用 primary。
- **Python (Django)**：在 `DATABASES` 中配置 `default`（主）和 `replica`，用 `using('replica')` 做只读查询；或使用 `django-db-read-replica` 等库。

### Python (FastAPI) 示例

本目录包含 FastAPI + MySQL 双数据源示例，写走主库、读走从库。

1. **依赖与配置**  
   在 `app/` 下执行：`pip install -r requirements.txt`。复制 `.env.example` 为 `.env`，填写主库/从库的 `DB_PRIMARY_*`、`DB_REPLICA_*`（或直接配置 `DB_PRIMARY_URL`、`DB_REPLICA_URL`）。

2. **运行**  
   `uvicorn main:app --reload --host 0.0.0.0 --port 8080`（需在 `app/` 目录下执行，或 `uvicorn app.main:app` 从项目根执行并设置 `PYTHONPATH`）。  
   - `GET /health`：健康检查。  
   - `GET /items`：从**从库**读列表。  
   - `POST /items`：往**主库**写一条。

3. **与 Nginx 负载均衡配合**  
   部署两台（或多台） API 实例，每台使用相同主从配置、无状态运行。在 [nginx/nginx.conf](./nginx/nginx.conf) 的 `upstream api_backend` 中填写这两台实例的 IP 与端口，Nginx 轮询转发；健康检查可指向各实例的 `/health`。

### 方式二：中间件

由 ProxySQL、MySQL Router、PgPool-II 等对应用暴露一个地址，中间件内部将写转发到主、读转发到从。应用只需配置一个 `DATABASE_URL`，无需改代码。

## 注意

- **主从延迟**：写后立刻读可能读到旧数据，强一致读应走主库或等待复制延迟后再读。
- **从库故障**：可降级为读也走主库，或摘除故障从库并告警。
