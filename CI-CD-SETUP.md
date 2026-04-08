# 🚀 完整 CI/CD 配置指南

## 📋 前置准备

### 1. 你需要的账号和服务器

✅ **GitHub 账号** - 已有（你的仓库：weitao-li/learn-devops）  
✅ **Docker Hub 账号** - 已有（用户名配置在 secrets 中）  
✅ **一台服务器** - 需要准备（云服务器或本地服务器）

---

## 🔐 配置 GitHub Secrets（重要！）

进入你的 GitHub 仓库：

```
https://github.com/weitao-li/learn-devops/settings/secrets/actions
```

### 方式一：使用 SSH 密钥（推荐 ⭐）

#### 步骤 1：在本地生成 SSH 密钥对

```bash
# 生成专用的 SSH 密钥
ssh-keygen -t rsa -b 4096 -C "github-actions-deploy" -f ~/.ssh/github_deploy_key

# 按提示操作：
# 1. 直接按回车（不设置密码更方便 CI/CD 使用）
# 2. 会生成两个文件：
#    - github_deploy_key      (私钥)
#    - github_deploy_key.pub  (公钥)
```

#### 步骤 2：将公钥添加到服务器

```bash
# 方法 A：使用 ssh-copy-id（推荐）
ssh-copy-id -i ~/.ssh/github_deploy_key.pub root@你的服务器IP

# 方法 B：手动复制
cat ~/.ssh/github_deploy_key.pub
# 复制输出的内容，然后：
ssh root@你的服务器IP
echo "复制的公钥内容" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

#### 步骤 3：测试 SSH 连接

```bash
ssh -i ~/.ssh/github_deploy_key root@你的服务器IP
# 如果能登录成功，说明配置正确
```

#### 步骤 4：将私钥添加到 GitHub Secrets

```bash
# 查看私钥内容
cat ~/.ssh/github_deploy_key
```

复制**全部内容**（包括 `-----BEGIN...` 和 `-----END...`），然后在 GitHub 添加：

| Secret Name | Value |
|------------|-------|
| `SSH_PRIVATE_KEY` | 粘贴完整私钥内容 |
| `SERVER_IP` | 你的服务器 IP（如：`47.100.200.50`） |
| `SERVER_USER` | `root`（或你的用户名如 `ubuntu`） |

---

### 方式二：使用密码（简单但不安全）

如果你不想配置密钥，可以直接用密码：

| Secret Name | Value |
|------------|-------|
| `SERVER_IP` | 你的服务器 IP |
| `SERVER_USER` | `root` 或你的用户名 |
| `SERVER_PASSWORD` | 你的服务器登录密码 |

⚠️ **注意**：密码方式不如密钥安全，生产环境建议用密钥！

---

## 📸 完整的 Secrets 列表

配置完成后，你的 **Repository secrets** 应该有这些：

### 必须配置（4个）

| Secret Name | 说明 | 示例值 |
|------------|------|--------|
| `DOCKER_USERNAME` | Docker Hub 用户名 | `wli007` |
| `DOCKER_PASSWORD` | Docker Hub 密码/Token | `dckr_pat_xxxxx...` |
| `SERVER_IP` | 服务器 IP 地址 | `47.100.200.50` |
| `SERVER_USER` | 服务器登录用户 | `root` |

### 选择其一（1个）

| Secret Name | 说明 | 推荐度 |
|------------|------|--------|
| `SSH_PRIVATE_KEY` | SSH 私钥完整内容 | ⭐⭐⭐⭐⭐ 强烈推荐 |
| `SERVER_PASSWORD` | 服务器登录密码 | ⭐⭐ 简单但不安全 |

---

## 🖥️ 服务器环境准备

### 1. 安装 Docker

```bash
# 登录你的服务器
ssh root@你的服务器IP

# 安装 Docker（Ubuntu/Debian）
curl -fsSL https://get.docker.com | bash

# 启动 Docker
systemctl start docker
systemctl enable docker

# 验证安装
docker --version
```

### 2. 安装 Docker Compose

```bash
# 下载 Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# 添加执行权限
chmod +x /usr/local/bin/docker-compose

# 验证安装
docker-compose --version
```

### 3. 配置防火墙（如果有）

```bash
# 开放 3000 端口
ufw allow 3000/tcp

