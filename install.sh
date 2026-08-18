#!/bin/bash

# ============================================================
#  loginfopush 一键安装脚本 (Telegram-only 版)
#  仓库: https://github.com/jiam9069/loginfopush
#  站点: https://jiam9069.github.io/loginfopush/
#  使用: curl -fsSL https://jiam9069.github.io/loginfopush/install.sh -o install.sh && bash install.sh --tg-webhook 'URL' --tg-chatid 'ID' --server-name '名称' --server-tag '标签'
# ============================================================

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示帮助信息"
    echo "  --tg-webhook URL          设置 Telegram webhook URL (必填)"
    echo "  --tg-chatid ID            设置 Telegram chat ID (必填)"
    echo "  --server-name NAME        设置服务器名称 (可选, 默认取主机名)"
    echo "  --server-tag TAG          设置服务器标签 (可选, 默认按公网 IP 自动定位)"
    echo "示例:"
    echo "$0 --tg-webhook 'https://api.telegram.org/bot<token>/sendMessage' --tg-chatid '<chat_id>' --server-name 'my-server' --server-tag 'CN'"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --tg-webhook)
            TG_WEBHOOK="$2"
            shift 2
            ;;
        --tg-chatid)
            TG_CHATID="$2"
            shift 2
            ;;
        --server-name)
            SERVER_NAME="$2"
            shift 2
            ;;
        --server-tag)
            SERVER_TAG="$2"
            shift 2
            ;;
        *)
            echo "错误: 未知参数 $1"
            show_help
            exit 1
            ;;
    esac
done

# 非交互校验: 必须提供 tg-webhook 与 tg-chatid
if [ -z "$TG_WEBHOOK" ] || [ -z "$TG_CHATID" ]; then
    echo "错误: 缺少必填参数 --tg-webhook 和 --tg-chatid。"
    echo "    请提供完整的 Telegram token 与 chat id 后重试, 脚本将跳过所有交互提示直接安装。"
    echo ""
    show_help
    exit 1
fi

# 必须以 root 运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请使用 root 权限运行此脚本 (sudo bash install.sh ...)"
    exit 1
fi

# ---------- 系统准备: 安装 rsyslog / fail2ban 并初始化日志 ----------
echo "[1/5] 更新软件源并安装依赖 (rsyslog, fail2ban)..."
apt-get update -y
apt-get install -y rsyslog fail2ban

echo "[2/5] 初始化系统日志文件..."
touch /var/log/auth.log /var/log/secure /var/log/fail2ban.log

# 重启 rsyslog 以确保日志文件就绪
systemctl restart rsyslog || service rsyslog restart || true
mkdir -p /var/log

echo "[3/5] 获取服务器信息..."

# 获取服务器 IP 和位置信息 (仅用于 server-tag 缺省时)
get_server_location() {
    PUBLIC_IP=$(curl -s --max-time 10 https://api.ipify.org)
    LOCATION_INFO=$(curl -s --max-time 10 "http://ip-api.com/json/$PUBLIC_IP")
    COUNTRY=$(echo "$LOCATION_INFO" | grep -o '"country":"[^"]*' | cut -d'"' -f4)
    CITY=$(echo "$LOCATION_INFO" | grep -o '"city":"[^"]*' | cut -d'"' -f4)

    if [ ! -z "$CITY" ] && [ ! -z "$COUNTRY" ]; then
        echo "$COUNTRY-$CITY"
    elif [ ! -z "$COUNTRY" ]; then
        echo "$COUNTRY"
    else
        echo "$PUBLIC_IP"
    fi
}

DEFAULT_SERVER_NAME=$(hostname)
DEFAULT_SERVER_TAG=$(get_server_location)

# 非交互: 未传入名称/标签时使用默认值, 不向用户提问
SERVER_NAME=${SERVER_NAME:-$DEFAULT_SERVER_NAME}
SERVER_TAG=${SERVER_TAG:-$DEFAULT_SERVER_TAG}

# ---------- 安装程序 ----------
SERVICE_NAME="loginfopush.service"
SERVICE_DIR="/etc/systemd/system"
INSTALL_DIR="/opt/loginfopush"
CONFIG_DIR="$INSTALL_DIR/config"

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "错误: 不支持的系统架构: $arch"
            exit 1
            ;;
    esac
}

