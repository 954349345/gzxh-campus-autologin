#!/bin/sh
# =============================================================================
#  OpenWrt 一键安装：cp 本目录到路由器 /tmp/campus && cd /tmp/campus && sh install.sh
# =============================================================================

set -u
DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR"

[ -f campus-login.sh ] || { echo "错误：请在包含 campus-login.sh 的目录里运行"; exit 1; }
[ -f campus-login.conf.example ] || { echo "错误：缺少 campus-login.conf.example"; exit 1; }

echo "==> 安装主脚本到 /usr/bin/campus-login.sh"
cp campus-login.sh /usr/bin/campus-login.sh
chmod 755 /usr/bin/campus-login.sh

if [ ! -f /etc/campus-login.conf ]; then
    echo "==> 生成配置 /etc/campus-login.conf（请立即填写账号密码）"
    cp campus-login.conf.example /etc/campus-login.conf
else
    echo "==> 保留已有配置 /etc/campus-login.conf"
fi
chmod 600 /etc/campus-login.conf

echo "==> 安装开机服务 /etc/init.d/campus-login"
cp campus-login.init /etc/init.d/campus-login
chmod 755 /etc/init.d/campus-login
/etc/init.d/campus-login enable || echo "    提示：enable 失败（非 OpenWrt 环境可忽略），请手动执行 /etc/init.d/campus-login enable"

echo "==> 安装 WAN 上线触发 /etc/hotplug.d/iface/99-campus-login"
mkdir -p /etc/hotplug.d/iface
cp 99-campus-login /etc/hotplug.d/iface/99-campus-login
chmod 755 /etc/hotplug.d/iface/99-campus-login

echo "==> 安装 URL 触发接口 /www/cgi-bin/campus-login"
if [ -d /www/cgi-bin ]; then
    cp campus-login.cgi /www/cgi-bin/campus-login
    chmod 755 /www/cgi-bin/campus-login
else
    echo "    跳过（没有 /www/cgi-bin 目录）"
fi

echo
echo "安装完成。接下来："
echo "  1) 编辑配置： vi /etc/campus-login.conf"
echo "  2) 测试登录： /usr/bin/campus-login.sh login"
echo "  3) 查看状态： /usr/bin/campus-login.sh status"
echo "  4) 启动服务： /etc/init.d/campus-login start"
echo
echo "URL 插件里填： http://<路由器IP>/cgi-bin/campus-login"
