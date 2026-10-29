#!/bin/sh
# =============================================================================
#  Android (Termux) 一键安装：把本目录 push 到手机后执行 sh install-termux.sh
#  前提：已安装 Termux（F-Droid 版）和 Termux:Boot，并且打开过 Termux:Boot 一次
# =============================================================================

set -u
DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || DIR="."
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BIN_DIR="$HOME/bin"
CONF="$HOME/.campus-login.conf"

echo "==> 检查依赖"
if ! command -v curl >/dev/null 2>&1; then
    echo "    安装 curl ..."
    pkg install -y curl || { echo "安装 curl 失败，请手动执行 pkg install curl"; exit 1; }
fi
command -v awk >/dev/null 2>&1 || { echo "缺少 awk，请执行 pkg install gawk"; exit 1; }

echo "==> 安装脚本到 $BIN_DIR/campus-login.sh"
mkdir -p "$BIN_DIR"
cp "$DIR/campus-login.sh" "$BIN_DIR/campus-login.sh"
chmod 755 "$BIN_DIR/campus-login.sh"
command -v termux-fix-shebang >/dev/null 2>&1 && termux-fix-shebang "$BIN_DIR/campus-login.sh" >/dev/null 2>&1

if [ ! -f "$CONF" ]; then
    echo "==> 生成配置 $CONF"
    cp "$DIR/campus-login.conf.example" "$CONF"
else
    echo "==> 保留已有配置 $CONF"
fi
chmod 600 "$CONF"

echo "==> 安装开机自启（Termux:Boot）"
mkdir -p "$HOME/.termux/boot"
cat > "$HOME/.termux/boot/10-campus-login.sh" <<EOF
#!$PREFIX/bin/sh
# 由 install-termux.sh 生成：开机后静默启动守护进程
termux-wake-lock 2>/dev/null
CAMPUS_CONF="$CONF" nohup "$BIN_DIR/campus-login.sh" daemon >> "\$HOME/campus-login.boot.log" 2>&1 &
EOF
chmod 755 "$HOME/.termux/boot/10-campus-login.sh"

echo
echo "安装完成。接下来："
echo "  1) 编辑账号密码： nano $CONF"
echo "  2) 测试登录：     sh $BIN_DIR/campus-login.sh login"
echo "  3) 查看状态：     sh $BIN_DIR/campus-login.sh status"
echo "  4) 手工启动守护： CAMPUS_CONF=$CONF nohup sh $BIN_DIR/campus-login.sh daemon >/dev/null 2>&1 &"
echo
echo "开机自启需要安装 Termux:Boot 并打开它一次（否则重启后不会自动运行）。"
