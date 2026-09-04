# IB Gateway Automation (IBGA) — 中文文档

> 本目录为 ibga-docker 的**中文文档**，英文文档见上级 `docs/` 目录。
> 项目 README 见 [English](../README.md) / [中文](../README.zh-CN.md)。

## 目录

- [快速开始（配置）](getting-started.md)
- [环境变量参考](config-args.md)
- [常见问题（FAQ）](faq.md)
- [安全须知](security.md)

## 简介

IBGA 在 Docker 中以无头模式运行 [IB Gateway](https://www.interactivebrokers.com/en/trading/ibgateway-latest.php)，自动完成登录、每日重启和选项弹窗处理。

IBKR 现已**强制 Passkey** 认证。IBGA 默认通过 `AUTH_METHOD=passkey` 配合 [soft-fido2](https://github.com/huieric/soft-fido2) 容器（经 USB/IP 提供软件安全密钥）实现无人值守登录；旧的 TOTP（Mobile Authenticator App）方式保留为文档选项。

## 核心能力

- 一条 `docker compose` 配置即可启动
- 用户名、密码、时区等全部通过环境变量管理
- 自动安装与升级 IB Gateway
- 自动处理每日重启、崩溃、一周登出限制
- 自动处理模拟交易确认框与选项弹窗
- 每日自动导出日志
- 升级不丢失设置（可丢弃容器设计）
- 无人值守 passkey 登录（soft-fido2，默认；IBKR 现强制）
- Mobile Authenticator App 自动化（旧方式）

## 底层依赖

- **JAuto**：JVMTI 代理，定位窗口、文本框、按钮的屏幕坐标
- **xdotool**：模拟键鼠输入
- **Xvfb + noVNC**：为 IB Gateway 提供可远程查看的 X11 环境
- **oathtool**：生成 TOTP 动态码（旧方式）
