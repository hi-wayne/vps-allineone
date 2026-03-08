#!/usr/bin/env bash
# 在有网络的机器上运行此脚本，预先下载所有组件的二进制文件。
# 支持架构：amd64、arm64
# 下载完成后将整个目录推送到目标 VPS，再执行 install.sh（无需联网）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── 版本配置 ────────────────────────────────────────────────────────────────
HYSTERIA_VERSION="2.6.1"
TROJAN_GO_VERSION="0.10.6"
XRAY_VERSION="25.3.6"

ARCHS=("amd64" "arm64")

# ─── 辅助函数 ────────────────────────────────────────────────────────────────
have_cmd() { command -v "$1" >/dev/null 2>&1; }

dl() {
  local url="$1" dest="$2" desc="${3:-}"
  echo "  下载: ${desc:-$(basename "$dest")}"
  echo "    <- ${url}"
  if have_cmd curl; then
    curl -fsSL --connect-timeout 30 --retry 3 -o "$dest" "$url"
  elif have_cmd wget; then
    wget -qO "$dest" "$url"
  else
    echo "错误：未找到 curl 或 wget，无法下载。"
    exit 1
  fi
  echo "    -> ${dest}"
}

extract_zip_entry() {
  local zip_file="$1" entry="$2" dest="$3"
  if have_cmd unzip; then
    unzip -p "$zip_file" "$entry" > "$dest"
  elif have_cmd python3; then
    python3 -c "
import zipfile, sys
zf = zipfile.ZipFile(sys.argv[1])
open(sys.argv[2], 'wb').write(zf.read(sys.argv[3]))
" "$zip_file" "$dest" "$entry"
  else
    echo "错误：需要 unzip 或 python3 来解压 zip 文件。"
    exit 1
  fi
}

# ─── Hysteria2 ────────────────────────────────────────────────────────────────
echo ""
echo "=== 下载 Hysteria2 v${HYSTERIA_VERSION} ==="
mkdir -p "${ROOT_DIR}/hysteria"

for arch in "${ARCHS[@]}"; do
  dest="${ROOT_DIR}/hysteria/hysteria-linux-${arch}"
  url="https://github.com/apernet/hysteria/releases/download/app%2Fv${HYSTERIA_VERSION}/hysteria-linux-${arch}"
  dl "$url" "$dest" "Hysteria2 ${arch}"
  chmod +x "$dest"
done

# ─── Trojan-go ────────────────────────────────────────────────────────────────
echo ""
echo "=== 下载 Trojan-go v${TROJAN_GO_VERSION} ==="
mkdir -p "${ROOT_DIR}/trojan"

TROJAN_ARCH_MAP=("amd64:amd64" "arm64:armv8")
TMP_ZIP="/tmp/trojan-go-download.zip"

for item in "${TROJAN_ARCH_MAP[@]}"; do
  arch="${item%%:*}"
  zip_arch="${item##*:}"
  dest="${ROOT_DIR}/trojan/trojan-go-linux-${arch}"
  url="https://github.com/p4gefau1t/trojan-go/releases/download/v${TROJAN_GO_VERSION}/trojan-go-linux-${zip_arch}.zip"
  dl "$url" "$TMP_ZIP" "Trojan-go ${arch} (zip)"
  extract_zip_entry "$TMP_ZIP" "trojan-go" "$dest"
  chmod +x "$dest"
  rm -f "$TMP_ZIP"
done

# ─── Xray-core（VLESS Reality） ───────────────────────────────────────────────
echo ""
echo "=== 下载 Xray-core v${XRAY_VERSION} ==="
mkdir -p "${ROOT_DIR}/xray"

# amd64 → Xray-linux-64.zip；arm64 → Xray-linux-arm64-v8a.zip
XRAY_ARCH_MAP=("amd64:64" "arm64:arm64-v8a")
TMP_XRAY_ZIP="/tmp/xray-download.zip"

for item in "${XRAY_ARCH_MAP[@]}"; do
  arch="${item%%:*}"
  zip_arch="${item##*:}"
  dest="${ROOT_DIR}/xray/xray-linux-${arch}"
  url="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${zip_arch}.zip"
  dl "$url" "$TMP_XRAY_ZIP" "Xray-core ${arch} (zip)"
  extract_zip_entry "$TMP_XRAY_ZIP" "xray" "$dest"
  chmod +x "$dest"
  rm -f "$TMP_XRAY_ZIP"