# 或者 CentOS/RHEL
firewall-cmd --permanent --add-port=3000/tcp
firewall-cmd --reload
```

---

## 🎯 使用流程

### 1. 推送代码触发部署

```bash
# 在本地修改代码
echo "console.log('Updated!');" >> app.js

# 提交并推送
git add .
git commit -m "Update app"
git push origin main
```

### 2. 查看部署进度

访问：`https://github.com/weitao-li/learn-devops/actions`

你会看到 4 个阶段：
- 🧪 **测试阶段** - 运行单元测试
- 🏗️ **构建阶段** - 构建 Docker 镜像
- 🚀 **部署阶段** - 部署到服务器
- 📊 **通知阶段** - 发送部署结果

### 3. 访问你的应用

部署成功后，访问：

```
http://你的服务器IP:3000
```

应该看到：`Hello CI/CD 🚀`

---

## 🔍 常见问题排查

### ❌ 错误 1：SSH 连接失败

```
Permission denied (publickey)
```

**解决方法：**
```bash
# 确保公钥已添加到服务器
ssh root@你的服务器IP "cat ~/.ssh/authorized_keys"

# 检查私钥格式是否完整
cat ~/.ssh/github_deploy_key
# 必须包含 -----BEGIN 和 -----END 行
```

### ❌ 错误 2：Docker 镜像拉取失败

```
Error response from daemon: pull access denied
```

**解决方法：**
```bash
# 在服务器上手动登录 Docker Hub
docker login -u 你的用户名

# 或者检查 DOCKER_PASSWORD 是否正确
```

### ❌ 错误 3：端口被占用

```
Bind for 0.0.0.0:3000 failed: port is already allocated
```

**解决方法：**
```bash
# 查看占用端口的进程
lsof -i :3000

# 停止旧容器
docker stop ci-demo-app
docker rm ci-demo-app

# 或者修改 docker-compose.yml 中的端口
ports:
  - "8080:3000"  # 改为 8080
```

---

## 📊 CI/CD 流程架构

```
┌─────────────────────────────────────────────────────────────┐
│  1. 本地开发                                                 │
│     ├─ 修改代码 (app.js)                                    │
│     ├─ git commit                                            │
│     └─ git push origin main ⬇️                              │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────┐
│  2. GitHub Actions 自动触发                                │
└─────────────────────────────┬─────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────▼────────┐  ┌─────────▼────────┐  ┌────────▼────────┐
│  🧪 测试阶段   │  │  🏗️ 构建镜像     │  │  🚀 部署到服务器 │
│  ├─ npm test   │  │  ├─ docker build │  │  ├─ SSH 连接    │
│  └─ 代码检查   │  │  ├─ 打标签       │  │  ├─ 拉取镜像    │
│                │  │  └─ 推送到 Hub   │  │  ├─ docker up   │
└────────────────┘  └──────────────────┘  └─────────┬───────┘
                                                     │
                              ┌──────────────────────▼────────┐
                              │  3. 应用运行在服务器          │
                              │     http://SERVER_IP:3000      │
                              └───────────────────────────────┘
```

---

## 🎉 配置检查清单

在推送代码前，确保：

- [ ] ✅ `DOCKER_USERNAME` 已配置
- [ ] ✅ `DOCKER_PASSWORD` 已配置
- [ ] ✅ `SERVER_IP` 已配置
- [ ] ✅ `SERVER_USER` 已配置
- [ ] ✅ `SSH_PRIVATE_KEY` 或 `SERVER_PASSWORD` 已配置
- [ ] ✅ 服务器已安装 Docker 和 Docker Compose
- [ ] ✅ 服务器防火墙已开放 3000 端口
- [ ] ✅ SSH 连接测试成功

---

## 🚀 下一步优化建议

1. **添加测试**：在 `package.json` 中添加测试脚本
2. **环境变量**：使用 `.env` 文件管理配置
3. **日志收集**：集成 ELK 或 Loki 收集日志
4. **监控告警**：配置 Prometheus + Grafana
5. **自动回滚**：健康检查失败时自动回滚到上一版本

---

## 📞 需要帮助？

如果遇到问题：

1. 查看 GitHub Actions 日志
2. SSH 登录服务器查看容器日志：`docker-compose logs -f`
3. 检查容器状态：`docker ps -a`

祝部署成功！🎉
