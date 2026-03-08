#!/usr/bin/env bash
# vps-allineone 交互式安装脚本
# 支持组件：Caddy (NaiveProxy)、Hysteria2、Trojan、VLESS Reality (Xray)、H2 Client
# 所有二进制须预先通过 download-bins.sh 下载到本地目录，安装时无需联网。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── 基础检查 ────────────────────────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 或 sudo 运行此脚本。"
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "未找到 systemctl，本脚本需要基于 systemd 的 Linux 系统。"
  exit 1
fi

# ─── 辅助命令检测 ────────────────────────────────────────────────────────────
have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ─── 系统检测 ────────────────────────────────────────────────────────────────
detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    echo "${ID:-unknown}"
  elif [[ -f /etc/redhat-release ]]; then
    echo "rhel"
  elif [[ -f /etc/debian_version ]]; then
    echo "debian"
  else
    echo "unknown"
  fi
}

detect_os_family() {
  case "$(detect_os)" in
    debian|ubuntu|linuxmint|pop|kali|raspbian) echo "debian" ;;
    centos|rhel|fedora|rocky|almalinux|ol)     echo "rhel"   ;;
    arch|manjaro|endeavouros)                   echo "arch"   ;;
    alpine)                                     echo "alpine" ;;
    opensuse*|sles)                             echo "suse"   ;;
    *)                                          echo "unknown";;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l)        echo "armv7" ;;
    armv6l)        echo "armv6" ;;
    i386|i686)     echo "386"   ;;
    *)             uname -m     ;;
  esac
}

OS_ID="$(detect_os)"
OS_FAMILY="$(detect_os_family)"
ARCH="$(detect_arch)"


# ─── 交互函数 ────────────────────────────────────────────────────────────────
prompt() {
  local var_name="$1" message="$2" default="${3:-}" value=""
  while true; do
    if [[ -n "$default" ]]; then
      read -r -p "  ${message} [${default}]: " value
      value="${value:-$default}"
    else
      read -r -p "  ${message}: " value
    fi
    if [[ -n "$value" ]]; then
      printf -v "$var_name" '%s' "$value"
      return 0
    fi
    echo "  输入不能为空。"
  done
}

prompt_optional() {
  local var_name="$1" message="$2" default="${3:-}" value=""
  if [[ -n "$default" ]]; then
    read -r -p "  ${message} [${default}]: " value
    value="${value:-$default}"
  else
    read -r -p "  ${message}（可留空）: " value
  fi
  printf -v "$var_name" '%s' "$value"
}

random_token() {
  local length="${1:-16}"
  if have_cmd openssl; then
    openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-"$length"
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
  fi
}

prompt_with_random_default() {
  local var_name="$1" message="$2" length="${3:-16}" value="" default
  default="$(random_token "$length")"
  read -r -p "  ${message} [${default}]: " value
  printf -v "$var_name" '%s' "${value:-$default}"
}

confirm() {
  local message="$1" default="${2:-y}" reply="" prompt_str
  [[ "$default" == "y" ]] && prompt_str="Y/n" || prompt_str="y/N"
  while true; do
    read -r -p "  ${message} [${prompt_str}]: " reply
    [[ -z "$reply" ]] && reply="$default"
    case "$reply" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *)   echo "  请输入 y 或 n。" ;;
    esac
  done
}

# ─── 端口检测（智能识别进程与协议） ─────────────────────────────────────────

# 获取占用指定端口的进程 PID（兼容 mawk/gawk/nawk）
_port_pid() {
  local port="$1" proto="${2:-tcp}" pid=""
  if have_cmd ss; then
    local flag; [[ "$proto" == "udp" ]] && flag="-ulnp" || flag="-tlnp"
    # 用 grep -oP 替代 gawk 专有的 match(str,re,arr) 语法
    pid=$(ss $flag 2>/dev/null \
      | grep -E "(:|^)${port} " \
      | grep -oP 'pid=\K[0-9]+' \
      | head -1)
  fi
  if [[ -z "$pid" ]] && have_cmd netstat; then
    local flag; [[ "$proto" == "udp" ]] && flag="-ulnp" || flag="-tlnp"
    pid=$(netstat $flag 2>/dev/null \
      | awk -v p=":${port}" '$4 ~ p"$" { split($NF,a,"/"); if(a[1]+0>0) print a[1] }' \
      | head -1)
  fi
  echo "${pid:-}"
}

# 根据进程名猜测协议描述
_guess_proto() {
  case "$1" in
    nginx|apache2|httpd|lighttpd|tengine) echo "HTTP/HTTPS Web Server" ;;
    sshd|ssh)       echo "SSH" ;;
    caddy)          echo "Caddy（NaiveProxy）" ;;
    hysteria*)      echo "Hysteria2 (QUIC)" ;;
    trojan*)        echo "Trojan" ;;
    xray)           echo "Xray（多协议代理）" ;;
    v2ray)          echo "V2Ray（多协议代理）" ;;
    sing-box)       echo "sing-box（多协议代理）" ;;
    ss-server|shadowsocks*) echo "Shadowsocks" ;;
    frps|frpc)      echo "FRP 内网穿透" ;;
    docker-proxy)   echo "Docker 端口映射" ;;
    openvpn)        echo "OpenVPN" ;;
    wg-quick|wireguard) echo "WireGuard VPN" ;;
    mysqld|mariadbd) echo "MySQL/MariaDB" ;;
    postgres*)      echo "PostgreSQL" ;;
    redis-server)   echo "Redis" ;;
    *)              echo "" ;;
  esac
}

# 检查端口是否被占用（支持 tcp/udp）
port_in_use() {
  local port="$1" proto="${2:-tcp}"
  if have_cmd ss; then
    local flag; [[ "$proto" == "udp" ]] && flag="-ulnH" || flag="-tlnH"
    ss $flag 2>/dev/null | awk '{print $4}' | grep -Eq "(:|^)${port}$"
  elif have_cmd netstat; then
    local flag; [[ "$proto" == "udp" ]] && flag="-ulnt" || flag="-tlnt"
    netstat $flag 2>/dev/null | awk '{print $4}' | grep -Eq "(:|^)${port}$"
  else
    return 2
  fi
}

# 检查端口，打印占用详情。返回 0=空闲，1=占用
check_port_smart() {
  local port="$1" proto="${2:-tcp}"
  if port_in_use "$port" "$proto"; then
    local pid proc proto_guess msg
    pid="$(_port_pid "$port" "$proto")"
    proc=""
    [[ -n "$pid" ]] && proc="$(cat /proc/"$pid"/comm 2>/dev/null | tr -d '\n' || true)"
    proto_guess="$(_guess_proto "$proc")"

    msg="  警告：${proto^^} 端口 ${port} 已被占用"
    if [[ -n "$proc" ]]; then
      msg+="（进程: ${proc}"
      [[ -n "$proto_guess" ]] && msg+="，协议: ${proto_guess}"
      msg+="）"
    fi
    echo "$msg"
    return 1
  fi
  return 0
}

