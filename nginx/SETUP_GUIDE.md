# Nginx从零到一完整搭建服务器集群指南

本指南将帮助您从零开始搭建一个完整的Nginx负载均衡服务器集群，适用于CentOS/RHEL系统，使用Docker部署，包含SSL/HTTPS配置。

## 目录

1. [前置准备](#1-前置准备)
2. [Docker环境搭建](#2-docker环境搭建)
3. [Nginx容器部署](#3-nginx容器部署)
4. [负载均衡配置详解](#4-负载均衡配置详解)
5. [SSL/HTTPS配置](#5-sslhttps配置)
6. [高级配置](#6-高级配置)
7. [监控和日志](#7-监控和日志)
8. [验证和测试](#8-验证和测试)
9. [故障排查](#9-故障排查)
10. [生产环境优化](#10-生产环境优化)

---

## 1. 前置准备

### 1.1 服务器环境要求

- **操作系统**: CentOS 7/8/9 或 RHEL 7/8/9
- **CPU**: 至少 2 核
- **内存**: 至少 2GB RAM
- **磁盘**: 至少 20GB 可用空间
- **网络**: 公网IP（用于SSL证书申请）或内网IP（用于内网负载均衡）

### 1.2 网络架构规划

典型的负载均衡架构：

```
                    ┌─────────────┐
                    │   Nginx LB  │  (负载均衡器)
                    │  10.0.0.10  │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
       ┌─────────────┐           ┌─────────────┐
       │  API #1     │           │  API #2     │
       │ 10.0.0.11   │           │ 10.0.0.12   │
       │   :8080     │           │   :8080     │
       └─────────────┘           └─────────────┘
```

**IP分配示例**:
- Nginx负载均衡器: `10.0.0.10`
- API服务器1: `10.0.0.11:8080`
- API服务器2: `10.0.0.12:8080`
- 域名（如需要）: `api.example.com`

### 1.3 防火墙配置

#### CentOS 7/8 (firewalld)

```bash
# 检查firewalld状态
sudo systemctl status firewalld

# 如果未启动，启动firewalld
sudo systemctl start firewalld
sudo systemctl enable firewalld

# 开放HTTP和HTTPS端口
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# 验证端口开放
sudo firewall-cmd --list-all
```

#### CentOS 6 或使用iptables

```bash
# 开放HTTP和HTTPS端口
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo service iptables save
```

### 1.4 SSH访问和基础安全设置

```bash
# 更新系统
sudo yum update -y

# 安装基础工具
sudo yum install -y wget curl vim net-tools

# 配置SSH密钥认证（推荐）
# 在本地生成密钥对
ssh-keygen -t rsa -b 4096

# 复制公钥到服务器
ssh-copy-id root@your-server-ip

# 禁用密码登录（可选，更安全）
sudo vim /etc/ssh/sshd_config
# 设置: PasswordAuthentication no
sudo systemctl restart sshd
```

---

## 2. Docker环境搭建

### 2.1 安装Docker Engine

#### CentOS 7

```bash
# 卸载旧版本（如果有）
sudo yum remove -y docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine

# 安装必要的依赖
sudo yum install -y yum-utils device-mapper-persistent-data lvm2

# 添加Docker官方仓库
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 安装Docker CE
sudo yum install -y docker-ce docker-ce-cli containerd.io

# 启动Docker服务
sudo systemctl start docker
sudo systemctl enable docker

# 验证安装
sudo docker --version
sudo docker run hello-world
```

#### CentOS 8/9

```bash
# 卸载旧版本
sudo yum remove -y docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine

# 安装必要的依赖
sudo yum install -y yum-utils

# 添加Docker官方仓库
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 安装Docker CE
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 启动Docker服务
sudo systemctl start docker
sudo systemctl enable docker

# 验证安装
sudo docker --version
sudo docker run hello-world
```

### 2.2 安装Docker Compose

#### 方法一：使用Docker Compose插件（推荐，CentOS 8/9）

```bash
# 已在上面安装docker-compose-plugin
docker compose version
```

#### 方法二：独立安装Docker Compose（CentOS 7）

```bash
# 下载最新版本的Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# 添加执行权限
sudo chmod +x /usr/local/bin/docker-compose

# 创建符号链接（可选）
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# 验证安装
docker-compose --version
```

### 2.3 Docker网络配置

```bash
# 查看Docker网络
sudo docker network ls

# 创建自定义网络（可选，用于多容器通信）
sudo docker network create nginx-network

# 查看网络详情
sudo docker network inspect nginx-network
```

### 2.4 验证Docker环境

```bash
# 检查Docker服务状态
sudo systemctl status docker

# 测试Docker命令
sudo docker ps
sudo docker images

# 测试Docker Compose
docker-compose --version  # 或 docker compose version
```

---

## 3. Nginx容器部署

### 3.1 创建项目目录结构

```bash
# 创建项目目录
sudo mkdir -p /opt/nginx-lb/{conf,logs,ssl,html}

# 设置权限
sudo chown -R $USER:$USER /opt/nginx-lb
cd /opt/nginx-lb
```

### 3.2 准备Nginx配置文件

将项目中的 `nginx.conf` 复制到配置目录：

```bash
# 复制nginx配置文件
cp /path/to/your/project/nginx/nginx.conf /opt/nginx-lb/conf/nginx.conf

# 编辑配置文件，修改后端服务器IP
vim /opt/nginx-lb/conf/nginx.conf
```

### 3.3 创建Docker Compose配置

创建 `docker-compose.yml` 文件（见下一节详细配置）：

```bash
vim /opt/nginx-lb/docker-compose.yml
```

### 3.4 启动Nginx容器

```bash
# 进入项目目录
cd /opt/nginx-lb

# 使用Docker Compose启动
docker-compose up -d

# 查看容器状态
docker-compose ps

# 查看日志
docker-compose logs -f nginx
```

### 3.5 验证容器运行

```bash
# 检查容器是否运行
sudo docker ps | grep nginx

# 测试HTTP访问
curl http://localhost

# 检查Nginx配置
sudo docker exec nginx-lb-nginx-1 nginx -t
```

---

## 4. 负载均衡配置详解

### 4.1 Upstream配置详解

#### 轮询（Round Robin）- 默认方式

```nginx
upstream api_backend {
    server 192.168.1.10:8080 max_fails=2 fail_timeout=30s;
    server 192.168.1.11:8080 max_fails=2 fail_timeout=30s;
}
```

#### 加权轮询（Weighted Round Robin）

```nginx
upstream api_backend {
    server 192.168.1.10:8080 weight=3 max_fails=2 fail_timeout=30s;
    server 192.168.1.11:8080 weight=2 max_fails=2 fail_timeout=30s;
    server 192.168.1.12:8080 weight=1 max_fails=2 fail_timeout=30s;
}
```

#### IP哈希（会话保持）

```nginx
upstream api_backend {
    ip_hash;
    server 192.168.1.10:8080 max_fails=2 fail_timeout=30s;
    server 192.168.1.11:8080 max_fails=2 fail_timeout=30s;
}
```

#### 最少连接（Least Connections）

```nginx
upstream api_backend {
    least_conn;
    server 192.168.1.10:8080 max_fails=2 fail_timeout=30s;
    server 192.168.1.11:8080 max_fails=2 fail_timeout=30s;
}
```

### 4.2 健康检查机制

- **max_fails**: 连续失败次数，超过后标记为不可用
- **fail_timeout**: 失败超时时间，之后重新尝试
- **backup**: 标记为备用服务器，仅当所有主服务器不可用时使用
- **down**: 永久标记为不可用

```nginx
upstream api_backend {
    server 192.168.1.10:8080 max_fails=3 fail_timeout=30s;
    server 192.168.1.11:8080 max_fails=3 fail_timeout=30s backup;
    server 192.168.1.12:8080 down;  # 临时下线
}
```

### 4.3 代理头设置

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Port $server_port;
```

### 4.4 超时和连接池配置

```nginx
proxy_connect_timeout 10s;      # 连接超时
proxy_send_timeout 60s;         # 发送超时
proxy_read_timeout 60s;         # 读取超时
proxy_buffering on;             # 启用缓冲
proxy_buffer_size 4k;           # 缓冲区大小
proxy_buffers 8 4k;             # 缓冲区数量和大小
```

### 4.5 日志配置

```nginx
log_format detailed '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'upstream=$upstream_addr '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

access_log /var/log/nginx/access.log detailed;
error_log /var/log/nginx/error.log warn;
```

---

## 5. SSL/HTTPS配置

### 5.1 安装Certbot

```bash
# CentOS 7
sudo yum install -y epel-release
sudo yum install -y certbot python3-certbot-nginx

# CentOS 8/9
sudo dnf install -y certbot python3-certbot-nginx
```

### 5.2 申请SSL证书

#### 方法一：使用Certbot自动配置（推荐用于非Docker环境）

```bash
# 确保域名已解析到服务器IP
# 申请证书（需要先停止Nginx容器或使用standalone模式）
sudo certbot certonly --standalone -d api.example.com

# 证书将保存在 /etc/letsencrypt/live/api.example.com/
```

#### 方法二：使用提供的脚本（见 ssl-setup.sh）

```bash
# 使用项目提供的SSL设置脚本
chmod +x /opt/nginx-lb/ssl-setup.sh
sudo ./ssl-setup.sh api.example.com your-email@example.com
```

### 5.3 配置Nginx SSL

在 `nginx.conf` 中添加SSL配置（详见更新后的配置文件）：

```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    
    # SSL优化配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 其他配置...
}

# HTTP重定向到HTTPS
server {
    listen 80;
    server_name api.example.com;
    return 301 https://$server_name$request_uri;
}
```

### 5.4 证书自动续期

```bash
# 测试续期
sudo certbot renew --dry-run

# 设置自动续期（certbot已自动配置systemd timer）
sudo systemctl status certbot.timer

# 手动续期
sudo certbot renew

# 续期后重启Nginx容器
docker-compose restart nginx
```

### 5.5 证书挂载到Docker容器

在 `docker-compose.yml` 中添加证书卷挂载：

```yaml
volumes:
  - ./ssl:/etc/nginx/ssl:ro
  - /etc/letsencrypt:/etc/letsencrypt:ro
```

---

## 6. 高级配置

### 6.1 限流配置

```nginx
# 在http块中定义限流区域
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

server {
    location / {
        limit_req zone=api_limit burst=20 nodelay;
        proxy_pass http://api_backend;
    }
}
```

### 6.2 缓存配置

```nginx
# 定义缓存路径
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=api_cache:10m max_size=1g 
                 inactive=60m use_temp_path=off;

server {
    location / {
        proxy_cache api_cache;
        proxy_cache_valid 200 302 10m;
        proxy_cache_valid 404 1m;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_background_update on;
        proxy_cache_lock on;
        
        proxy_pass http://api_backend;
    }
}
```

### 6.3 压缩配置

```nginx
gzip on;
gzip_vary on;
gzip_min_length 1000;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml text/javascript 
           application/json application/javascript application/xml+rss 
           application/rss+xml font/truetype font/opentype 
           application/vnd.ms-fontobject image/svg+xml;
```

### 6.4 安全头设置

```nginx
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;
add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

---

## 7. 监控和日志

### 7.1 访问日志分析

```bash
# 查看实时访问日志
tail -f /opt/nginx-lb/logs/access.log

# 统计访问最多的IP
awk '{print $1}' /opt/nginx-lb/logs/access.log | sort | uniq -c | sort -rn | head -10

# 统计HTTP状态码
awk '{print $9}' /opt/nginx-lb/logs/access.log | sort | uniq -c | sort -rn

# 查看错误请求
grep -E " 4[0-9]{2} | 5[0-9]{2} " /opt/nginx-lb/logs/access.log
```

### 7.2 错误日志监控

```bash
# 查看错误日志
tail -f /opt/nginx-lb/logs/error.log

# 统计错误类型
grep -i error /opt/nginx-lb/logs/error.log | awk '{print $4}' | sort | uniq -c
```

### 7.3 健康检查端点

确保后端API提供健康检查端点（如 `/health`），Nginx配置中已包含：

```nginx
location /health {
    proxy_pass http://api_backend;
    access_log off;
}
```

### 7.4 使用监控脚本

使用项目提供的 `monitor.sh` 脚本：

```bash
chmod +x /opt/nginx-lb/monitor.sh
./monitor.sh
```

---

## 8. 验证和测试

### 8.1 负载均衡轮询验证

```bash
# 多次请求，观察后端服务器轮换
for i in {1..10}; do
    curl -s http://your-nginx-ip/ | grep -o "upstream=[^ ]*" || echo "Request $i"
    sleep 1
done

# 查看访问日志确认轮询
tail -f /opt/nginx-lb/logs/access.log | grep upstream
```

### 8.2 健康检查故障转移测试

```bash
# 1. 停止一台后端服务器
# 在API服务器1上
sudo systemctl stop your-api-service

# 2. 观察Nginx日志，应该看到错误
tail -f /opt/nginx-lb/logs/error.log

# 3. 继续请求，应该只转发到健康的服务器
curl http://your-nginx-ip/

# 4. 恢复服务器
sudo systemctl start your-api-service

# 5. 等待fail_timeout后，服务器应重新加入负载均衡
```

### 8.3 SSL证书验证

```bash
# 检查SSL证书
openssl s_client -connect api.example.com:443 -servername api.example.com

# 使用在线工具验证
# https://www.ssllabs.com/ssltest/

# 测试HTTPS访问
curl -v https://api.example.com
```

### 8.4 性能测试

```bash
# 使用ab (Apache Bench)
ab -n 1000 -c 10 http://your-nginx-ip/

# 使用wrk
wrk -t4 -c100 -d30s http://your-nginx-ip/

# 使用curl测试响应时间
curl -o /dev/null -s -w "Time: %{time_total}s\n" http://your-nginx-ip/
```

---

## 9. 故障排查

### 9.1 常见问题诊断

#### 问题1: 容器无法启动

```bash
# 查看容器日志
docker-compose logs nginx

# 检查配置文件语法
docker exec nginx-lb-nginx-1 nginx -t

# 检查端口占用
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443
```

#### 问题2: 502 Bad Gateway

```bash
# 检查后端服务器是否可达
curl http://192.168.1.10:8080/health

# 检查防火墙规则
sudo firewall-cmd --list-all

# 查看Nginx错误日志
tail -50 /opt/nginx-lb/logs/error.log
```

#### 问题3: SSL证书问题

```bash
# 检查证书文件是否存在
ls -la /opt/nginx-lb/ssl/

# 检查证书有效期
openssl x509 -in /opt/nginx-lb/ssl/fullchain.pem -noout -dates

# 检查证书挂载
docker exec nginx-lb-nginx-1 ls -la /etc/nginx/ssl/
```

### 9.2 日志查看方法

```bash
# 实时查看访问日志
docker-compose logs -f nginx

# 查看错误日志
tail -f /opt/nginx-lb/logs/error.log

# 查看Docker容器日志
docker logs nginx-lb-nginx-1 -f
```

### 9.3 网络连通性检查

```bash
# 从Nginx容器ping后端服务器
docker exec nginx-lb-nginx-1 ping -c 3 192.168.1.10

# 测试端口连通性
docker exec nginx-lb-nginx-1 nc -zv 192.168.1.10 8080

# 检查DNS解析
docker exec nginx-lb-nginx-1 nslookup api.example.com
```

### 9.4 容器调试技巧

```bash
# 进入容器内部
docker exec -it nginx-lb-nginx-1 /bin/bash

# 在容器内测试配置
nginx -t

# 在容器内查看进程
ps aux

# 在容器内查看网络连接
netstat -tlnp
```

---

## 10. 生产环境优化

### 10.1 性能调优参数

在 `nginx.conf` 的 `http` 块中添加：

```nginx
# Worker进程优化
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    # 连接优化
    keepalive_timeout 65;
    keepalive_requests 100;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    
    # 缓冲优化
    client_body_buffer_size 128k;
    client_max_body_size 10m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    
    # 超时优化
    client_body_timeout 12;
    client_header_timeout 12;
    send_timeout 10;
}
```

### 10.2 安全加固建议

1. **隐藏Nginx版本信息**
```nginx
server_tokens off;
```

2. **限制请求方法**
```nginx
if ($request_method !~ ^(GET|HEAD|POST|PUT|DELETE|OPTIONS)$ ) {
    return 405;
}
```

3. **防止DDoS攻击**
```nginx
limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;
limit_req_zone $binary_remote_addr zone=req_limit_per_ip:10m rate=5r/s;

server {
    limit_conn conn_limit_per_ip 10;
    limit_req zone=req_limit_per_ip burst=10 nodelay;
}
```

4. **禁止访问隐藏文件**
```nginx
location ~ /\. {
    deny all;
    access_log off;
    log_not_found off;
}
```

### 10.3 备份和恢复策略

```bash
# 备份配置文件
tar -czf nginx-backup-$(date +%Y%m%d).tar.gz \
    /opt/nginx-lb/conf/ \
    /opt/nginx-lb/docker-compose.yml

# 备份SSL证书
sudo tar -czf ssl-backup-$(date +%Y%m%d).tar.gz \
    /opt/nginx-lb/ssl/ \
    /etc/letsencrypt/

# 设置自动备份（添加到crontab）
0 2 * * * tar -czf /backup/nginx-$(date +\%Y\%m\%d).tar.gz /opt/nginx-lb/
```

### 10.4 高可用方案（Keepalived）

对于生产环境，建议使用Keepalived实现Nginx负载均衡器的高可用：

```bash
# 安装Keepalived
sudo yum install -y keepalived

# 配置Keepalived（主节点）
sudo vim /etc/keepalived/keepalived.conf
```

Keepalived配置示例：

```conf
vrrp_script chk_nginx {
    script "/usr/bin/curl -f http://localhost/health || exit 1"
    interval 2
    weight -2
    fall 3
    rise 2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 101
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass your_password
    }
    virtual_ipaddress {
        10.0.0.100/24
    }
    track_script {
        chk_nginx
    }
}
```

---

## 总结

通过本指南，您已经完成了：

1. ✅ 服务器环境准备和防火墙配置
2. ✅ Docker和Docker Compose安装
3. ✅ Nginx负载均衡容器部署
4. ✅ SSL/HTTPS证书配置
5. ✅ 高级功能配置（限流、缓存、压缩等）
6. ✅ 监控和日志管理
7. ✅ 故障排查方法
8. ✅ 生产环境优化建议

## 下一步

- 根据实际需求调整负载均衡策略
- 配置监控告警系统（如Prometheus + Grafana）
- 实施日志收集和分析（如ELK Stack）
- 考虑实施高可用方案（Keepalived）
- 定期进行安全审计和性能优化

## 参考资源

- [Nginx官方文档](https://nginx.org/en/docs/)
- [Docker官方文档](https://docs.docker.com/)
- [Let's Encrypt文档](https://letsencrypt.org/docs/)
- [Certbot文档](https://certbot.eff.org/docs/)

---

**最后更新**: 2024年
**维护者**: 项目团队
