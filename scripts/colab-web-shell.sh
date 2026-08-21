#!/usr/bin/env bash
# ============================================================
# Colab Web Shell + MEGA 云盘（四隧道冗余 + 中文交互菜单）
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

ok() { echo -e " ${G}[✓]${NC} $1"; }
warn() { echo -e " ${Y}[!]${NC} $1"; }
err() { echo -e " ${R}[✗]${NC} $1"; }
info() { echo -e " ${DG}[i]${NC} $1"; }

pause() {
  echo -e "\n${DG}按回车键继续...${NC}"
  read -r
}

# ---------- 环境诊断 ----------
diag_env() {
  header
  echo -e " ${Y}[环境诊断]${NC}\n"

  echo -e " ${DG}── 系统信息 ──${NC}"
  echo -e " 主机名: $(hostname)"
  echo -e " 用户名: $(whoami)"
  echo -e " 工作目录: $(pwd)"
  echo -e " 运行时间: $(uptime -p 2>/dev/null || echo 'N/A')"

  echo -e "\n ${DG}── GPU/TPU ──${NC}"
  if command -v nvidia-smi &>/dev/null; then
    nvidia-smi -L 2>/dev/null || echo " NVIDIA 驱动异常"
    nvidia-smi --query-gpu=memory.total,memory.used --format=csv,noheader 2>/dev/null || true
  else
    warn "未检测到 NVIDIA GPU"
  fi
  if [ -d "/sys/class/accelerator" ]; then
    echo " TPU: $(ls /sys/class/accelerator 2>/dev/null || echo '无')"
  fi

  echo -e "\n ${DG}── 磁盘空间 ──${NC}"
  df -h /content 2>/dev/null | head -2 || true
  df -h /tmp 2>/dev/null | head -2 || true

  echo -e "\n ${DG}── 网络连通 ──${NC}"
  if curl -s --max-time 3 https://www.google.com >/dev/null 2>&1; then
    ok "Google 可达"
  else
    warn "Google 不可达"
  fi

  echo -e "\n ${DG}── 已安装工具 ──${NC}"
  for cmd in ttyd megatools cloudflared ngrok ssh; do
    if command -v "$cmd" &>/dev/null; then
      ok "$cmd"
    else
      warn "$cmd 未安装"
    fi
  done

  pause
}

# ---------- MEGA 操作 ----------
mega_op() {
  header
  echo -e " ${Y}[MEGA 云盘操作]${NC}\n"

  if [ -z "${MEGA_EMAIL}" ] || [ -z "${MEGA_PASSWORD}" ]; then
    err "未配置 MEGA 凭证"
    echo -e " ${DG}请设置环境变量:${NC}"
    echo -e "   MEGA_EMAIL=*** MEGA_PASSWORD=***"
    pause
    return
  fi

  while true; do
    header
    echo -e " ${Y}[MEGA 云盘操作]${NC}"
    echo -e " 账号: ${MEGA_EMAIL}\n"
    echo -e " ${DG}1)${NC} 列出云端文件 (megals /Root)"
    echo -e " ${DG}2)${NC} 上传文件到 MEGA (megaput)"
    echo -e " ${DG}3)${NC} 下载文件从 MEGA (megaget)"
    echo -e " ${DG}4)${NC} 查看本地挂载 (/mnt/clouddisk-mega-honey)"
    echo -e " ${DG}5)${NC} 返回主菜单\n"
    echo -ne " ${W}请选择 [1-5]: ${NC}"
    read -r choice

    case $choice in
      1)
        echo -e "\n${DG}── 云端文件列表 ──${NC}"
        megals --username="${MEGA_EMAIL}" --password="${MEGA_PASSWORD}" --no-ask-password /Root 2>/dev/null || err "查询失败"
        pause
        ;;
      2)
        echo -ne "\n请输入要上传的文件路径: "
        read -r fpath
        if [ -f "$fpath" ]; then
          megaput --username="${MEGA_EMAIL}" --password="${MEGA_PASSWORD}" --no-ask-password -f "$fpath" "/Root/" 2>/dev/null && ok "上传成功" || err "上传失败"
        else
          err "文件不存在: $fpath"
        fi
        pause
        ;;
      3)
        echo -ne "\n请输入要下载的文件名: "
        read -r fname
        megaget --username="${MEGA_EMAIL}" --password="${MEGA_PASSWORD}" --no-ask-password "/Root/$fname" --path="/content/$fname" 2>/dev/null && ok "下载到 /content/$fname" || err "下载失败"
        pause
        ;;
      4)
        echo -e "\n${DG}── 本地 MEGA 挂载点 ──${NC}"
        ls -lah /mnt/clouddisk-mega-honey 2>/dev/null || warn "挂载点不可用"
        pause
        ;;
      5)
        return
        ;;
      *)
        warn "无效选择"
        sleep 1
        ;;
    esac
  done
}

