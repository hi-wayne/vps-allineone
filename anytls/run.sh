#!/bin/sh
# anytls-server 只接受命令行参数，没有配置文件。
# 这里从 /data/anytls/config.yaml 读取监听地址与密码后再启动，
# 使凭据与其他组件一样保存在各自的配置文件中，而不是写在 systemd unit 里。
set -e
cd /data/anytls

CONF="/data/anytls/config.yaml"
[ -f "$CONF" ] || { echo "缺少配置文件 $CONF" >&2; exit 1; }

listen=$(sed -n 's/^listen:[[:space:]]*//p'   "$CONF" | head -1)
password=$(sed -n 's/^password:[[:space:]]*//p' "$CONF" | head -1)

[ -n "$listen" ]   || { echo "$CONF 中缺少 listen"   >&2; exit 1; }
[ -n "$password" ] || { echo "$CONF 中缺少 password" >&2; exit 1; }

exec /data/anytls/anytls-server -l "$listen" -p "$password"
