#!/usr/bin/env bash
# Colab Web Terminal — Agent 专用版（ttyd + cloudflared HTTP tunnel）
# 逻辑：装 ttyd → 起在 7681 → CF HTTP 隧道 → 输出浏览器 URL
# 零 SSH、零交互、纯自动化
set -uo pipefail

echo "[*] Colab Web Terminal Setup"
echo "[*] 端口: 7681"

# 1. 安装 ttyd
echo "[1/3] 安装 ttyd..."
apt-get update -qq
apt-get install -y -qq ttyd >/dev/null 2>&1

# 2. 启动 ttyd（bash，无认证，直接可用）
echo "[2/3] 启动 ttyd..."
nohup ttyd -p 7681 -W bash >/tmp/ttyd.log 2>&1 &
sleep 3
if curl -s --max-time 3 http://127.0.0.1:7681/ >/dev/null 2>&1; then
  echo "[OK] ttyd 已启动"
else
  echo "[!] ttyd 启动失败，查看日志"
  tail -5 /tmp/ttyd.log
fi

# 3. 启动 cloudflared HTTP tunnel
echo "[3/3] 启动 cloudflared HTTP tunnel..."
if ! command -v cloudflared >/dev/null 2>&1; then
  curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
  chmod +x /tmp/cloudflared
fi
nohup /tmp/cloudflared tunnel --url http://localhost:7681 >/tmp/cf_http.log 2>&1 &
sleep 10

CF_HOST=$(grep -oE '[a-z0-9-]+\.trycloudflare\.com' /tmp/cf_http.log | tail -1 || true)

# 输出连接信息
echo "=========================================="
echo "AGENT_CONNECT_INFO"
echo "TTYD_URL=http://127.0.0.1:7681"
echo "CF_HOST=${CF_HOST:-NONE}"
echo "BROWSER_URL=https://${CF_HOST:-NONE}"
echo "=========================================="

wait
