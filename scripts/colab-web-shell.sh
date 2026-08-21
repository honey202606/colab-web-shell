#!/usr/bin/env bash
# Colab 网页终端（极简版：CF + SSHX）
set -euo pipefail

PORT=7681
PASSWORD=$(openssl rand -hex 6)

# 依赖
apt-get update -qq
apt-get install -y -qq ttyd protobuf-compiler >/dev/null 2>&1 || true
PROTOC=/usr/bin/protoc cargo install sshx >/dev/null 2>&1 || true
export PATH="/root/.cargo/bin:$PATH"

# ttyd
mkdir -p /tmp/colab-shell
ttyd -p ${PORT} -c "${PASSWORD}" bash >/tmp/ttyd.log 2>&1 &
sleep 3

# 隧道① sshx
sshx -q >/tmp/sshx.log 2>&1 &
sleep 5

# 隧道② cloudflared
cloudflared tunnel --url http://localhost:${PORT} >/tmp/cf.log 2>&1 &
sleep 8

# 输出
clear
cat << EOF
═══════════════════════════════════════════════════════════════
  Colab Web Shell 就绪
  密码: ${PASSWORD}
═══════════════════════════════════════════════════════════════
EOF

SSHX_URL=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9]+#[A-Za-z0-9]+' /tmp/sshx.log | tail -1)
[ -n "${SSHX_URL}" ] && echo "① sshx:  ${SSHX_URL}" || echo "① sshx:  生成中..."

CF_URL=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' /tmp/cf.log | tail -1)
[ -n "${CF_URL}" ] && echo "② CF:    ${CF_URL}" || echo "② CF:    生成中..."

echo "═══════════════════════════════════════════════════════════════"
echo "后台运行中..."

wait
