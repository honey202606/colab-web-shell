#!/usr/bin/env bash
# ============================================================
# Colab SSH 四通道暴露（陛下指定优先级）
# 优先级：
#   ① serveo（标准 SSH，无需跳板机）
#   ② localhost.run（标准 SSH，无需跳板机）
#   ③ Cloudflare SSH（需 cloudflared 客户端）
#   ④ sshx.io（浏览器终端兜底）
# ============================================================
set -euo pipefail

SSH_PORT=22
SSH_PASSWORD=${SSH_PASSWORD:-$(openssl rand -hex 8)}
SSH_USER=${SSH_USER:-root}
SERVEO_PORT=2222
LH_PORT=2223

echo "========================================="
echo "  Colab SSH 四通道启动"
echo "  用户: ${SSH_USER}"
echo "  密码: ${SSH_PASSWORD}"
echo "========================================="

# ---------- 1. 安装 SSH ----------
echo "[1/6] 安装 openssh-server..."
apt-get update -qq
apt-get install -y -qq openssh-server >/dev/null 2>&1 || {
  echo "openssh-server 安装失败"
  exit 1
}

echo "[2/6] 配置 SSH..."
mkdir -p /var/run/sshd
echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
service ssh start 2>/dev/null || /usr/sbin/sshd || true

# ---------- 2. 通道1: serveo ----------
echo "[3/6] 通道1: serveo..."
ssh -o StrictHostKeyChecking=no -R ${SERVEO_PORT}:localhost:${SSH_PORT} serveo.net >/tmp/serveo_ssh.log 2>&1 &
SERVEO_PID=$!
sleep 6
SERVEO_HOST=$(grep -oE '[a-z0-9.-]+\.serveo\.net' /tmp/serveo_ssh.log | tail -1 || true)

# ---------- 3. 通道2: localhost.run ----------
echo "[4/6] 通道2: localhost.run..."
ssh -o StrictHostKeyChecking=no -R ${LH_PORT}:localhost:${SSH_PORT} localhost.run >/tmp/lh_ssh.log 2>&1 &
LH_PID=$!
sleep 6
LH_HOST=$(grep -oE '[a-z0-9.-]+\.localhost\.run' /tmp/lh_ssh.log | tail -1 || true)

# ---------- 4. 通道3: Cloudflare SSH ----------
echo "[5/6] 通道3: Cloudflare SSH..."
if ! command -v cloudflared >/dev/null 2>&1; then
  curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
  chmod +x /tmp/cloudflared
fi
/tmp/cloudflared tunnel --url ssh://localhost:${SSH_PORT} >/tmp/cf_ssh.log 2>&1 &
CF_PID=$!
sleep 8
CF_HOST=$(grep -oE '[a-z0-9-]+\.trycloudflare\.com' /tmp/cf_ssh.log | tail -1 || true)

# ---------- 5. 通道4: sshx ----------
echo "[6/6] 通道4: sshx (浏览器终端)..."
if ! command -v sshx >/dev/null 2>&1; then
  if [ -f /root/.cargo/bin/sshx ]; then
    export PATH="/root/.cargo/bin:$PATH"
  else
    apt-get install -y -qq protobuf-compiler >/dev/null 2>&1 || true
    PROTOC=/usr/bin/protoc cargo install sshx >/dev/null 2>&1 || true
    export PATH="/root/.cargo/bin:$PATH"
  fi
fi
sshx -q >/tmp/sshx.log 2>&1 &
SSHX_PID=$!
sleep 5
SSHX_URL=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9]+#[A-Za-z0-9]+' /tmp/sshx.log | tail -1 || true)

# ---------- 6. 输出连接信息 ----------
echo ""
echo "========================================="
echo "  连接信息（按优先级尝试）"
echo "========================================="
echo ""
echo "【① serveo】主用（标准 SSH）"
if [ -n "${SERVEO_HOST}" ]; then
  echo "   ssh -p ${SERVEO_PORT} ${SSH_USER}@${SERVEO_HOST}"
else
  echo "   ssh -p ${SERVEO_PORT} ${SSH_USER}@serveo.net"
fi
echo "   密码: ${SSH_PASSWORD}"
echo ""
echo "【② localhost.run】备用（标准 SSH）"
if [ -n "${LH_HOST}" ]; then
  echo "   ssh -p ${LH_PORT} ${SSH_USER}@${LH_HOST}"
else
  echo "   ssh -p ${LH_PORT} ${SSH_USER}@localhost.run"
fi
echo "   密码: ${SSH_PASSWORD}"
echo ""
echo "【③ Cloudflare SSH】备用（需 cloudflared 客户端）"
if [ -n "${CF_HOST}" ]; then
  echo "   ssh -o ProxyCommand='cloudflared access ssh --hostname ${CF_HOST}' ${SSH_USER}@${CF_HOST}"
else
  echo "   域名生成中，查看 /tmp/cf_ssh.log"
fi
echo "   密码: ${SSH_PASSWORD}"
echo ""
echo "【④ sshx.io】浏览器兜底"
if [ -n "${SSHX_URL}" ]; then
  echo "   ${SSHX_URL}"
else
  echo "   生成中，查看 /tmp/sshx.log"
fi
echo ""
echo "========================================="
echo "  serveo PID: ${SERVEO_PID:-unknown}"
echo "  localhost.run PID: ${LH_PID:-unknown}"
echo "  cloudflared PID: ${CF_PID:-unknown}"
echo "  sshx PID: ${SSHX_PID:-unknown}"
echo "  后台运行中..."
echo "========================================="

wait
