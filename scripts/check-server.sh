#!/bin/bash

# 🔍 服务器环境检查脚本
# 用途: 检查服务器是否满足部署要求

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    WARNINGS=$((WARNINGS + 1))
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    ERRORS=$((ERRORS + 1))
}

echo "==================================="
echo "🔍 服务器环境检查"
echo "==================================="
echo ""

# 检查操作系统
echo "📋 操作系统信息:"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "  系统: $NAME $VERSION"
    log_success "操作系统检测完成"
else
    log_warning "无法识别操作系统"
fi
echo ""

# 检查 Docker
echo "🐳 Docker 检查:"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo "  版本: $DOCKER_VERSION"
    log_success "Docker 已安装"

    # 检查 Docker 服务状态
    if systemctl is-active --quiet docker 2>/dev/null; then
        log_success "Docker 服务运行中"
    else
        log_error "Docker 服务未运行"
    fi

    # 检查 Docker 权限
    if docker ps &> /dev/null; then
        log_success "Docker 权限正常"
    else
        log_error "Docker 权限不足，需要 sudo 或将用户添加到 docker 组"
    fi
else
    log_error "Docker 未安装"
fi
echo ""

# 检查 Docker Compose
echo "📦 Docker Compose 检查:"
if command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version)
    echo "  版本: $COMPOSE_VERSION"
    log_success "docker-compose 已安装"
elif docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version)
    echo "  版本: $COMPOSE_VERSION"
    log_success "docker compose (v2) 已安装"
else
    log_warning "Docker Compose 未安装（可自动安装）"
fi
echo ""

# 检查端口占用
echo "🔌 端口检查:"
PORTS=(3000)
for PORT in "${PORTS[@]}"; do
    if ss -tuln 2>/dev/null | grep -q ":$PORT " || netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
        log_warning "端口 $PORT 已被占用"
    else
        log_success "端口 $PORT 可用"
    fi
done
echo ""

# 检查磁盘空间
echo "💾 磁盘空间检查:"
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
echo "  可用空间: $DISK_AVAIL"
echo "  使用率: ${DISK_USAGE}%"

if [ "$DISK_USAGE" -lt 80 ]; then
    log_success "磁盘空间充足"
elif [ "$DISK_USAGE" -lt 90 ]; then
    log_warning "磁盘空间不足 (${DISK_USAGE}%)"
else
    log_error "磁盘空间严重不足 (${DISK_USAGE}%)"
fi
echo ""

# 检查内存
echo "🧠 内存检查:"
if command -v free &> /dev/null; then
    TOTAL_MEM=$(free -h | awk 'NR==2 {print $2}')
    AVAIL_MEM=$(free -h | awk 'NR==2 {print $7}')
    echo "  总内存: $TOTAL_MEM"
    echo "  可用内存: $AVAIL_MEM"
    log_success "内存信息正常"
else
    log_warning "无法检测内存信息"
fi
echo ""

# 检查网络连接
echo "🌐 网络连接检查:"
if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
    log_success "外网连接正常"
else
    log_warning "外网连接异常"
fi

if ping -c 1 -W 2 registry-1.docker.io &> /dev/null; then
    log_success "Docker Hub 可达"
else
    log_warning "Docker Hub 连接异常（可使用镜像加速）"
fi
echo ""

# 检查必要的命令
echo "🛠️  命令工具检查:"
REQUIRED_CMDS=("curl" "git")
OPTIONAL_CMDS=("jq" "wget")

for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" &> /dev/null; then
        log_success "$cmd 已安装"
    else
        log_error "$cmd 未安装（必需）"
    fi
done

for cmd in "${OPTIONAL_CMDS[@]}"; do
    if command -v "$cmd" &> /dev/null; then
        log_success "$cmd 已安装"
    else
        log_warning "$cmd 未安装（可选）"
    fi
done
echo ""

# 检查防火墙
echo "🔥 防火墙检查:"
if command -v ufw &> /dev/null; then
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        echo "  UFW 防火墙: 已启用"
        for PORT in "${PORTS[@]}"; do
            if ufw status 2>/dev/null | grep -q "$PORT"; then
                log_success "端口 $PORT 已在防火墙中开放"
            else
                log_warning "端口 $PORT 未在 UFW 中开放"
            fi
        done
    else
        log_success "UFW 防火墙未启用"
    fi
elif command -v firewall-cmd &> /dev/null; then
    if firewall-cmd --state 2>/dev/null | grep -q "running"; then
        echo "  Firewalld: 已启用"
        log_warning "请确保端口 ${PORTS[*]} 已开放"
    else
        log_success "Firewalld 未启用"
    fi
else
    log_success "未检测到防火墙"
fi
echo ""

# 总结
echo "==================================="
echo "📊 检查总结"
echo "==================================="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    log_success "所有检查通过！服务器环境就绪"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  检查完成，有 $WARNINGS 个警告${NC}"
    exit 0
else
    echo -e "${RED}❌ 检查失败，有 $ERRORS 个错误和 $WARNINGS 个警告${NC}"
    exit 1
fi
