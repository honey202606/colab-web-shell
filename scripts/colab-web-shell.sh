#!/usr/bin/env bash
# ============================================================
# Colab 网页终端（中文美化版 + sshx 真终端）
# 核心：sshx.io 一键可达浏览器终端（开源、安全、无远程拉取）
# 备用：cloudflared / serveo / ngrok / Colab 原生（参考 ptero 冗余思路，但全本地实现）
# ============================================================
set -euo pipefail

# ---------- 颜色 ----------
R='\033[1;38;5;196m'
G='\033[1;38;5;82m'
Y='\033[1;38;5;220m'
C='\033[1;38;5;51m'
P='\033[1;38;5;201m'
VIOLET='\033[1;38;5;135m'
NEON='\033[1;38;5;198m'
W='\033[1;38;5;255m'
DG='\033[0;38;5;244m'
NC='\033[0m'

# ---------- 配置 ----------
PORT=${PORT:-7681}
PASSWORD=${PASSWORD:-$(openssl rand -hex 6)}
NGROK_TOKEN=${NGROK_TOKEN:-}
MEGA_EMAIL=${MEGA_EMAIL:-}
MEGA_PASSWORD=${MEGA_PASSWORD:-}

# ---------- UI ----------
clear
echo -e "${P}"
cat << "EOF"
███╗   ██╗ ██████╗ ██╗    ██╗ █████╗ ██████╗     ███████╗██╗  ██╗ █████╗  ██████╗
████╗  ██║██╔═══██╗██║    ██║██╔══██╗██╔══██╗    ██╔════╝╚██╗██╔╝██╔══██╗██╔════╝
██╔██╗ ██║██║   ██║██║ █╗ ██║███████║██║  ██║    █████╗   ╚███╔╝ ███████║██║     
██║╚██╗██║██║   ██║██║███╗██║██╔══██║██║  ██║    ██╔══╝   ██╔██╗ ██╔══██║██║     
██║ ╚████║╚██████╔╝╚███╔███╔╝██║  ██║██████╔╝    ███████╗██╔╔╝  ██║  ██║╚██████╗
╚═╝  ╚═══╝ ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═╝╚═════╝     ╚══════╝╚═╝    ╚═╝  ╚═╝ ╚═════╝
EOF
echo -e "${NC}"
echo -e "${VIOLET}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${VIOLET}║${NC}            ${P}☢️  Colab 网页终端 ${NEON}— ${Y}中文美化版 v1.0${NC}              ${VIOLET}║${NC}"
echo -e "${VIOLET}║${NC}            ${DG}$(date +"%Y-%m-%d %H:%M:%S")${NC}   ${G}SSHX 核心${NC}   ${VIOLET}║${NC}"
echo -e "${VIOLET}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo -e "\n${Y}                  ★★★ 远程终端协议已激活 ★★★${NC}\n"

# ---------- 诊断 ----------
echo -e " ${C}◉ 环境诊断${NC}"
echo -e " ${DG}├─ 主机名:${NC} ${W}$(hostname)${NC}"
echo -e " ${DG}├─ 用户:${NC} ${W}$(whoami)${NC}"
echo -e " ${DG}├─ 工作目录:${NC} ${W}$(pwd)${NC}"
echo -e " ${DG}├─ GPU:${NC} ${W}$(nvidia-smi -L 2>/dev/null | head -1 || echo '无')${NC}"
echo -e " ${DG}└─ 网络:${NC} ${G}$(curl -s --max-time 3 https://www.google.com >/dev/null 2>&1 && echo '可达' || echo '不可达')${NC}"
echo -e "${DG}──────────────────────────────────────────────────────────────────────────────${NC}"

# ---------- 主流程 ----------
echo -e "\n ${Y}[1/4] 安装依赖...${NC}"
if ! command -v sshx >/dev/null 2>&1; then
  if [ -f /root/.cargo/bin/sshx ]; then
    export PATH="/root/.cargo/bin:$PATH"
  else
    apt-get update -qq
    apt-get install -y -qq protobuf-compiler >/dev/null 2>&1
    PROTOC=/usr/bin/protoc cargo install sshx >/dev/null 2>&1 || true
    export PATH="/root/.cargo/bin:$PATH"
  fi
fi
command -v sshx >/dev/null 2>&1 && echo -e " ${G}[✓]${NC} sshx 就绪" || echo -e " ${R}[✗]${NC} sshx 安装失败"

