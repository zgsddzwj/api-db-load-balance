#!/bin/bash

# Nginx负载均衡监控脚本
# 功能: 健康检查、日志监控、性能统计

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
NGINX_CONTAINER="nginx-lb"
LOG_DIR="./logs"
ACCESS_LOG="$LOG_DIR/access.log"
ERROR_LOG="$LOG_DIR/error.log"
HEALTH_CHECK_URL="http://localhost/health"
ALERT_EMAIL=""  # 可选: 设置告警邮箱

# 检查函数
check_nginx_status() {
    echo -e "${BLUE}=== Nginx状态检查 ===${NC}"
    
    if command -v docker &> /dev/null; then
        if docker ps | grep -q "$NGINX_CONTAINER"; then
            echo -e "${GREEN}✓ Nginx容器运行中${NC}"
            docker ps | grep "$NGINX_CONTAINER"
        else
            echo -e "${RED}✗ Nginx容器未运行${NC}"
            return 1
        fi
    else
        if systemctl is-active --quiet nginx; then
            echo -e "${GREEN}✓ Nginx服务运行中${NC}"
        else
            echo -e "${RED}✗ Nginx服务未运行${NC}"
            return 1
        fi
    fi
    echo ""
}

check_nginx_config() {
    echo -e "${BLUE}=== Nginx配置检查 ===${NC}"
    
    if command -v docker &> /dev/null; then
        if docker exec "$NGINX_CONTAINER" nginx -t 2>&1 | grep -q "successful"; then
            echo -e "${GREEN}✓ Nginx配置正确${NC}"
        else
            echo -e "${RED}✗ Nginx配置有错误${NC}"
            docker exec "$NGINX_CONTAINER" nginx -t
            return 1
        fi
    else
        if nginx -t 2>&1 | grep -q "successful"; then
            echo -e "${GREEN}✓ Nginx配置正确${NC}"
        else
            echo -e "${RED}✗ Nginx配置有错误${NC}"
            nginx -t
            return 1
        fi
    fi
    echo ""
}

check_backend_health() {
    echo -e "${BLUE}=== 后端服务器健康检查 ===${NC}"
    
    # 从nginx.conf提取后端服务器
    if [ -f "./nginx.conf" ]; then
        BACKENDS=$(grep -E "server\s+[0-9]" ./nginx.conf | grep -v "^#" | awk '{print $2}' | cut -d: -f1)
        
        for backend in $BACKENDS; do
            if ping -c 1 -W 2 "$backend" &> /dev/null; then
                echo -e "${GREEN}✓ $backend 可达${NC}"
            else
                echo -e "${RED}✗ $backend 不可达${NC}"
            fi
        done
    else
        echo -e "${YELLOW}警告: 未找到nginx.conf文件${NC}"
    fi
    echo ""
}

check_health_endpoint() {
    echo -e "${BLUE}=== 健康检查端点测试 ===${NC}"
    
    if curl -f -s "$HEALTH_CHECK_URL" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 健康检查端点正常: $HEALTH_CHECK_URL${NC}"
        RESPONSE_TIME=$(curl -o /dev/null -s -w "%{time_total}" "$HEALTH_CHECK_URL")
        echo "  响应时间: ${RESPONSE_TIME}s"
    else
        echo -e "${RED}✗ 健康检查端点异常: $HEALTH_CHECK_URL${NC}"
        return 1
    fi
    echo ""
}

analyze_access_log() {
    echo -e "${BLUE}=== 访问日志分析 ===${NC}"
    
    if [ ! -f "$ACCESS_LOG" ]; then
        echo -e "${YELLOW}警告: 访问日志文件不存在: $ACCESS_LOG${NC}"
        echo ""
        return
    fi
    
    # 统计时间范围（最近1小时）
    SINCE=$(date -d '1 hour ago' '+%d/%b/%Y:%H:%M:%S' 2>/dev/null || date -v-1H '+%d/%b/%Y:%H:%M:%S' 2>/dev/null || echo "")
    
    echo "最近1小时统计:"
    
    # 总请求数
    TOTAL_REQUESTS=$(wc -l < "$ACCESS_LOG" 2>/dev/null || echo "0")
    echo "  总请求数: $TOTAL_REQUESTS"
    
    # HTTP状态码统计
    echo "  HTTP状态码分布:"
    awk '{print $9}' "$ACCESS_LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -5 | while read count code; do
        echo "    $code: $count"
    done
    
    # 最活跃的IP
    echo "  最活跃的IP (Top 5):"
    awk '{print $1}' "$ACCESS_LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -5 | while read count ip; do
        echo "    $ip: $count 次请求"
    done
    
    # 最常访问的URL
    echo "  最常访问的URL (Top 5):"
    awk '{print $7}' "$ACCESS_LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -5 | while read count url; do
        echo "    $url: $count 次"
    done
    
    # 平均响应时间（如果日志包含响应时间）
    if grep -q "rt=" "$ACCESS_LOG" 2>/dev/null; then
        AVG_RT=$(awk -F'rt=' '{print $2}' "$ACCESS_LOG" 2>/dev/null | awk '{print $1}' | awk '{sum+=$1; count++} END {if(count>0) print sum/count; else print 0}')
        echo "  平均响应时间: ${AVG_RT}s"
    fi
    
    echo ""
}

