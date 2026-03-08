# vps-allineone

一键在 VPS 上部署多种代理协议，支持 **Caddy (NaiveProxy)**、**Hysteria2**、**Trojan**、**VLESS Reality (Xray)**、**H2 Client**。

- 交互式安装，引导填写域名/端口/密码，支持随机生成
- 全离线部署，所有二进制预先下载好，安装时无需联网
- 自动检测已安装的代理软件并展示概览
- 重复执行安全，已安装组件可选覆盖/仅更新配置/跳过
- 智能端口检测，识别占用端口的进程与协议
- 支持架构：amd64、arm64

---

## 目录结构

```
vps-allineone/
├── install.sh                   # 主安装脚本
├── download-bins.sh             # 升级二进制时使用（见下方说明）
├── caddy/
│   ├── caddy-linux-amd64        # Caddy（含 NaiveProxy 插件，仅 amd64）
│   ├── caddy.service            # systemd 服务文件
├── hysteria/
│   ├── hysteria-linux-amd64     # Hysteria2 服务端
│   ├── hysteria-linux-arm64
│   └── h2server.service         # systemd 服务文件
├── trojan/
│   ├── trojan-go-linux-amd64    # Trojan-go 服务端
│   ├── trojan-go-linux-arm64
│   └── trojan.service           # systemd 服务文件
├── xray/
│   ├── xray-linux-amd64         # Xray-core（VLESS Reality）
│   ├── xray-linux-arm64
│   └── xray.service             # systemd 服务文件
└── h2client/
    ├── h2-linux-amd64           # Hysteria2 客户端
    ├── h2-linux-arm64
    └── h2client.service         # systemd 服务文件
```

---

## 系统兼容说明

本脚本目前仅在 **Debian** 系系统上进行过验证，推荐使用 Debian 作为 VPS 操作系统。

| Debian 版本 | 代号 | 状态 | 兼容性 |
|------------|------|------|--------|
| Debian 12 | Bookworm | 当前稳定版 | 完全支持 |
| Debian 11 | Bullseye | 旧稳定版 | 完全支持 |
| Debian 10 | Buster | 已停止维护（EOL） | 支持，脚本自动切换包源到 archive.debian.org |
| Debian 9 及以下 | — | 已停止维护 | 未测试 |

> **Debian 10 说明**：官方包源已停止服务，脚本安装 `qrencode` 等工具时会自动将包源切换到归档镜像（`archive.debian.org`），无需手动操作。

其他发行版（Ubuntu、CentOS、Arch 等）理论上可用，但未经过测试验证。

---

## 内置安装包版本

仓库中已预置所有组件的二进制文件，克隆后**无需联网**即可安装。

| 组件 | 版本 | 架构 |
|------|------|------|
| Caddy（含 NaiveProxy 插件） | 自定义编译 | amd64 |
| Hysteria2 | 2.6.1 | amd64、arm64 |
| Trojan-go | 0.10.6 | amd64、arm64 |
| Xray-core | 25.3.6 | amd64、arm64 |
| H2 Client（Hysteria2 客户端） | 2.6.1 | amd64、arm64 |

### 关于 download-bins.sh

此脚本**不需要在日常安装时执行**，仅在以下情况使用：

- **升级组件版本**：修改脚本中的版本号后，在有网络的机器上运行，重新下载最新二进制，再 `git push` 更新仓库
- **重新下载损坏的包**：某个二进制文件损坏时单独补下
- **新增架构支持**：需要其他 CPU 架构的包时使用

> Caddy arm64 不在自动下载范围，需本地用 xcaddy 编译：
> ```bash
> go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
> GOARCH=arm64 GOOS=linux xcaddy build \
>   --with github.com/klzgrad/forwardproxy \
>   --output caddy/caddy-linux-arm64
> ```

---

## 快速开始

### Step 1  在 VPS 上克隆仓库

```bash
git clone git@github.com:hi-wayne/vps-allineone.git
cd vps-allineone
```

### Step 2  执行安装

```bash
cd vps-allineone
sudo ./install.sh
```

安装脚本会依次：

1. **扫描本机已有代理软件**，展示各服务运行状态、协议、端口、域名
2. **检测各组件二进制是否就绪**，有包才询问是否安装
3. **交互式配置**，引导填写域名/端口/密码（支持回车随机生成）
4. **检查域名解析**是否指向本机
5. **检查端口占用**，识别占用进程与协议
6. **写入配置到 `/data/`**，安装并启动 systemd 服务
7. **生成连接信息**到 `/data/connection-info/` 目录（每个服务独立文件）

