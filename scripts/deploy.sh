#!/bin/bash

# 🚀 CI/CD 部署脚本
# 用途: 在远程服务器上部署 Docker 应用
# 使用: ./deploy.sh <image_name> [project_dir]

set -euo pipefail  # 严格模式

# 配置变量
IMAGE_NAME="${1:-}"
PROJECT_DIR="${2:-~/ci-demo}"
HEALTH_CHECK_URL="http://localhost:3000"
MAX_HEALTH_CHECK_WAIT=60
DOCKER_PULL_TIMEOUT=300
MAX_RETRY=3

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 重试函数
retry_command() {
    local cmd="$@"
    local attempt=1

    while [ $attempt -le $MAX_RETRY ]; do
        log_info "尝试 $attempt/$MAX_RETRY: $cmd"
        if timeout $DOCKER_PULL_TIMEOUT $cmd; then
            return 0
        fi
        log_warning "失败，等待10秒后重试..."
        sleep 10
        attempt=$((attempt + 1))
    done

    log_error "命令失败: $cmd"
    return 1
}

# 检查必要参数
if [ -z "$IMAGE_NAME" ]; then
    log_error "用法: $0 <image_name> [project_dir]"
    exit 1
fi

log_info "开始部署 $IMAGE_NAME 到 $PROJECT_DIR"

# 进入项目目录
cd "$PROJECT_DIR" || {
    log_error "无法进入目录: $PROJECT_DIR"
    exit 1
}

# 检测 docker compose 命令
detect_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        log_error "docker compose 未安装"
        log_info "正在安装 docker compose..."

        # 尝试安装 docker compose
        if curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /tmp/docker-compose; then
            sudo mv /tmp/docker-compose /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            echo "docker-compose"
        else
            log_error "安装 docker compose 失败"
            exit 1
        fi
    fi
}

COMPOSE_CMD=$(detect_compose_cmd)
log_info "使用命令: $COMPOSE_CMD"

# 配置 Docker 镜像加速
configure_docker_mirror() {
    if [ ! -f /etc/docker/daemon.json ] || ! grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
        log_info "配置 Docker 镜像加速..."

        sudo mkdir -p /etc/docker
        sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://mirror.ccs.tencentyun.com",
    "https://docker.nju.edu.cn"
  ],
  "max-concurrent-downloads": 10,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

        sudo systemctl daemon-reload 2>/dev/null || true
        sudo systemctl restart docker 2>/dev/null || true
        sleep 5
        log_success "Docker 镜像加速配置完成"
    fi
}

# 如果是首次部署，配置镜像加速
if [ ! -f .deploy_initialized ]; then
    configure_docker_mirror
    touch .deploy_initialized
fi

# 保存当前状态用于回滚
log_info "保存当前状态..."
OLD_IMAGE_ID=$(docker images -q "$IMAGE_NAME" 2>/dev/null || echo "")
BACKUP_CONTAINER=$(docker ps -q -f name=ci-demo-app 2>/dev/null || echo "")

if [ -n "$OLD_IMAGE_ID" ]; then
    log_info "当前镜像ID: $OLD_IMAGE_ID"
else
    log_warning "未找到旧镜像"
fi

# 拉取最新镜像
log_info "拉取最新镜像: $IMAGE_NAME"
if ! retry_command docker pull "$IMAGE_NAME"; then
    log_error "镜像拉取失败"
    exit 1
fi

# 验证镜像
NEW_IMAGE_ID=$(docker images -q "$IMAGE_NAME" 2>/dev/null)
if [ -z "$NEW_IMAGE_ID" ]; then
    log_error "镜像验证失败"
    exit 1
fi

log_success "镜像拉取成功: $NEW_IMAGE_ID"

# 检查镜像是否有变化
if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ]; then
    log_warning "镜像未更新，跳过部署"
    # 但仍然检查容器状态
    if ! docker ps | grep -q ci-demo-app; then
        log_warning "容器未运行，重新启动..."
    else
        log_success "容器运行正常"
        exit 0
    fi
fi

# 停止旧容器
log_info "停止旧容器..."
$COMPOSE_CMD down --remove-orphans 2>/dev/null || true

# 启动新容器
log_info "启动新容器..."
if ! $COMPOSE_CMD up -d; then
    log_error "容器启动失败"

    # 回滚
    if [ -n "$BACKUP_CONTAINER" ]; then
        log_warning "尝试恢复旧容器..."
        docker start "$BACKUP_CONTAINER" 2>/dev/null || true
    fi
    exit 1
fi

log_success "容器启动成功"

# 健康检查
log_info "执行健康检查..."
ELAPSED=0
HEALTH_PASSED=false

while [ $ELAPSED -lt $MAX_HEALTH_CHECK_WAIT ]; do
    # 检查容器是否运行
    if ! docker ps | grep -q ci-demo-app; then
        log_error "容器已停止"
        break
    fi

    # 检查健康状态
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' ci-demo-app 2>/dev/null || echo "none")

    if [ "$HEALTH_STATUS" = "healthy" ]; then
        log_success "容器健康检查通过"
        HEALTH_PASSED=true
        break
    elif [ "$HEALTH_STATUS" = "none" ]; then
        # 如果没有配置健康检查，直接测试端口
        if curl -f -m 5 "$HEALTH_CHECK_URL" >/dev/null 2>&1; then
            log_success "服务响应正常"
            HEALTH_PASSED=true
            break
        fi
    fi

    echo -n "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""

# 健康检查结果处理
if [ "$HEALTH_PASSED" = false ]; then
    log_error "健康检查失败"

    # 显示日志
    log_info "容器日志:"
    $COMPOSE_CMD logs --tail=50

    # 回滚
    log_warning "回滚部署..."
    $COMPOSE_CMD down 2>/dev/null || true

    if [ -n "$OLD_IMAGE_ID" ] && [ "$OLD_IMAGE_ID" != "$NEW_IMAGE_ID" ]; then
        log_info "恢复旧镜像..."
        docker tag "$OLD_IMAGE_ID" "$IMAGE_NAME" 2>/dev/null || true
        $COMPOSE_CMD up -d 2>/dev/null || true
    fi

    exit 1
fi

# 清理旧镜像（保留最新3个版本）
log_info "清理旧镜像..."
docker images "$IMAGE_NAME" --format "{{.ID}}" | tail -n +4 | xargs -r docker rmi -f 2>/dev/null || true
docker image prune -f >/dev/null 2>&1 || true

# 显示部署信息
log_success "部署完成！"
echo ""
log_info "容器状态:"
$COMPOSE_CMD ps
echo ""
log_info "最近日志:"
$COMPOSE_CMD logs --tail=20
echo ""
log_success "部署成功完成！"
