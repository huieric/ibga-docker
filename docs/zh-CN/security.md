# 安全须知

## 在公网服务器上运行

IBGA 未针对直接暴露到公网做加固。若必须在远程托管，请采取以下措施。

### 限制 API 端口

IB API 端口是无认证的裸 TCP。绝不要暴露到公网。在 compose 文件中绑定到 localhost：

```yaml
ports:
  - "127.0.0.1:8888:8888"
```

并通过 SSH 隧道或同机进程连接。

### 保护宿主机

- 使用 SSH 密钥认证（禁用密码登录）
- 用防火墙（UFW）把入站端口限制到你的客户端 IP，或对变化的 IP 使用 VPN（如 WireGuard）

### 保护凭据

IBGA 需要你的 IB 用户名和密码来登录。优先使用 Docker secrets 或 `.env` 文件，
而不是把真实凭据硬编码在 `docker-compose.yml` 里，也避免把真实凭据提交到版本控制。

## VNC / noVNC 访问

noVNC 界面（`6080`）用于监控。它不是上面 API 端口限制的替代——只保护 VNC
仍然会让 API 端口暴露。