#### 重复执行

再次运行 `install.sh` 时，已安装的组件会弹出选择：
```
检测到 Hysteria2 已安装（服务状态：运行中）
  1) 覆盖安装  —— 替换二进制文件 + 重新生成配置
  2) 仅更新配置 —— 保留二进制，只重新生成配置文件
  3) 跳过      —— 保持当前安装不变
```

---

## 各组件说明

### Caddy / NaiveProxy

基于 HTTPS/HTTP2 的代理，伪装成普通 HTTPS 网站流量。

| 参数 | 默认值 |
|------|--------|
| 监听端口 | 8443（HTTPS） |
| 用户名 | 随机生成 |
| 密码 | 随机生成 |

**证书获取**：Caddy 内置 ACME 客户端，安装时自动向 Let's Encrypt 申请 TLS 证书（HTTP Challenge，需 80 端口可访问）。

**证书位置**：`/root/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/{域名}/`

**证书续期**：Caddy 服务运行期间自动检测到期并续期，无需手动操作。

- 配置文件：`/data/caddy/Caddyfile`
- 服务名：`caddy`
- 状态查看：`systemctl status caddy`
- 手动启动：`/data/caddy/caddy run --config /data/caddy/Caddyfile`

### Hysteria2

基于 QUIC 的代理，高带宽、低延迟，适合 UDP 通畅的网络。

| 参数 | 默认值 |
|------|--------|
| 监听端口 | 443（UDP） |
| 密码 | 随机生成 |

**证书获取**：优先复用 Caddy 已申请的证书（同域名时）；否则由 Hysteria2 自身通过 ACME HTTP Challenge 申请（需 80 端口可访问）。

**证书位置**：
- 复用 Caddy 证书时：`/root/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/{域名}/`
- 由 Hysteria2 自身申请时：`/data/hysteria/`（由 hysteria2 daemon 管理）

**证书续期**：复用 Caddy 证书时由 Caddy 负责续期；自身申请时由 Hysteria2 服务运行期间自动续期。

- 配置文件：`/data/hysteria/server.yaml`
- 服务名：`h2server`
- 状态查看：`systemctl status h2server`
- 手动启动：`/data/hysteria/hysteria server -c /data/hysteria/server.yaml`

### Trojan

基于 TLS 的代理，适合 UDP 受限、只有 TCP 可用的网络。

| 参数 | 默认值 |
|------|--------|
| 监听端口 | 8880（TCP） |
| 密码 | 随机生成 |

**证书获取**：优先复用 Caddy 已申请的证书（同域名时）；否则由 Trojan-go 自身通过 ACME 申请，策略按优先级选择：
1. HTTP Challenge（80 端口空闲时）
2. TLS-ALPN Challenge（在自身 TCP 端口上完成，无需 80 端口）

**证书位置**：
- 复用 Caddy 证书时：`/root/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/{域名}/`
- 由 Trojan-go 自身申请时：`/data/trojan/`（由 trojan-go daemon 管理）

**证书续期**：复用 Caddy 证书时由 Caddy 负责续期；自身申请时由 Trojan-go 服务运行期间自动续期。

- 配置文件：`/data/trojan/server.json`
- 服务名：`trojan`
- 状态查看：`systemctl status trojan`
- 手动启动：`/data/trojan/trojan-go -config /data/trojan/server.json`

### VLESS Reality (Xray)

基于 REALITY 协议的代理，无需域名和 TLS 证书，通过模仿目标站点的 TLS 握手规避检测。

| 参数 | 默认值 |
|------|--------|
| 监听端口 | 443（TCP） |
| UUID | 随机生成 |
| SNI | www.pizzeriabianco.com |
| Flow | xtls-rprx-vision |

**证书获取**：不需要证书。REALITY 协议使用服务端生成的密钥对（PublicKey/PrivateKey）进行认证，无需申请 TLS 证书，安装后立即可用。

- 配置文件：`/data/xray/config.json`
- 服务名：`xray`
- 状态查看：`systemctl status xray`
- 手动启动：`/data/xray/xray run -c /data/xray/config.json`

> **说明**：不需要域名，连接信息中包含 UUID、PublicKey、ShortId，直接填入客户端即可。

### H2 Client（本地 Linux 客户端）

在本机连接 Hysteria2 服务端，提供本地 SOCKS5 与 HTTP 代理端口，供本机其他程序使用。

| 参数 | 默认值 |
|------|--------|
| 本地 SOCKS5 | :1080 |
| 本地 HTTP 代理 | :2080 |

**证书**：无需证书（客户端角色，连接远端 Hysteria2 服务器）。

