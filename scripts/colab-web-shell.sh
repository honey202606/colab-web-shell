#!/usr/bin/env bash
# ============================================================
# Colab 一键 Web Shell + MEGA 上传（四隧道冗余，中文菜单）
# 隧道优先级：
#   ① cloudflared（主）
#   ② serveo（SSH 反向隧道，零依赖）
#   ③ Colab 原生 serve_kernel_port（兜底）
#   ④ ngrok（最后启用，已知昨天失效）
#
# 使用（在 Colab Cell 里）：
#   PORT=7681 PASSWORD=*** NGROK_TOKEN=*** \
#   MEGA_EMAIL=*** MEGA_PASSWORD=*** \
#   bash <(curl -fsSL <你的raw URL>/colab-web-shell.sh)
#
# 上传文件示例：
#   megaput --username=$MEGA_EMAIL --password=$MEGA_PASSWORD \
#            --no-ask-password -f /content/output.png /Root/
#
# ⚠️ 所有敏感信息通过环境变量传入，脚本本身不含任何凭证
# ============================================================
set -euo pipefail

# ---------- 配置 ----------
PORT=${PORT:-7681}
PASSWORD=${PASSWORD:-$(openssl rand -hex 6)}
NGROK_TOKEN=${NGROK_TOKEN:-}
MEGA_EMAIL=${MEGA_EMAIL:-}
MEGA_PASSWORD=${MEGA_PASSWORD:-}

# ---------- 颜色 ----------
R='\033[1;38;5;196m'
G='\033[1;38;5;82m'
Y='\033[1;38;5;220m'
C='\033[1;38;5;51m'
W='\033[1;38;5;255m'
DG='\033[0;38;5;244m'
NC='\033[0m'

# ---------- 工具函数 ----------
header() {
  clear
  echo -e "${C}"
  cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║        Colab Web Shell + MEGA 云盘（四隧道冗余）        ║
╚══════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
}

status_line() {
  echo -e " ${DG}├─ $1${NC} ${W}$2${NC}"
}

ok() { echo -e " ${G}[✓]${NC} $1"; }
warn() { echo -e " ${Y}[!]${NC} $1"; }
err() { echo -e " ${R}[✗]${NC} $1"; }

# ---------- 主流程 ----------
main() {
  header

  echo -e " ${Y}[1/5] 安装依赖...${NC}"
  if ! command -v ttyd >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq ttyd >/dev/null 2>&1
  fi
  if ! command -v megatools >/dev/null 2>&1; then
    apt-get install -y -qq megatools >/dev/null 2>&1 || pip install -q megatools 2>/dev/null || true
  fi
  ok "ttyd + megatools 就绪"

  echo -e "\n ${Y}[2/5] 启动 ttyd (端口 ${PORT})...${NC}"
  mkdir -p /tmp/colab-shell
  ttyd -p ${PORT} -c "${PASSWORD}" bash >/tmp/ttyd.log 2>&1 &
  sleep 3
  ok "ttyd 已启动 (密码: ${PASSWORD})"

  echo -e "\n ${Y}[3/5] 启动隧道...${NC}"
  # ① cloudflared
  cloudflared tunnel --url http://localhost:${PORT} >/tmp/cf.log 2>&1 &
  sleep 2
  # ② serveo
  ssh -o StrictHostKeyChecking=no -R 80:localhost:${PORT} serveo.net >/tmp/serveo.log 2>&1 &
  sleep 2
  # ④ ngrok（最后）
  if [ -n "${NGROK_TOKEN}" ]; then
    ngrok config add-authtoken ${NGROK_TOKEN} >/dev/null 2>&1 || true
    ngrok http ${PORT} >/tmp/ngrok.log 2>&1 &
  fi
  ok "四隧道已启动（等待 URL 生成...）"

  echo -e "\n ${Y}[4/5] MEGA 云盘配置...${NC}"
  if [ -n "${MEGA_EMAIL}" ] && [ -n "${MEGA_PASSWORD}" ]; then
    ok "MEGA 账号: ${MEGA_EMAIL}"
    echo -e "   ${DG}本地挂载: /mnt/clouddisk-mega-honey${NC}"
    echo -e "   ${DG}上传命令:${NC}"
    echo -e "     megaput --username=${MEGA_EMAIL} --password=${MEGA_PASSWORD} \\"
    echo -e "             --no-ask-password -f /content/文件.png /Root/"
  else
    warn "未提供 MEGA 凭证，跳过云盘配置"
    echo -e "   ${DG}需要时重跑并设置:${NC}"
    echo -e "     MEGA_EMAIL=*** MEGA_PASSWORD=***"
  fi

  echo -e "\n ${Y}[5/5] 等待隧道就绪...${NC}"
  sleep 8

  # ---------- 结果展示 ----------
  header
  echo -e " ${G}★ Web Shell 已就绪 ★${NC}\n"

  echo -e " ${DG}─ 基本信息 ─${NC}"
  status_line "本地地址:" "http://localhost:${PORT}"
  status_line "登录密码:" "${PASSWORD}"

  echo -e "\n ${DG}─ 四隧道 URL（按优先级排序） ─${NC}"

  # ① cloudflared
  CF_URL=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' /tmp/cf.log | tail -1)
  if [ -n "${CF_URL}" ]; then
    ok "① cloudflared（主）: ${CF_URL}"
  else
    warn "① cloudflared（主）: 生成中..."
  fi

  # ② serveo
  SRV_URL=$(grep -oE 'https://[a-z0-9.-]+\.serveo\.net' /tmp/serveo.log | tail -1)
  if [ -n "${SRV_URL}" ]; then
    ok "② serveo（SSH 零依赖）: ${SRV_URL}"
  else
    warn "② serveo（SSH 零依赖）: 生成中..."
  fi

  # ③ Colab 原生
  echo -e " ${C}③ Colab 原生（兜底）:${NC}"
  echo -e "   ${DG}在 Cell 里运行:${NC}"
  echo -e "     from google.colab import output"
  echo -e "     output.serve_kernel_port(${PORT})"

  # ④ ngrok
  if [ -n "${NGROK_TOKEN}" ]; then
    NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -oE 'https://[a-z0-9.-]+\.ngrok\.io' | head -1)
    if [ -n "${NGROK_URL}" ]; then
      ok "④ ngrok（备用）: ${NGROK_URL}"
    else
      warn "④ ngrok（备用）: 生成中..."
    fi
  else
    warn "④ ngrok（备用）: 未配置 NGROK_TOKEN"
  fi

  echo -e "\n ${DG}─ MEGA 上传 ─${NC}"
  if [ -n "${MEGA_EMAIL}" ] && [ -n "${MEGA_PASSWORD}" ]; then
    echo -e "  ${G}megaput${NC} --username=${MEGA_EMAIL} --password=${MEGA_PASSWORD} \\"
    echo -e "         --no-ask-password -f /content/文件.png /Root/"
    echo -e "  ${DG}本地查看:${NC} /mnt/clouddisk-mega-honey"
  else
    warn "未配置 MEGA_EMAIL / MEGA_PASSWORD"
  fi

  echo -e "\n ${DG}──────────────────────────────────────────────────────${NC}"
  echo -e " ⏳ 连接超时约 90 分钟（Colab 免费版限制）"
  echo -e " ${DG}按 Ctrl+C 不会停止服务，只是退出本脚本${NC}"
  echo -e " ${DG}需要停止时请在 Colab 里重启运行时${NC}"
  echo -e "${NC}"

  # 保持前台运行
  wait
}

main "$@"
