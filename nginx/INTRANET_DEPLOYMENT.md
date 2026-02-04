# 内网部署指南

本指南介绍如何在内网服务器（无公网IP）上部署Nginx负载均衡方案。

## ✅ 完全可以部署

内网服务器完全可以部署和使用Nginx负载均衡方案，只需要注意以下几点：

## 🏗️ 内网部署特点

### 优势

- ✅ 无需公网IP，内网访问即可
- ✅ 安全性更高（不暴露到公网）
- ✅ 适合企业内部部署
- ✅ 可以使用单机部署方案
- ✅ 完全本地化，不受网络限制

### 限制

- ⚠️ 无法从外网直接访问
- ⚠️ Let's Encrypt证书申请需要公网访问（可使用自签名证书）
- ⚠️ 需要通过内网IP或域名访问

## 🚀 快速开始

### 步骤1：确认服务器信息

```bash
# 查看内网IP地址
ip addr show
# 或
ifconfig

# 查看Docker是否安装
docker --version
docker-compose --version
```

### 步骤2：部署服务

```bash
# 进入nginx目录
cd nginx/

# 使用单机部署方案（推荐）
docker-compose -f docker-compose.single-host.yml up -d

# 查看服务状态
docker-compose -f docker-compose.single-host.yml ps
```

### 步骤3：访问服务

```bash
# 使用内网IP访问（替换为实际IP）
curl http://192.168.1.100/health

# 或使用localhost（在服务器本地）
curl http://localhost/health
```

## 🔒 SSL/HTTPS配置（内网）

### 方案1：使用自签名证书（推荐用于内网）

```bash
# 创建SSL目录
mkdir -p nginx/ssl

# 生成自签名证书
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/privkey.pem \
  -out nginx/ssl/fullchain.pem \
  -subj "/C=CN/ST=State/L=City/O=Organization/CN=localhost"

# 修改nginx.conf.single-host，启用HTTPS配置
# 取消注释HTTPS server块，并设置证书路径
```

### 方案2：跳过HTTPS（最简单）

内网环境可以只使用HTTP，无需HTTPS：

```nginx
# 在nginx.conf.single-host中，只保留HTTP server块
# 注释掉或删除HTTPS server块
```

### 方案3：使用内网CA签发的证书

如果有内网CA，可以使用CA签发的证书：

```bash
# 将CA签发的证书放到nginx/ssl/目录
cp your-cert.pem nginx/ssl/fullchain.pem
cp your-key.pem nginx/ssl/privkey.pem
```

## 📝 配置示例

### 内网IP访问配置

编辑 `nginx.conf.single-host`：

```nginx
server {
    listen 80;
    # 可以设置为内网IP或内网域名
    server_name 192.168.1.100 localhost;
    
    # ... 其他配置
}
```

### Docker Compose端口映射

如果需要从其他内网机器访问，确保端口映射正确：

```yaml
services:
  nginx:
    ports:
      - "80:80"      # HTTP端口
      - "443:443"    # HTTPS端口（如果使用）
    # 如果需要绑定到特定IP
    # ports:
    #   - "192.168.1.100:80:80"
```

## 🔍 访问方式

### 方式1：服务器本地访问

```bash
# 在服务器上直接访问
curl http://localhost/health
curl http://127.0.0.1/health
```

### 方式2：内网其他机器访问

```bash
# 使用内网IP访问（替换为实际IP）
curl http://192.168.1.100/health

# 浏览器访问
http://192.168.1.100
```

### 方式3：使用内网域名

如果有内网DNS，可以配置域名：

```bash
# 在/etc/hosts中添加（客户端机器）
192.168.1.100  api.internal.company.com

# 然后访问
curl http://api.internal.company.com/health
```

## 🛠️ 常见场景

### 场景1：开发测试环境

```bash
# 完全本地化，只在本机访问
docker-compose -f docker-compose.single-host.yml up -d
curl http://localhost/health
```

### 场景2：内网服务器供团队使用

```bash
# 1. 确认服务器内网IP
ip addr show

# 2. 启动服务
docker-compose -f docker-compose.single-host.yml up -d

# 3. 配置防火墙（如果需要）
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload

# 4. 团队成员通过内网IP访问
# http://192.168.1.100
```

### 场景3：通过SSH隧道访问

如果服务器只能通过SSH访问：

```bash
# 在本地机器上建立SSH隧道
ssh -L 8080:localhost:80 user@192.168.1.100

# 然后在本地浏览器访问
# http://localhost:8080
```

## ⚙️ 防火墙配置

### CentOS/RHEL (firewalld)

```bash
# 开放HTTP端口
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload

# 查看开放的端口
sudo firewall-cmd --list-ports
```

### Ubuntu (ufw)

```bash
# 开放HTTP端口
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

### iptables

```bash
# 开放HTTP端口
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo service iptables save
```

## 🔐 安全建议

### 1. 内网访问控制

```nginx
# 限制访问来源（只允许特定内网段）
location / {
    allow 192.168.1.0/24;  # 允许内网段
    deny all;              # 拒绝其他
    
    proxy_pass http://api_backend;
    # ... 其他配置
}
```

### 2. 使用自签名证书时的浏览器警告

自签名证书会在浏览器中显示警告，这是正常的：

- 点击"高级" → "继续访问"即可
- 或者将证书添加到系统信任列表

### 3. 日志监控

```bash
# 监控访问日志
tail -f nginx/logs/access.log

# 查看异常访问
grep -E " 4[0-9]{2} | 5[0-9]{2} " nginx/logs/access.log
```

## 📊 验证部署

### 1. 检查服务状态

```bash
# 查看所有容器
docker-compose -f docker-compose.single-host.yml ps

# 查看Nginx日志
docker-compose -f docker-compose.single-host.yml logs nginx

# 查看API服务日志
docker-compose -f docker-compose.single-host.yml logs api1
```

### 2. 测试负载均衡

```bash
# 多次请求，观察日志中的upstream轮换
for i in {1..10}; do
    curl -s http://localhost/health
    sleep 0.5
done

# 查看日志
tail -f nginx/logs/access.log | grep upstream
```

### 3. 测试故障转移

```bash
# 停止一个API容器
docker stop api-service-1

# 请求应该仍然正常（转发到api2）
curl http://localhost/health

# 恢复容器
docker start api-service-1
```

## 🎯 总结

内网部署完全可行，主要区别：

| 项目 | 公网部署 | 内网部署 |
|------|---------|---------|
| 访问方式 | 公网IP/域名 | 内网IP/内网域名 |
| SSL证书 | Let's Encrypt | 自签名证书或内网CA |
| 安全性 | 需要严格防护 | 相对安全 |
| 适用场景 | 生产环境 | 开发/测试/内网环境 |

## 📚 相关文档

- [单机部署指南](SINGLE_HOST_DEPLOYMENT.md) - 单机部署详细步骤
- [完整搭建指南](SETUP_GUIDE.md) - 多服务器部署指南
- [README.md](README.md) - 快速使用指南

---

**提示**：内网部署非常适合学习和测试，无需担心公网安全问题，可以放心实验各种配置！
