#!/usr/bin/env bash
# ============================================================
# Colab SSH 双通道暴露（serveo + 反向隧道）
# 功能：Colab 容器开 sshd + 两条独立外连通道
#   通道1: serveo（标准 SSH，无需跳板机）
#   通道2: 反向 SSH 隧道（需要 JUMBPHOST 环境变量）
# 用法：
#   仅 serveo：
#     bash <(curl -fsSL <raw_url>/colab-ssh-setup.sh)
#   同时开启反向隧道（需要跳板机）：
#     JUMBPHOST=user@jumphost.example.com bash <(curl -fsSL <raw_url>/colab-ssh-setup.sh)
# ============================================================
set -euo pipefail

# ---------- 配置 ----------
SSH_PORT=22
SSH_PASSWORD=${SSH_PASSWORD:-$(openssl rand -hex 8)}
SSH_USER=${SSH_USER:-root}
JUMBPHOST=${JUMBPHOST:-}
SERVEO_PORT=2222

echo "========================================="
echo "  Colab SSH 双通道启动"
echo "  用户: ${SSH_USER}"
echo "  密码: ${SSH_PASSWORD}"
echo "========================================="

# ---------- 1. 安装 SSH ----------
echo "[1/5] 安装 openssh-server..."
apt-get update -qq
apt-get install -y -qq openssh-server >/dev/null 2>&1 || {
  echo "openssh-server 安装失败"
  exit 1
}

echo "[2/5] 配置 SSH..."
mkdir -p /var/run/sshd
echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
service ssh start 2>/dev/null || /usr/sbin/sshd || true

# ---------- 2. 通道1: serveo ----------
echo "[3/5] 通道1: serveo（标准 SSH）..."
ssh -o StrictHostKeyChecking=no -R ${SERVEO_PORT}:localhost:${SSH_PORT} serveo.net >/tmp/serveo_ssh.log 2>&1 &
SERVEO_PID=$!
sleep 6
SERVEO_URL=$(grep -oE 'ssh://[a-z0-9.-]+\.serveo\.net' /tmp/serveo_ssh.log | tail -1 || true)
SERVEO_HOST=$(echo "${SERVEO_URL}" | sed -E 's|ssh://||; s|:.*||' || true)
if [ -n "${SERVEO_HOST}" ]; then
  echo "  [✓] serveo: ${SERVEO_HOST}:${SERVEO_PORT}"
else
  echo "  [!] serveo: 生成中或失败，查看 /tmp/serveo_ssh.log"
fi

# ---------- 3. 通道2: 反向 SSH 隧道 ----------
echo "[4/5] 通道2: 反向 SSH 隧道..."
if [ -n "${JUMBPHOST}" ]; then
  ssh -o StrictHostKeyChecking=no -R 2222:localhost:${SSH_PORT} ${JUMBPHOST} >/tmp/reverse_ssh.log 2>&1 &
  REVERSE_PID=$!
  sleep 4
  echo "  [✓] 反向隧道已启动到 ${JUMBPHOST}"
  echo "      在跳板机上执行: ssh -p 2222 ${SSH_USER}@localhost"
else
  echo "  [i] 未提供 JUMBPHOST，跳过反向隧道"
  echo "      如需开启，执行: JUMBPHOST=user@host bash <(curl ...)"
fi

# ---------- 4. 输出连接信息 ----------
echo ""
echo "========================================="
echo "  连接信息"
echo "========================================="
echo ""
echo "【通道1】serveo（推荐）"
if [ -n "${SERVEO_HOST}" ]; then
  echo "   ssh -p ${SERVEO_PORT} ${SSH_USER}@${SERVEO_HOST}"
  echo "   密码: ${SSH_PASSWORD}"
else
  echo "   ssh -p ${SERVEO_PORT} ${SSH_USER}@serveo.net"
  echo "   密码: ${SSH_PASSWORD}"
  echo "   （等待 URL 生成，或查看 /tmp/serveo_ssh.log）"
fi
echo ""
echo "【通道2】反向隧道（需跳板机）"
if [ -n "${JUMBPHOST}" ]; then
  echo "   在跳板机 ${JUMBPHOST} 上："
  echo "   ssh -p 2222 ${SSH_USER}@localhost"
  echo "   密码: ${SSH_PASSWORD}"
else
  echo "   未配置 JUMBPHOST，跳过"
fi
echo ""
echo "【本地直连测试】"
echo "   ssh -p ${SSH_PORT} ${SSH_USER}@localhost"
echo "   密码: ${SSH_PASSWORD}"
echo ""
echo "========================================="
echo "  sshd PID: $(cat /var/run/sshd.pid 2>/dev/null || echo 'unknown')"
echo "  serveo PID: ${SERVEO_PID:-unknown}"
echo "  后台运行中..."
echo "========================================="

wait