analyze_error_log() {
    echo -e "${BLUE}=== 错误日志分析 ===${NC}"
    
    if [ ! -f "$ERROR_LOG" ]; then
        echo -e "${YELLOW}警告: 错误日志文件不存在: $ERROR_LOG${NC}"
        echo ""
        return
    fi
    
    # 最近错误数
    RECENT_ERRORS=$(tail -100 "$ERROR_LOG" 2>/dev/null | wc -l)
    echo "最近100行错误数: $RECENT_ERRORS"
    
    # 错误类型统计
    if [ "$RECENT_ERRORS" -gt 0 ]; then
        echo "错误类型分布:"
        tail -100 "$ERROR_LOG" 2>/dev/null | grep -i "error" | awk '{print $4}' | sort | uniq -c | sort -rn | head -5 | while read count type; do
            echo "  $type: $count"
        done
        
        # 显示最近的错误
        echo "最近的错误:"
        tail -5 "$ERROR_LOG" 2>/dev/null | while read line; do
            echo -e "  ${RED}$line${NC}"
        done
    else
        echo -e "${GREEN}✓ 最近无错误${NC}"
    fi
    
    echo ""
}

check_ssl_certificate() {
    echo -e "${BLUE}=== SSL证书检查 ===${NC}"
    
    SSL_CERT="./ssl/fullchain.pem"
    
    if [ -f "$SSL_CERT" ]; then
        # 检查证书有效期
        EXPIRY_DATE=$(openssl x509 -in "$SSL_CERT" -noout -enddate 2>/dev/null | cut -d= -f2)
        EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null || echo "0")
        CURRENT_EPOCH=$(date +%s)
        DAYS_LEFT=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))
        
        if [ "$DAYS_LEFT" -gt 30 ]; then
            echo -e "${GREEN}✓ SSL证书有效${NC}"
            echo "  到期时间: $EXPIRY_DATE"
            echo "  剩余天数: $DAYS_LEFT 天"
        elif [ "$DAYS_LEFT" -gt 0 ]; then
            echo -e "${YELLOW}⚠ SSL证书即将到期${NC}"
            echo "  到期时间: $EXPIRY_DATE"
            echo "  剩余天数: $DAYS_LEFT 天"
        else
            echo -e "${RED}✗ SSL证书已过期${NC}"
            echo "  到期时间: $EXPIRY_DATE"
        fi
    else
        echo -e "${YELLOW}警告: 未找到SSL证书文件${NC}"
    fi
    
    echo ""
}

check_disk_usage() {
    echo -e "${BLUE}=== 磁盘使用检查 ===${NC}"
    
    DISK_USAGE=$(df -h . | tail -1 | awk '{print $5}' | sed 's/%//')
    echo "当前目录磁盘使用率: ${DISK_USAGE}%"
    
    if [ "$DISK_USAGE" -gt 90 ]; then
        echo -e "${RED}✗ 磁盘使用率过高${NC}"
    elif [ "$DISK_USAGE" -gt 80 ]; then
        echo -e "${YELLOW}⚠ 磁盘使用率较高${NC}"
    else
        echo -e "${GREEN}✓ 磁盘使用率正常${NC}"
    fi
    
    # 日志文件大小
    if [ -f "$ACCESS_LOG" ]; then
        LOG_SIZE=$(du -h "$ACCESS_LOG" | cut -f1)
        echo "访问日志大小: $LOG_SIZE"
    fi
    
    echo ""
}

performance_stats() {
    echo -e "${BLUE}=== 性能统计 ===${NC}"
    
    if command -v docker &> /dev/null; then
        # Docker容器资源使用
        echo "容器资源使用:"
        docker stats --no-stream "$NGINX_CONTAINER" 2>/dev/null | tail -1 | awk '{print "  CPU: " $3 ", 内存: " $4 ", 网络: " $7 "/" $10}'
    fi
    
    # 连接数统计
    if command -v netstat &> /dev/null; then
        CONNECTIONS=$(netstat -an | grep :80 | grep ESTABLISHED | wc -l)
        echo "  当前ESTABLISHED连接数 (80端口): $CONNECTIONS"
    elif command -v ss &> /dev/null; then
        CONNECTIONS=$(ss -an | grep :80 | grep ESTAB | wc -l)
        echo "  当前ESTABLISHED连接数 (80端口): $CONNECTIONS"
    fi
    
    echo ""
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Nginx负载均衡监控报告${NC}"
    echo -e "${GREEN}  时间: $(date)${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    check_nginx_status
    check_nginx_config
    check_backend_health
    check_health_endpoint
    check_ssl_certificate
    analyze_access_log
    analyze_error_log
    check_disk_usage
    performance_stats
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}监控报告完成${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# 实时监控模式
watch_mode() {
    echo -e "${GREEN}进入实时监控模式 (按Ctrl+C退出)${NC}"
    while true; do
        clear
        main
        sleep 5
    done
}

# 参数处理
case "${1:-}" in
    --watch|-w)
        watch_mode
        ;;
    --help|-h)
        echo "使用方法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  -w, --watch    实时监控模式（每5秒刷新）"
        echo "  -h, --help     显示帮助信息"
        echo ""
        echo "默认: 运行一次监控检查"
        ;;
    *)
        main
        ;;
esac
