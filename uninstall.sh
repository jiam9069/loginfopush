#!/bin/bash
# ============================================================
#  loginfopush 一键卸载脚本 (Telegram-only 版)
#  仓库: https://github.com/jiam9069/loginfopush
#  站点: https://jiam9069.github.io/loginfopush/uninstall.sh
#  用法: curl -fsSL https://jiam9069.github.io/loginfopush/uninstall.sh -o uninstall.sh && bash uninstall.sh
# ============================================================

SERVICE_NAME="loginfopush"
INSTALL_DIR="/opt/loginfopush"

echo "============================================"
echo "  loginfopush 一键卸载脚本"
echo "  将移除: 服务、程序目录、systemd 配置"
echo "  保留:   /var/log/auth.log 等系统日志"
echo "============================================"

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请使用 root 权限运行此脚本 (sudo bash uninstall.sh)"
    exit 1
fi

# 检查是否安装
if [ ! -f "$INSTALL_DIR/loginfopush" ] && ! systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
    echo "loginfopush 未安装，无需卸载。"
    exit 0
fi

echo ""
echo "[1/3] 停止并移除服务..."

# 停止并禁用服务
if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
    systemctl stop ${SERVICE_NAME}.service 2>/dev/null || true
    systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
    echo "    服务已停止并禁用"
else
    echo "    未找到 systemd 服务，跳过"
fi

# 删除 systemd unit 文件
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    echo "    已删除 systemd unit 文件"
fi

# 重新加载 systemd
systemctl daemon-reload
systemctl reset-failed ${SERVICE_NAME}.service 2>/dev/null || true

echo ""
echo "[2/3] 删除程序目录..."

if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "    已删除 $INSTALL_DIR"
else
    echo "    目录不存在，跳过"
fi

echo ""
echo "[3/3] 卸载完成"

# 最终确认
if systemctl is-active ${SERVICE_NAME}.service >/dev/null 2>&1; then
    echo "警告: 服务仍在运行，请检查。"
else
    echo "✅ loginfopush 已成功卸载"
fi

echo ""
echo "提示: 安装时附加安装的 rsyslog / fail2ban 属系统组件，未一并移除。"
echo "如需一并移除 fail2ban: apt-get remove --purge fail2ban -y"
