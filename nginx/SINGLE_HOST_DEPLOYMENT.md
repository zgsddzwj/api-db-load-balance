# 单机部署指南

本指南介绍如何在一台服务器上使用Docker部署完整的Nginx负载均衡方案。

## 📋 适用场景

- ✅ 只有一台服务器
- ✅ 本地开发测试
- ✅ 学习负载均衡原理
- ✅ 小规模应用部署
- ⚠️ 不适合高并发生产环境（建议使用多服务器）

## 🏗️ 架构说明

```
┌─────────────────────────────────────────┐
│         单台服务器                        │
│                                         │
│  ┌─────────────┐                        │
│  │   Nginx     │  :80, :443             │
│  │  (LB)       │                        │
│  └──────┬──────┘                        │
│         │                               │
│    ┌────┴────┐                          │
│    │         │                          │
│    ▼         ▼                          │
│  ┌─────┐  ┌─────┐                       │
│  │API1 │  │API2 │  (Docker容器)          │
│  │:8080│  │:8080│                       │
│  └─────┘  └─────┘                       │
│    │         │                          │
│    └────┬────┘                          │
│         │                               │
│         ▼                               │
│   外部数据库或容器                         │
└─────────────────────────────────────────┘
```

## 🚀 快速开始

### 前置要求

- 一台服务器（Linux/Mac/Windows with WSL2）
- Docker Engine 20.10+
- Docker Compose 2.0+
- 至少 2GB 可用内存
- 至少 10GB 可用磁盘空间

### 步骤1：准备项目文件

```bash
# 克隆或下载项目
git clone <your-repo-url>
cd api-db-load-balance

# 进入nginx目录
cd nginx/
```

### 步骤2：配置环境变量（可选）

如果API服务需要连接数据库，创建`.env`文件：

```bash
# 在nginx目录下创建.env文件
cat > .env << EOF
# 数据库配置
DB_PRIMARY_HOST=your-db-host
DB_PRIMARY_PORT=3306
DB_PRIMARY_USER=root
DB_PRIMARY_PASSWORD=your-password
DB_PRIMARY_DATABASE=app_db

DB_REPLICA_HOST=your-replica-host
DB_REPLICA_PORT=3306
DB_REPLICA_USER=root
DB_REPLICA_PASSWORD=your-password
DB_REPLICA_DATABASE=app_db
EOF
```

### 步骤3：启动所有服务

```bash
# 使用单机部署配置启动
docker-compose -f docker-compose.single-host.yml up -d

# 查看服务状态
docker-compose -f docker-compose.single-host.yml ps
```

### 步骤4：验证部署

```bash
# 检查Nginx是否运行
curl http://localhost/health

# 检查API服务
curl http://localhost/items

# 查看日志，观察负载均衡
docker-compose -f docker-compose.single-host.yml logs -f nginx | grep upstream
```

## 📊 验证负载均衡

### 方法1：查看访问日志

```bash
# 多次请求
for i in {1..10}; do
    curl -s http://localhost/health > /dev/null
    sleep 0.5
done

# 查看日志，观察upstream在不同API容器间轮换
tail -f logs/access.log | grep upstream
```

### 方法2：停止一个API容器测试故障转移

```bash
# 停止api1
docker stop api-service-1

# 请求应该仍然正常（转发到api2）
curl http://localhost/health

# 恢复api1
docker start api-service-1
```

## 🔧 配置说明

### 添加更多API实例

编辑 `docker-compose.single-host.yml`，添加更多API服务：

```yaml
  api3:
    build:
      context: ../app
      dockerfile: Dockerfile
    container_name: api-service-3
    restart: unless-stopped
    expose:
      - "8080"
    networks:
      - app-network
    environment:
      - TZ=Asia/Shanghai
      # ... 其他环境变量
```

然后在 `nginx.conf.single-host` 中添加：

```nginx
upstream api_backend {
    server api1:8080 max_fails=2 fail_timeout=30s;
    server api2:8080 max_fails=2 fail_timeout=30s;
    server api3:8080 max_fails=2 fail_timeout=30s;  # 新增
}
```

重启服务：

```bash
docker-compose -f docker-compose.single-host.yml up -d
```

### 修改负载均衡策略

编辑 `nginx.conf.single-host`，修改upstream配置：

```nginx
# 加权轮询
upstream api_backend {
    server api1:8080 weight=3 max_fails=2 fail_timeout=30s;
    server api2:8080 weight=2 max_fails=2 fail_timeout=30s;
}

# IP哈希（会话保持）
upstream api_backend {
    ip_hash;
    server api1:8080 max_fails=2 fail_timeout=30s;
    server api2:8080 max_fails=2 fail_timeout=30s;
}
```

重启Nginx容器：

```bash
docker-compose -f docker-compose.single-host.yml restart nginx
```

## 📝 常用命令

```bash
# 启动所有服务
docker-compose -f docker-compose.single-host.yml up -d

# 停止所有服务
docker-compose -f docker-compose.single-host.yml down

# 查看服务状态
docker-compose -f docker-compose.single-host.yml ps

# 查看日志
docker-compose -f docker-compose.single-host.yml logs -f

# 查看特定服务日志
docker-compose -f docker-compose.single-host.yml logs -f nginx
docker-compose -f docker-compose.single-host.yml logs -f api1

# 重启服务
docker-compose -f docker-compose.single-host.yml restart nginx

# 重新构建并启动
docker-compose -f docker-compose.single-host.yml up -d --build

# 查看资源使用
docker stats
```

## 🔍 故障排查

### 问题1：API服务无法启动

```bash
# 检查API服务日志
docker-compose -f docker-compose.single-host.yml logs api1

# 检查API服务是否健康
docker exec api-service-1 curl http://localhost:8080/health
```

### 问题2：Nginx无法连接后端

```bash
# 检查网络连接
docker exec nginx-lb ping api1
docker exec nginx-lb nc -zv api1 8080

# 检查Nginx配置
docker exec nginx-lb nginx -t
```

### 问题3：端口冲突

如果80或443端口被占用：

```yaml
# 修改docker-compose.single-host.yml中的端口映射
ports:
  - "8080:80"    # 改为其他端口
  - "8443:443"
```

### 问题4：内存不足

```bash
# 查看资源使用
docker stats

# 如果内存不足，可以减少API实例数量或增加服务器内存
```

## 💡 性能优化建议

1. **资源限制**：为容器设置资源限制

   ```yaml
   deploy:
     resources:
       limits:
         cpus: '0.5'
         memory: 512M
   ```

2. **连接池**：合理配置数据库连接池大小

3. **缓存**：启用Nginx缓存减少后端压力

4. **监控**：使用监控脚本定期检查服务状态

## 🚀 升级到多服务器部署

当需要更高性能或高可用时，可以：

1. 将API服务部署到多台服务器
2. 使用 `nginx.conf` 和 `docker-compose.yml`（多服务器配置）
3. 配置外部数据库集群
4. 使用Keepalived实现Nginx高可用

## 📚 相关文档

- [完整搭建指南](SETUP_GUIDE.md) - 多服务器部署详细步骤
- [README.md](README.md) - 快速使用指南
- [监控脚本使用](README.md#监控和日志) - 监控和日志查看

---

**提示**：单机部署适合学习和测试，生产环境建议使用多服务器部署以获得更好的性能和可用性。