ARCH=$(detect_arch)
echo "检测到系统架构: $ARCH"

# 二进制下载地址 (jiam9069 release)
VERSION="v0.0.6"
EXECUTABLE_URL="https://github.com/jiam9069/loginfopush/releases/download/$VERSION/loginfopush-linux-$VERSION-$ARCH"

echo "[4/5] 下载并部署程序..."

# 删除已存在的目录
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

# 下载可执行文件
if ! curl -L "$EXECUTABLE_URL" -o "$INSTALL_DIR/loginfopush" --silent --retry 3 -f; then
    echo "错误: 程序文件下载失败: $EXECUTABLE_URL"
    echo "    请确认仓库中已发布 $VERSION 版本 (包含 amd64 与 arm64 二进制)。"
    exit 1
fi

if [ ! -s "$INSTALL_DIR/loginfopush" ]; then
    echo "错误: 程序文件下载不完整"
    exit 1
fi

chmod +x "$INSTALL_DIR/loginfopush"

# TODO: 下载失败会残留目录标记, 这里再补一次删除以便重装干净
rm -f "$INSTALL_DIR/loginfopush.lock"

# 生成 telegram-only 配置文件
cat > "$CONFIG_DIR/config.json" <<EOF
{
  "server": {
    "name": "$SERVER_NAME",
    "tag": "$SERVER_TAG"
  },
  "notifiers": {
    "telegram": {
      "type": "telegram",
      "enabled": true,
      "config": {
        "webhook_url": "$TG_WEBHOOK",
        "chat_id": "$TG_CHATID"
      }
    }
  },
  "events": {
    "ban": {
      "type": "ban",
      "enabled": false,
      "title": "fail2ban",
      "template": "🚫 服务器: {{.Server.Name}} ({{.Server.Tag}})\nIP: {{.IP}} 已被封禁\n时间: {{.Time}}\n位置: {{.Location}}\n详情: {{.Details}}",
      "icon": "🚫",
      "notifiers": ["telegram"]
    },
    "login_failure": {
      "type": "fail",
      "enabled": false,
      "title": "fail2ban",
      "template": "⚠️ 服务器: {{.Server.Name}} ({{.Server.Tag}})\nIP: {{.IP}} 登录失败\n时间: {{.Time}}\n位置: {{.Location}}\n详情: {{.Details}}",
      "icon": "⚠️",
      "notifiers": ["telegram"]
    },
    "login_success": {
      "type": "success",
      "enabled": true,
      "title": "loginfopush",
      "template": "✅ 服务器: {{.Server.Name}} ({{.Server.Tag}})\nIP: {{.IP}} 登录成功\n时间: {{.Time}}\n位置: {{.Location}}\n详情: {{.Details}}",
      "icon": "✅",
      "notifiers": ["telegram"]
    }
  }
}
EOF

# 校验配置文件是否为合法 JSON
if ! python3 -c "import json,sys; json.load(open('$CONFIG_DIR/config.json'))" 2>/dev/null; then
    echo "警告: 配置文件 JSON 校验失败, 请检查 webhook 中是否包含特殊字符。"
fi

# ---------- 注册 systemd 服务 ----------
echo "[5/5] 注册并启动 systemd 服务..."

cat > "$SERVICE_DIR/$SERVICE_NAME" <<EOF
[Unit]
Description=loginfopush Service

[Service]
ExecStart=$INSTALL_DIR/loginfopush
Restart=always
User=root
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "loginfopush 服务已安装并启动成功。"
else
    echo "警告: 服务状态异常, 请运行 journalctl -u $SERVICE_NAME 查看日志。"
fi

echo ""
echo "======================================================"
echo "  安装完成"
echo "  服务器名称: $SERVER_NAME"
echo "  服务器标签: $SERVER_TAG"
echo "  Telegram 通知: 已启用"
echo "  配置目录: $CONFIG_DIR/config.json"
echo "  服务: systemctl status $SERVICE_NAME"
echo "  查看日志: journalctl -u $SERVICE_NAME -f"
echo "======================================================"