# ibga-docker — 把盈透证券 IB Gateway 装进容器里的一行启动方案

> 仓库地址：[https://github.com/huieric/ibga-docker](https://github.com/huieric/ibga-docker)  
> 基于上游项目：[heshiming/ibga](https://github.com/heshiming/ibga) · GPLv3 授权  
> 89 commits · 21 releases · 最新版本 `ibgateway 10.37.1p-stable`（2026-03-11）

---

## 一句话总结

**ibga-docker 让你用一条 `docker compose up` 命令，在任何服务器上 7×24 小时无人值守地运行盈透证券（Interactive Brokers）的 IB Gateway，彻底解决"必须开着电脑才能跑量化策略"的痛点。**

### 运行效果预览（noVNC 浏览器视角）

下图是通过浏览器打开 `http://服务器IP:15800` 后看到的真实画面——容器启动、虚拟桌面拉起、IB Gateway 自动登录的完整过程：

![IBGA 自动启动登录全过程](https://heshiming.github.io/ibga/images/ibga-video.gif)

> 从容器启动到 API 端口就绪，全程零人工干预。

---

## 这个仓库解决了什么问题？

Interactive Brokers (IBKR) 是全球主流量化/算法交易券商之一，提供的 IB Gateway 是连接你的交易程序与 IBKR 账户的桥梁。但它有一个致命缺陷：

| 传统痛点 | 说明 |
|---|---|
| **必须有图形界面** | IB Gateway 是 Java GUI 程序，不能在纯命令行服务器运行 |
| **每天强制重启** | IBKR 要求每天凌晨断线重启，策略程序会中断 |
| **每周强制登出** | 超过一周不重新登录会被踢下线 |
| **双因素认证** | 2FA 要求手动操作手机，无法自动化 |
| **Paper/Live 弹窗** | 模拟交易模式下每次启动都有确认弹窗 |

ibga-docker 用 Docker 容器 + 一套精巧的自动化脚本，把以上所有痛点**一次性消灭**。

---

## 架构总览

```
┌─────────────────────────────────────────────────────┐
│                   Docker 容器 (ibga)                  │
│                                                       │
│  ┌──────────┐   ┌──────────┐   ┌──────────────────┐  │
│  │  Xvfb    │   │ x11vnc / │   │   Bash 自动化     │  │
│  │ 虚拟显示  │──▶│  noVNC   │   │   脚本组          │  │
│  └──────────┘   └──────────┘   └────────┬─────────┘  │
│        │                                │             │
│        ▼                                ▼             │
│  ┌──────────────────────┐   ┌──────────────────────┐  │
│  │   IB Gateway (Java)  │◀──│  JAuto + xdotool     │  │
│  │   完整 GUI 程序      │   │  UI 坐标定位 + 模拟  │  │
│  └──────────┬───────────┘   │  键鼠输入             │  │
│             │               └──────────────────────┘  │
└─────────────┼───────────────────────────────────────  ┘
              │ TCP Port 4000
              ▼
   ┌─────────────────────┐
   │  你的交易策略程序    │
   │  ib_insync / TWS API│
   └─────────────────────┘
```

---

## 核心技术组件

| 组件 | 用途 | 类比 |
|---|---|---|
| **Xvfb** | 虚拟 X11 显示帧缓冲 | 给 IB Gateway 提供一个"假屏幕" |
| **x11vnc + noVNC** | VNC 远程桌面 (浏览器可访问) | 让你用浏览器"看着" Gateway 在跑 |
| **JAuto** | JVMTI 代理，读取 Java UI 坐标 | 自动找到登录框、按钮的屏幕位置 |
| **xdotool** | 模拟键盘鼠标输入 | 自动"点击"按钮、"输入"密码 |
| **oathtool** | 生成 TOTP 6 位动态码 | 替你填写手机 Authenticator 的验证码 |
| **Bash 脚本组** | 编排整个自动化流程 | 指挥以上所有工具的"大脑" |

---

## Docker Compose 配置示例

```yaml
version: '2'
services:
  my-ibga:
    image: heshiming/ibga          # 或 huieric/ibga-docker
    restart: unless-stopped        # 崩溃自动重启
    environment:
      - TERM=xterm
      - IB_USERNAME=your_username
      - IB_PASSWORD=your_password
      - IB_REGION=America
      - IB_TIMEZONE=America/New_York
      - IB_LOGINTAB=IB API
      - IB_LOGINTYPE=Live Trading  # 或 Paper Trading
      - IB_LOGOFF=11:55 PM         # 自动每天定时重启
      - IB_APILOG=data
      - IB_LOGLEVEL=Error
      - TOTP_KEY=XXXXXXXXXXXXXX    # 可选：TOTP 密钥，全自动 2FA
    volumes:
      - ./run/program:/home/ibg          # IB Gateway 程序目录（持久化）
      - ./run/settings:/home/ibg_settings # 用户设置目录（持久化）
    ports:
      - "15800:5800"   # noVNC 浏览器界面
      - "4000:4000"    # IB Gateway API 端口（供策略程序连接）
```

---

## 完整启动流程图

```
docker compose up
       │
       ▼
[1] 容器启动，Bash 脚本初始化
       │
       ▼
[2] Xvfb 创建虚拟 X11 显示环境
       │
       ▼
[3] 启动 x11vnc + noVNC（可选，用于调试）
       │
       ▼
[4] 下载/更新 IB Gateway（首次运行）
       │
       ▼
[5] 启动 IB Gateway GUI（在虚拟屏幕中）
       │
       ▼
[6] JAuto 扫描窗口，定位登录框
       │
       ▼
[7] xdotool 自动填入用户名 + 密码
       │
       ▼
[8] 二次验证（2FA）处理
       │           │
       ▼           ▼
  [有TOTP密钥]  [无TOTP密钥]
  oathtool自动  用户通过VNC
  生成6位码     手机APP确认
       │           │
       └─────┬─────┘
             ▼
[9] 登录成功，IB Gateway 就绪
             │
             ▼
[10] API Port 4000 开放，接受策略程序连接
             │
             ▼
[11] 每天 IB_LOGOFF 时间自动重启登录（循环 → 步骤 5）
```

---

## 核心功能（Features）

### ✅ 自动化程度

- **自动安装 & 升级 IB Gateway**：首次运行自动下载，无需手动安装
- **全自动登录**：用户名、密码、地区全部通过环境变量注入
- **TOTP 自动化**（最新特性）：提供密钥后，6 位动态验证码由 `oathtool` 自动生成并填入，无需摸手机
- **自动处理弹窗**：模拟交易确认框、选项对话框全部自动点击确认

**当没有配置 TOTP 密钥时，登录后 noVNC 界面会显示如下 2FA 等待画面**，此时只需在手机上点一下"允许"即可：

![2FA 等待确认界面（通过 noVNC 在浏览器中看到的画面）](https://heshiming.github.io/ibga/images/two-factor-auth.png)

### ♾️ 高可用设计

- **每日自动重启**：IB_LOGOFF 时间触发，自动完成每日断线重连循环
- **崩溃自动恢复**：容器级别的 `restart: unless-stopped` + 脚本级别的崩溃检测双重保障
- **跨越一周限制**：脚本处理超时重新登录，不受 IBKR 一周强制登出的影响

**IB Gateway 每日定时重启的设置界面**（IBGA 会自动配置并强制选中"Auto restart"，无需手动操作）：

![每日自动重启配置界面](https://heshiming.github.io/ibga/images/ibg-logoff.png)

### 💾 持久化 & 可移植

- **设置持久化**：IB Gateway 程序和用户配置挂载到宿主机目录，升级容器不丢失配置
- **容器可丢弃**：删除容器重新拉取镜像即可完成升级，数据完全保留
- **跨机器迁移**：复制 `./run/` 目录到新机器，立刻恢复

### 🔍 可观测性

- **浏览器 VNC 界面**（端口 5800→15800）：打开浏览器就能看到 Gateway 的实时运行状态
- **每日自动导出日志**：通过 `IBGA_EXPORT_LOGS=true` 开启，支持自定义日志目录
- **日志级别可配置**：`IB_LOGLEVEL=Error/Warning/Info` 按需调整

---

## 🔄 IBGateway 版本自动检测与升级

这是 `huieric/ibga-docker` 相比手动方案最省心的工程特性之一：**IBGateway 有新版本发布时，CI/CD 流水线自动检测、自动构建新镜像、自动发布 Release，用户线上只需更换镜像 tag 即可完成升级，无需任何手动操作。**

### 双通道版本体系

仓库维护 `stable` 和 `latest` 两条独立版本通道，分别对应 IBKR 官方的两个发布轨道：

| 通道 | 镜像 tag | 适合场景 | 特点 |
|---|---|---|---|
| **stable** | `huieric/ibga-docker:stable` | 生产实盘交易 | IBKR 充分测试过的版本，稳定优先 |
| **latest** | `huieric/ibga-docker:latest` | 测试/模拟交易 | 跟进 IBKR 最新功能，第一时间获得修复 |

### 自动化发布历史

下图展示了近期 21 次 Release 的时间线——**全部由 `github-actions` 机器人自动完成**，无人工介入：

> 版本命名规则：`{IBGateway版本号}-{通道}`，例如 `10.37.1p-stable`、`10.44.1g-latest`

![GitHub Releases 页面 — 21次全自动发布记录](https://github.com/huieric/ibga-docker/releases)

截至 2026-03-20 的最新版本：
- **stable 通道**：`ibgateway 10.37.1p-stable`（2026-03-11 发布）
- **latest 通道**：`ibgateway 10.44.1g-latest`（2026-03-04 发布）

### 升级操作极简

```bash
# 升级到最新 stable 版本，只需两条命令：
docker compose pull
docker compose up -d
```

IBGateway 程序和所有用户设置通过 volume 持久化，**升级容器不会丢失任何配置或数据**。

---

## 🌐 开源版本管理 · 欢迎社区共建

`huieric/ibga-docker` 以 **GPLv3** 开源协议发布，完整源码托管在 GitHub，所有构建逻辑、自动化脚本、CI 配置公开透明。

### 为什么开源很重要？

对于量化交易工具来说，开源意味着：

- **可审计**：任何人都可以检查代码，确认没有隐藏的数据上传或安全后门
- **可定制**：团队可以 fork 后针对自身需求修改，例如集成私有监控系统
- **可持续**：不依赖单一维护者，社区可以共同修复 bug、跟进 IBKR 的 API 变更
- **透明升级**：每次版本变更都有 commit message 记录原因，例如 `fix(totp): fix mobile authenticator failed`

### 参与方式

| 方式 | 说明 |
|---|---|
| 🐛 提交 Issue | 发现 bug 或有功能建议，直接在 GitHub Issues 反馈 |
| 🔀 提交 PR | 修复问题或新增特性，欢迎 Pull Request |
| ⭐ Star 仓库 | 帮助提升项目可见度，让更多量化开发者发现它 |
| 📖 完善文档 | 补充使用案例、部署踩坑记录等 |

**当前重点迭代方向：**
- 进一步提升登录自动化的鲁棒性（应对 IBKR 界面更新）
- 安全加固：支持 Docker secrets 管理敏感凭证
- 多账户并行部署的易用性优化
- ARM 架构（Apple Silicon / 树莓派）镜像支持

> 仓库地址：[https://github.com/huieric/ibga-docker](https://github.com/huieric/ibga-docker) · 欢迎 Star & Fork

---

## huieric/ibga-docker 相比上游做了什么？

`heshiming/ibga`（上游）是核心脚本仓库，但它更像一个"源代码工程"——用户需要自己 clone 并手动 build。`huieric/ibga-docker` 在此基础上做了一套完整的**工程化包装**：

| 维度 | 上游 `heshiming/ibga` | `huieric/ibga-docker` |
|---|---|---|
| 提交数 | 30 commits | **89 commits** |
| Release 数量 | 11 tags | **21 releases**，最新 `10.37.1p-stable` |
| 目录结构 | 单层脚本 | `base/` + `stable/` + `latest/` 三层镜像 |
| 构建方式 | 手动 `build.sh` | **GitHub Actions 自动 CI/CD** |
| 安装包来源 | 从 IBKR 官网下载 | **自己托管 + SHA256 哈希校验** |
| 语言构成 | Shell + C | Shell + Dockerfile + Python + HTML |
| 版本通道 | 无 | **stable / latest 双通道** |

简而言之：上游解决了"怎么自动化登录 IB Gateway"，本仓库解决了"怎么让用户**开箱即用**"。

---

## 与同类方案的对比

| 方案 | 无头运行 | 全自动登录 | TOTP 自动化 | 活跃维护 | 使用难度 |
|---|---|---|---|---|---|
| **ibga-docker** | ✅ | ✅ | ✅ | ✅ | 低 |
| IBC (IBController) | ❌（设计上不支持容器化） | 部分 | ❌ | ✅ | 中 |
| IBEAM | ✅ | ✅ | ❌ | ✅ | 中（需改 API 客户端） |
| 手动运行 IB Gateway | ❌ | ❌ | ❌ | — | 高 |

> IBGA 的核心优势在于它**不需要逆向工程 IB Gateway 的 Java 代码**（IBC 的做法），而是用 JAuto 读取 UI 布局 + xdotool 模拟输入，更稳定且不依赖 IB 内部实现。

---

## 端口映射说明

| 容器端口 | 宿主机端口（示例） | 用途 |
|---|---|---|
| 5800 | 15800 | noVNC 浏览器界面，用于监控和调试 |
| 4000 | 4000 | IB Gateway TWS API，策略程序连接此端口 |

浏览器访问 `http://服务器IP:15800` 即可打开 noVNC 界面，实时看到 IB Gateway 的运行状态（如下图所示，这也是上方演示 GIF 的视角来源）：

![noVNC 界面 — 登录自动化全程可视](https://heshiming.github.io/ibga/images/ibga-video.gif)

---

## 快速上手（3 步启动）

**第一步：准备配置文件**
```bash
mkdir -p ibga && cd ibga
# 创建 docker-compose.yml，填入你的 IB 账号信息
```

**第二步：启动容器**
```bash
docker compose up -d
```

**第三步：在浏览器里确认登录**
```bash
# 浏览器打开 http://你的服务器IP:15800
# 你会看到 noVNC 画面里 IB Gateway 正在自动完成登录
# （如配置了 TOTP_KEY，全自动无感；否则第一次需手机点"允许"）
```

**连接你的策略**
```python
import ib_insync
ib = ib_insync.IB()
ib.connect('127.0.0.1', 4000, clientId=1)
# 开始交易 🚀
```

---

## 安全注意事项

- **不要将 4000 端口暴露到公网**：IB Gateway 的 API 是无认证的裸 TCP，公网暴露等于把交易账户送出去
- **建议使用 127.0.0.1 绑定**：`ports: - "127.0.0.1:4000:4000"`
- **敏感信息管理**：生产环境建议使用 Docker secrets 或 `.env` 文件，而非直接写在 `docker-compose.yml` 里
- **TOTP_KEY 保密**：这相当于你的 Authenticator 种子密钥，泄露即泄露 2FA

---

## 总结：为什么值得一用？

1. **从此量化策略可以在云服务器上 7×24 无人值守运行**，不再依赖本地开着的电脑
2. **配置极简**：一个 `docker-compose.yml` 文件，所有参数用环境变量管理，一目了然
3. **可靠性强**：双重崩溃恢复机制，自动处理 IBKR 的每日/每周强制重启
4. **调试友好**：浏览器 VNC 随时查看 Gateway 运行状态，出问题一眼就看到
5. **可扩展**：同时跑多个账户？给每个服务起不同名字，暴露不同端口，完全可以并行
