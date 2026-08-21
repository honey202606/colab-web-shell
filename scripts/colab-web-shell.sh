#!/usr/bin/env bash
# ============================================================
# Colab 一键 Web Shell（自包含，无第二阶段远程拉取）
# 隧道：cloudflared（主） + ngrok（备，可选）
# 使用：在 Colab Cell 里 !bash <(curl -fsSL <你的托管地址>)
# ============================================================
set -euo pipefail

PORT=${PORT:-7681}
PASSWORD=${PASSWORD:-$(openssl rand -hex 6)}
NGROK_TOKEN=${NGROK_TOKEN:-}

echo "[1/3] installing ttyd..."
if ! command -v ttyd >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq ttyd >/dev/null 2>&1
fi
echo "  ttyd ready"

echo "[2/3] starting ttyd on :${PORT}"
mkdir -p /tmp/colab-shell
ttyd -p ${PORT} -c "${PASSWORD}" bash >/tmp/ttyd.log 2>&1 &
sleep 3

echo "[3/3] exposing tunnels..."
cloudflared tunnel --url http://localhost:${PORT} >/tmp/cf.log 2>&1 &
if [ -n "${NGROK_TOKEN}" ]; then
  ngrok config add-authtoken ${NGROK_TOKEN} >/dev/null 2>&1 || true
  ngrok http ${PORT} >/tmp/ngrok.log 2>&1 &
fi

sleep 8

echo ""
echo "========================================="
echo "  Web Shell 已就绪"
echo "  密码: ${PASSWORD}"
echo "  本地: http://localhost:${PORT}"
echo ""
echo "--- cloudflared (主) ---"
grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' /tmp/cf.log | tail -1 || echo "checking..."
echo ""
if [ -n "${NGROK_TOKEN}" ]; then
  echo "--- ngrok (备) ---"
  curl -s http://localhost:4040/api/tunnels | grep -oE 'https://[a-z0-9.-]+\.ngrok\.io' | head -1 || echo "checking..."
fi
echo ""
echo "  Colab 原生兜底: output.serve_kernel_port(${PORT})"
echo "========================================="
echo "⏳ 连接超时约 90 分钟（Colab 免费版限制）"
