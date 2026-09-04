# 配置参数（环境变量）

IBGA 通过 `docker-compose.yml` 中的环境变量进行配置。

| 变量 | 必填 | 说明 |
|----------|:---:|-------------|
| `IB_USERNAME` | ✓ | IB 账户用户名 |
| `IB_PASSWORD` | ✓ | IB 账户密码 |
| `IB_TIMEZONE` | ✓ | 时区（TZ 数据库名，如 `Asia/Shanghai`）。决定每日重启时间和 API 报告的时间 |
| `IB_LOGINTAB` | ✓ | 登录页/API 类型：`IB API` 或 `FIX CTCI` |
| `IB_LOGINTYPE` | ✓ | 登录类型/交易模式：`Live Trading` 或 `Paper Trading` |
| `IB_LOGOFF` | ✓ | 每日重启时间，格式 `HH:MM AM/PM`（如 `05:30 AM`）。IBGA 会应用并强制 "Auto restart" |
| `IB_REGION` | | 地区下拉框：`America`、`Europe`、`Asia`、`China` |
| `IB_APILOG` | | 开启 API 消息日志。空 = 关闭，任意值 = 开启，`data` = 同时包含行情数据 |
| `IB_LOGLEVEL` | | 日志级别：`System`、`Error`、`Warning`、`Info`、`Detail` |
| `AUTH_METHOD` | | 二步认证：`passkey`（默认，IBKR 强制）或 `totp`（旧）。二者互斥 |
| `TOTP_KEY` | | TOTP 密钥；仅 `AUTH_METHOD=totp` 时使用 |
| `IBGA_EXPORT_LOGS` | | 为 `true` 时每日导出当天与前一天的 Gateway/API 日志 |
| `IBGA_LOG_EXPORT_DIR` | | 日志导出目录（默认：设置目录 `/home/ibg_settings/exported_logs`） |

内部变量（`IBG_DIR`、`IBG_SETTINGS_DIR`、`IBG_PORT_INTERNAL`、`IBG_PORT`、
`IBG_DOWNLOAD_URL`）有默认值，一般无需覆盖。