# ─── ACME 证书策略协调 ───────────────────────────────────────────────────────
# 跨服务跟踪 ACME 端口占用，避免多个服务争抢 port 80/443
ACME_HTTP_CLAIMED="no"   # 是否已有服务认领 HTTP Challenge (port 80)

# Caddy 默认证书路径（root 运行）
_caddy_cert() { echo "/root/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${1}/${1}.crt"; }
_caddy_key()  { echo "/root/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${1}/${1}.key"; }

# 为服务决定最优 ACME 策略
# 参数: domain  tcp_port（服务监听的 TCP 端口，供 TLS-ALPN 用；无 TCP 端口传空）
# stdout 输出:
#   http           → HTTP Challenge，使用 port 80
#   tls-alpn:PORT  → TLS-ALPN Challenge，在指定 TCP 端口完成
#   caddy-cert     → 复用 Caddy 已管理/即将管理的证书文件（无需独立 ACME）
resolve_acme() {
  local domain="$1" tcp_port="${2:-}"

  # 优先：Caddy 正在本次安装中且域名相同 → 复用（Caddy 启动后自动获取）
  if [[ "${INSTALL_CADDY:-no}" == "yes" && "${CADDY_DOMAIN:-}" == "$domain" ]]; then
    echo "caddy-cert"; return
  fi

  # 其次：Caddy 证书文件已存在（Caddy 已安装且已获取）
  if [[ -f "$(_caddy_cert "$domain")" && -f "$(_caddy_key "$domain")" ]]; then
    echo "caddy-cert"; return
  fi

  # 再次：HTTP Challenge（port 80 空闲且本次安装中其他服务未认领）
  if [[ "$ACME_HTTP_CLAIMED" == "no" ]] && ! port_in_use "80" "tcp"; then
    ACME_HTTP_CLAIMED="yes"
    echo "http"; return
  fi

  # 再次：TLS-ALPN Challenge（在服务自身 TCP 端口完成，不依赖 port 80）
  if [[ -n "$tcp_port" ]]; then
    echo "tls-alpn:${tcp_port}"; return
  fi

  # 兜底：HTTP Challenge（可能失败，运行时会有明确报错）
  echo "http"
}

# ─── 网络检测 ────────────────────────────────────────────────────────────────
get_local_ips() {
  if have_cmd ip; then
    { ip -4 addr show scope global; ip -6 addr show scope global; } 2>/dev/null \
      | awk '/inet6? /{print $2}' | cut -d/ -f1 | sort -u
  fi
}

resolve_domain_ips() {
  local domain="$1"
  if have_cmd getent; then
    getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u
  elif have_cmd dig; then
    dig +short "$domain" 2>/dev/null | sort -u
  elif have_cmd host; then
    host "$domain" 2>/dev/null | awk '/has address|has IPv6/{print $NF}' | sort -u
  fi
}

check_domain_points() {
  local domain="$1"
  local local_ips resolved_ips
  local_ips="$(get_local_ips)"
  resolved_ips="$(resolve_domain_ips "$domain" || true)"

  if [[ -z "$resolved_ips" ]]; then
    echo "  警告：无法解析 ${domain}（DNS 无结果，请检查域名配置）。"
    return 1
  fi
  if [[ -z "$local_ips" ]]; then
    echo "  警告：无法获取本机 IP，跳过域名校验。DNS 解析结果：${resolved_ips}"
    return 1
  fi
  if echo "$resolved_ips" | grep -Fqx -f <(echo "$local_ips"); then
    echo "  OK：${domain} 已正确解析到本机。"
    return 0
  fi
  echo "  警告：${domain} 未指向本机。"
  echo "    DNS 解析：$(echo "$resolved_ips" | tr '\n' ' ')"
  echo "    本机  IP：$(echo "$local_ips"    | tr '\n' ' ')"
  return 1
}

# ─── 安装状态检测 ─────────────────────────────────────────────────────────────
service_installed() {
  [[ -f "/etc/systemd/system/${1}.service" ]]
}

# 询问重复安装的处理方式
# stdout 输出: overwrite / reconfigure / skip
ask_reinstall() {
  local name="$1" svc="$2"
  local status="未运行"
  systemctl is-active  --quiet "$svc" 2>/dev/null && status="运行中"
  systemctl is-failed  --quiet "$svc" 2>/dev/null && status="已失败（异常）"

  # 菜单文字输出到 stderr，确保在 $() 捕获时仍能显示在终端
  echo "" >&2
  echo "  检测到 ${name} 已安装（服务状态：${status}）" >&2
  echo "  1) 覆盖安装   —— 替换二进制文件 + 重新生成配置" >&2
  echo "  2) 仅更新配置 —— 保留二进制，只重新生成配置文件" >&2
  echo "  3) 跳过       —— 保持当前安装不变" >&2
  local choice
  while true; do
    read -r -p "  请选择 [1/2/3，默认 3]: " choice </dev/tty
    choice="${choice:-3}"
    case "$choice" in
      1) echo "overwrite";   return ;;
      2) echo "reconfigure"; return ;;
      3) echo "skip";        return ;;
      *) echo "  请输入 1、2 或 3。" >&2 ;;
    esac
  done
}

# ─── 连接信息目录 ─────────────────────────────────────────────────────────────
# 每个服务独立文件：/data/connection-info/<service>.txt 和 <service>-qr.png
CONN_DIR="/data/connection-info"

# Debian EOL 版本（10 Buster 及以下）包源自动切换到 archive.debian.org
_fix_debian_eol_sources() {
  [[ "$OS_FAMILY" != "debian" ]] && return 0
  local ver; ver="$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-0}")"
  [[ "$ver" -gt 10 ]] 2>/dev/null && return 0   # 11+ 无需处理
  if grep -q 'deb.debian.org' /etc/apt/sources.list 2>/dev/null; then
    echo "  检测到 Debian ${ver}（已停止维护），自动切换包源到 archive.debian.org ..."
    cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true
    sed -i 's|deb.debian.org|archive.debian.org|g' /etc/apt/sources.list
    sed -i 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' /etc/apt/sources.list
    apt-get update -qq >/dev/null 2>&1 || true
  fi
}

# 打印导入 URI 并生成二维码（终端 + PNG）
# 用法：_show_uri "服务名" "uri" "/path/to/qr.png"
_ensure_qrencode_done=0
_show_uri() {
  local name="$1" uri="$2" png="${3:-}"
  echo ""
  echo "  ── ${name} 导入 URI ──"
  echo "  ${uri}"

  if [[ "$_ensure_qrencode_done" -eq 0 ]]; then
    if ! have_cmd qrencode; then
      echo "  安装 qrencode..."
      case "$OS_FAMILY" in
        debian) _fix_debian_eol_sources
                apt-get install -y -q qrencode >/dev/null 2>&1 || true ;;
        rhel)   yum install -y -q qrencode >/dev/null 2>&1 || \
                dnf install -y -q qrencode >/dev/null 2>&1 || true ;;
        arch)   pacman -Sq --noconfirm qrencode >/dev/null 2>&1 || true ;;
        alpine) apk add -q qrencode >/dev/null 2>&1 || true ;;
      esac
    fi
    _ensure_qrencode_done=1
  fi

  echo ""
  echo "  ── ${name} 二维码（手机扫码导入）──"
  if have_cmd qrencode; then
    qrencode -t UTF8 "$uri"
    if [[ -n "$png" ]]; then
      qrencode -o "$png" "$uri" 2>/dev/null && echo "  二维码已保存：${png}"
    fi
  elif have_cmd python3 && python3 -c "import qrcode" 2>/dev/null; then
    python3 - "$uri" <<'PYEOF'
