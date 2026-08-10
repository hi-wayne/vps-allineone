# vps-allineone

## 最快的开始方式：把这一句话发给 AI 工具

什么都不用懂，连服务器都还没买也没关系。打开一个能联网、能执行命令的 AI 工具（比如 Claude Code），把下面这句话发给它：

```
请按 https://github.com/hi-wayne/vps-allineone 里面的说明，指导我从零创建一个
自己的 VPN。我完全不懂技术，请一步步告诉我每一步该做什么。
```

它会读到本文档，然后带着你走完全程：**买服务器 → 装系统 → 拿登录信息 → 自动安装 → 手机/电脑客户端配置**。中间它问你什么就答什么，看不懂就直接回一句「这是什么意思，用大白话讲」。

如果你已经买好服务器了，可以把 IP 和 root 密码一起发给它，会更快。想自己看清每一步再动手的，往下看「[完全不懂技术？让 AI 工具帮你装](#完全不懂技术让-ai-工具帮你装)」。

> **AI 工具请注意**：如果你是接到上面那句话的 AI 工具，请直接按「[给 AI 工具的执行指引](#给-ai-工具的执行指引人类可跳过)」一节执行，那里有完整的应答规则和注意事项。

---

## 这个仓库是什么

一键在 VPS 上部署多种代理协议，支持 **Caddy (NaiveProxy)**、**Hysteria2**、**Trojan**、**VLESS Reality (Xray)**、**H2 Client**。

**优先支持 Hysteria2 + VLESS Reality 这两个组件**：有域名时安装脚本会直接推荐这个组合，两者可同用 443（Hysteria2 占 UDP、Reality 占 TCP），互不冲突。Hysteria2 走 QUIC，线路丢包时速度远好于 TCP 协议，适合做日常主力；Reality 抗封锁最强、无需证书，适合做备用。

- 交互式安装，引导填写域名/端口/密码，支持随机生成
- 全离线部署，所有二进制预先下载好，安装时无需联网
- 自动检测已安装的代理软件并展示概览
- 重复执行安全，已安装组件可选覆盖/仅更新配置/跳过
- 智能端口检测，识别占用端口的进程与协议
- 支持架构：amd64、arm64

---

## 完全不懂技术？让 AI 工具帮你装

如果你不了解 VPN、代理、Linux，只想要一个能用的翻墙服务，按下面五步走。全程你只需要复制粘贴，技术活交给 AI 工具做。

**你不需要看懂任何技术名词**，也不需要决定用什么协议、要不要买域名——下面给的默认方案是最省事的一种：只买一台服务器，不用买域名。

### 先花 30 秒认识三个词

看完这三句就够了，其他名词后面都不用你管。

| 名词 | 大白话解释 |
|------|-----------|
| **VPS** | 就是一台租来的电脑，放在国外，24 小时开着。你花钱租它，让它帮你转发上网流量。一个月十几到几十块。 |
| **域名** | 就是 `baidu.com` 这种网址。它的作用是给一台服务器起个好记的名字，代替 `123.45.67.89` 这种数字。**下面的默认方案不需要域名**，直接用数字地址就能用，不用买、不用管。 |
| **协议** | 你的手机和这台国外电脑之间「说话的方式」。方式不同，伪装效果和速度不同。**你不用选**，默认方案会装当前最好用的那种（VLESS Reality），它的最大优点正是不需要域名。 |

> 后面出现的 SNI、UUID、ACME、证书之类的词，全部由脚本和 AI 工具处理，你看到了直接跳过就行。

### Step 1  买一台 VPS（服务器）

推荐 **DMIT**，CN2/CMIN2 优化线路，国内访问延迟低、稳定：

- 注册地址：https://www.dmit.io/aff.php?aff=12025
- 机房选 **Los Angeles（洛杉矶）**，套餐里带 **Premium / CN2 GIA** 字样的线路国内体验最好
- 最低配置（1 核 / 512M 内存）就够跑代理，不用买大配置
- 付款后等几分钟，DMIT 会发一封邮件给你

#### 洛杉矶缺货怎么办

DMIT 的洛杉矶 CN2 GIA 套餐经常卖光（页面显示 Out of Stock / 无货），有两条备选路：

1. **换 DMIT 的其他机房**：**香港** 或 **日本东京** 也可以，物理距离更近、延迟通常更低，缺点是价格比洛杉矶贵一些、带宽小一些。买之前看清套餐里的线路说明。
2. **换服务商**：**RackNerd** —— https://my.racknerd.com/ ，价格便宜很多（常有年付十几美元的促销），机房选 **Los Angeles**。代价是它走的是普通国际线路，不是 CN2 优化线路，晚上高峰时段（20:00-24:00）可能变慢。预算有限、或只是想先试试的话，它完全够用。

不管在哪买、买谁的，本仓库的安装流程都一样，后面的步骤照做即可。

### Step 2  装系统时选 Debian 12

在服务商后台的机器管理页面（或开通时的选项里）选择操作系统，**选 Debian 12**（**Ubuntu 24.04 LTS** 也已实测可用，二选一都行）。别的系统没验证过，可能装不上。

> RackNerd 等服务商的后台里这个功能一般叫 **Reinstall / Rebuild / 重装系统**，在系统列表里挑 Debian 12 即可。重装会清空机器上的数据，新买的机器无所谓。

### Step 3  找到登录服务器要用的三样东西

从服务商的开通邮件或后台控制台里找到（DMIT、RackNerd 都一样）：

| 要找的东西 | 长什么样 | 在哪找 |
|-----------|---------|--------|
| 服务器 IP | `123.45.67.89` | 开通邮件 / 后台机器详情页 |
| 登录用户名 | 一般就是 `root` | 同上 |
| 登录密码 | 一串随机字符 | 开通邮件；忘了可在后台重置 root 密码 |

> 有些套餐默认只让 SSH 密钥登录。如果邮件里没有密码，去后台把 root 密码重置一下，拿到密码即可。

### Step 4  把下面这段话交给 AI 工具

用任意能执行命令的 AI 编程工具（如 Claude Code），把下面整段复制进去，**只需要把两处方括号换成 Step 3 拿到的 IP 和密码**，其他一个字都不用改，然后发送：

```
请帮我在一台 VPS 上部署翻墙代理服务。我完全不懂技术，请全程用大白话告诉我
进展；需要我做什么操作时，一步一步说清楚点哪里；我问任何名词请用生活里的
例子解释，不要甩术语给我。

服务器信息：
- IP: [填你的服务器 IP]
- 用户: root
- 密码: [填你的 root 密码]
- 系统: Debian 12

请按这个流程做：
1. SSH 登录到这台服务器
2. 执行 apt update && apt install -y git
3. git clone https://github.com/hi-wayne/vps-allineone.git && cd vps-allineone
4. 执行 sudo ./install.sh，这是个交互式脚本，请这样回答：
   - 第一个问题「你有自己的域名」          → 回答 n
     （回答 n 之后脚本会自动只装 VLESS Reality，不会再问其他组件）
   - 之后所有带默认值的提问（端口、SNI 等） → 一律直接回车用默认值
5. 装完后把 /data/connection-info/xray.txt 的内容完整发给我
6. 告诉我在手机和电脑上分别用什么客户端软件、怎么把这段连接信息导入进去。
   如果我用 iPhone 的 Shadowrocket，请把每一栏该填什么逐项列给我：地址、端口、
   UUID、流控、传输方式、TLS 开关、SNI、公钥(PublicKey)、ShortID、指纹
```

发出去之后你基本不用管了，AI 工具会自己登录、下载、装好。中间它可能问你一两个问题，照它说的答即可；看不懂就直接回它「这是什么意思，用大白话讲」。

### Step 5  拿到连接信息，装客户端

脚本跑完后，AI 工具会把连接信息给你，长这样：

```
URI: vless://xxxxxxxx@123.45.67.89:443?security=reality&flow=xtls-rprx-vision&sni=www.samsung.com&pbk=...&sid=...&fp=chrome&type=tcp#VPS-Reality
```

把这段 `vless://...` 整个复制，粘贴到客户端软件里（客户端一般有「从剪贴板导入」的按钮）。手机上还可以直接扫服务器上生成的二维码图片 `/data/connection-info/xray-qr.png`。

客户端选哪个，直接问 AI 工具「我用 iPhone / 安卓 / Windows / Mac，装哪个客户端」，它会告诉你当前能用的。

#### iPhone：Shadowrocket 怎么填（逐项对照）

**最省事的办法**：复制那段 `vless://...`，打开 Shadowrocket，右上角 **+**，类型选 **Subscribe / 或直接点首页顶部弹出的「从剪贴板添加」**，它会自动把所有参数填好。扫 `xray-qr.png` 二维码也一样。

如果自动导入失败，就手动加一个节点：右上角 **+** → 类型选 **VLESS**，然后按下表逐项填。左边是 Shadowrocket 里的字段名，右边是从 `/data/connection-info/xray.txt` 里对应抄哪一项：

| Shadowrocket 字段 | 填什么 | 从哪抄 |
|------------------|--------|--------|
| 类型 | `VLESS` | — |
| 地址 | DMIT 主机的 IP，如 `123.45.67.89` | `xray.txt` 里 URI 中 `@` 后面那串数字 |
| 端口 | `443` | `Port` 那行 |
| UUID | 一长串带横线的字符 | `UUID` 那行 |
| 流控（Flow） | `xtls-rprx-vision` | `Flow` 那行，固定就是这个 |
| 传输方式（Transport） | **none** | 固定选 none，不要选 ws / grpc / h2 |
| TLS | **打开（开启）** | — |
| SNI（有的版本叫 Peer 名称） | 伪装域名 `www.samsung.com` | `SNI` 那行 |
| 公钥（PublicKey / Reality 公钥） | 一串 43 位字符 | `PublicKey` 那行 |
| ShortID（Short ID） | 8 位字母数字，如 `a1b2c3d4` | `ShortId` 那行 |
| 指纹（Fingerprint） | `chrome` | — |
| 允许不安全（Allow Insecure） | **关闭** | — |

**几个最容易填错、导致连不上的地方**：

- **地址填 IP，不要填 SNI 那个域名**。`www.samsung.com` 只是用来伪装的「幌子」，不是你的服务器，填进地址栏一定连不上。
- **传输方式必须是 none**。选了 ws / grpc 会握手失败。
- **TLS 必须打开**，同时 **公钥（PublicKey）和 ShortID 一个都不能漏**——这两项是 Reality 的身份凭证，漏了就连不上。有些 Shadowrocket 版本要先把 TLS 开关打开，公钥和 ShortID 的输入框才会出现。
- **SNI 必须和服务器上的一致**。服务器默认是 `www.samsung.com`，客户端也必须一字不差地填它。
- **允许不安全（Allow Insecure）保持关闭**。Reality 靠的就是真证书校验，打开反而不对。

安卓（v2rayNG / Nekobox）、Windows / Mac（v2rayN、Clash Verge、sing-box）填的字段名基本一样，一一对应上表即可；这些客户端也都支持直接粘贴 `vless://` 链接导入。

### 进阶（可选，不看也不影响使用）：想再快一点，可以多买个域名

上面的方案已经能正常上网了，看视频也够。如果你后来觉得想更快、或者网络环境比较差（比如经常掉线、丢包多），可以再花一年几十块买一个域名，多装一个 **Hysteria2**。

为什么这个要买域名：Hysteria2 需要一张「身份证明」（TLS 证书）才能工作，而免费发证书的机构只认域名，不认 `123.45.67.89` 这种数字地址。VLESS Reality 不需要证书，所以不用域名——这就是它被设为默认的原因。

| 协议 | 要买域名吗 | 大白话 |
|------|-----------|--------|
| **VLESS Reality**（默认装） | 不用 | 把自己的流量伪装成访问某个真实大网站，只要服务器的数字地址就能跑，最抗封锁 |
| **Hysteria2**（可选加装） | 要 | 走另一条更「冲」的通道，网络差的时候速度明显更好 |

想加装的话，域名在阿里云、腾讯云、Cloudflare、Namecheap 之类的地方都能买，买完还要做一步「把域名指向你的服务器」的设置。这些都不用自己研究，把下面这段发给同一个 AI 工具，让它带你做：

```
我已经装好 VLESS Reality 了，现在想再加装 Hysteria2。我买了域名 [填你的域名]，
服务器还是之前那台。请：
1. 先教我在域名服务商后台怎么添加一条指向服务器 IP 的记录，一步步说点哪里
2. 确认域名已经生效后，重新运行 vps-allineone 目录下的 sudo ./install.sh
3. 这次第一个问题「你有自己的域名」回答 y，然后只在问 Hysteria2 时回答 y 并填
   我的域名，其他组件一律回答 n（已装好的 VLESS Reality 如果被问到，选「跳过」），
   端口和密码直接回车用默认
4. 装完把 /data/connection-info/hysteria2.txt 的内容发给我，并告诉我怎么导入客户端
```

### 安全提醒

- 把 root 密码交给 AI 工具，等于让它拥有这台服务器的完全控制权。**只在自己买的、没有别的用途的服务器上这么做**，不要把公司或他人的服务器密码贴给 AI 工具。
- 装完后建议让 AI 工具帮你把 root 密码改成一个新的强密码。
- 连接信息（UUID、PublicKey）等同于密码，不要发到群里或公开的地方。

---

## 给 AI 工具的执行指引（人类可跳过）

> 如果你是被用户要求「按这个仓库的说明指导我创建 VPN」的 AI 工具，按本节执行。

**沟通原则**

- 假设用户完全不懂技术。全程用大白话，不要输出术语而不解释，不要贴大段命令让用户自己看。
- 一次只让用户做一件事，等他回复确认后再进行下一步。
- 用户没有主动提「域名」，你就不要提域名、证书、ACME、SNI 这些概念——默认方案不需要它们。

**执行流程**

1. **确认前提**：先问用户「有没有已经买好的国外 VPS」。
   - 没有 → 按本文档 Step 1 引导他购买：首选 DMIT 洛杉矶（CN2 GIA），缺货则建议 DMIT 香港/东京，或 RackNerd 洛杉矶。告诉他最低配置即可。
   - 有 → 直接进第 3 步。
2. **系统**：要求系统是 **Debian 12**（Debian 11/10、Ubuntu 24.04 LTS 也已验证支持）。如果他买的是别的系统，引导他在服务商后台 Reinstall / Rebuild 成 Debian 12 或 Ubuntu 24.04，并提醒重装会清空数据。**如果他坚持用 CentOS/Arch 等，明确告知本脚本未在这些系统上验证过，可能失败。**
   - Ubuntu 上如果 `apt install` 报 dpkg 锁被 `unattended-upgr` 占用，等几分钟它跑完再重试，不要去 kill 它或删锁文件。
3. **收集凭据**：向用户索取服务器 IP、用户名（一般是 root）、密码。同时提醒他：这等于把服务器的完全控制权交给你，只应该在他自己买的、没有其他用途的机器上这么做。**不要在后续的总结或回复里重复回显这个密码。**
4. **安装**：SSH 登录后依次执行
   ```bash
   apt update && apt install -y git
   git clone https://github.com/hi-wayne/vps-allineone.git
   cd vps-allineone && sudo ./install.sh
   ```
   `install.sh` 是交互式的，按下面的规则应答：
   - 第一个问题「你有自己的域名」→ 用户没有域名就答 **n**，脚本会自动只安装 VLESS Reality 并跳过其余全部组件询问。
   - 用户明确说有域名 → 答 **y**，接着脚本会问「安装推荐组合（Hysteria2 + VLESS Reality）」→ 答 **y**，两个组件会一起装好并跳过其余组件询问；域名填他提供的那个，安装前先确认 A 记录已指向本机（且 Cloudflare 上必须是 **DNS only 灰云**，开橙云代理会导致证书申请和 QUIC 都失败）。
   - 需要装推荐组合之外的组件时，对推荐组合答 **n**，再在完整组件菜单里逐个选。
   - 其余所有带默认值的提问（端口、SNI、回落目标、密码）→ 一律回车用默认值。Hysteria2 与 Reality 同用 443 不冲突：前者占 UDP、后者占 TCP，脚本会自动跳过 Hysteria2 的 HTTP 伪装站点以避开 TCP 端口冲突。
   - 若脚本报告某组件已安装并给出「覆盖 / 仅更新配置 / 跳过」三选，默认选**跳过**，除非用户要求重装。
5. **交付连接信息**：读取 `/data/connection-info/xray.txt`（装了 Hysteria2 则还有 `hysteria2.txt`），把里面的 `vless://` 链接完整给用户。
6. **指导客户端**：问用户用什么设备，然后给出对应客户端并**逐项**说明怎么填。iPhone / Shadowrocket 的字段对照见本文档「iPhone：Shadowrocket 怎么填」一节——务必包含 **公钥(PublicKey) 和 ShortID**，漏掉这两项连不上；并提醒他地址栏填服务器 IP、不是 SNI 里那个伪装域名。
7. **收尾**：确认服务已启动（`systemctl status xray`），告诉用户日后怎么查看状态和重启，并建议他把 root 密码改成新的强密码。

**不要做的事**

- 不要修改与本次安装无关的系统配置（SSH 端口、内核参数、防火墙全局策略等），除非用户要求。
- 不要替用户改动 `install.sh` 的默认 SNI、端口等参数——默认值是经过验证的。
- 不要跳过交互式提问去手写配置文件；用脚本生成，才能保证与 systemd 服务、证书策略一致。

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

本脚本已在 **Debian** 和 **Ubuntu** 上验证过，推荐使用 Debian 12 或 Ubuntu 24.04 LTS 作为 VPS 操作系统。

| 系统版本 | 代号 | 状态 | 兼容性 |
|---------|------|------|--------|
| Debian 12 | Bookworm | 当前稳定版 | 完全支持 |
| Debian 11 | Bullseye | 旧稳定版 | 完全支持 |
| Debian 10 | Buster | 已停止维护（EOL） | 支持，脚本自动切换包源到 archive.debian.org |
| Ubuntu 24.04 LTS | Noble | 当前 LTS | 完全支持（已实测） |
| Ubuntu 22.04 LTS | Jammy | 旧 LTS | 理论可用，未实测 |
| Debian 9 及以下 | — | 已停止维护 | 未测试 |

> **Debian 10 说明**：官方包源已停止服务，脚本安装 `qrencode` 等工具时会自动将包源切换到归档镜像（`archive.debian.org`），无需手动操作。

> **Ubuntu 说明**：新装的 Ubuntu 开机后 `unattended-upgrades`（自动安全更新）会占用 apt 锁，此时安装 `qrencode` 会报 `Could not get lock /var/lib/dpkg/lock-frontend`。等它跑完（通常几分钟）再重试即可，不用改任何配置。

其他发行版（CentOS、Arch 等）理论上可用，但未经过测试验证。

---

## 内置安装包版本

仓库中已预置所有组件的二进制文件，克隆后**无需联网**即可安装。

| 组件 | 版本 | 架构 |
|------|------|------|
| Caddy（含 NaiveProxy 插件） | 自定义编译 | amd64 |
| Hysteria2 | 2.12.1 | amd64、arm64 |
| Trojan-go | 0.10.6 | amd64、arm64 |
| Xray-core | 26.3.27 | amd64、arm64 |
| H2 Client（Hysteria2 客户端） | 2.12.1 | amd64、arm64 |
| Mieru (mita) | 3.32.0 | amd64、arm64 |

> Hysteria2 2.12.1 是上游标记为 urgent 的更新；Xray 26.3.27 会对 apple/icloud 类伪装目标发出告警，本仓库默认 SNI 已相应改为 `www.samsung.com`。Trojan-go 上游已停止维护，版本停留在 0.10.6，与 Mieru 一样不在优先支持范围内。

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
git clone https://github.com/hi-wayne/vps-allineone.git
cd vps-allineone
```

### Step 2  执行安装

```bash
cd vps-allineone
sudo ./install.sh
```

安装脚本会依次：

1. **扫描本机已有代理软件**，展示各服务运行状态、协议、端口、域名
2. **询问是否有自己的域名** —— 回答「否」则直接只安装 VLESS Reality，跳过其余全部组件询问；回答「是」才展开完整的组件选择菜单
3. **检测各组件二进制是否就绪**，有包才询问是否安装
4. **交互式配置**，引导填写域名/端口/密码（支持回车随机生成）
5. **检查域名解析**是否指向本机
6. **检查端口占用**，识别占用进程与协议
7. **写入配置到 `/data/`**，安装并启动 systemd 服务
8. **生成连接信息**到 `/data/connection-info/` 目录（每个服务独立文件）

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
| SNI | www.samsung.com |
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
- **VLESS Reality**：服务器 IP:端口 + UUID + PublicKey + ShortId + SNI（见 `/data/connection-info/xray.txt`）；Shadowrocket 逐项填法见上方「[iPhone：Shadowrocket 怎么填](#iphoneshadowrocket-怎么填逐项对照)」

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

**首选 DMIT**：Premium 网络，CN2/CMIN2 优化线路，稳定低延迟。
邀请注册：https://www.dmit.io/aff.php?aff=12025

洛杉矶套餐缺货时的备选：

| 备选 | 说明 |
|------|------|
| DMIT 香港 / 日本东京 | 距离近、延迟低，价格偏高、带宽偏小 |
| [RackNerd](https://my.racknerd.com/) | 价格便宜（常有年付十几美元促销），机房选 Los Angeles；普通国际线路，晚高峰可能变慢 |

安装流程与服务商无关，任意提供 Debian 12 和 root 权限的 VPS 均可。
