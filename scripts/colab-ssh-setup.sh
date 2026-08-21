#!/usr/bin/env bash
# ============================================================
# Colab SSH via Cloudflare Tunnel（一键脚本）
# 功能：Colab 容器开 sshd + cloudflared 隧道 → 本地 SSH 直连
# 用法：bash <(curl -fsSL <raw_url>/colab-ssh-setup.sh)
# ============================================================
set -euo pipefail

# 配置
SSH_PORT=22
SSH_PASSWORD=${SSH_PASSWORD:-$(openssl rand -hex 8)}
SSH_USER=${SSH_USER:-root}

echo "[1/5] 安装 openssh-server + cloudflared..."
apt-get update -qq
apt-get install -y -qq openssh-server >/dev/null 2>&1 || {
  echo "openssh-server 安装失败，Colab 可能不允许 root 操作"
  exit 1
}

echo "[2/5] 下载 cloudflared..."
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
chmod +x /tmp/cloudflared

echo "[3/5] 配置 SSH..."
mkdir -p /var/run/sshd
echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true
service ssh start 2>/dev/null || /usr/sbin/sshd || true

echo "[4/5] 启动 Cloudflare SSH Tunnel..."
/tmp/cloudflared tunnel --url ssh://localhost:${SSH_PORT} >/tmp/cf_ssh.log 2>&1 &
sleep 8

echo "[5/5] 提取连接信息..."
CF_HOST=$(grep -oE '[a-z0-9-]+\.trycloudflare\.com' /tmp/cf_ssh.log | tail -1 || true)

echo ""
echo "========================================="
echo "  Colab SSH 已就绪"
echo "  用户: ${SSH_USER}"
echo "  密码: ${SSH_PASSWORD}"
echo "========================================="
echo ""
if [ -n "${CF_HOST}" ]; then
  echo "① 直接 SSH（需要本地也装 cloudflared）："
  echo "   ssh ${SSH_USER}@${CF_HOST}"
  echo ""
  echo "② 通过 cloudflared ProxyCommand："
  echo "   本地 ~/.ssh/config："
  echo "   Host colab"
  echo "     HostName ${CF_HOST}"
  echo "     User ${SSH_USER}"
  echo "     ProxyCommand cloudflared access ssh --hostname %h"
  echo ""
  echo "   然后："
  echo "   ssh colab"
else
  echo "⚠ cloudflared 域名尚未生成，查看日志："
  echo "   tail -f /tmp/cf_ssh.log"
fi
echo "========================================="

wait