import sys, qrcode
qr = qrcode.QRCode(border=1)
qr.add_data(sys.argv[1])
qr.make(fit=True)
qr.print_ascii(invert=True)
PYEOF
  elif have_cmd python3; then
    python3 -m pip install -q qrcode 2>/dev/null || true
    if python3 -c "import qrcode" 2>/dev/null; then
      python3 - "$uri" <<'PYEOF'
import sys, qrcode
qr = qrcode.QRCode(border=1)
qr.add_data(sys.argv[1])
qr.make(fit=True)
qr.print_ascii(invert=True)
PYEOF
    else
      echo "  提示：手动安装后可显示二维码：apt install qrencode 或 pip3 install qrcode"
    fi
  else
    echo "  提示：安装 qrencode 后可显示二维码：apt install qrencode"
  fi
}

# ─── 已安装代理软件扫描 ───────────────────────────────────────────────────────

# 扫描服务状态：运行中 / 已停止 / ""（未安装）
_scan_svc_status() {
  if systemctl is-active  --quiet "$1" 2>/dev/null; then echo "运行中"
  elif systemctl is-enabled --quiet "$1" 2>/dev/null; then echo "已停止"
  fi
}
# 从文件 grep JSON 字段
_scan_jstr() { grep -oP "\"${1}\"\\s*:\\s*\"\\K[^\"]+" "${2}" 2>/dev/null | head -1 || true; }
_scan_jnum() { grep -oP "\"${1}\"\\s*:\\s*\\K[0-9]+"  "${2}" 2>/dev/null | head -1 || true; }

_scan_found=0

_scan_row() {
  # $1=名称  $2=状态  $3=协议  $4=端口  $5=域名/备注
  local st_color="\033[33m"
  [ "$2" = "运行中" ] && st_color="\033[32m"
  [ "$2" = "未安装" ] && st_color="\033[2m"
  printf "  \033[1m%-22s\033[0m ${st_color}%-8s\033[0m  %-20s  %-16s  %s\n" \
    "$1" "$2" "$3" "$4" "${5:--}"
  _scan_found=$(( _scan_found + 1 ))
}

