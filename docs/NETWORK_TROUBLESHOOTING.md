# 🌐 网络问题故障排查指南

## 问题：Docker Hub 连接超时

### 错误信息
```
Error response from daemon: Get "https://registry-1.docker.io/v2/": 
net/http: request canceled while waiting for connection 
(Client.Timeout exceeded while awaiting headers)
```

### 根本原因

1. **网络延迟或不稳定**
   - 服务器到 Docker Hub 的网络连接质量差
   - 防火墙或网络策略阻止连接

2. **Docker Hub 服务问题**
   - Docker Hub 服务暂时不可用
   - 区域性网络故障

3. **Docker 配置问题**
   - 默认超时时间太短
   - 没有配置镜像加速

## 🔧 解决方案

### 方案 1: 使用镜像加速器（推荐）

我们的脚本已经自动配置了多个镜像加速器：

```bash
# 查看当前配置
cat /etc/docker/daemon.json
```

应该看到：
```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://mirror.ccs.tencentyun.com",
    "https://docker.nju.edu.cn"
  ],
  "max-concurrent-downloads": 10,
  "max-download-attempts": 5
}
```

如果没有，手动配置：

```bash
# 创建/编辑配置文件
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://mirror.ccs.tencentyun.com",
    "https://docker.nju.edu.cn",
    "https://dockerhub.azk8s.cn",
    "https://reg-mirror.qiniu.com"
  ],
  "max-concurrent-downloads": 10,
  "max-download-attempts": 5
}
EOF

# 重启 Docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# 等待服务就绪
sleep 10

# 验证配置
docker info | grep -A 5 "Registry Mirrors"
```

---

### 方案 2: 增加超时时间

编辑 Docker 配置：

```bash
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io"
  ],
  "max-concurrent-downloads": 10,
  "default-runtime": "runc",
  "live-restore": true,
  "shutdown-timeout": 600,
  "max-download-attempts": 5
}
EOF

sudo systemctl restart docker
```

---

### 方案 3: 手动测试连接

#### 1. 测试网络连接

```bash
# 测试 Docker Hub 可达性
ping -c 4 registry-1.docker.io

# 测试 HTTPS 连接
curl -I https://registry-1.docker.io/v2/

# 测试镜像加速器
curl -I https://docker.m.daocloud.io/v2/
curl -I https://mirror.ccs.tencentyun.com/v2/
```

#### 2. 测试 Docker 登录

```bash
# 登录测试（使用超时）
timeout 60 docker login -u your-username

# 或使用环境变量
export DOCKER_USERNAME="your-username"
export DOCKER_PASSWORD="your-password"
echo "$DOCKER_PASSWORD" | timeout 60 docker login -u "$DOCKER_USERNAME" --password-stdin
```

#### 3. 测试镜像拉取

```bash
# 拉取小镜像测试
timeout 120 docker pull hello-world

# 拉取你的镜像
timeout 300 docker pull your-username/your-image:latest
```

---

### 方案 4: 使用代理

如果服务器需要通过代理访问外网：

#### 方法 A: Docker 守护进程代理

```bash
# 创建 systemd 配置目录
sudo mkdir -p /etc/systemd/system/docker.service.d

# 创建代理配置
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
Environment="NO_PROXY=localhost,127.0.0.1,docker.io"
EOF

# 重载配置
sudo systemctl daemon-reload
sudo systemctl restart docker

# 验证
sudo systemctl show --property=Environment docker
```

#### 方法 B: Docker 客户端代理

```bash
# 在 ~/.docker/config.json 中配置
mkdir -p ~/.docker
cat > ~/.docker/config.json <<'EOF'
{
  "proxies": {
    "default": {
      "httpProxy": "http://proxy.example.com:8080",
      "httpsProxy": "http://proxy.example.com:8080",
      "noProxy": "localhost,127.0.0.1"
    }
  }
}
EOF
```

---

### 方案 5: 优化 DNS 配置

有时候 DNS 解析慢也会导致超时：

```bash
# 使用公共 DNS
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "dns": ["8.8.8.8", "8.8.4.4", "114.114.114.114"],
  "registry-mirrors": [
    "https://docker.m.daocloud.io"
  ]
}
EOF

sudo systemctl restart docker
```

---

### 方案 6: 使用本地镜像（离线部署）

如果网络实在不行，可以考虑离线部署：

#### 1. 在本地导出镜像

```bash
# 在有网络的机器上
docker pull your-username/your-image:latest
docker save -o image.tar your-username/your-image:latest

# 压缩（可选）
gzip image.tar
```

#### 2. 传输到服务器

```bash
# 使用 scp
scp image.tar.gz user@server:/tmp/

# 或使用 rsync
rsync -avz image.tar.gz user@server:/tmp/
```

#### 3. 在服务器上导入

```bash
# 解压（如果压缩了）
gunzip /tmp/image.tar.gz

# 导入镜像
docker load -i /tmp/image.tar

# 验证
docker images
```

---

## 🔍 诊断工具

### 1. 网络连通性检查脚本

