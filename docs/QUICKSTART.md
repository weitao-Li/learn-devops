# 🚀 快速开始指南

## 📝 前置条件

- ✅ GitHub 账号
- ✅ Docker Hub 账号
- ✅ 一台服务器（Ubuntu/Debian/CentOS）
- ✅ 服务器已安装 Docker

## ⚡ 5 分钟快速部署

### 步骤 1: Fork 或 Clone 项目

```bash
git clone https://github.com/weitao-Li/learn-devops.git
cd learn-devops
```

### 步骤 2: 配置 GitHub Secrets

进入 GitHub 仓库 → Settings → Secrets and variables → Actions，添加以下 Secrets：

| Secret | 说明 | 获取方式 |
|--------|------|----------|
| `SERVER_IP` | 服务器 IP | `curl ifconfig.me` (在服务器上运行) |
| `SERVER_USER` | SSH 用户名 | 通常是 `ubuntu`, `root` 等 |
| `SSH_PRIVATE_KEY` | SSH 私钥 | 见下方 "生成 SSH 密钥" |
| `DOCKER_USERNAME` | Docker Hub 用户名 | [Docker Hub](https://hub.docker.com/) 注册 |
| `DOCKER_PASSWORD` | Docker Hub Token | Docker Hub → Account Settings → Security → New Access Token |

#### 生成 SSH 密钥

**在本地机器上执行**:

```bash
# 1. 生成新的 SSH 密钥对
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_actions

# 2. 将公钥复制到服务器
ssh-copy-id -i ~/.ssh/github_actions.pub user@your-server-ip

# 3. 测试连接
ssh -i ~/.ssh/github_actions user@your-server-ip

# 4. 复制私钥内容
cat ~/.ssh/github_actions
# 将输出的全部内容（包括 BEGIN 和 END 行）复制到 GitHub Secrets 的 SSH_PRIVATE_KEY
```

### 步骤 3: 检查服务器环境

**在服务器上执行**:

```bash
# 下载检查脚本
curl -o check-server.sh https://raw.githubusercontent.com/weitao-Li/learn-devops/main/scripts/check-server.sh

# 运行检查
bash check-server.sh
```

如果检查通过，继续下一步。如果有错误，按照提示修复。

### 步骤 4: 修改配置

#### 1. 修改 Docker 镜像名称

编辑 [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml):

```yaml
env:
  IMAGE_NAME: your-dockerhub-username/your-app-name  # 改为你的 Docker Hub 用户名和应用名
```

编辑 [`docker-compose.yml`](docker-compose.yml):

```yaml
services:
  app:
    image: your-dockerhub-username/your-app-name:latest  # 改为你的镜像名
```

#### 2. (可选) 修改端口

如果 3000 端口已被占用，修改 `docker-compose.yml`:

```yaml
ports:
  - "8080:3000"  # 改为 8080 或其他端口
```

### 步骤 5: 推送并部署

```bash
# 1. 提交修改
git add .
git commit -m "chore: update configuration"

# 2. 推送到 GitHub（触发自动部署）
git push origin main
```

### 步骤 6: 查看部署状态

1. 进入 GitHub 仓库页面
2. 点击 "Actions" 标签
3. 查看最新的 workflow 运行状态

![GitHub Actions](https://docs.github.com/assets/images/help/repository/actions-quickstart-nav-ci.png)

### 步骤 7: 验证部署

部署完成后，访问你的服务器：

```bash
# 方式 1: 浏览器访问
http://your-server-ip:3000

# 方式 2: curl 测试
curl http://your-server-ip:3000
```

应该看到类似输出：
```
Hello from Docker!
```

---

## 🎉 恭喜！部署完成

现在每次你推送代码到 `main` 分支，都会自动触发部署流程。

---

## 🔧 故障排查

### 问题 1: Actions 提示 "SSH connection failed"

**解决方案**:
```bash
# 检查 SSH 是否可以连接
ssh -i ~/.ssh/github_actions user@your-server-ip

# 确保私钥格式正确（包括开始和结束行）
-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----
```

### 问题 2: "Permission denied (publickey)"

**解决方案**:
```bash
# 在服务器上检查 authorized_keys
cat ~/.ssh/authorized_keys

# 如果为空，重新复制公钥
ssh-copy-id -i ~/.ssh/github_actions.pub user@server
```

### 问题 3: "Docker pull failed"

**解决方案**:
```bash
# 在服务器上手动测试
docker pull your-dockerhub-username/your-app-name:latest

# 如果失败，检查 Docker Hub 认证
docker login

# 配置镜像加速
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io"
  ]
}
EOF
sudo systemctl restart docker
```

### 问题 4: "Port already in use"

**解决方案**:
```bash
# 查找占用端口的进程
sudo ss -tulpn | grep :3000

# 停止占用的容器
docker ps
docker stop <container-id>

# 或修改 docker-compose.yml 使用其他端口
```

### 问题 5: 健康检查失败

**解决方案**:
```bash
# 查看容器日志
docker logs ci-demo-app

# 查看容器状态
docker ps -a

# 进入容器调试
docker exec -it ci-demo-app sh
```

---

## 📚 下一步

### 学习资源
- 📖 [完整部署文档](DEPLOYMENT.md)
- ⚡ [优化说明](OPTIMIZATION.md)
- 🐳 [Docker 官方文档](https://docs.docker.com/)
- 🔧 [GitHub Actions 文档](https://docs.github.com/actions)

### 进阶功能
- 🔵 [配置蓝绿部署](DEPLOYMENT.md#蓝绿部署)
- 🐤 [配置金丝雀发布](DEPLOYMENT.md#金丝雀发布)
- 📊 [添加监控告警](DEPLOYMENT.md#监控告警)
- 🌍 [多环境部署](DEPLOYMENT.md#多环境支持)

### 自定义部署
你可以修改以下文件来自定义部署流程：
- [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) - CI/CD 流程
- [`docker-compose.yml`](docker-compose.yml) - 容器配置
- [`scripts/deploy.sh`](scripts/deploy.sh) - 部署脚本

---

## 💡 提示和技巧

### 技巧 1: 本地测试部署脚本

在推送到 GitHub 之前，可以先本地测试：

```bash
# 1. 上传脚本到服务器
scp scripts/deploy.sh user@server:~/
scp docker-compose.yml user@server:~/ci-demo/

# 2. 在服务器上测试
ssh user@server
cd ~/ci-demo
bash ../deploy.sh your-image-name
```

### 技巧 2: 查看实时日志

```bash
# SSH 到服务器
ssh user@server

# 实时查看日志
cd ~/ci-demo
docker compose logs -f
```

### 技巧 3: 手动回滚

如果需要回滚到之前的版本：

```bash
# 查看可用的镜像
docker images your-username/your-app

# 修改 docker-compose.yml 中的镜像标签
# 然后重新部署
docker compose down
docker compose up -d
```

### 技巧 4: 定期维护

建议每周执行一次清理：

```bash
# 清理未使用的 Docker 资源
docker system prune -af

# 查看磁盘使用情况
docker system df
```

---

## 🆘 获取帮助

遇到问题？

1. 📖 查看 [完整文档](DEPLOYMENT.md)
2. 🔍 查看 [常见问题](DEPLOYMENT.md#故障排查)
3. 🐛 [提交 Issue](https://github.com/weitao-Li/learn-devops/issues)
4. 💬 [讨论区](https://github.com/weitao-Li/learn-devops/discussions)

---

## ✅ 检查清单

部署前确认：

- [ ] GitHub Secrets 已配置完整
- [ ] SSH 密钥可以连接到服务器
- [ ] 服务器已安装 Docker
- [ ] 服务器端口 3000 未被占用
- [ ] Docker Hub 账号可以正常登录
- [ ] 镜像名称已修改为你的 Docker Hub 用户名

全部完成后，推送代码即可触发自动部署！

Happy Deploying! 🚀