scan_installed_proxies() {
  # 纯信息展示，关闭 set -e 避免任何检测命令失败中断安装
  set +e
  set +o pipefail
  _scan_found=0

  echo ""
  echo "── 本机已安装代理软件扫描 ──"
  printf "  %-22s %-8s  %-20s  %-16s  %s\n" "服务" "状态" "协议" "端口" "域名/备注"
  printf "  %s\n" "──────────────────────────────────────────────────────────────────────────────"

  local st port domain proto cfg

  # ── Caddy / NaiveProxy ──────────────────────────────────────────────────
  st="$(_scan_svc_status caddy)"
  if [ -n "$st" ] || have_cmd caddy || [ -x /data/caddy/caddy ]; then
    [ -z "$st" ] && st="已安装"
    port=""; domain=""; proto="HTTPS"
    for cfg in /data/caddy/Caddyfile /etc/caddy/Caddyfile /usr/local/etc/caddy/Caddyfile; do
      [ -f "$cfg" ] || continue
      port=$(grep -oP '(?<![a-zA-Z0-9:/]):\K[0-9]{2,5}(?=[\s,{]|$)' "$cfg" 2>/dev/null \
             | grep -v '^80$' | sort -un | head -1)
      domain=$(grep -oP '[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(?=:[0-9])' \
               "$cfg" 2>/dev/null | head -1)
      grep -q "forward_proxy" "$cfg" 2>/dev/null && proto="NaiveProxy"
      break
    done
    _scan_row "Caddy" "$st" "$proto" "${port:+:${port}/TCP}" "$domain"
  else
    _scan_row "Caddy" "未安装" "NaiveProxy" "" ""
  fi

  # ── Hysteria2 ───────────────────────────────────────────────────────────
  st="$(_scan_svc_status h2server)"
  [ -z "$st" ] && st="$(_scan_svc_status hysteria)"
  if [ -n "$st" ] || have_cmd hysteria || [ -x /data/hysteria/hysteria ]; then
    [ -z "$st" ] && st="已安装"
    port=""; domain=""
    for cfg in /data/hysteria/server.yaml /etc/hysteria/config.yaml /etc/hysteria/server.yaml; do
      [ -f "$cfg" ] || continue
      port=$(grep -oP '^listen:\s*:\K[0-9]+' "$cfg" 2>/dev/null | head -1)
      domain=$(grep -A3 'domains:' "$cfg" 2>/dev/null | grep -oP '^\s*-\s*\K\S+' | head -1)
      break
    done
    _scan_row "Hysteria2" "$st" "Hysteria2/QUIC" "${port:+:${port}/UDP}" "$domain"
  else
    _scan_row "Hysteria2" "未安装" "Hysteria2/QUIC" "" ""
  fi

  # ── Trojan / Trojan-go ──────────────────────────────────────────────────
  st="$(_scan_svc_status trojan)"
  if [ -n "$st" ] || have_cmd trojan-go || have_cmd trojan || [ -x /data/trojan/trojan-go ]; then
    [ -z "$st" ] && st="已安装"
    port=""; domain=""
    for cfg in /data/trojan/server.json /usr/local/etc/trojan/config.json /etc/trojan/config.json; do
      [ -f "$cfg" ] || continue
      port="$(_scan_jnum local_port "$cfg")"
      domain="$(_scan_jstr sni "$cfg")"
      [ -z "$domain" ] && domain="$(_scan_jstr acme_host "$cfg")"
      break
    done
    _scan_row "Trojan" "$st" "Trojan/TLS" "${port:+:${port}/TCP}" "$domain"
  else
    _scan_row "Trojan" "未安装" "Trojan/TLS" "" ""
  fi

  # ── Xray ────────────────────────────────────────────────────────────────
  st="$(_scan_svc_status xray)"
  if [ -n "$st" ] || have_cmd xray || [ -x /data/xray/xray ] \
     || [ -f /etc/systemd/system/xray.service ] || [ -f /data/xray/config.json ]; then
    [ -z "$st" ] && st="已安装"
    local xports="" xprotos="" xsni=""
    for cfg in /data/xray/config.json /usr/local/etc/xray/config.json /etc/xray/config.json; do
      [ -f "$cfg" ] || continue
      xports=$(grep -oP '"port"\s*:\s*\K[0-9]+'    "$cfg" 2>/dev/null | head -3 | tr '\n' ',' | sed 's/,$//')
      xprotos=$(grep -oP '"protocol"\s*:\s*"\K[^"]+' "$cfg" 2>/dev/null | head -3 | tr '\n' '/' | sed 's|/$||')
      xsni=$(grep -oP '"serverNames"\s*:\s*\[\s*"\K[^"]+' "$cfg" 2>/dev/null | head -1)
      break
    done
    local xdesc="${xsni:-见配置文件}"
    _scan_row "Xray" "$st" "${xprotos:-多协议}" "${xports:+:${xports}/TCP}" "$xdesc"
  else
    _scan_row "VLESS Reality (Xray)" "未安装" "VLESS/REALITY" "" ""
  fi

  # ── V2Ray ───────────────────────────────────────────────────────────────
  st="$(_scan_svc_status v2ray)"
  if [ -n "$st" ] || have_cmd v2ray; then
    [ -z "$st" ] && st="已安装"
    local vports="" vprotos=""
    for cfg in /usr/local/etc/v2ray/config.json /etc/v2ray/config.json; do
      [ -f "$cfg" ] || continue
      vports=$(grep -oP '"port"\s*:\s*\K[0-9]+'    "$cfg" 2>/dev/null | head -3 | tr '\n' ',' | sed 's/,$//')
      vprotos=$(grep -oP '"protocol"\s*:\s*"\K[^"]+' "$cfg" 2>/dev/null | head -3 | tr '\n' '/' | sed 's|/$||')
      break
    done
    _scan_row "V2Ray" "$st" "${vprotos:-多协议}" "${vports:+:${vports}/TCP}" "见配置文件"
  fi

  # ── sing-box ────────────────────────────────────────────────────────────
  st="$(_scan_svc_status sing-box)"
  if [ -n "$st" ] || have_cmd sing-box; then
    [ -z "$st" ] && st="已安装"
    local sbports="" sbtypes=""
    for cfg in /etc/sing-box/config.json /usr/local/etc/sing-box/config.json; do
      [ -f "$cfg" ] || continue
      sbports=$(grep -oP '"listen_port"\s*:\s*\K[0-9]+' "$cfg" 2>/dev/null | head -3 | tr '\n' ',' | sed 's/,$//')
      sbtypes=$(grep -oP '"type"\s*:\s*"\K[^"]+' "$cfg" 2>/dev/null \
                | grep -Ev 'dns|selector|loadbalance|urltest' | head -3 | tr '\n' '/' | sed 's|/$||')
      break
    done
    _scan_row "sing-box" "$st" "${sbtypes:-多协议}" "${sbports:+:${sbports}/TCP}" "见配置文件"
  fi

  # ── Shadowsocks ─────────────────────────────────────────────────────────
  st="$(_scan_svc_status shadowsocks-libev)"
  [ -z "$st" ] && st="$(_scan_svc_status shadowsocks)"
  [ -z "$st" ] && st="$(_scan_svc_status shadowsocks-rust)"
  if [ -n "$st" ] || have_cmd ss-server || have_cmd ssserver; then
    [ -z "$st" ] && st="已安装"
    port=""; local ssmethod=""
    for cfg in /etc/shadowsocks-libev/config.json /etc/shadowsocks/config.json /etc/shadowsocks-rust/config.json; do
      [ -f "$cfg" ] || continue
      port="$(_scan_jnum server_port "$cfg")"
      ssmethod="$(_scan_jstr method "$cfg")"
      break
    done
    _scan_row "Shadowsocks" "$st" "SS${ssmethod:+/${ssmethod}}" "${port:+:${port}/TCP}" "-"
  fi

  # ── 3x-ui / x-ui ────────────────────────────────────────────────────────
  st="$(_scan_svc_status x-ui)"
  [ -z "$st" ] && st="$(_scan_svc_status 3x-ui)"
  if [ -n "$st" ] || have_cmd x-ui; then
    [ -z "$st" ] && st="已安装"
    port=$(grep -oP '(?i)port\s*[=:]\s*\K[0-9]+' \
           /etc/x-ui/x-ui.conf /usr/local/x-ui/x-ui.conf 2>/dev/null | head -1)
    _scan_row "3x-ui/x-ui" "$st" "Web面板(Xray)" "${port:+:${port}/TCP}" "多协议管理面板"
  fi

  # ── H2 Client ───────────────────────────────────────────────────────────
  st="$(_scan_svc_status h2client)"
  if [ -n "$st" ] || [ -x /data/h2client/h2 ] || [ -f /data/h2client/client.yaml ]; then
    local h2c_server="" h2c_socks=""
    cfg="/data/h2client/client.yaml"
    if [ -f "$cfg" ]; then
      h2c_server=$(grep -oP '^server:\s*\K\S+' "$cfg" 2>/dev/null | head -1)
      h2c_socks=$(grep -oP '^\s*listen:\s*\K\S+' "$cfg" 2>/dev/null | head -1)
    fi
    _scan_row "H2 Client" "$st" "Hysteria2客户端" "${h2c_socks:+SOCKS5 ${h2c_socks}}" "$h2c_server"
  else
    _scan_row "H2 Client" "未安装" "Hysteria2客户端" "" ""
  fi

  # ── WireGuard ───────────────────────────────────────────────────────────
  if [ -d /etc/wireguard ]; then
    local wg_conf; wg_conf=$(ls /etc/wireguard/*.conf 2>/dev/null | head -1)
    if [ -n "$wg_conf" ]; then
      local wg_iface wg_port wg_st
      wg_iface=$(basename "$wg_conf" .conf)
      wg_port=$(grep 'ListenPort' "$wg_conf" 2>/dev/null | grep -oP '[0-9]+' | head -1)
      wg_st="$(_scan_svc_status "wg-quick@${wg_iface}")"
      [ -z "$wg_st" ] && wg_st="已配置"
      _scan_row "WireGuard(${wg_iface})" "$wg_st" "WireGuard/VPN" "${wg_port:+:${wg_port}/UDP}" "-"
    fi
  fi

  # ── OpenVPN ─────────────────────────────────────────────────────────────
  st="$(_scan_svc_status openvpn)"
  [ -z "$st" ] && st="$(_scan_svc_status openvpn@server)"
  if [ -n "$st" ] || have_cmd openvpn; then
    [ -z "$st" ] && st="已安装"
    local ovpn_port="" ovpn_proto=""
    cfg=$(find /etc/openvpn -name "*.conf" 2>/dev/null | head -1)
    if [ -n "$cfg" ]; then
      ovpn_port=$(grep -oP '^port\s+\K[0-9]+' "$cfg" 2>/dev/null | head -1)
      ovpn_proto=$(grep -oP '^proto\s+\K\S+'  "$cfg" 2>/dev/null | head -1)
    fi
    _scan_row "OpenVPN" "$st" "OpenVPN/VPN" "${ovpn_port:+:${ovpn_port}/${ovpn_proto:-UDP}}" "-"
  fi

  # ── Nginx ───────────────────────────────────────────────────────────────
  st="$(_scan_svc_status nginx)"
  if [ -n "$st" ] || have_cmd nginx; then
    [ -z "$st" ] && st="已安装"
    local ng_ports=""
    ng_ports=$(grep -rh 'listen ' /etc/nginx/ 2>/dev/null \
               | grep -oP 'listen\s+\K[0-9]+' | sort -un | head -5 | tr '\n' ',' | sed 's/,$//')
    _scan_row "Nginx" "$st" "HTTP/HTTPS" "${ng_ports:+:${ng_ports}/TCP}" "-"
  fi

  # ── 汇总 ────────────────────────────────────────────────────────────────
  if [ "$_scan_found" -eq 0 ]; then
    echo "  （未检测到已安装的代理/VPN 软件）"
  fi
  echo ""

  set -e
  set -o pipefail
}

# ─── 本地二进制路径（按架构） ────────────────────────────────────────────────
CADDY_LOCAL_BIN="${ROOT_DIR}/caddy/caddy-linux-${ARCH}"
H2_LOCAL_BIN="${ROOT_DIR}/hysteria/hysteria-linux-${ARCH}"
TROJAN_LOCAL_BIN="${ROOT_DIR}/trojan/trojan-go-linux-${ARCH}"
XRAY_LOCAL_BIN="${ROOT_DIR}/xray/xray-linux-${ARCH}"
H2C_LOCAL_BIN="${ROOT_DIR}/h2client/h2-linux-${ARCH}"

# ─── 欢迎界面 ────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         vps-allineone  交互式安装脚本            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  系统：${OS_ID} (${OS_FAMILY})  |  架构：${ARCH}"
echo "  配置与服务将安装到 /data 和 /etc/systemd/system"

scan_installed_proxies

# ─── 检测各组件二进制是否存在 ────────────────────────────────────────────────
echo "组件可用性检测："
[[ -f "$CADDY_LOCAL_BIN"  ]] && echo "  [可用] Caddy (NaiveProxy)    caddy-linux-${ARCH}" \
                              || echo "  [缺包] Caddy (NaiveProxy)  — 未找到 caddy-linux-${ARCH}"
[[ -f "$H2_LOCAL_BIN"     ]] && echo "  [可用] Hysteria2             hysteria-linux-${ARCH}" \
                              || echo "  [缺包] Hysteria2           — 未找到 hysteria-linux-${ARCH}"
[[ -f "$TROJAN_LOCAL_BIN" ]] && echo "  [可用] Trojan                trojan-go-linux-${ARCH}" \
                              || echo "  [缺包] Trojan              — 未找到 trojan-go-linux-${ARCH}"
[[ -f "$XRAY_LOCAL_BIN"   ]] && echo "  [可用] VLESS Reality (Xray)  xray-linux-${ARCH}" \
                              || echo "  [缺包] VLESS Reality (Xray) — 未找到 xray-linux-${ARCH}"
[[ -f "$H2C_LOCAL_BIN"    ]] && echo "  [可用] H2 Client             h2-linux-${ARCH}" \
                              || echo "  [缺包] H2 Client           — 未找到 h2-linux-${ARCH}"
echo ""

# ─── 组件选择（仅有包的组件才询问） ─────────────────────────────────────────
INSTALL_CADDY="no"
INSTALL_HYSTERIA="no"
INSTALL_TROJAN="no"
INSTALL_XRAY="no"
INSTALL_H2CLIENT="no"

echo "请选择要安装的组件："
if [[ -f "$CADDY_LOCAL_BIN"  ]]; then
  if confirm "安装 Caddy（NaiveProxy over HTTPS）" "y"; then INSTALL_CADDY="yes"; fi
else
  echo "  跳过 Caddy（缺少 caddy-linux-${ARCH}，请先运行 download-bins.sh）"
fi

if [[ -f "$H2_LOCAL_BIN" ]]; then
  if confirm "安装 Hysteria2（QUIC 协议代理）" "y"; then INSTALL_HYSTERIA="yes"; fi
else
  echo "  跳过 Hysteria2（缺少 hysteria-linux-${ARCH}，请先运行 download-bins.sh）"
fi

if [[ -f "$TROJAN_LOCAL_BIN" ]]; then
  if confirm "安装 Trojan（TLS 代理）" "n"; then INSTALL_TROJAN="yes"; fi
else
  echo "  跳过 Trojan（缺少 trojan-go-linux-${ARCH}，请先运行 download-bins.sh）"
fi

if [[ -f "$XRAY_LOCAL_BIN" ]]; then
  if confirm "安装 VLESS Reality（Xray，无需证书）" "n"; then INSTALL_XRAY="yes"; fi
else
  echo "  跳过 VLESS Reality（缺少 xray-linux-${ARCH}，请先运行 download-bins.sh）"
fi

if [[ -f "$H2C_LOCAL_BIN" ]]; then
  if confirm "安装 H2 Client（本地 Linux 客户端）" "n"; then INSTALL_H2CLIENT="yes"; fi
else
  echo "  跳过 H2 Client（缺少 h2-linux-${ARCH}，请先运行 download-bins.sh）"
fi

if [[ "${INSTALL_CADDY}${INSTALL_HYSTERIA}${INSTALL_TROJAN}${INSTALL_XRAY}${INSTALL_H2CLIENT}" == "nonononono" ]]; then
  echo ""
  echo "未选择任何组件，退出。"
  exit 0
fi

mkdir -p /data
umask 077
mkdir -p "$CONN_DIR"

# ══════════════════════════════════════════════════════════════════════════════
# Caddy / NaiveProxy
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$INSTALL_CADDY" == "yes" ]]; then
  echo ""
  echo "── Caddy / NaiveProxy 配置 ──"
fi

if [[ "$INSTALL_CADDY" == "yes" ]]; then
  CADDY_ACTION="install"
  if service_installed "caddy"; then
    CADDY_ACTION="$(ask_reinstall "Caddy" "caddy")"
  fi

  if [[ "$CADDY_ACTION" == "skip" ]]; then
    echo "  跳过 Caddy 安装（保留现有）。"
    INSTALL_CADDY="no"
  else
    prompt          CADDY_DOMAIN "Caddy 域名（A/AAAA 记录指向此 VPS）"
    prompt_optional CADDY_PORT   "Caddy HTTPS 端口" "8443"
    prompt_with_random_default CADDY_USER "基本认证用户名（回车随机生成）" 10
    prompt_with_random_default CADDY_PASS "基本认证密码（回车随机生成）"   20

    echo ""
    echo "  正在检查域名解析..."
    check_domain_points "$CADDY_DOMAIN" || \
      { confirm "域名未指向本机，仍然继续安装 Caddy" "y" || { INSTALL_CADDY="no"; echo "  已跳过。"; }; }

    if [[ "$INSTALL_CADDY" == "yes" ]]; then
      echo "  正在检查端口..."
      check_port_smart "80"          "tcp" || \
        { confirm "端口 80 被占用，继续安装 Caddy" "n" || { INSTALL_CADDY="no"; echo "  已跳过。"; }; }
    fi

    if [[ "$INSTALL_CADDY" == "yes" ]]; then
      check_port_smart "$CADDY_PORT" "tcp" || \
        { confirm "端口 ${CADDY_PORT} 被占用，继续安装 Caddy" "n" || { INSTALL_CADDY="no"; echo "  已跳过。"; }; }
    fi

    if [[ "$INSTALL_CADDY" == "yes" ]]; then
      mkdir -p /data/caddy

      # 覆盖安装：替换二进制 + service 文件
      if [[ "$CADDY_ACTION" == "overwrite" ]]; then
        cp -p "$CADDY_LOCAL_BIN" /data/caddy/caddy
        chmod +x /data/caddy/caddy
        cp "${ROOT_DIR}/caddy/caddy.service" /etc/systemd/system/caddy.service
      fi
      # 首次安装
      if [[ "$CADDY_ACTION" == "install" ]]; then
        cp -p "$CADDY_LOCAL_BIN" /data/caddy/caddy
        chmod +x /data/caddy/caddy
        cp "${ROOT_DIR}/caddy/caddy.service" /etc/systemd/system/caddy.service
      fi

      # 生成 Caddyfile（覆盖/重新配置/首次安装均执行）
      cat > /data/caddy/Caddyfile <<EOF
{
  order forward_proxy before file_server
}

:80 {
  header server "Nginx-1.1"
}

:${CADDY_PORT}, ${CADDY_DOMAIN}:${CADDY_PORT} {
  header server "Nginx-1.1"
  header -etag

  root * /var/www/html
  file_server

  handle_errors {
    rewrite * /error.html
    file_server
  }

  log {
    output discard
    level ERROR
  }

  route {
    forward_proxy {
      basic_auth ${CADDY_USER} ${CADDY_PASS}
      hide_ip
      hide_via
      probe_resistance
    }
  }
}
EOF

      # Caddy 使用 port 80 做 ACME HTTP Challenge，标记已认领
      ACME_HTTP_CLAIMED="yes"

      caddy_uri="naive+https://${CADDY_USER}:${CADDY_PASS}@${CADDY_DOMAIN}:${CADDY_PORT}#VPS-Naive"
      {
        echo "[Caddy / NaiveProxy]"
        echo "Domain  : ${CADDY_DOMAIN}"
        echo "Port    : ${CADDY_PORT}"
        echo "Username: ${CADDY_USER}"
        echo "Password: ${CADDY_PASS}"
        echo ""
        echo "URI: ${caddy_uri}"
      } > "$CONN_DIR/caddy.txt"
      _show_uri "NaiveProxy" "$caddy_uri" "$CONN_DIR/caddy-qr.png"
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Hysteria2
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$INSTALL_HYSTERIA" == "yes" ]]; then
  echo ""
  echo "── Hysteria2 配置 ──"
fi

if [[ "$INSTALL_HYSTERIA" == "yes" ]]; then
  H2_ACTION="install"
  if service_installed "h2server"; then
    H2_ACTION="$(ask_reinstall "Hysteria2" "h2server")"
  fi

  if [[ "$H2_ACTION" == "skip" ]]; then
    echo "  跳过 Hysteria2 安装（保留现有）。"
    INSTALL_HYSTERIA="no"
  else
    prompt          H2_DOMAIN   "Hysteria 域名（A/AAAA 记录指向此 VPS）"
    prompt_optional H2_PORT     "Hysteria 监听端口（UDP）" "443"
    prompt_with_random_default H2_PASSWORD "Hysteria 密码（回车随机生成）" 20
    prompt_optional H2_EMAIL    "ACME 注册邮箱（可留空）"

    echo ""
    echo "  正在检查域名解析..."
    check_domain_points "$H2_DOMAIN" || \
      { confirm "域名未指向本机，仍然继续安装 Hysteria2" "y" || { INSTALL_HYSTERIA="no"; echo "  已跳过。"; }; }

    if [[ "$INSTALL_HYSTERIA" == "yes" ]]; then
      echo "  正在检查端口（Hysteria2 使用 UDP）..."
      check_port_smart "$H2_PORT" "udp" || \
        { confirm "UDP 端口 ${H2_PORT} 被占用，继续安装 Hysteria2" "n" || { INSTALL_HYSTERIA="no"; echo "  已跳过。"; }; }
    fi

    if [[ "$INSTALL_HYSTERIA" == "yes" ]]; then
      mkdir -p /data/hysteria

      if [[ "$H2_ACTION" == "overwrite" || "$H2_ACTION" == "install" ]]; then
        cp -p "$H2_LOCAL_BIN" /data/hysteria/hysteria
        chmod +x /data/hysteria/hysteria
        sed 's|hysteria-linux-amd64|hysteria|g; s|hysteria-linux-arm64|hysteria|g' \
          "${ROOT_DIR}/hysteria/h2server.service" > /etc/systemd/system/h2server.service
      fi

      # Hysteria2 自身是 UDP，ACME 只支持 HTTP Challenge（无内置 TLS-ALPN）
      # → 优先复用 Caddy 证书文件；次选 HTTP Challenge；无法 HTTP 则输出警告
      h2_acme_method="$(resolve_acme "$H2_DOMAIN" "")"

      {
        echo "listen: :${H2_PORT}"
        echo ""
        case "$h2_acme_method" in
          caddy-cert)
            h2_crt="$(_caddy_cert "$H2_DOMAIN")"
            h2_key="$(_caddy_key  "$H2_DOMAIN")"
            echo "  TLS 证书：复用 Caddy 管理的证书"
            echo "  → cert: ${h2_crt}"
            echo "  → key : ${h2_key}" >&2
            echo "tls:"
            echo "  cert: ${h2_crt}"
            echo "  key: ${h2_key}"
            ;;
          http)
            echo "acme:"
            echo "  domains:"
            echo "    - ${H2_DOMAIN}"
            [[ -n "$H2_EMAIL" ]] && echo "  email: ${H2_EMAIL}"
            ;;
          tls-alpn:*)
            # Hysteria2 不支持 TLS-ALPN，退化为 HTTP Challenge 并警告
            echo "  警告：port 80 不可用且 Hysteria2 不支持 TLS-ALPN，ACME 可能失败。" >&2
            echo "  建议与 Caddy 共用同一域名以复用证书，或手动提供证书文件。" >&2
            echo "acme:"
            echo "  domains:"
            echo "    - ${H2_DOMAIN}"
            [[ -n "$H2_EMAIL" ]] && echo "  email: ${H2_EMAIL}"
            ;;
        esac
        echo ""
        echo "auth:"
        echo "  type: password"
        echo "  password: ${H2_PASSWORD}"
        echo ""
        echo "masquerade:"
        echo "  listenHTTPS: :${H2_PORT}"
        echo "  forceHTTPS: true"
        echo "  type: string"
        echo "  string:"
        echo "    statusCode: 404"
        echo "    headers:"
        echo "      content-type: text/plain"
        echo "    content: 404"
      } 2>/dev/null > /data/hysteria/server.yaml

      echo "  Hysteria2 ACME 策略：${h2_acme_method}"
      h2_uri="hysteria2://${H2_PASSWORD}@${H2_DOMAIN}:${H2_PORT}#VPS-Hysteria2"
      {
        echo "[Hysteria2]"
        echo "Server  : ${H2_DOMAIN}:${H2_PORT}"
        echo "Password: ${H2_PASSWORD}"
        echo "ACME    : ${h2_acme_method}"
        echo ""
        echo "URI: ${h2_uri}"
      } > "$CONN_DIR/hysteria2.txt"
      _show_uri "Hysteria2" "$h2_uri" "$CONN_DIR/hysteria2-qr.png"
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Trojan
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$INSTALL_TROJAN" == "yes" ]]; then
  echo ""
  echo "── Trojan 配置 ──"
fi

if [[ "$INSTALL_TROJAN" == "yes" ]]; then
  TROJAN_ACTION="install"
  if service_installed "trojan"; then
    TROJAN_ACTION="$(ask_reinstall "Trojan" "trojan")"
  fi

  if [[ "$TROJAN_ACTION" == "skip" ]]; then
    echo "  跳过 Trojan 安装（保留现有）。"
    INSTALL_TROJAN="no"
  else
    prompt          TROJAN_DOMAIN "Trojan 域名（A/AAAA 记录指向此 VPS）"
    prompt_optional TROJAN_PORT   "Trojan 监听端口（TCP）" "8880"
    prompt_with_random_default TROJAN_PASS  "Trojan 密码（回车随机生成）" 20
    prompt_optional TROJAN_EMAIL  "ACME 注册邮箱（可留空）"

    echo ""
    echo "  正在检查域名解析..."
    check_domain_points "$TROJAN_DOMAIN" || \
      { confirm "域名未指向本机，仍然继续安装 Trojan" "y" || { INSTALL_TROJAN="no"; echo "  已跳过。"; }; }

    if [[ "$INSTALL_TROJAN" == "yes" ]]; then
      echo "  正在检查端口..."
      check_port_smart "$TROJAN_PORT" "tcp" || \
        { confirm "TCP 端口 ${TROJAN_PORT} 被占用，继续安装 Trojan" "n" || { INSTALL_TROJAN="no"; echo "  已跳过。"; }; }
    fi

    if [[ "$INSTALL_TROJAN" == "yes" ]]; then
      mkdir -p /data/trojan

      if [[ "$TROJAN_ACTION" == "overwrite" || "$TROJAN_ACTION" == "install" ]]; then
        cp -p "$TROJAN_LOCAL_BIN" /data/trojan/trojan-go
        chmod +x /data/trojan/trojan-go
        cp "${ROOT_DIR}/trojan/trojan.service" /etc/systemd/system/trojan.service
      fi

      # Trojan-go 支持 HTTP Challenge 和 TLS-ALPN（在自身 TCP 端口完成）
      tj_acme_method="$(resolve_acme "$TROJAN_DOMAIN" "$TROJAN_PORT")"
      echo "  Trojan ACME 策略：${tj_acme_method}"

      umask 077
      # 根据 ACME 策略生成不同的 ssl 块
      tj_ssl_block=""
      case "$tj_acme_method" in
        caddy-cert)
          tj_crt="$(_caddy_cert "$TROJAN_DOMAIN")"
          tj_key="$(_caddy_key  "$TROJAN_DOMAIN")"
          tj_ssl_block=$(cat <<SSLEOF
  "ssl": {
    "cert": "${tj_crt}",
    "key": "${tj_key}",
    "sni": "${TROJAN_DOMAIN}",
    "alpn": ["h2", "http/1.1"],
    "reuse_session": true,
    "session_ticket": false
  }
SSLEOF
)
          ;;
        http)
          tj_ssl_block=$(cat <<SSLEOF
  "ssl": {
    "cert": "",
    "key": "",
    "sni": "${TROJAN_DOMAIN}",
    "fallback_port": 80,
    "alpn": ["h2", "http/1.1"],
    "reuse_session": true,
    "session_ticket": false,
    "acme": {
      "email": "${TROJAN_EMAIL}",
      "acme_host": "${TROJAN_DOMAIN}",
      "acme_port": ${TROJAN_PORT},
      "disable_http_challenge": false,
      "disable_tls_alpn_challenge": true,
      "disable_dns_challenge": true
    }
  }
SSLEOF
)
          ;;
        tls-alpn:*)
          tls_port="${tj_acme_method#tls-alpn:}"
          tj_ssl_block=$(cat <<SSLEOF
  "ssl": {
    "cert": "",
    "key": "",
    "sni": "${TROJAN_DOMAIN}",
    "alpn": ["h2", "http/1.1"],
    "reuse_session": true,
    "session_ticket": false,
    "acme": {
      "email": "${TROJAN_EMAIL}",
      "acme_host": "${TROJAN_DOMAIN}",
      "acme_port": ${tls_port},
      "disable_http_challenge": true,
      "disable_tls_alpn_challenge": false,
      "disable_dns_challenge": true
    }
  }
SSLEOF
)
          ;;
      esac

      cat > /data/trojan/server.json <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": ${TROJAN_PORT},
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["${TROJAN_PASS}"],
${tj_ssl_block},
  "mux": {
    "enabled": true,
    "concurrency": 8,
    "idle_timeout": 60
  }
}
EOF

      trojan_uri="trojan://${TROJAN_PASS}@${TROJAN_DOMAIN}:${TROJAN_PORT}?sni=${TROJAN_DOMAIN}&allowInsecure=0#VPS-Trojan"
      {
        echo "[Trojan]"
        echo "Server  : ${TROJAN_DOMAIN}:${TROJAN_PORT}"
        echo "Password: ${TROJAN_PASS}"
        echo "ACME    : ${tj_acme_method}"
        echo ""
        echo "URI: ${trojan_uri}"
      } > "$CONN_DIR/trojan.txt"
      _show_uri "Trojan" "$trojan_uri" "$CONN_DIR/trojan-qr.png"
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# VLESS Reality (Xray)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$INSTALL_XRAY" == "yes" ]]; then
  echo ""
  echo "── VLESS Reality (Xray) 配置 ──"
fi

if [[ "$INSTALL_XRAY" == "yes" ]]; then
  XRAY_ACTION="install"
  if service_installed "xray"; then
    XRAY_ACTION="$(ask_reinstall "VLESS Reality (Xray)" "xray")"
  fi

  if [[ "$XRAY_ACTION" == "skip" ]]; then
    echo "  跳过 VLESS Reality 安装（保留现有）。"
    INSTALL_XRAY="no"
  else
    prompt_optional XRAY_PORT  "VLESS Reality 监听端口（TCP）" "443"
    prompt_optional XRAY_SNI   "SNI（目标站点域名）" "www.pizzeriabianco.com"
    prompt_optional XRAY_DEST  "回落目标（SNI:port）" "${XRAY_SNI:-www.pizzeriabianco.com}:443"

    echo ""
    echo "  正在检查端口..."
    check_port_smart "$XRAY_PORT" "tcp" || \
      { confirm "TCP 端口 ${XRAY_PORT} 被占用，继续安装 VLESS Reality" "n" || { INSTALL_XRAY="no"; echo "  已跳过。"; }; }

    if [[ "$INSTALL_XRAY" == "yes" ]]; then
      mkdir -p /data/xray

      if [[ "$XRAY_ACTION" == "overwrite" || "$XRAY_ACTION" == "install" ]]; then
        cp -p "$XRAY_LOCAL_BIN" /data/xray/xray
        chmod +x /data/xray/xray
        cp "${ROOT_DIR}/xray/xray.service" /etc/systemd/system/xray.service
      fi

      # 生成 UUID
      if have_cmd uuidgen; then
        XRAY_UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
      elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        XRAY_UUID="$(cat /proc/sys/kernel/random/uuid)"
      else
        XRAY_UUID="$(od -x /dev/urandom | head -1 | \
          awk '{printf "%s-%s-%s-%s-%s%s%s\n", $2$3, $4, $5, $6, $7, $8, $9}')"
      fi

      # 生成 x25519 密钥对（使用 xray 二进制）
      echo "  正在生成 x25519 密钥对..."
      xray_kp="$(/data/xray/xray x25519 2>/dev/null)"
      XRAY_PRIVATE_KEY="$(echo "$xray_kp" | grep -oP 'Private key:\s*\K\S+')"
      XRAY_PUBLIC_KEY="$(echo  "$xray_kp" | grep -oP 'Public key:\s*\K\S+')"
      if [[ -z "$XRAY_PRIVATE_KEY" || -z "$XRAY_PUBLIC_KEY" ]]; then
        echo "  错误：密钥对生成失败，请检查 xray 二进制是否正常。"
        INSTALL_XRAY="no"
      fi
    fi

    if [[ "$INSTALL_XRAY" == "yes" ]]; then
      # 生成 shortId（8位随机 hex）
      if have_cmd openssl; then
        XRAY_SHORT_ID="$(openssl rand -hex 4)"
      else
        XRAY_SHORT_ID="$(od -An -tx1 /dev/urandom | head -1 | tr -d ' \n' | cut -c1-8)"
      fi

      umask 077
      cat > /data/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${XRAY_UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${XRAY_DEST}",
          "xver": 0,
          "serverNames": [
            "${XRAY_SNI}"
          ],
          "privateKey": "${XRAY_PRIVATE_KEY}",
          "shortIds": [
            "${XRAY_SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF

      xray_public_ip="$(curl -fsSL --connect-timeout 5 https://api.ipify.org 2>/dev/null || \
                        curl -fsSL --connect-timeout 5 https://ifconfig.me 2>/dev/null || \
                        echo "YOUR_VPS_IP")"
      xray_uri="vless://${XRAY_UUID}@${xray_public_ip}:${XRAY_PORT}?security=reality&flow=xtls-rprx-vision&sni=${XRAY_SNI}&pbk=${XRAY_PUBLIC_KEY}&sid=${XRAY_SHORT_ID}&fp=chrome&type=tcp#VPS-Reality"

      {
        echo "[VLESS Reality (Xray)]"
        echo "Port      : ${XRAY_PORT}/TCP"
        echo "UUID      : ${XRAY_UUID}"
        echo "PublicKey : ${XRAY_PUBLIC_KEY}"
        echo "ShortId   : ${XRAY_SHORT_ID}"
        echo "SNI       : ${XRAY_SNI}"
        echo "Flow      : xtls-rprx-vision"
        echo "Network   : tcp  Security: reality"
        echo ""
        echo "URI: ${xray_uri}"
      } > "$CONN_DIR/xray.txt"
      _show_uri "VLESS Reality" "$xray_uri" "$CONN_DIR/xray-qr.png"
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# H2 Client
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$INSTALL_H2CLIENT" == "yes" ]]; then
  echo ""
  echo "── H2 Client 配置 ──"
fi

if [[ "$INSTALL_H2CLIENT" == "yes" ]]; then
  H2C_ACTION="install"
  if service_installed "h2client"; then
    H2C_ACTION="$(ask_reinstall "H2 Client" "h2client")"
  fi

  if [[ "$H2C_ACTION" == "skip" ]]; then
    echo "  跳过 H2 Client 安装（保留现有）。"
    INSTALL_H2CLIENT="no"
  else
    prompt          H2CLIENT_SERVER   "H2 服务地址（domain:port）"
    prompt_with_random_default H2CLIENT_PASSWORD "H2 密码（回车随机生成）" 20
    prompt_optional H2CLIENT_SOCKS    "本地 SOCKS5 监听（host:port）" ":1080"
    prompt_optional H2CLIENT_HTTP     "本地 HTTP 代理监听（host:port）" ":2080"

    if [[ "$INSTALL_H2CLIENT" == "yes" ]]; then
      mkdir -p /data/h2client

      if [[ "$H2C_ACTION" == "overwrite" || "$H2C_ACTION" == "install" ]]; then
        cp -p "$H2C_LOCAL_BIN" /data/h2client/h2
        chmod +x /data/h2client/h2
        cp "${ROOT_DIR}/h2client/h2client.service" /etc/systemd/system/h2client.service
      fi

      cat > /data/h2client/client.yaml <<EOF
server: ${H2CLIENT_SERVER}

auth: ${H2CLIENT_PASSWORD}

socks5:
  listen: ${H2CLIENT_SOCKS}

http:
  listen: ${H2CLIENT_HTTP}

tcpTProxy:
  listen: 127.0.0.1:2500

udpTProxy:
  listen: 127.0.0.1:2500
EOF

      {
        echo "[H2 Client]"
        echo "Server  : ${H2CLIENT_SERVER}"
        echo "Password: ${H2CLIENT_PASSWORD}"
        echo "SOCKS5  : ${H2CLIENT_SOCKS}"
        echo "HTTP    : ${H2CLIENT_HTTP}"
      } > "$CONN_DIR/h2client.txt"
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# 启用与启动服务
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── 启用与启动服务 ──"
systemctl daemon-reload

_start_service() {
  local svc="$1" name="$2"
  echo -n "  启动 ${name} ... "
  systemctl enable "$svc" 2>/dev/null
  if systemctl restart "$svc"; then
    echo "OK"
  else
    echo "失败（请运行 systemctl status ${svc} 查看详情）"
  fi
}

[[ "$INSTALL_CADDY"    == "yes" ]] && _start_service "caddy"    "Caddy"
[[ "$INSTALL_HYSTERIA" == "yes" ]] && _start_service "h2server" "Hysteria2"
[[ "$INSTALL_TROJAN"   == "yes" ]] && _start_service "trojan"   "Trojan"
[[ "$INSTALL_XRAY"     == "yes" ]] && _start_service "xray"     "VLESS Reality (Xray)"
[[ "$INSTALL_H2CLIENT" == "yes" ]] && _start_service "h2client" "H2 Client"

# ══════════════════════════════════════════════════════════════════════════════
# 完成汇总
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 安装完成 ══"
[[ "$INSTALL_CADDY"    == "yes" ]] && echo "  Caddy 状态          ：systemctl status caddy"
[[ "$INSTALL_HYSTERIA" == "yes" ]] && echo "  Hysteria2 状态      ：systemctl status h2server"
[[ "$INSTALL_TROJAN"   == "yes" ]] && echo "  Trojan 状态         ：systemctl status trojan"
[[ "$INSTALL_XRAY"     == "yes" ]] && echo "  VLESS Reality 状态  ：systemctl status xray"
[[ "$INSTALL_H2CLIENT" == "yes" ]] && echo "  H2 Client 状态      ：systemctl status h2client"
echo ""
echo "  连接信息已保存到：${CONN_DIR}/"
echo "  请妥善保管此目录中的密码信息。"
