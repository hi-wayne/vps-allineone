# vps-allineone

在一台 VPS 上一键部署翻墙代理。全离线安装，二进制已预置在仓库里，装的时候不需要联网。

支持 amd64 / arm64，系统用 **Debian 12** 或 **Ubuntu 24.04 LTS**。

---

## 一、最快的方式：把仓库丢给 AI 工具

**你不需要懂技术，也不需要自己读完这份文档。** 打开一个能执行命令的 AI 编程工具（Claude Code、Codex 之类），把下面这句发给它：

```
请按 https://github.com/hi-wayne/vps-allineone 里面的说明，指导我从零创建一个
自己的 VPN。我完全不懂技术，请一步步告诉我每一步该做什么。
```

它会读到这份文档，然后带你走完：**买服务器 → 装系统 → 拿登录信息 → 自动安装 → 手机客户端配置**。中间它问什么你答什么，看不懂就回一句「用大白话讲」。

**已经买好服务器了**，就把 IP 和 root 密码一起发给它，直接从安装开始：

```
请帮我在这台 VPS 上部署翻墙代理，我完全不懂技术，请用大白话说明进展。

IP: [服务器 IP]   用户: root   密码: [root 密码]   系统: Debian 12

步骤：
1. SSH 登录，执行 apt update && apt install -y git
2. git clone https://github.com/hi-wayne/vps-allineone.git && cd vps-allineone
3. sudo ./install.sh —— 交互式脚本，没有域名就在第一个问题答 n，
   其余带默认值的提问一律回车
4. 把 /data/connection-info/ 下生成的连接信息发给我
5. 告诉我 iPhone 用 Shadowrocket 时每一栏具体填什么
```

