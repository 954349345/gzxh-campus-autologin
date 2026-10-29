#!/data/data/com.termux/files/usr/bin/sh
# =============================================================================
#  广州新华学院（东莞校区）校园网 自动登录脚本
#  适用：OpenWrt (BusyBox ash) / Android Termux / 任意 POSIX sh
#  认证系统：深信服 Sangfor AC 网页认证  /ac_portal/login.php
#  密码算法：RC4(明文密码, 密钥=13位毫秒时间戳)，输出小写十六进制
# -----------------------------------------------------------------------------
#  用法：
#    ./campus-login.sh status     查看当前是否已联网
#    ./campus-login.sh login      立即登录一次
#    ./campus-login.sh logout     注销
#    ./campus-login.sh urlgen     输出一条可直接访问的 GET 登录链接
#    ./campus-login.sh probe      诊断：打印重定向地址、门户地址、响应片段
#    ./campus-login.sh daemon     常驻守护（默认动作，供 init.d / boot 调用）
#  配置文件：同目录 campus-login.conf，或用 CAMPUS_CONF=/path/to/conf 指定
# =============================================================================

APPNAME="campus-login"
VERSION="1.0.0"

# ---------- 默认配置（可被 campus-login.conf 覆盖） --------------------------
# 认证门户主机名（学校域名）
PORTAL_HOST="${PORTAL_HOST:-dgauth.xhsysu.cn}"
# 登录接口路径
PORTAL_PATH="${PORTAL_PATH:-/ac_portal/login.php}"
# 门户协议（一般为 https，个别学校为 http）
PORTAL_SCHEME="${PORTAL_SCHEME:-https}"
# 账号 / 密码（请在 campus-login.conf 里填写，不要写死在这里）
USERNAME="${USERNAME:-}"
PASSWORD="${PASSWORD:-}"
# 联网检测地址（返回 204 表示已认证）
CHECK_URLS="${CHECK_URLS:-http://connect.rom.miui.com/generate_204 http://www.gstatic.com/generate_204 http://wifi.vivo.com.cn/generate_204}"
# 守护模式检测周期（秒）
INTERVAL="${INTERVAL:-60}"
# 加密方式：auto=自动尝试(推荐) / rc4 / plain
ENCRYPT="${ENCRYPT:-auto}"
# 单次请求超时（秒）
TIMEOUT="${TIMEOUT:-8}"
# 是否在守护模式下唤醒锁（Termux 用）
WAKE_LOCK="${WAKE_LOCK:-0}"

# ---------- 路径 -------------------------------------------------------------
SELF_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || SELF_DIR="."
if [ -z "${CAMPUS_CONF:-}" ]; then
    for _c in "$SELF_DIR/campus-login.conf" /etc/campus-login.conf "$HOME/.campus-login.conf"; do
        [ -f "$_c" ] && { CAMPUS_CONF="$_c"; break; }
    done
fi
CONF="${CAMPUS_CONF:-$SELF_DIR/campus-login.conf}"
LOG="${CAMPUS_LOG:-$SELF_DIR/campus-login.log}"
STATE="${CAMPUS_STATE:-$SELF_DIR/.campus-login.state}"

[ -f "$CONF" ] && . "$CONF"

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36"

TMPDIR_RUN="${TMPDIR:-/tmp}/campus-login.$$"
mkdir -p "$TMPDIR_RUN" 2>/dev/null || TMPDIR_RUN="$SELF_DIR/.tmp.$$"
mkdir -p "$TMPDIR_RUN" 2>/dev/null
TMP_BODY="$TMPDIR_RUN/body"
TMP_HDR="$TMPDIR_RUN/hdr"
TMP_JAR="$TMPDIR_RUN/cookie"

cleanup() { rm -rf "$TMPDIR_RUN" 2>/dev/null; }
on_signal() { cleanup; exit 143; }
trap cleanup EXIT
trap on_signal INT TERM

# ---------- 日志 -------------------------------------------------------------
log() {
    _lvl="$1"; shift
    _line="$(date '+%Y-%m-%d %H:%M:%S') [$_lvl] $*"
    printf '%s\n' "$_line"
    if [ -n "$LOG" ]; then
        printf '%s\n' "$_line" >> "$LOG" 2>/dev/null
        # 简单滚动：超过 300 行截断
        if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 300 ]; then
            tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
        fi
    fi
}

