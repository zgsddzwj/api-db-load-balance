# Nginx API 负载均衡

将 2 台 API 服务器放入同一 upstream，对外单一入口，轮询分发并带健康检查。

## 文件说明

| 文件 | 说明 |
|------|------|
| `nginx.conf` | Nginx主配置文件（多服务器部署），包含负载均衡、SSL、限流、缓存等完整配置 |
| `nginx.conf.single-host` | Nginx单机部署配置（使用Docker容器名称作为后端） |
| `docker-compose.yml` | Docker Compose配置文件（仅Nginx，后端API需单独部署） |
| `docker-compose.single-host.yml` | **单机部署方案**：在一台服务器上运行Nginx和多个API容器 |
| `SETUP_GUIDE.md` | **完整搭建指南**，从零到一详细步骤（推荐先阅读） |
| `ssl-setup.sh` | SSL证书申请和配置脚本（Let's Encrypt） |
| `monitor.sh` | 监控脚本，用于健康检查、日志分析、性能统计 |

## 快速开始

### 🎯 单机部署方案（推荐：只有一台服务器）

**如果您只有一台服务器，可以使用Docker在一台机器上运行Nginx和多个API服务容器：**

```bash
# 1. 进入nginx目录
cd nginx/

# 2. 使用单机部署配置启动所有服务（Nginx + 2个API实例）
docker-compose -f docker-compose.single-host.yml up -d

# 3. 查看所有服务状态
docker-compose -f docker-compose.single-host.yml ps

# 4. 查看日志
docker-compose -f docker-compose.single-host.yml logs -f

# 5. 验证负载均衡
curl http://localhost/health
# 多次请求，观察日志中的upstream在不同API容器间轮换

# 6. 停止服务
docker-compose -f docker-compose.single-host.yml down
```

**单机部署特点：**

- ✅ 只需一台服务器
- ✅ 使用Docker容器模拟多台服务器
- ✅ 完全本地测试和学习
- ✅ 可以轻松扩展API实例数量
- ⚠️ 适合开发、测试和小规模部署
- ⚠️ 生产环境建议使用多台服务器

**配置说明：**

- 后端API通过Docker网络名称访问（`api1:8080`, `api2:8080`）
- 如需更多API实例，在`docker-compose.single-host.yml`中添加`api3`、`api4`等
- 数据库可以使用外部数据库或添加数据库容器到docker-compose中

### 方式一：使用完整指南（多服务器部署）

**首次部署请先阅读 [SETUP_GUIDE.md](SETUP_GUIDE.md)**，包含：

- 服务器环境准备
- Docker环境搭建
- Nginx容器部署
- SSL/HTTPS配置
- 高级功能配置
- 监控和故障排查

### 方式二：Docker Compose部署（仅Nginx，后端API需单独部署）

```bash
# 1. 修改nginx.conf中的后端服务器IP
vim nginx.conf

# 2. 启动Nginx容器
docker-compose up -d

# 3. 查看日志
docker-compose logs -f nginx

# 4. 验证
curl http://localhost/health
```

### 方式三：直接使用系统Nginx（需先改 IP/端口）

```bash
# 复制到系统 Nginx 配置目录（按系统调整路径）
sudo cp nginx.conf /etc/nginx/nginx.conf
# 或作为 include：在 /etc/nginx/conf.d/ 下建 api-lb.conf，内容为 server { ... } 块，upstream 放在 http 内

# 检查配置
sudo nginx -t

# 重载
sudo nginx -s reload
```

## 配置说明

### 负载均衡策略

**多服务器部署（nginx.conf）：**

- **upstream api_backend**：后端为 `192.168.1.10:8080` 与 `192.168.1.11:8080`，请按实际 IP/端口修改。

**单机部署（nginx.conf.single-host）：**

- **upstream api_backend**：后端为 `api1:8080` 与 `api2:8080`（Docker容器名称），无需修改。

**通用配置：**

- **max_fails=2 fail_timeout=30s**：连续 2 次失败则摘除该节点 30 秒，之后自动恢复。
- **策略**：
  - 默认轮询（round_robin）
  - 会话保持：取消注释 `ip_hash`
  - 加权轮询：使用 `weight` 参数
  - 最少连接：使用 `least_conn`

### SSL/HTTPS配置

1. **申请证书**（使用提供的脚本）：

```bash
chmod +x ssl-setup.sh
sudo ./ssl-setup.sh api.example.com your-email@example.com
```

1. **修改nginx.conf**：
   - 将 `server_name _;` 改为实际域名
   - 确保SSL证书路径正确

2. **重启容器**：

```bash
docker-compose restart nginx
```

### 监控和日志

**使用监控脚本**：

```bash
chmod +x monitor.sh
./monitor.sh              # 运行一次检查
./monitor.sh --watch      # 实时监控模式
```

**查看日志**：

```bash
# 访问日志
tail -f logs/access.log

# 错误日志
tail -f logs/error.log

# Docker容器日志
docker-compose logs -f nginx
```

## 验证

- 多次请求 `http://<nginx-ip>/`，观察 `upstream=` 在 access 日志中在两根后端间轮换。
- 停掉一台 API 后，应只转发到另一台；恢复后应重新参与轮询。
- 使用监控脚本检查系统状态：`./monitor.sh`

## 高级功能

配置文件已包含以下高级功能（可根据需要启用/禁用）：

- ✅ SSL/HTTPS支持（Let's Encrypt）
- ✅ 限流配置（防止DDoS）
- ✅ 缓存配置（提升性能）
- ✅ Gzip压缩
- ✅ 安全头设置
- ✅ 多种负载均衡策略
- ✅ 健康检查
- ✅ 详细日志记录

详细配置说明请参考 `nginx.conf` 中的注释。

## 故障排查

遇到问题？请参考：

1. [SETUP_GUIDE.md](SETUP_GUIDE.md) 中的"故障排查"章节
2. 使用监控脚本诊断：`./monitor.sh`
3. 查看Nginx错误日志：`tail -f logs/error.log`
