#!/usr/bin/env bash
# Colab 网页终端（一键可达，外部可访问）
# 凭证通过环境变量后填，脚本零硬编码
set -euo pipefail

PORT=${PORT:-7681}
PASSWORD=${PASSWORD:-$(openssl rand -hex 6)}

# ① cloudflared（主）
# ② serveo（SSH 反向隧道）
# ③ Colab 原生 serve_kernel_port（兜底）
# ④ ngrok（最后启用，已知昨天失效）

echo "[1/4] installing ttyd..."
if ! command -v ttyd >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq ttyd >/dev/null 2>&1
fi

echo "[2/4] starting ttyd on :${PORT}"
mkdir -p /tmp/colab-shell
ttyd -p ${PORT} -c "${PASSWORD}" bash >/tmp/ttyd.log 2>&1 &
sleep 3

echo "[3/4] tunnels..."
cloudflared tunnel --url http://localhost:${PORT} >/tmp/cf.log 2>&1 &
ssh -o StrictHostKeyChecking=no -R 80:localhost:${PORT} serveo.net >/tmp/serveo.log 2>&1 &
if [ -n "${NGROK_TOKEN:-}" ]; then
  ngrok config add-authtoken ${NGROK_TOKEN} >/dev/null 2>&1 || true
  ngrok http ${PORT} >/tmp/ngrok.log 2>&1 &
fi

sleep 8

echo ""
echo "============ Web Shell 就绪 ============"
echo "密码: ${PASSWORD}"
echo "① cloudflared: $(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' /tmp/cf.log | tail -1 || echo '生成中...')"
echo "② serveo:      $(grep -oE 'https://[a-z0-9.-]+\.serveo\.net' /tmp/serveo.log | tail -1 || echo '生成中...')"
echo "③ Colab 原生:  output.serve_kernel_port(${PORT})"
[ -n "${NGROK_TOKEN:-}" ] && echo "④ ngrok:       $(curl -s http://localhost:4040/api/tunnels | grep -oE 'https://[a-z0-9.-]+\.ngrok\.io' | head -1 || echo '生成中...')"
echo "========================================="

wait
