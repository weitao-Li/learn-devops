# 🚀 部署指南

## 📋 目录

- [概述](#概述)
- [架构说明](#架构说明)
- [优化内容](#优化内容)
- [环境准备](#环境准备)
- [部署流程](#部署流程)
- [故障排查](#故障排查)
- [回滚策略](#回滚策略)

## 概述

本项目使用 GitHub Actions 实现全自动 CI/CD 流程，包括代码测试、Docker 镜像构建、推送和自动部署。

### 技术栈

- **CI/CD**: GitHub Actions
- **容器化**: Docker + Docker Compose
- **部署方式**: SSH 远程部署
- **镜像仓库**: Docker Hub

## 架构说明

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│   GitHub    │─────>│GitHub Actions│─────>│   服务器    │
│ Push/PR     │      │   Pipeline   │      │   Docker    │
└─────────────┘      └──────────────┘      └─────────────┘
                             │
                             │
                     ┌───────┴────────┐
                     │                │
                  ┌──▼──┐         ┌──▼──┐
                  │Test │         │Build│
                  └──┬──┘         └──┬──┘
                     │               │
                     └───────┬───────┘
                             │
                         ┌───▼────┐
                         │ Deploy │
                         └────────┘
```

## 优化内容

### 🎯 主要问题修复

#### 1. 文件下载超时问题
**问题**: curl 从 GitHub 下载 docker-compose.yml 耗时 6+ 分钟
**解决方案**:
- 使用 `appleboy/scp-action` 直接传输文件
- 传输时间从 6+ 分钟降至 < 5 秒

#### 2. Docker 镜像拉取失败
**问题**: 
- Docker Hub 连接超时 (`context deadline exceeded`)
- 镜像加速器返回 403 错误
- 没有重试机制

**解决方案**:
- 配置多个镜像加速器（daocloud, 腾讯云, 南京大学）
- 实现智能重试机制（最多 3 次，每次等待 10 秒）
- 增加超时时间到 300 秒
- 自动检测并配置镜像加速

#### 3. docker-compose 命令不存在
**问题**: 服务器使用 Docker Compose v2，命令为 `docker compose`

**解决方案**:
- 自动检测可用的 compose 命令
- 支持 `docker-compose` 和 `docker compose` 两种方式
- 如果都不存在，自动下载安装

#### 4. 缺少健康检查和回滚机制
**问题**: 部署失败时没有自动回滚，可能导致服务中断

**解决方案**:
- 实现完整的健康检查（最多等待 60 秒）
- 支持 Docker 原生健康检查和 HTTP 端点检查
- 部署失败自动回滚到旧版本
- 保留旧镜像用于快速回滚

### 🔧 其他优化

#### 性能优化
- 并发下载限制提升到 10
- 实现镜像层缓存
- 清理策略：保留最新 3 个版本
- 资源限制：CPU 1核，内存 512MB

#### 安全优化
- 使用严格模式 (`set -euo pipefail`)
- 密码通过 stdin 传递，不在进程列表中暴露
- 日志文件大小限制（10MB × 3 个文件）

#### 可维护性优化
- 模块化部署脚本
- 彩色日志输出
- 详细的错误信息
- 服务器环境检查脚本

## 环境准备

### 1. 服务器要求

- **操作系统**: Ubuntu 20.04+ / Debian 10+ / CentOS 7+
- **Docker**: 20.10+
- **内存**: 最小 512MB，推荐 1GB+
- **磁盘**: 最小 5GB 可用空间
- **端口**: 3000 需要开放

### 2. 检查服务器环境

首次部署前，运行环境检查脚本：

```bash
# 上传检查脚本到服务器
scp scripts/check-server.sh user@server:~/

# 在服务器上执行
ssh user@server 'bash ~/check-server.sh'
```

### 3. GitHub Secrets 配置

在 GitHub 仓库设置中添加以下 Secrets：

| Secret 名称 | 说明 | 示例 |
|------------|------|------|
| `SERVER_IP` | 服务器 IP 地址 | `192.168.1.100` |
| `SERVER_USER` | SSH 用户名 | `ubuntu` |
| `SERVER_PASSWORD` | SSH 密码（可选） | `your-password` |
| `SSH_PRIVATE_KEY` | SSH 私钥（推荐） | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `DOCKER_USERNAME` | Docker Hub 用户名 | `your-username` |
| `DOCKER_PASSWORD` | Docker Hub 密码/Token | `your-token` |

**推荐**: 使用 SSH 密钥而非密码

生成 SSH 密钥：
```bash
ssh-keygen -t ed25519 -C "github-actions"
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server
cat ~/.ssh/id_ed25519  # 复制私钥到 GitHub Secrets
```

## 部署流程

### 自动部署（推荐）

推送到 main 分支自动触发部署：

```bash
git add .
git commit -m "feat: add new feature"
git push origin main
```

### 手动部署

如果需要手动部署，可以直接使用部署脚本：

```bash
# 1. 上传脚本和配置文件
scp scripts/deploy.sh user@server:~/ci-demo/
scp docker-compose.yml user@server:~/ci-demo/

# 2. 执行部署
ssh user@server 'bash ~/ci-demo/deploy.sh wli007/ci-demo:latest ~/ci-demo'
```

### 部署阶段说明

#### 1️⃣ Test (测试)
- 拉取代码
- 安装依赖
- 运行测试

#### 2️⃣ Build (构建)
- 构建 Docker 镜像
- 推送到 Docker Hub
- 生成多个标签：
  - `latest`: 最新版本
  - `{sha}`: Git commit hash
  - `{date}`: 构建时间戳

#### 3️⃣ Deploy (部署)
- 传输配置文件
- 连接服务器
- 配置镜像加速
- 拉取最新镜像
- 停止旧容器
- 启动新容器
- 健康检查
- 清理旧镜像

## 故障排查

### 问题 1: 镜像拉取超时

**症状**: `context deadline exceeded`

**解决方案**:
```bash
# 手动配置镜像加速
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://mirror.ccs.tencentyun.com"
  ]
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

### 问题 2: 端口被占用

**症状**: `bind: address already in use`

**解决方案**:
```bash
# 查找占用端口的进程
sudo ss -tulpn | grep :3000

# 停止占用的进程
sudo docker stop <container-id>
# 或
sudo kill <pid>
```

### 问题 3: 容器健康检查失败

**症状**: 容器启动后立即退出

**解决方案**:
```bash
# 查看容器日志
docker logs ci-demo-app

# 查看详细信息
docker inspect ci-demo-app

# 进入容器调试
docker exec -it ci-demo-app sh
```

### 问题 4: 磁盘空间不足

**症状**: `no space left on device`

**解决方案**:
```bash
# 清理未使用的 Docker 资源
docker system prune -af

# 查看磁盘使用情况
docker system df

# 清理特定资源
docker image prune -af      # 清理镜像
docker container prune -f   # 清理容器
docker volume prune -f      # 清理卷
```

### 问题 5: SSH 连接失败

**症状**: `Permission denied` 或 `Connection timeout`

**解决方案**:
```bash
# 测试 SSH 连接
ssh -v user@server

# 检查防火墙
sudo ufw status
sudo ufw allow 22

# 检查 SSH 服务
sudo systemctl status sshd
```

## 回滚策略

### 自动回滚

部署脚本会在以下情况自动回滚：
- 镜像拉取失败
- 容器启动失败
- 健康检查失败

### 手动回滚

如果需要手动回滚到特定版本：

```bash
# 1. 查看可用的镜像标签
docker images wli007/ci-demo

# 2. 修改 docker-compose.yml
# 将 image: wli007/ci-demo:latest
# 改为 image: wli007/ci-demo:<specific-tag>

# 3. 重新部署
docker compose down
docker compose up -d
```

或者使用 GitHub Actions 回滚：

```bash
# 1. 找到之前成功的 commit
git log --oneline

# 2. 重新部署该版本
git revert HEAD
git push origin main

# 或者直接推送旧版本
git reset --hard <old-commit>
git push -f origin main  # 谨慎使用
```

## 监控和维护

### 日志查看

```bash
# 实时日志
docker compose logs -f

# 最近 100 行
docker compose logs --tail=100

# 特定时间范围
docker compose logs --since 10m
```

### 资源监控

```bash
# 查看容器资源使用
docker stats ci-demo-app

# 查看容器详情
docker inspect ci-demo-app

# 查看健康状态
docker inspect --format='{{.State.Health.Status}}' ci-demo-app
```

### 定期维护

建议每周执行：

```bash
# 清理旧镜像和容器
docker system prune -f

# 更新系统
sudo apt update && sudo apt upgrade -y

# 检查磁盘空间
df -h

# 检查日志大小
du -sh /var/lib/docker
```

## 最佳实践

### 1. 版本管理
- 使用语义化版本号
- 每次发布打标签
- 保留多个历史版本

### 2. 安全性
- 定期更新依赖
- 使用非 root 用户运行容器
- 启用 Docker Content Trust
- 定期轮换密钥和密码

### 3. 性能优化
- 使用多阶段构建减小镜像大小
- 启用构建缓存
- 配置资源限制
- 使用健康检查

### 4. 监控告警
- 集成监控系统（Prometheus, Grafana）
- 配置告警通知
- 记录关键指标

## 相关资源

- [GitHub Actions 文档](https://docs.github.com/actions)
- [Docker 官方文档](https://docs.docker.com/)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [项目仓库](https://github.com/weitao-Li/learn-devops)

## 联系方式

如有问题或建议，请提交 Issue 或 Pull Request。