echo -e "\n ${Y}[2/4] 启动 ttyd (端口 ${PORT})...${NC}"
if ! command -v ttyd >/dev/null 2>&1; then
  apt-get install -y -qq ttyd >/dev/null 2>&1
fi
mkdir -p /tmp/colab-shell
ttyd -p ${PORT} -c "${PASSWORD}" bash >/tmp/ttyd.log 2>&1 &
sleep 3
echo -e " ${G}[✓]${NC} ttyd 已启动 (密码: ${PASSWORD})"

echo -e "\n ${Y}[3/4] 启动隧道...${NC}"

# ① sshx（主，真终端）
echo -ne " ${DG}├─ sshx (主)...${NC} "
if command -v sshx >/dev/null 2>&1; then
  sshx -q >/tmp/sshx.log 2>&1 &
  sleep 4
  SSHX_URL=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9]+#[A-Za-z0-9]+' /tmp/sshx.log | tail -1)
  [ -n "$SSHX_URL" ] && echo -e "${G}OK${NC}" || echo -e "${Y}生成中...${NC}"
else
  echo -e "${R}未安装${NC}"
fi

# ② cloudflared（备）
echo -ne " ${DG}├─ cloudflared (备)...${NC} "
cloudflared tunnel --url http://localhost:${PORT} >/tmp/cf.log 2>&1 &
sleep 2
echo -e "${G}已启动${NC}"

# ③ serveo（第三）
echo -ne " ${DG}├─ serveo (第三)...${NC} "
ssh -o StrictHostKeyChecking=no -R 80:localhost:${PORT} serveo.net >/tmp/serveo.log 2>&1 &
sleep 2
echo -e "${G}已启动${NC}"

# ④ ngrok（最后）
if [ -n "${NGROK_TOKEN}" ]; then
  echo -ne " ${DG}└─ ngrok (最后)...${NC} "
  ngrok config add-authtoken ${NGROK_TOKEN} >/dev/null 2>&1 || true
  ngrok http ${PORT} >/tmp/ngrok.log 2>&1 &
  echo -e "${G}已启动${NC}"
else
  echo -e " ${DG}└─ ngrok: 跳过 (未配置 NGROK_TOKEN)${NC}"
fi

echo -e "\n ${Y}[4/4] MEGA 云盘...${NC}"
if [ -n "${MEGA_EMAIL}" ] && [ -n "${MEGA_PASSWORD}" ]; then
  echo -e " ${G}[✓]${NC} MEGA: ${MEGA_EMAIL}"
  echo -e "   ${DG}上传: megaput --username=${MEGA_EMAIL} --password=${MEGA_PASSWORD} --no-ask-password -f <文件> /Root/${NC}"
else
  echo -e " ${DG}[i]${NC} 未配置 MEGA（可选）"
fi

# ---------- 结果 ----------
sleep 6
echo -e "\n${DG}══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e " ${P}★★★ 终端已就绪 — 选一条 URL 连接 ★★★${NC}\n"

# sshx
[ -n "${SSHX_URL:-}" ] && echo -e " ${G}① sshx (主)${NC}: ${W}${SSHX_URL}${NC}" || echo -e " ${Y}① sshx (主)${NC}: 生成中..."

# cloudflared
CF_URL=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' /tmp/cf.log 2>/dev/null | tail -1)
[ -n "${CF_URL}" ] && echo -e " ${C}② cloudflared${NC}: ${W}${CF_URL}${NC}" || echo -e " ${DG}② cloudflared${NC}: 生成中..."

# serveo
SRV_URL=$(grep -oE 'https://[a-z0-9.-]+\.serveo\.net' /tmp/serveo.log 2>/dev/null | tail -1)
[ -n "${SRV_URL}" ] && echo -e " ${C}③ serveo${NC}: ${W}${SRV_URL}${NC}" || echo -e " ${DG}③ serveo${NC}: 生成中..."

# ngrok
if [ -n "${NGROK_TOKEN}" ]; then
  NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -oE 'https://[a-z0-9.-]+\.ngrok\.io' | head -1)
  [ -n "${NGROK_URL}" ] && echo -e " ${C}④ ngrok${NC}: ${W}${NGROK_URL}${NC}" || echo -e " ${DG}④ ngrok${NC}: 生成中..."
fi

echo -e "\n ${DG}⑤ Colab 原生兜底${NC}: output.serve_kernel_port(${PORT})"
echo -e "${DG}══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e " ${G}★ 推荐用 sshx（①）— 真终端、可协作、无需密码 ★${NC}"
echo -e " ${DG}后台运行中... 按 Ctrl+C 不停止服务${NC}\n"

wait
