# 使用官方 Node.js 18 Alpine 镜像（更小更快）
FROM node:18-alpine

# 设置工作目录
WORKDIR /app

# 复制 package.json（利用 Docker 缓存层）
COPY package*.json ./

# 安装依赖（生产环境）
RUN npm ci --only=production

# 复制应用代码
COPY . .

# 暴露端口
EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# 启动应用
CMD ["npm", "start"]