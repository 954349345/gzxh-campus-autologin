#!/bin/sh
# /www/cgi-bin/campus-login  —— 给「URL 插件 / 在线检测插件」调用的触发接口
#
# 安装：
#   cp campus-login.cgi /www/cgi-bin/campus-login && chmod +x /www/cgi-bin/campus-login
# 用法（在插件的「URL / 检测地址」里填）：
#   http://192.168.1.1/cgi-bin/campus-login           异步：立刻返回 triggered，后台去登录
#   http://192.168.1.1/cgi-bin/campus-login?sync=1    同步：等登录完成再返回 result=ok / fail
#
# 说明：uhttpd 的 CGI 目录默认是 /www/cgi-bin，端口即路由器管理端口（默认 80）。

CONF=/etc/campus-login.conf
BIN=/usr/bin/campus-login.sh
LOG=/var/log/campus-login.log

echo "Content-Type: text/plain; charset=utf-8"
echo "Cache-Control: no-store"
echo ""

if [ ! -x "$BIN" ]; then
    echo "result=error reason=script-missing"
    exit 0
fi

case "$QUERY_STRING" in
    *sync=1*)
        OUT=$(CAMPUS_CONF="$CONF" CAMPUS_LOG="$LOG" "$BIN" login 2>&1)
        if printf '%s' "$OUT" | grep -q '认证成功\|无需登录'; then
            echo "result=ok"
        else
            echo "result=fail"
            printf '%s\n' "$OUT" | tail -n 3
        fi
        ;;
    *)
        # 异步触发，避免插件超时
        ( CAMPUS_CONF="$CONF" CAMPUS_LOG="$LOG" "$BIN" login >/dev/null 2>&1 & ) 
        echo "result=triggered"
        ;;
esac
exit 0
