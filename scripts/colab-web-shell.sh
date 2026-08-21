#!/usr/bin/env bash
# Colab 网页终端（极简版：CF + SSHX）
set -euo pipefail

PORT=7681
PASSWORD=$(openssl rand -hex 6)

# 依赖
apt-get update -qq
apt-get install -y -qq ttyd >/dev/null 2>&1 || true

# sshx
if ! command -v sshx >/dev/null 2>&1; then
  if [ -f /root/.cargo/bin/sshx ]; then
    export PATH="/root/.cargo/bin:$PATH"
  else
    apt-get install -y -qq protobuf-compiler >/dev/null 2>&1 || true
    PROTOC=/usr/bin/protoc cargo install sshx >/dev/null 2>&1 || true
    export PATH="/root/.cargo/bin:$PATH"
  fi
fi

# cloudflared（优先本地二进制，否则下载）
if ! command -v cloudflared >/dev/null 2>&1; then
  if [ ! -f /tmp/cloudflared ]; then
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
    chmod +x /tmp/cloudflared
  fi
  export PATH="/tmp:$PATH"
fi

# ttyd
mkdir -p /tmp/colab-shell
ttyd -p ${PORT} -c "${PASSWORD}" bash >/tmp/ttyd.log 2>&1 &
sleep 3

# 隧道① sshx（输出在 stdout）
sshx -q >/tmp/sshx.log 2>&1 &
sleep 5

# 隧道② cloudflared
cloudflared tunnel --url http://localhost:${PORT} >/tmp/cf.log 2>&1 &
sleep 8

# 输出
clear
echo "═══════════════════════════════════════════════════════════════"
echo "  Colab Web Shell 就绪"
echo "  密码: ${PASSWORD}"
echo "═══════════════════════════════════════════════════════════════"

# sshx URL 在 stdout/stderr 都可能，两边都 grep
SSHX_URL=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9]+#[A-Za-z0-9]+' /tmp/sshx.log 2>/dev/null | tail -1)
if [ -z "${SSHX_URL}" ]; then
  SSHX_URL=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9]+#[A-Za-z0-9]+' /tmp/ttyd.log 2>/dev/null | tail -1)
fi
[ -n "${SSHX_URL}" ] && echo "① sshx:  ${SSHX_URL}" || echo "① sshx:  生成中..."

CF_URL=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' /tmp/cf.log | tail -1)
[ -n "${CF_URL}" ] && echo "② CF:    ${CF_URL}" || echo "② CF:    生成中..."

echo "═══════════════════════════════════════════════════════════════"
echo "后台运行中..."

wait
