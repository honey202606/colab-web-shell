#!/usr/bin/env bash
# Colab SSH via Cloudflare Quick Tunnel（对齐已验证方案）
set -euo pipefail

SSH_PASSWORD=${SSH_PASSWORD:-$(openssl rand -hex 8)}

echo "========================================="
echo "  Colab SSH via Cloudflare"
echo "  密码: ${SSH_PASSWORD}"
echo "========================================="

echo "[1/4] 安装 openssh-server..."
apt-get update -qq
apt-get install -y -qq openssh-server >/dev/null 2>&1

echo "[2/4] 配置 SSH..."
mkdir -p /var/run/sshd
echo "root:${SSH_PASSWORD}" | chpasswd
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
service ssh start 2>/dev/null || /usr/sbin/sshd || true

echo "[3/4] 下载 cloudflared..."
if ! command -v cloudflared >/dev/null 2>&1; then
  curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
  chmod +x /tmp/cloudflared
fi

echo "[4/4] 启动 Cloudflare SSH Tunnel..."
/tmp/cloudflared tunnel --url ssh://localhost:22 >/tmp/cf_ssh.log 2>&1 &
sleep 8

CF_HOST=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cf_ssh.log | tail -1 || true)
echo ""
echo "========================================="
echo "  连接命令（本地执行）"
echo "========================================="
if [ -n "${CF_HOST}" ]; then
  echo "ssh root@${CF_HOST} -o ProxyCommand=\"cloudflared access ssh --hostname ${CF_HOST}\""
else
  echo "域名生成中，查看 /tmp/cf_ssh.log"
fi
echo "密码: ${SSH_PASSWORD}"
echo "========================================="

wait
