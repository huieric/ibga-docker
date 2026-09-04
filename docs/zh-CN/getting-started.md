# 快速开始

## 示例 docker-compose.yml

IBGA 完全通过 `docker-compose.yml` 配置：

```yaml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr:stable
    restart: unless-stopped
    environment:
      - IB_USERNAME=username
      - IB_PASSWORD=password
      - IB_REGION=America
      - IB_TIMEZONE=America/New_York
      - IB_LOGINTAB=IB API
      - IB_LOGINTYPE=Live Trading     # 或 Paper Trading
      - IB_LOGOFF=11:55 PM
      - AUTH_METHOD=passkey
    volumes:
      - ./run/program:/home/ibg             # IB Gateway 安装目录
      - ./run/settings:/home/ibg_settings   # 用户设置目录
    ports:
      - "8888:8888"    # IB API 端口（socat 转发）
      - "6080:6080"    # noVNC 浏览器界面
```

## 启动容器

```bash
docker compose up -d
```

`-d` 让容器在后台运行。配合 `restart: unless-stopped`，容器会一直保持运行，
除非你手动停止或 Docker 关闭。

默认暴露两个端口：

| 端口 | 用途 |
|------|------|
| `6080` | 浏览器 noVNC 界面，查看运行中的 IB Gateway |
| `8888` | IB API 端口（socat 转发到 IBG 内部端口，接受任意 IP） |

## 每日重启

IB Gateway 每天重启。IBGA 根据 `IB_LOGOFF` 配置 "Auto restart" 时间，并在登录后
重新应用。一个 watchdog 每隔几秒检查一次，若 IBG 退出则重启它。

## 崩溃处理

重启逻辑本身就会监控 IBG 进程，因此崩溃和每日重启走的是同一套处理流程。

## 健康检查

镜像内置健康检查，会连接 API 端口。用以下命令查看状态：

```bash
docker ps          # 查看 "healthy" 状态
```

## 镜像与通道

```bash
docker pull ghcr.io/huieric/ibkr:stable
```

| 通道 | Tag | 用途 |
|------|-----|------|
| `stable` | `ghcr.io/huieric/ibkr:stable` | 生产实盘 |
| `latest` | `ghcr.io/huieric/ibkr:latest` | 测试 / 模拟交易 |

IBKR 发布新版本时，GitHub Actions 会自动构建并发布新镜像。

本地构建：

```bash
./build.sh stable <version>    # 或：latest <version>
```

## 升级

```bash
docker compose pull      # 拉取新镜像
docker compose up -d     # 重建容器（数据通过 volume 保留）
```

强制重装 IB Gateway（在容器停止时删除程序目录）：

```bash
docker compose down
rm -rf ./run/program
docker compose up -d
```

下次启动时 IBGA 会重新安装 IB Gateway 到 `./run/program`，`./run/settings` 中的
设置会被保留。