# ---------- 文件管理 ----------
file_mgr() {
  header
  echo -e " ${Y}[Colab 文件管理]${NC}\n"

  while true; do
    header
    echo -e " ${Y}[Colab 文件管理]${NC}"
    echo -e " 当前目录: $(pwd)\n"
    echo -e " ${DG}1)${NC} 查看当前目录文件"
    echo -e " ${DG}2)${NC} 查看 /content 目录"
    echo -e " ${DG}3)${NC} 清理临时文件 (/tmp)"
    echo -e " ${DG}4)${NC} 返回主菜单\n"
    echo -ne " ${W}请选择 [1-4]: ${NC}"
    read -r choice

    case $choice in
      1)
        echo -e "\n${DG}── 当前目录 ──${NC}"
        ls -lah 2>/dev/null | head -20
        pause
        ;;
      2)
        echo -e "\n${DG}── /content 目录 ──${NC}"
        ls -lah /content 2>/dev/null | head -20 || warn "/content 不可访问"
        pause
        ;;
      3)
        echo -e "\n${DG}── 清理 /tmp 临时文件 ──${NC}"
        ls -lah /tmp 2>/dev/null | head -20
        echo -ne "\n确认清理 /tmp/*.log /tmp/*.png? [y/N]: "
        read -r confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
          rm -f /tmp/*.log /tmp/*.png 2>/dev/null || true
          ok "临时文件已清理"
        else
          warn "已取消"
        fi
        pause
        ;;
      4)
        return
        ;;
      *)
        warn "无效选择"
        sleep 1
        ;;
    esac
  done
}

# ---------- 隧道状态 ----------
tunnel_status() {
  header
  echo -e " ${Y}[隧道状态]${NC}\n"

  # ① cloudflared
  CF_URL=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' /tmp/cf.log 2>/dev/null | tail -1)
  if [ -n "${CF_URL}" ]; then
    ok "① cloudflared（主）: ${CF_URL}"
  else
    warn "① cloudflared（主）: 未就绪"
  fi

  # ② serveo
  SRV_URL=$(grep -oE 'https://[a-z0-9.-]+\.serveo\.net' /tmp/serveo.log 2>/dev/null | tail -1)
  if [ -n "${SRV_URL}" ]; then
    ok "② serveo（SSH 零依赖）: ${SRV_URL}"
  else
    warn "② serveo（SSH 零依赖）: 未就绪"
  fi

  # ③ Colab 原生
  info "③ Colab 原生（兜底）: 需在 Cell 里运行 serve_kernel_port"

  # ④ ngrok
  if [ -n "${NGROK_TOKEN}" ]; then
    NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -oE 'https://[a-z0-9.-]+\.ngrok\.io' | head -1)
    if [ -n "${NGROK_URL}" ]; then
      ok "④ ngrok（备用）: ${NGROK_URL}"
    else
      warn "④ ngrok（备用）: 未就绪（已知昨天失效）"
    fi
  else
    warn "④ ngrok（备用）: 未配置 NGROK_TOKEN"
  fi

  pause
}

# ---------- 主菜单 ----------
main_menu() {
  header
  echo -e " ${G}★ Web Shell 已就绪 ★${NC}\n"

  echo -e " ${DG}─ 基本信息 ──${NC}"
  echo -e " 本地地址: http://localhost:${PORT}"
  echo -e " 登录密码: ${PASSWORD}"

  echo -e "\n ${DG}─ 快速操作 ──${NC}"
  echo -e " ${DG}1)${NC} 环境诊断（GPU/磁盘/网络）"
  echo -e " ${DG}2)${NC} MEGA 云盘操作（上传/下载）"
  echo -e " ${DG}3)${NC} Colab 文件管理"
  echo -e " ${DG}4)${NC} 查看隧道状态"
  echo -e " ${DG}5)${NC} 退出菜单（保持后台运行）\n"

  echo -ne " ${W}请选择 [1-5]: ${NC}"
  read -r choice

  case $choice in
    1) diag_env ;;
    2) mega_op ;;
    3) file_mgr ;;
    4) tunnel_status ;;
    5)
      echo -e "\n${G}菜单已退出，后台服务继续运行${NC}"
      return 1
      ;;
    *)
      warn "无效选择，请输入 1-5"
      sleep 1
      ;;
  esac

  return 0
}

# ---------- 后台启动（非交互模式） ----------
background_mode() {
  header
  echo -e " ${Y}[后台启动模式]${NC}\n"

  echo -e " [1/4] 安装依赖..."
  if ! command -v ttyd &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq ttyd &>/dev/null
  fi
  if ! command -v megatools &>/dev/null; then
    apt-get install -y -qq megatools &>/dev/null || pip install -q megatools &>/dev/null || true
  fi
  ok "ttyd + megatools 就绪"

  echo -e "\n [2/4] 启动 ttyd (端口 ${PORT})..."
  mkdir -p /tmp/colab-shell
  ttyd -p ${PORT} -c "${PASSWORD}" bash >/tmp/ttyd.log 2>&1 &
  sleep 3
  ok "ttyd 已启动 (密码: ${PASSWORD})"

  echo -e "\n [3/4] 启动隧道..."
  cloudflared tunnel --url http://localhost:${PORT} >/tmp/cf.log 2>&1 &
  sleep 2
  ssh -o StrictHostKeyChecking=no -R 80:localhost:${PORT} serveo.net >/tmp/serveo.log 2>&1 &
  sleep 2
  if [ -n "${NGROK_TOKEN}" ]; then
    ngrok config add-authtoken ${NGROK_TOKEN} &>/dev/null || true
    ngrok http ${PORT} >/tmp/ngrok.log 2>&1 &
  fi
  ok "四隧道已启动"

  echo -e "\n [4/4] MEGA 配置..."
  if [ -n "${MEGA_EMAIL}" ] && [ -n "${MEGA_PASSWORD}" ]; then
    ok "MEGA 账号: ${MEGA_EMAIL}"
  else
    warn "未配置 MEGA 凭证"
  fi

  sleep 8

  # 输出 URLs
  header
  echo -e " ${G}★ Web Shell 已就绪 ★${NC}\n"

  CF_URL=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' /tmp/cf.log 2>/dev/null | tail -1)
  SRV_URL=$(grep -oE 'https://[a-z0-9.-]+\.serveo\.net' /tmp/serveo.log 2>/dev/null | tail -1)

  [ -n "${CF_URL}" ] && ok "① cloudflared（主）: ${CF_URL}" || warn "① cloudflared（主）: 生成中..."
  [ -n "${SRV_URL}" ] && ok "② serveo（SSH 零依赖）: ${SRV_URL}" || warn "② serveo（SSH 零依赖）: 生成中..."
  info "③ Colab 原生（兜底）: output.serve_kernel_port(${PORT})"
  [ -n "${NGROK_TOKEN}" ] && {
    NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -oE 'https://[a-z0-9.-]+\.ngrok\.io' | head -1)
    [ -n "${NGROK_URL}" ] && ok "④ ngrok（备用）: ${NGROK_URL}" || warn "④ ngrok（备用）: 生成中..."
  } || warn "④ ngrok（备用）: 未配置"

  echo -e "\n${DG}── MEGA 上传示例 ──${NC}"
  if [ -n "${MEGA_EMAIL}" ] && [ -n "${MEGA_PASSWORD}" ]; then
    echo -e "  megaput --username=${MEGA_EMAIL} --password=${MEGA_PASSWORD} \\"
    echo -e "         --no-ask-password -f /content/文件.png /Root/"
  fi

  echo -e "\n${DG}──────────────────────────────────────────────────────${NC}"
  echo -e " ⏳ 连接超时约 90 分钟"
  echo -e " ${DG}后台运行中...${NC}"

  wait
}

# ---------- 入口 ----------
if [ "${INTERACTIVE:-1}" = "1" ] && [ -t 0 ]; then
  # 交互模式：先启动后台，再进菜单
  background_mode &
  BG_PID=$!
  sleep 10
  while main_menu; do
    sleep 1
  done
  # 菜单退出后保持后台运行
  wait $BG_PID 2>/dev/null || true
else
  # 非交互模式（管道/重定向）：纯后台启动
  background_mode
fi