done

# ─── H2 Client（Hysteria2 客户端复用同一二进制） ─────────────────────────────
echo ""
echo "=== 准备 H2 Client 二进制（复用 Hysteria2）==="
mkdir -p "${ROOT_DIR}/h2client"

for arch in "${ARCHS[@]}"; do
  src="${ROOT_DIR}/hysteria/hysteria-linux-${arch}"
  dest="${ROOT_DIR}/h2client/h2-linux-${arch}"
  cp -p "$src" "$dest"
  echo "  复制: hysteria-linux-${arch} -> h2client/h2-linux-${arch}"
done

# ─── Caddy（带 forward_proxy / NaiveProxy 插件） ─────────────────────────────
# klzgrad/forwardproxy 未在 Caddy 官方模块注册，无法通过下载 API 获取。
# 需要用 xcaddy 本地编译。amd64 若已有预编译二进制则直接复用。
echo ""
echo "=== 准备 Caddy（含 klzgrad/forwardproxy 插件）==="
mkdir -p "${ROOT_DIR}/caddy"

build_caddy_with_xcaddy() {
  local arch="$1" dest="$2"
  echo "  使用 xcaddy 编译 Caddy+forwardproxy (${arch})..."
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  # xcaddy 只支持当前机器架构；交叉编译需设置 GOARCH
  local goarch="$arch"
  [[ "$arch" == "arm64" ]] && goarch="arm64"
  [[ "$arch" == "amd64" ]] && goarch="amd64"
  GOARCH="$goarch" GOOS=linux xcaddy build \
    --with github.com/klzgrad/forwardproxy \
    --output "${tmp_dir}/caddy"
  mv "${tmp_dir}/caddy" "$dest"
  chmod +x "$dest"
  rm -rf "$tmp_dir"
  echo "  -> ${dest} OK"
}

# amd64：优先复用已有预编译二进制
CADDY_EXISTING="${ROOT_DIR}/caddy/caddy"
CADDY_AMD64="${ROOT_DIR}/caddy/caddy-linux-amd64"
if [[ ! -f "$CADDY_AMD64" ]]; then
  if [[ -x "$CADDY_EXISTING" ]]; then
    cp -p "$CADDY_EXISTING" "$CADDY_AMD64"
    echo "  复用已有二进制: caddy -> caddy-linux-amd64"
  elif have_cmd xcaddy; then
    build_caddy_with_xcaddy "amd64" "$CADDY_AMD64"
  else
    echo "  警告：未找到 Caddy amd64 二进制，也未安装 xcaddy。"
    echo "  请手动执行以下命令编译后放到 caddy/caddy-linux-amd64："
    echo "    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest"
    echo "    xcaddy build --with github.com/klzgrad/forwardproxy --output caddy/caddy-linux-amd64"
  fi
else
  echo "  caddy-linux-amd64 已存在，跳过。"
fi

# arm64：需要 xcaddy 交叉编译（需 Go 环境）
CADDY_ARM64="${ROOT_DIR}/caddy/caddy-linux-arm64"
if [[ ! -f "$CADDY_ARM64" ]]; then
  if have_cmd xcaddy && have_cmd go; then
    build_caddy_with_xcaddy "arm64" "$CADDY_ARM64"
  else
    echo "  提示：Caddy arm64 需要本地编译，请在安装了 Go + xcaddy 的机器上执行："
    echo "    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest"
    echo "    GOARCH=arm64 GOOS=linux xcaddy build \\"
    echo "      --with github.com/klzgrad/forwardproxy \\"
    echo "      --output $(basename "$ROOT_DIR")/caddy/caddy-linux-arm64"
  fi
else
  echo "  caddy-linux-arm64 已存在，跳过。"
fi

# ─── 汇总 ────────────────────────────────────────────────────────────────────
echo ""
echo "=== 下载完成 ==="
echo ""
echo "文件列表："
for dir in caddy hysteria trojan xray h2client; do
  echo "  ${dir}/"
  find "${ROOT_DIR}/${dir}" -maxdepth 1 -type f \( -name "*linux*" -o -name "*.zip" \) \
    -exec ls -lh {} \; 2>/dev/null | awk '{printf "    %-12s %s\n", $5, $NF}' || true
done
echo ""
echo "现在可以将整个目录部署到 VPS 后执行 install.sh（无需联网）。"
