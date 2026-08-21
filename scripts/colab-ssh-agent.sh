#!/usr/bin/env bash
# Colab SSH — Agent 专用版（非交互，供 Honey 远程接管）
# 逻辑：装 sshd + 起 cloudflared quick tunnel，打印连接信息，保持运行
# 不提供菜单/交互，纯自动化
set -uo pipefail

SSH_PASSWORD=${SSH_PASSWORD:-$(openssl rand -hex 8)}
echo "[*] Colab SSH Agent Setup"
echo "[*] 密码: ${SSH_PASSWORD}"

# 1. 安装 openssh-server
echo "[1/4] 安装 openssh-server..."
apt-get update -qq
apt-get install -y -qq openssh-server >/dev/null 2>&1

# 2. 配置 sshd
echo "[2/4] 配置 sshd..."
mkdir -p /var/run/sshd
echo "root:${SSH_PASSWORD}" | chpasswd
# 清理可能冲突的配置
rm -f /etc/ssh/sshd_config.d/* 2>/dev/null
# 追加允许 root 密码登录
grep -q "PermitRootLogin yes" /etc/ssh/sshd_config || echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
# 生成 host keys（sshd 启动必须）
ssh-keygen -A 2>/dev/null || true

# 3. 启动 sshd
echo "[3/4] 启动 sshd..."
pkill sshd 2>/dev/null || true
sleep 1
/usr/sbin/sshd
sleep 2
if ss -tlnp 2>/dev/null | grep -q ':22'; then
  echo "[OK] sshd 监听 22 端口"
else
  echo "[!] sshd 未监听，重试直接指定端口..."
  /usr/sbin/sshd -p 22
  sleep 2
fi

# 4. 启动 cloudflared tunnel
echo "[4/4] 启动 cloudflared quick tunnel..."
if ! command -v cloudflared >/dev/null 2>&1; then
  curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
  chmod +x /tmp/cloudflared
fi
/tmp/cloudflared tunnel --url ssh://localhost:22 >/tmp/cf_ssh.log 2>&1 &
sleep 10

CF_HOST=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cf_ssh.log | tail -1 || true)

# 输出连接信息（供 agent 读取）
echo "=========================================="
echo "AGENT_CONNECT_INFO"
echo "CF_HOST=${CF_HOST}"
echo "SSH_PASSWORD=${SSH_PASSWORD}"
echo "LOCAL_CMD=ssh -o ProxyCommand=\"cloudflared access ssh --hostname ${CF_HOST}\" root@${CF_HOST}"
echo "SSHD_LISTEN=$(ss -tlnp 2>/dev/null | grep ':22' || echo 'none')"
echo "=========================================="

wait