- 配置文件：`/data/h2client/client.yaml`
- 服务名：`h2client`
- 状态查看：`systemctl status h2client`

---

## 证书策略说明

多个服务部署在同一台机器时，脚本会自动协调证书获取方式，避免多个服务同时争抢 ACME 端口。

**核心逻辑**：只让一个服务负责申请证书，其他服务直接读取同一份证书文件。

**触发复用 Caddy 证书的两种情况**：

1. **本次安装同时勾选了 Caddy，且域名相同** — 脚本直接让 Hysteria2 / Trojan 指向 Caddy 的证书路径，Caddy 启动后申请，其他服务读同一份文件。
2. **Caddy 之前已安装，证书文件已存在** — 再次运行脚本加装其他服务时，若域名相同，脚本检测到证书文件已在磁盘上，直接复用，不再独立申请。

**不复用时的降级策略**（域名与 Caddy 不同，或未安装 Caddy）：

| 优先级 | 方式 | 条件 |
|--------|------|------|
| 1 | HTTP Challenge（port 80） | 80 端口空闲且本次安装中无其他服务已认领 |
| 2 | TLS-ALPN Challenge（服务自身端口） | 仅 Trojan 支持；80 端口不可用时使用 |
| 3 | HTTP Challenge（可能失败） | Hysteria2 兜底；建议与 Caddy 共用域名 |

> 实际使用中大多数人会将所有服务配置在同一域名下，Caddy 负责申请和续期，Hysteria2 与 Trojan 直接复用，整台机器只有一个 ACME 客户端在工作。

---

## 连接信息

安装完成后，各服务的连接参数分别保存到独立文件：

```
/data/connection-info/
├── caddy.txt          # Caddy / NaiveProxy 连接参数及导入 URI
├── caddy-qr.png       # NaiveProxy 二维码图片
├── hysteria2.txt      # Hysteria2 连接参数及导入 URI
├── hysteria2-qr.png   # Hysteria2 二维码图片
├── trojan.txt         # Trojan 连接参数及导入 URI
├── trojan-qr.png      # Trojan 二维码图片
├── xray.txt           # VLESS Reality 连接参数及导入 URI
├── xray-qr.png        # VLESS Reality 二维码图片
└── h2client.txt       # H2 Client 连接参数
```

重复运行脚本时，每个服务只更新自己的文件，其他服务的文件保持不变。

---

## 客户端推荐

### 浏览器代理分流

Chrome 插件 [Proxy SwitchyOmega](https://chromewebstore.google.com/detail/proxy-switchyomega-3-zero/pfnededegaaopdmhkdmcofjmoldfiped?hl=zh-CN)，配合 SOCKS5 端口使用。

### 移动端 / 桌面端

- **NaiveProxy**：服务器域名:端口 + 用户名/密码
- **Hysteria2**：服务器域名:端口 + 密码
- **Trojan**：服务器域名:端口 + 密码
- **VLESS Reality**：服务器 IP:端口 + UUID + PublicKey + ShortId + SNI（见 `/data/connection-info/xray.txt`）

---

## 排错

```bash
# 查看服务状态与日志
systemctl status caddy
systemctl status h2server
systemctl status trojan
systemctl status xray
systemctl status h2client

# 手动前台运行查看详细输出
/data/caddy/caddy run --config /data/caddy/Caddyfile
/data/hysteria/hysteria server -c /data/hysteria/server.yaml
/data/trojan/trojan-go -config /data/trojan/server.json
/data/xray/xray run -c /data/xray/config.json
```

| 问题 | 排查方向 |
|------|---------|
| 域名解析失败 | 确认 A/AAAA 记录已指向 VPS 公网 IP，等待解析生效 |
| 端口被占用 | `ss -tlnp` 或 `netstat -tlnp` 查看占用进程，脚本会自动识别 |
| ACME 证书申请失败 | 域名需正确解析，80/443 端口需可访问，防火墙放行 |
| 服务启动失败 | 手动前台运行查看日志 |
| 防火墙未放行 | `ufw allow 端口` 或 `firewall-cmd --add-port=端口/协议 --permanent` |

---

## 安全建议

- 防火墙仅放行必要端口
- 密码使用脚本随机生成的强密码
- 不使用的服务及时停用：`systemctl disable --now 服务名`
- 定期更新二进制（重新执行 `download-bins.sh` 后覆盖安装）

---

## VPS 推荐

DMIT Premium 网络，CN2/CMIN2 优化线路，稳定低延迟。
邀请注册：https://www.dmit.io/aff.php?aff=12025
