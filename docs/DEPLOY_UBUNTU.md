# ConvertAPK 用户构建端部署（Ubuntu 24.04）

本文档适用于把 ConvertAPK（用户构建端 + 构建工程）部署到 Ubuntu 24.04 服务器，以网页方式使用。

## 1. 服务器要求

- Ubuntu 24.04 LTS
- 至少 2C/4G（推荐 4C/8G）
- 需要 root 权限
- 允许安装/运行 Docker

## 2. 安装 Docker 与 Compose

```bash
apt update
apt install -y docker.io docker-compose-plugin
systemctl enable --now docker
```

验证：
```bash
docker --version
docker compose version
```

## 3. 拉取代码

```bash
git clone https://github.com/Jminchannel/ConvertAPK-Desktop.git
cd ConvertAPK-Desktop
```

## 4. 准备数据目录

后端会把任务、输出、日志写到 `/data/convertapk`：

```bash
mkdir -p /data/convertapk/gradle-cache
```

## 5. 修改端口对外可访问

`docker-compose.yml` 当前只绑定本机回环地址，需要改成 `0.0.0.0`：

```yaml
services:
  backend:
    ports:
      - "0.0.0.0:8000:8000"

  frontend:
    ports:
      - "0.0.0.0:8080:80"
```

文件位置：`docker-compose.yml`

## 6. 构建 apk-builder 镜像（只需一次）

```bash
docker compose --profile builder build apk-builder
```

> 说明：后端会通过宿主机 Docker 调用 `apk-builder:latest` 来构建 APK。

## 7. 启动服务

```bash
docker compose up -d --build
```

查看状态：
```bash
docker compose ps
```

## 8. 访问

- 前端：`http://服务器IP:8080`
- 后端：`http://服务器IP:8000`

## 9. （可选）对接管理端

如果你有管理端（Admin）服务，可在 `docker-compose.yml` 为后端增加：

```yaml
environment:
  - ADMIN_API_URL=https://admin.example.com
  - ADMIN_CLIENT_TOKEN=你的token
```

然后重启：
```bash
docker compose up -d
```

## 10. 防火墙端口

如启用防火墙，请放行 8080（前端）和 8000（后端）：

```bash
ufw allow 8080/tcp
ufw allow 8000/tcp
```

## 11. 常见问题

### 11.1 构建失败提示找不到 docker
- 确保宿主机安装了 Docker
- 后端容器已挂载 `/var/run/docker.sock`（`docker-compose.yml` 已配置）

### 11.2 构建慢
- Gradle 缓存已挂载到 `/data/convertapk/gradle-cache`
- 第一次构建需要下载依赖，后续会快很多

### 11.3 前端能打开但 API 请求失败
- 确认 `docker compose ps` 中 `backend` 为 `healthy/running`
- 确认端口映射为 `0.0.0.0:8000` 与 `0.0.0.0:8080`

## 12. 升级步骤

```bash
cd ConvertAPK-Desktop

git pull

docker compose up -d --build
```

## 13. 关闭服务

```bash
docker compose down
```

---

如需配置域名/HTTPS（Nginx/SSL），告诉我域名，我可以补一份对应的反代配置。
