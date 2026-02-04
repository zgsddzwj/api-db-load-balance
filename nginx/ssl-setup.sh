#!/bin/bash

# SSL证书申请和配置脚本
# 使用方法: ./ssl-setup.sh <domain> <email>
# 示例: ./ssl-setup.sh api.example.com admin@example.com

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查参数
if [ $# -lt 2 ]; then
    echo -e "${RED}错误: 缺少参数${NC}"
    echo "使用方法: $0 <domain> <email>"
    echo "示例: $0 api.example.com admin@example.com"
    exit 1
fi

DOMAIN=$1
EMAIL=$2
SSL_DIR="./ssl"
NGINX_CONF="./nginx.conf"

echo -e "${GREEN}开始SSL证书设置流程...${NC}"
echo "域名: $DOMAIN"
echo "邮箱: $EMAIL"
echo ""

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}警告: 建议使用sudo运行此脚本${NC}"
fi

# 检查certbot是否安装
if ! command -v certbot &> /dev/null; then
    echo -e "${YELLOW}Certbot未安装，正在安装...${NC}"
    
    # 检测系统类型
    if [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        if command -v dnf &> /dev/null; then
            sudo dnf install -y epel-release
            sudo dnf install -y certbot
        elif command -v yum &> /dev/null; then
            sudo yum install -y epel-release
            sudo yum install -y certbot
        fi
    elif [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y certbot
    else
        echo -e "${RED}错误: 无法检测系统类型，请手动安装certbot${NC}"
        exit 1
    fi
fi

# 创建SSL目录
mkdir -p "$SSL_DIR"
echo -e "${GREEN}✓ SSL目录已创建: $SSL_DIR${NC}"

# 检查域名解析
echo -e "${YELLOW}检查域名解析...${NC}"
DOMAIN_IP=$(dig +short $DOMAIN @8.8.8.8 | tail -n1)
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)

if [ -z "$DOMAIN_IP" ]; then
    echo -e "${RED}错误: 无法解析域名 $DOMAIN${NC}"
    echo "请确保域名已正确配置DNS记录"
    exit 1
fi

echo "域名解析IP: $DOMAIN_IP"
echo "服务器IP: $SERVER_IP"

if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
    echo -e "${YELLOW}警告: 域名解析IP与服务器IP不匹配${NC}"
    echo "域名解析IP: $DOMAIN_IP"
    echo "服务器IP: $SERVER_IP"
    read -p "是否继续? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 停止Nginx容器（如果运行中）
echo -e "${YELLOW}检查Nginx容器状态...${NC}"
if command -v docker-compose &> /dev/null; then
    if docker-compose ps | grep -q "nginx"; then
        echo "停止Nginx容器以释放80端口..."
        docker-compose stop nginx || true
        NGINX_STOPPED=true
    fi
elif command -v docker &> /dev/null; then
    if docker ps | grep -q "nginx-lb"; then
        echo "停止Nginx容器以释放80端口..."
        docker stop nginx-lb || true
        NGINX_STOPPED=true
    fi
fi

# 申请证书
echo -e "${GREEN}开始申请SSL证书...${NC}"
echo "这可能需要几分钟时间..."

sudo certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN" \
    --preferred-challenges http

if [ $? -ne 0 ]; then
    echo -e "${RED}错误: 证书申请失败${NC}"
    exit 1
fi

# 复制证书到项目目录
echo -e "${GREEN}复制证书文件...${NC}"
sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem "$SSL_DIR/"
sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem "$SSL_DIR/"
sudo chown $USER:$USER "$SSL_DIR"/*.pem
sudo chmod 644 "$SSL_DIR"/fullchain.pem
sudo chmod 600 "$SSL_DIR"/privkey.pem

echo -e "${GREEN}✓ 证书文件已复制到 $SSL_DIR${NC}"

# 设置证书自动续期脚本
echo -e "${GREEN}配置证书自动续期...${NC}"
RENEW_SCRIPT="/etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh"
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy

sudo tee "$RENEW_SCRIPT" > /dev/null <<EOF
#!/bin/bash
# 证书续期后重新加载Nginx
cd $(pwd)
if command -v docker-compose &> /dev/null; then
    docker-compose exec -T nginx nginx -s reload || docker-compose restart nginx
elif command -v docker &> /dev/null; then
    docker exec nginx-lb nginx -s reload || docker restart nginx-lb
fi

# 复制新证书到项目目录
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem $SSL_DIR/
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem $SSL_DIR/
chown $USER:$USER $SSL_DIR/*.pem
chmod 644 $SSL_DIR/fullchain.pem
chmod 600 $SSL_DIR/privkey.pem
EOF

sudo chmod +x "$RENEW_SCRIPT"
echo -e "${GREEN}✓ 自动续期脚本已配置${NC}"

# 测试证书续期
echo -e "${YELLOW}测试证书续期...${NC}"
sudo certbot renew --dry-run

# 恢复Nginx容器（如果之前停止了）
if [ "$NGINX_STOPPED" = true ]; then
    echo -e "${YELLOW}恢复Nginx容器...${NC}"
    if command -v docker-compose &> /dev/null; then
        docker-compose start nginx
    elif command -v docker &> /dev/null; then
        docker start nginx-lb
    fi
fi

# 检查nginx.conf是否包含SSL配置
echo -e "${YELLOW}检查Nginx配置...${NC}"
if [ -f "$NGINX_CONF" ]; then
    if grep -q "ssl_certificate" "$NGINX_CONF"; then
        echo -e "${GREEN}✓ Nginx配置已包含SSL设置${NC}"
    else
        echo -e "${YELLOW}警告: Nginx配置文件中未找到SSL配置${NC}"
        echo "请确保nginx.conf中包含以下配置:"
        echo "  ssl_certificate /etc/nginx/ssl/fullchain.pem;"
        echo "  ssl_certificate_key /etc/nginx/ssl/privkey.pem;"
    fi
else
    echo -e "${YELLOW}警告: 未找到nginx.conf文件${NC}"
fi

# 显示证书信息
echo ""
echo -e "${GREEN}=== SSL证书设置完成 ===${NC}"
echo "证书文件位置:"
echo "  完整链: $SSL_DIR/fullchain.pem"
echo "  私钥: $SSL_DIR/privkey.pem"
echo ""
echo "证书有效期:"
sudo openssl x509 -in "$SSL_DIR/fullchain.pem" -noout -dates
echo ""
echo -e "${GREEN}下一步:${NC}"
echo "1. 确保nginx.conf中已配置SSL（监听443端口）"
echo "2. 重启Nginx容器: docker-compose restart nginx"
echo "3. 测试HTTPS访问: curl -I https://$DOMAIN"
echo "4. 证书将在到期前自动续期"
echo ""