# ---------- RC4（与门户 JS 一致：key=时间戳字符串，输出小写 hex） --------------
rc4_hex() {
    RC4K="$1" RC4D="$2" LC_ALL=C awk '
    function bxor(a, b,   r, bit, x, y) {
        r = 0; bit = 1
        while (a > 0 || b > 0) {
            x = a % 2; y = b % 2
            if (x != y) r += bit
            a = int(a / 2); b = int(b / 2); bit *= 2
        }
        return r
    }
    function rc4(key, data,   S, i, j, t, kl, dl, out, n, k, c) {
        kl = length(key); dl = length(data)
        for (i = 0; i < 256; i++) S[i] = i
        j = 0
        for (i = 0; i < 256; i++) {
            j = (j + S[i] + ORD[substr(key, i % kl + 1, 1)]) % 256
            t = S[i]; S[i] = S[j]; S[j] = t
        }
        i = 0; j = 0; out = ""
        for (n = 1; n <= dl; n++) {
            i = (i + 1) % 256
            j = (j + S[i]) % 256
            t = S[i]; S[i] = S[j]; S[j] = t
            k = S[(S[i] + S[j]) % 256]
            c = bxor(ORD[substr(data, n, 1)], k)
            out = out sprintf("%02x", c)
        }
        return out
    }
    BEGIN {
        for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i
        printf "%s", rc4(ENVIRON["RC4K"], ENVIRON["RC4D"])
    }'
}

# ---------- URL 编码 ---------------------------------------------------------
urlenc() {
    S="$1" LC_ALL=C awk '
    BEGIN {
        for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i
        s = ENVIRON["S"]
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c ~ /[A-Za-z0-9._~-]/) printf "%s", c
            else printf "%%%02X", ORD[c]
        }
    }'
}

# ---------- HTTP -------------------------------------------------------------
http_get() { # url bodyfile hdrfile -> stdout: http_code
    curl -sS -k --noproxy '*' -m "$TIMEOUT" --connect-timeout 4 \
        -A "$UA" -o "$2" -D "$3" -w '%{http_code}' "$1" 2>/dev/null
}

# 从响应中提取门户（认证页）地址
extract_portal() {
    _body="$1"; _hdr="$2"
    _url=""
    if [ -f "$_hdr" ]; then
        _url=$(sed -n 's/^[Ll]ocation:[[:space:]]*//p' "$_hdr" | tr -d '\r' | head -n 1)
        case "$_url" in http*) : ;; *) _url="" ;; esac
    fi
    if [ -z "$_url" ] && [ -f "$_body" ]; then
        _url=$(tr -d '\r\n' < "$_body" |
               grep -oE "https?://[A-Za-z0-9._:/?=&%~+-]+" |
               grep -iE "ac_portal|login|auth|portal|wengine" | head -n 1)
    fi
    [ -z "$_url" ] && _url="$PORTAL_SCHEME://$PORTAL_HOST/"
    PORTAL_URL="$_url"
}

# 门户根地址 scheme://host[:port]
portal_base() {
    _b=$(printf '%s' "$PORTAL_URL" | sed -n 's#^\(https\{0,1\}://[^/]*\).*#\1#p')
    [ -z "$_b" ] && _b="$PORTAL_SCHEME://$PORTAL_HOST"
    printf '%s' "$_b"
}

# 检测是否已联网。返回 0=在线 1=需要认证 2=网络异常
detect_online() {
    PORTAL_URL=""
    for _u in $CHECK_URLS; do
        _code=$(http_get "$_u" "$TMP_BODY" "$TMP_HDR")
        case "$_code" in
            204) return 0 ;;
            2??)
                if [ -s "$TMP_BODY" ] && grep -qiE 'ac_portal|window\.location|http-equiv="?refresh|login\.html' "$TMP_BODY"; then
                    extract_portal "$TMP_BODY" "$TMP_HDR"; return 1
                fi
                return 0 ;;
            3??|4??)
                extract_portal "$TMP_BODY" "$TMP_HDR"; return 1 ;;
            ""|000)
                continue ;;
            *)
                extract_portal "$TMP_BODY" "$TMP_HDR"; return 1 ;;
        esac
    done
    return 2
}

