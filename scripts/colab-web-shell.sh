#!/usr/bin/env bash
# ============================================================
# Colab 一键 Web Shell + MEGA 上传（自包含，无第二阶段远程拉取）
# 隧道：cloudflared（主） + ngrok（备，可选）
# 云盘：MEGA push（Colab 是远端环境，不能 FUSE 挂载你本地）
#       产出文件通过 megaput 上传到 MEGA，你本地 /mnt/clouddisk-mega-honey 自动可见
#
# 使用（在 Colab Cell 里）：
#   PORT=7681 PASSWORD=*** NGROK_TOKEN=*** \
#   MEGA_EMAIL=*** MEGA_PASSWORD=*** \
#   bash <(curl -fsSL <你的raw URL>/colab-web-shell.sh)
#
# 上传文件示例：
#   mega-put --username=$MEGA_EMAIL --password=$MEGA_PASSWORD \
#            --no-ask-password -f /content/output.png /Root/
#
# ⚠️ 所有敏感信息通过环境变量传入，脚本本身不含任何凭证，
#    可安全 push 到 GitHub 公开仓库。
# ============================================================
set -euo pipefail

# ---------- 凭证：全部后填（环境变量），脚本零硬编码 ----------
PORT=${PORT:-7681}
PASSWORD=${PASSWORD:-$(openssl rand -hex 6)}
NGROK_TOKEN=${NGROK_TOKEN:-}

# MEGA push 配置（可选，留空则不初始化）
MEGA_EMAIL=${MEGA_EMAIL:-}
MEGA_PASSWORD=${MEGA_PASSWORD:-}

echo "[1/4] installing ttyd + megatools..."
if ! command -v ttyd >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq ttyd >/dev/null 2>&1
fi
if ! command -v megatools >/dev/null 2>&1; then
  apt-get install -y -qq megatools >/dev/null 2>&1 || pip install -q megatools 2>/dev/null || true
fi
echo "  ttyd + megatools ready"

echo "[2/4] starting ttyd on :${PORT}"
mkdir -p /tmp/colab-shell
ttyd -p ${PORT} -c "${PASSWORD}" bash >/tmp/ttyd.log 2>&1 &
sleep 3

echo "[3/4] exposing tunnels..."
cloudflared tunnel --url http://localhost:${PORT} >/tmp/cf.log 2>&1 &
if [ -n "${NGROK_TOKEN}" ]; then
  ngrok config add-authtoken ${NGROK_TOKEN} >/dev/null 2>&1 || true
  ngrok http ${PORT} >/tmp/ngrok.log 2>&1 &
fi

echo "[4/4] MEGA push setup (if credentials provided)..."
if [ -n "${MEGA_EMAIL}" ] && [ -n "${MEGA_PASSWORD}" ]; then
  echo "  MEGA_EMAIL=${MEGA_EMAIL}"
  echo "  上传示例："
  echo "    megaput --username=${MEGA_EMAIL} --password=${MEGA_PASSWORD} \\"
  echo "            --no-ask-password -f /content/your_file.png /Root/"
  echo "  云端查看：你本地 /mnt/clouddisk-mega-honey （已 FUSE 挂载，20GB）"
else
  echo "  MEGA 未配置（未提供 MEGA_EMAIL/MEGA_PASSWORD）"
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
echo "  MEGA 上传: megaput --username=\$MEGA_EMAIL --password=\$MEGA_PASSWORD -f <file> /Root/"
echo "========================================="
echo "⏳ 连接超时约 90 分钟（Colab 免费版限制）"