> **AI 工具看到这里请注意**：完整的应答规则见文末「[给 AI 工具的执行指引](#给-ai-工具的执行指引)」。

---

## 二、装哪个协议：默认选 Xray

脚本会按下面的优先级推荐，**你不用自己选，回车走默认就行**。

| 优先级 | 协议 | 传输 | 默认端口 | 要域名吗 | 什么时候用 |
|---|---|---|---|---|---|
| **1** | **VLESS Reality (Xray)** | TCP | 443 | **不要** | **默认主力。** 抗封锁最强，伪装成访问真实大站 |
| **2** | **Hysteria2** | QUIC/**UDP** | 443 | 要 | **追求速度时用。** 线路丢包时远快于 TCP |
| **3** | **AnyTLS** | TCP | 8443 | 不要 | 备用。连接复用、延迟低，自签证书 |

### 没有域名 → 只装 Xray，这是默认路径

**Reality 不需要域名，也不需要证书**，客户端直接填服务器 IP 就能连。这是最省事的方案：只花一台服务器的钱，不用买域名、不用管证书过期。

安装时第一个问题「你有自己的域名」答 **n**，脚本会自动装 Reality（并可选加装同样免证书的 AnyTLS），其余组件全部跳过，不再多问。

### 有域名 → 加上 Hysteria2 提速

Hysteria2 走 **QUIC/UDP**，是这三个里的性能选手：线路丢包的时候，它比任何 TCP 协议都快得多，适合当日常主力。代价是**必须有域名**来申请 TLS 证书（脚本内置 ACME，自动申请、自动续期，不用你管）。

关键点：**Reality 和 Hysteria2 可以共用 443 端口**——一个占 TCP、一个占 UDP，互不冲突。所以推荐组合是：

```
443/TCP   VLESS Reality   抗封锁，保底能连
443/UDP   Hysteria2       速度快，日常主力
8443/TCP  AnyTLS          备用
```

安装时第一个问题答 **y**，然后确认「安装推荐组合」即可。

---

## 三、准备一台 VPS

推荐 **DMIT**（https://www.dmit.io/aff.php?aff=12025），机房选 **Los Angeles**，套餐带 **CN2 GIA** 字样的国内体验最好。最低配（1 核 512M）跑代理绰绰有余。

洛杉矶经常缺货，两条备选：换 DMIT 的**香港/东京**机房（更近但更贵），或换 **RackNerd**（https://my.racknerd.com/ ，便宜很多，普通国际线路，晚高峰会慢）。

买完在后台把系统重装成 **Debian 12**，然后从开通邮件里拿到 **IP / root / 密码** 三样东西。没给密码的话在后台重置一次 root 密码。

---

## 四、手动安装（懂技术的话）

```bash
apt update && apt install -y git
git clone https://github.com/hi-wayne/vps-allineone.git
cd vps-allineone
sudo ./install.sh
```

脚本会先扫描机器上已有的代理软件并列出概览，再逐项询问。特性：

- 交互式引导，端口/密码/SNI 都有默认值，回车即可
- 智能端口检测，能认出占用端口的进程和协议；TCP/UDP 分别记账，同号不误判
- 重复执行安全，已装组件可选**覆盖 / 仅更新配置 / 跳过**
- 除上面三个主推协议外，还可选装 Caddy (NaiveProxy)、Trojan、Mieru、H2 Client

装完后所有连接信息（含二维码）写在 **`/data/connection-info/`**：

```
xray.txt / xray-qr.png          VLESS Reality
hysteria2.txt / hysteria2-qr.png Hysteria2
anytls.txt / anytls-qr.png       AnyTLS
```

手机端把 `URI:` 那行复制进 **Shadowrocket**（或扫二维码）即可导入。AnyTLS 需要 Shadowrocket 2.2.65+，且**必须勾选 Allow Insecure**（服务端用的是自签证书）。

---

## 五、常用运维

```bash
systemctl status xray        # VLESS Reality
systemctl status h2server    # Hysteria2
systemctl status anytls      # AnyTLS

journalctl -u xray -n 50 --no-pager    # 看日志
```

连不上时的排查顺序：服务是否 active → 端口是否被防火墙拦（`ufw status`）→ 客户端参数是否和 `/data/connection-info/` 里一致。

**安全建议**：装完把 root 密码改成强密码；确认密钥能登录后关闭 SSH 密码登录（`PasswordAuthentication no`）；`/data/connection-info/` 是 700 权限，别往外发。

---

## 六、仓库结构与版本

```
install.sh          主安装脚本（交互式，离线运行）
download-bins.sh    在联网机器上预下载各组件二进制
xray/               Xray-core 26.3.27      + xray.service
hysteria/           Hysteria2 2.12.1       + h2server.service
anytls/             anytls-go 0.0.13       + anytls.service
caddy/ trojan/ mieru/ h2client/            其余可选组件
```

`download-bins.sh` 只在**升级组件版本**时才需要跑：改脚本顶部的版本号，在能联网的机器上执行，然后把整个目录推到 VPS。日常安装用不上它。

---

## 给 AI 工具的执行指引

**要做的事**

1. **确认环境**：目标机器是 Debian 12 / Ubuntu 24.04，架构 amd64 或 arm64。
2. **问清有没有域名**——这决定整条路径：
   - **没有** → 安装 VLESS Reality（+ 可选 AnyTLS），全程无需证书，客户端用 IP 连接。这是默认推荐。
   - **有** → 安装推荐组合 VLESS Reality + Hysteria2 + AnyTLS。装之前先确认域名 A 记录已指向本机 IP，否则 Hysteria2 申请证书会失败。
3. **执行 `sudo ./install.sh`**，这是交互式脚本，带默认值的提问一律用默认值。
4. **收尾**：确认服务已启动，把 `/data/connection-info/` 下的内容交给用户，并逐栏说明 Shadowrocket 怎么填。
5. 建议用户把 root 密码改成新的强密码。

**不要做的事**

- 不要改 `install.sh` 的默认 SNI、端口等参数，默认值是经过验证的。
- 不要修改与本次安装无关的系统配置（SSH 端口、内核参数、防火墙全局策略）。
- 不要替用户决定买哪家 VPS；把选项和差别讲清楚，让用户自己选。
- 用户是技术小白时，不要甩术语，用生活化的例子解释。