# ---------- 登录 -------------------------------------------------------------
_state_enc() {
    [ -f "$STATE" ] && sed -n 's/^ENC=//p' "$STATE" 2>/dev/null | head -n 1
}
_save_enc() {
    printf 'ENC=%s\n' "$1" > "$STATE" 2>/dev/null
}

# 发一次登录请求，$1 = rc4|plain
_login_once() {
    _enc="$1"
    _ts=$(date +%s)000
    if [ "$_enc" = "plain" ]; then
        _pwd="$PASSWORD"
    else
        _pwd=$(rc4_hex "$_ts" "$PASSWORD")
    fi
    [ -z "$_pwd" ] && { printf 'ERR\trc4 计算失败'; return 1; }

    _base=$(portal_base)
    # 先访问认证页拿 Cookie（部分版本需要）
    if [ -n "$PORTAL_URL" ]; then
        curl -sS -k --noproxy '*' -m "$TIMEOUT" -c "$TMP_JAR" -o /dev/null "$PORTAL_URL" 2>/dev/null
    fi

    _resp=$(curl -sS -k --noproxy '*' -m 12 --connect-timeout 5 \
        -A "$UA" -b "$TMP_JAR" -c "$TMP_JAR" \
        -e "${PORTAL_URL:-$_base}" \
        --data "opr=pwdLogin" \
        --data-urlencode "userName=$USERNAME" \
        --data-urlencode "pwd=$_pwd" \
        --data "auth_tag=$_ts" \
        --data "rememberPwd=1" \
        "$_base$PORTAL_PATH" 2>&1)

    _flat=$(printf '%s' "$_resp" | tr -d ' \r\n\t')
    case "$_flat" in
        *'"success":true'*|*'"success":1'*|*'login_ok'*|*'登录成功'*|*'认证成功'*)
            printf 'OK\t%s' "$_flat"; return 0 ;;
    esac
    printf 'FAIL\t%s' "$_flat"
    return 1
}

do_login() {
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
        log "ERROR" "未配置账号或密码，请编辑 $CONF"
        return 2
    fi
    command -v curl >/dev/null 2>&1 || { log "ERROR" "缺少 curl"; return 2; }

    detect_online
    _st=$?
    if [ "$_st" -eq 0 ]; then
        log "INFO" "当前已在线，无需登录"
        return 0
    fi
    if [ "$_st" -eq 2 ]; then
        log "ERROR" "网络不可达（未连接校园网 / DNS 异常）"
        return 1
    fi
    log "INFO" "检测到未认证，门户：${PORTAL_URL:-$PORTAL_SCHEME://$PORTAL_HOST/}"

    _order="rc4"
    case "$ENCRYPT" in
        plain) _order="plain" ;;
        rc4)   _order="rc4" ;;
        *)
            _cached=$(_state_enc)
            if [ -n "$_cached" ]; then
                if [ "$_cached" = "plain" ]; then _order="plain rc4"; else _order="rc4 plain"; fi
            else
                _order="rc4 plain"
            fi ;;
    esac

    _ok=0; _last=""
    for _m in $_order; do
        _out=$(_login_once "$_m")
        case "$_out" in
            OK*)
                _save_enc "$_m"
                log "INFO" "认证成功（加密方式：$_m）"
                _ok=1; break ;;
            *)
                _msg=$(printf '%s' "$_out" | sed 's/.*"msg":"\([^"]*\)".*/\1/; s/^FAIL\t//')
                _last="$_msg"
                log "WARN" "登录失败（$_m）：${_msg:-无响应}"
                [ "$ENCRYPT" != "auto" ] && break
                # 只有明确是密码/参数错误才换另一种加密方式重试
                case "$_msg" in
                    *密码*|*password*|*账号*|*错误*|*失败*|*invalid*|*error*) : ;;
                    *) break ;;
                esac ;;
        esac
    done

    [ "$_ok" = "1" ] || return 1

    # 二次验证
    sleep 2
    if detect_online; then
        log "INFO" "联网验证通过"
        return 0
    fi
    log "WARN" "接口返回成功，但联网验证未通过（可能分配 IP 延迟）"
    return 0
}