```bash
#!/bin/bash

echo "=== Docker Hub 连通性检查 ==="

# 检查 Docker Hub
echo -n "Docker Hub (registry-1.docker.io): "
if ping -c 2 -W 5 registry-1.docker.io >/dev/null 2>&1; then
    echo "✅ 可达"
else
    echo "❌ 不可达"
fi

# 检查镜像加速器
mirrors=(
    "docker.m.daocloud.io"
    "mirror.ccs.tencentyun.com"
    "docker.nju.edu.cn"
)

for mirror in "${mirrors[@]}"; do
    echo -n "镜像源 ($mirror): "
    if curl -s -m 5 -I "https://$mirror/v2/" | grep -q "200\|401"; then
        echo "✅ 可用"
    else
        echo "❌ 不可用"
    fi
done

# 检查 Docker 服务
echo -n "Docker 服务: "
if docker info >/dev/null 2>&1; then
    echo "✅ 运行中"
else
    echo "❌ 未运行"
fi

# 检查登录状态
echo -n "Docker Hub 登录: "
if docker info 2>/dev/null | grep -q "Username"; then
    echo "✅ 已登录"
else
    echo "⚠️  未登录"
fi
```

保存为 `check-docker-network.sh`，然后运行：

```bash
chmod +x check-docker-network.sh
./check-docker-network.sh
```

---

### 2. Docker 日志分析

```bash
# 查看 Docker 守护进程日志
sudo journalctl -u docker -n 100 --no-pager

# 实时监控
sudo journalctl -u docker -f

# 查看特定时间范围
sudo journalctl -u docker --since "10 minutes ago"
```

---

### 3. 网络跟踪

```bash
# 使用 traceroute
traceroute registry-1.docker.io

# 使用 mtr（更详细）
mtr registry-1.docker.io

# 使用 tcpdump 抓包
sudo tcpdump -i any -n host registry-1.docker.io
```

---

## 📊 性能优化建议

### 1. 调整并发下载数

```json
{
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 5
}
```

### 2. 启用 HTTP/2

```json
{
  "registry-mirrors": ["https://docker.m.daocloud.io"],
  "insecure-registries": [],
  "features": {
    "buildkit": true
  }
}
```

### 3. 配置日志驱动

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

---

## 🚨 常见错误及解决方案

### 错误 1: `connection refused`

**原因**: 防火墙阻止连接

**解决**:
```bash
# 检查防火墙
sudo ufw status

# 允许 Docker 相关端口
sudo ufw allow 2375/tcp
sudo ufw allow 2376/tcp

# 或临时禁用防火墙测试
sudo ufw disable
```

---

### 错误 2: `EOF`

**原因**: 连接中断

**解决**:
```bash
# 清理 Docker 缓存
docker system prune -af

# 重启 Docker
sudo systemctl restart docker

# 重新拉取
docker pull your-image
```

---

### 错误 3: `unauthorized: incorrect username or password`

**原因**: 认证失败

**解决**:
```bash
# 退出登录
docker logout

# 重新登录
docker login

# 或使用 Token
docker login -u your-username -p your-token
```

---

### 错误 4: `context deadline exceeded`

**原因**: 操作超时

**解决**:
```bash
# 方案 1: 增加超时
export COMPOSE_HTTP_TIMEOUT=300

# 方案 2: 使用镜像加速
# 参考上面的方案 1

# 方案 3: 分步操作
docker pull your-image:latest  # 单独拉取
docker compose up -d           # 再启动
```

---

## 🔄 完整排查流程

### 第 1 步: 基础检查

```bash
# 1. Docker 服务状态
sudo systemctl status docker

# 2. Docker 版本
docker --version

# 3. 网络连通性
ping -c 4 8.8.8.8
ping -c 4 registry-1.docker.io

# 4. DNS 解析
nslookup registry-1.docker.io
```

### 第 2 步: 配置检查

```bash
# 1. 查看 Docker 配置
cat /etc/docker/daemon.json

# 2. 查看环境变量
env | grep -i proxy

# 3. 查看 Docker 信息
docker info
```

### 第 3 步: 测试连接

```bash
# 1. 测试登录
docker login

# 2. 测试拉取小镜像
docker pull hello-world

# 3. 测试拉取目标镜像
docker pull your-image:latest
```

### 第 4 步: 应用修复

```bash
# 根据上面的诊断结果应用相应的方案
# 通常组合使用：
# - 镜像加速器
# - 增加超时
# - 重试机制
```

---

## 📝 最佳实践

### 1. 部署前检查

```bash
# 运行环境检查脚本
./scripts/check-server.sh

# 运行网络检查
./check-docker-network.sh
```

### 2. 使用健康检查

```yaml
# docker-compose.yml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3000"]
  interval: 30s
  timeout: 10s
  retries: 3
```

### 3. 日志监控

```bash
# 实时查看部署日志
docker compose logs -f

# 设置日志告警
# 使用 Prometheus + Alertmanager 或其他监控工具
```

### 4. 定期维护

```bash
# 每周清理一次
docker system prune -f

# 更新镜像
docker compose pull
docker compose up -d

# 检查资源使用
docker stats
```

---

## 🆘 仍然无法解决？

如果尝试了以上所有方案仍然无法解决：

1. **检查服务器网络策略**
   - 联系服务器提供商
   - 检查是否有网络限制

2. **考虑使用替代方案**
   - 使用国内的容器镜像服务（阿里云、腾讯云）
   - 使用私有镜像仓库

3. **提交 Issue**
   - [GitHub Issues](https://github.com/weitao-Li/learn-devops/issues)
   - 提供详细的错误日志和环境信息

---

## 📚 相关资源

- [Docker 官方文档](https://docs.docker.com/)
- [Docker Hub Status](https://status.docker.com/)
- [镜像加速器列表](https://gist.github.com/y0ngb1n/7e8f16af3242c7815e7ca2f0833d3ea6)
