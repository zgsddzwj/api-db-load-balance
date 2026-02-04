# Nginx API 负载均衡

将 2 台 API 服务器放入同一 upstream，对外单一入口，轮询分发并带健康检查。

## 文件说明

| 文件 | 说明 |
|------|------|
| `nginx.conf` | Nginx主配置文件，包含负载均衡、SSL、限流、缓存等完整配置 |
| `docker-compose.yml` | Docker Compose配置文件，用于容器化部署 |
| `SETUP_GUIDE.md` | **完整搭建指南**，从零到一详细步骤（推荐先阅读） |
| `ssl-setup.sh` | SSL证书申请和配置脚本（Let's Encrypt） |
| `monitor.sh` | 监控脚本，用于健康检查、日志分析、性能统计 |

## 快速开始

### 方式一：使用完整指南（推荐）

**首次部署请先阅读 [SETUP_GUIDE.md](SETUP_GUIDE.md)**，包含：
- 服务器环境准备
- Docker环境搭建
- Nginx容器部署
- SSL/HTTPS配置
- 高级功能配置
- 监控和故障排查

### 方式二：Docker Compose部署（快速）

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

- **upstream api_backend**：后端为 `192.168.1.10:8080` 与 `192.168.1.11:8080`，请按实际 IP/端口修改。
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

2. **修改nginx.conf**：
   - 将 `server_name _;` 改为实际域名
   - 确保SSL证书路径正确

3. **重启容器**：
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