do_logout() {
    _base=$(portal_base)
    _resp=$(curl -sS -k --noproxy '*' -m "$TIMEOUT" -A "$UA" \
        --data "opr=logout" --data-urlencode "userName=$USERNAME" \
        "$_base$PORTAL_PATH" 2>&1)
    log "INFO" "注销请求已发送：$(printf '%s' "$_resp" | tr -d '\r\n' | cut -c1-200)"
}

# 生成 GET 登录链接（给「URL 插件」用）
do_urlgen() {
    [ -z "$USERNAME" ] && { echo "错误：未配置用户名"; return 2; }
    _ts=$(date +%s)000
    case "$ENCRYPT" in
        plain) _pwd="$PASSWORD" ;;
        *)     _pwd=$(rc4_hex "$_ts" "$PASSWORD") ;;
    esac
    detect_online >/dev/null 2>&1
    _base=$(portal_base)
    printf '%s%s?opr=pwdLogin&userName=%s&pwd=%s&auth_tag=%s&rememberPwd=1\n' \
        "$_base" "$PORTAL_PATH" "$(urlenc "$USERNAME")" "$(urlenc "$_pwd")" "$_ts"
}

do_probe() {
    echo "== 版本 $VERSION  $(date)"
    echo "== 配置：$CONF"
    echo "== 账号：${USERNAME:-<未配置>}   加密：$ENCRYPT"
    for _u in $CHECK_URLS; do
        _code=$(http_get "$_u" "$TMP_BODY" "$TMP_HDR")
        echo "-- 检测 $_u => HTTP ${_code:-超时}"
        if [ -f "$TMP_HDR" ]; then
            sed -n 's/^[Ll]ocation:[[:space:]]*/   重定向: /p' "$TMP_HDR" | tr -d '\r' | head -n 2
        fi
        [ -s "$TMP_BODY" ] && echo "   内容: $(tr -d '\r\n' < "$TMP_BODY" | cut -c1-160)"
    done
    if detect_online; then echo "== 结论：已在线"; else echo "== 结论：未认证，门户=$PORTAL_URL"; fi
}

# ---------- 守护 -------------------------------------------------------------
do_daemon() {
    log "INFO" "守护模式启动 v$VERSION，周期 ${INTERVAL}s，配置 $CONF"
    if [ "$WAKE_LOCK" = "1" ] && command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock && log "INFO" "已获取 Termux 唤醒锁"
    fi
    _fail=0
    while :; do
        detect_online
        _st=$?
        if [ "$_st" -eq 2 ]; then
            log "WARN" "网络不可达（DNS/链路异常），${INTERVAL}s 后重试"
            sleep "$INTERVAL"
            continue
        fi
        if [ "$_st" -eq 0 ]; then
            [ "$_fail" -gt 0 ] && log "INFO" "网络已恢复在线"
            _fail=0
            sleep "$INTERVAL"
            continue
        fi
        if do_login; then
            _fail=0
            sleep "$INTERVAL"
            continue
        fi
        _fail=$((_fail + 1))
        if [ "$_fail" -ge 3 ]; then
            _wait=$((INTERVAL * 5)); [ "$_wait" -lt 300 ] && _wait=300
            log "WARN" "连续失败 ${_fail} 次（请核对账号密码），休眠 ${_wait}s 后再试"
            sleep "$_wait"
        else
            sleep "$INTERVAL"
        fi
    done
}

# ---------- 入口 -------------------------------------------------------------
case "${1:-daemon}" in
    login)   do_login ;;
    logout)  do_logout ;;
    status)
        if detect_online; then echo "ONLINE"; exit 0; else echo "OFFLINE ${PORTAL_URL}"; exit 1; fi ;;
    urlgen)  do_urlgen ;;
    probe)   do_probe ;;
    daemon|auto) do_daemon ;;
    -v|--version) echo "$APPNAME $VERSION" ;;
    *)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        echo "用法: $0 {login|logout|status|urlgen|probe|daemon}" ;;
esac
