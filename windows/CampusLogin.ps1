<#
.SYNOPSIS
    广州新华学院（东莞校区）校园网自动登录 - Windows 版
.DESCRIPTION
    深信服 Sangfor AC 网页认证：POST /ac_portal/login.php
    密码 = RC4(明文, 密钥 = 13 位毫秒时间戳)，小写十六进制
    依赖：Windows 10/11 自带的 PowerShell 5.1，无需安装任何东西
.PARAMETER Action
    auto(默认) | login | logout | status | probe | urlgen | daemon
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\CampusLogin.ps1 -Action login
#>
[CmdletBinding()]
param(
    [ValidateSet('auto', 'login', 'logout', 'status', 'probe', 'urlgen', 'daemon')]
    [string]$Action = 'auto',

    [string]$ConfigPath,

    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$script:Version  = '1.0.0'
$script:AppName  = 'campus-login'
$script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36'

if (-not $ConfigPath) { $ConfigPath = Join-Path $script:ScriptDir 'config.ini' }
$script:ConfigPath = $ConfigPath

$script:DataRoot = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.local/share' }
$script:DataDir = Join-Path $script:DataRoot 'CampusLogin'
if (-not (Test-Path $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }
$script:LogFile   = Join-Path $script:DataDir 'campus-login.log'
$script:StateFile = Join-Path $script:DataDir 'state.txt'

# ------------------------------------------------------------------ 日志
function Write-Log {
    param([string]$Level, [string]$Message)
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if (-not $Quiet) { Write-Host $line }
    try {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        $fi = Get-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
        if ($fi -and $fi.Length -gt 512KB) {
            $tail = Get-Content -LiteralPath $script:LogFile -Tail 300 -ErrorAction SilentlyContinue
            Set-Content -LiteralPath $script:LogFile -Value $tail -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    } catch { }
}

# ------------------------------------------------------------------ 配置
function Import-Config {
    $cfg = [ordered]@{
        Username     = ''
        Password     = ''
        PortalHost   = 'dgauth.xhsysu.cn'
        PortalPath   = '/ac_portal/login.php'
        PortalScheme = 'https'
        Encrypt      = 'auto'
        Interval     = 60
        Timeout      = 8
        CheckUrls    = @(
            'http://connect.rom.miui.com/generate_204',
            'http://www.gstatic.com/generate_204',
            'http://wifi.vivo.com.cn/generate_204'
        )
    }

    if (Test-Path -LiteralPath $script:ConfigPath) {
        foreach ($raw in (Get-Content -LiteralPath $script:ConfigPath -Encoding UTF8)) {
            $t = $raw.Trim()
            if (-not $t) { continue }
            if ($t.StartsWith('#') -or $t.StartsWith(';')) { continue }
            $i = $t.IndexOf('=')
            if ($i -lt 1) { continue }
            $k = $t.Substring(0, $i).Trim().ToLower()
            $v = $t.Substring($i + 1).Trim()
            if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) {
                $v = $v.Substring(1, $v.Length - 2)
            }
            switch ($k) {
                'username'     { $cfg.Username = $v }
                'password'     { $cfg.Password = $v }
                'portalhost'   { $cfg.PortalHost = $v }
                'portalpath'   { $cfg.PortalPath = $v }
                'portalscheme' { $cfg.PortalScheme = $v }
                'encrypt'      { $cfg.Encrypt = $v.ToLower() }
                'interval'     { if ($v -match '^\d+$') { $cfg.Interval = [int]$v } }
                'timeout'      { if ($v -match '^\d+$') { $cfg.Timeout = [int]$v } }
                'checkurls'    { $cfg.CheckUrls = @($v -split '\s+' | Where-Object { $_ }) }
            }
        }
    }
    return $cfg
}

# ------------------------------------------------------------------ RC4
function Get-Rc4Hex {
    param([string]$Key, [string]$Data)

    $k = [System.Text.Encoding]::UTF8.GetBytes($Key)
    $d = [System.Text.Encoding]::UTF8.GetBytes($Data)
    if ($k.Length -eq 0 -or $d.Length -eq 0) { return '' }

    $S = New-Object 'int[]' 256
    for ($i = 0; $i -lt 256; $i++) { $S[$i] = $i }

    $j = 0
    for ($i = 0; $i -lt 256; $i++) {
        $j = ($j + $S[$i] + $k[$i % $k.Length]) -band 0xFF
        $t = $S[$i]; $S[$i] = $S[$j]; $S[$j] = $t
    }

    $i = 0; $j = 0
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $d) {
        $i = ($i + 1) -band 0xFF
        $j = ($j + $S[$i]) -band 0xFF
        $t = $S[$i]; $S[$i] = $S[$j]; $S[$j] = $t
        $kk = $S[($S[$i] + $S[$j]) -band 0xFF]
        [void]$sb.Append((($ch -bxor $kk)).ToString('x2'))
    }
    return $sb.ToString()
}

# ------------------------------------------------------------------ HTTP
function Read-ResponseText {
    param($Response)
    try {
        $stream = $Response.GetResponseStream()
        $ms = New-Object System.IO.MemoryStream
        $stream.CopyTo($ms)
        $bytes = $ms.ToArray()
        $ms.Dispose(); $stream.Dispose()
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return ''
    }
}

function Invoke-Http {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Method = 'GET',
        [string]$Body = $null,
        [string]$Referer = $null
    )

    $res = [pscustomobject]@{ StatusCode = 0; Location = ''; Content = ''; Error = '' }

    try {
        $req = [System.Net.HttpWebRequest]::Create($Uri)
        $req.Method = $Method
        $req.Proxy = $null
        $req.AllowAutoRedirect = $false
        $req.KeepAlive = $false
        $req.Timeout = $script:Cfg.Timeout * 1000
        $req.ReadWriteTimeout = $script:Cfg.Timeout * 1000
        $req.UserAgent = $script:UA
        $req.Accept = '*/*'
        $req.Headers.Add('Accept-Language', 'zh-CN,zh;q=0.9')
        if ($Referer) { $req.Referer = $Referer }

        if ($Method -eq 'POST') {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $req.ContentType = 'application/x-www-form-urlencoded; charset=UTF-8'
            $req.ContentLength = $bytes.Length
            $s = $req.GetRequestStream()
            $s.Write($bytes, 0, $bytes.Length)
            $s.Flush(); $s.Close()
        }

        $resp = $req.GetResponse()
        $res.StatusCode = [int]$resp.StatusCode
        $res.Location = [string]$resp.Headers['Location']
        $res.Content = Read-ResponseText $resp
        $resp.Close()
    } catch [System.Net.WebException] {
        $we = $_.Exception
        if ($we.Response) {
            try {
                $res.StatusCode = [int]$we.Response.StatusCode
                $res.Location = [string]$we.Response.Headers['Location']
                $res.Content = Read-ResponseText $we.Response
                $we.Response.Close()
            } catch { }
        } else {
            $res.Error = $we.Message
        }
    } catch {
        $res.Error = $_.Exception.Message
    }
    return $res
}

# ------------------------------------------------------------------ 门户探测
function Get-PortalBase {
    param([string]$Url)
    if ($Url -and $Url -match '^(https?://[^/]+)') { return $matches[1] }
    return ('{0}://{1}' -f $script:Cfg.PortalScheme, $script:Cfg.PortalHost)
}

function Test-OnlineState {
    $script:PortalUrl = ''

    foreach ($u in $script:Cfg.CheckUrls) {
        $r = Invoke-Http -Uri $u -Method GET
        if ($r.StatusCode -eq 204) { return 'online' }
        if ($r.StatusCode -eq 0) { continue }

        $loc = $r.Location
        if (-not $loc) {
            $m = [regex]::Match($r.Content, 'https?://[^\s"''<>]+')
            if ($m.Success) { $loc = $m.Value }
        }

        if ($r.StatusCode -ge 300 -and $r.StatusCode -lt 400) {
            $script:PortalUrl = $loc
            return 'offline'
        }
        if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) {
            if ($r.Content -match 'ac_portal|window\.location|http-equiv\s*=\s*"?refresh|login\.html') {
                $script:PortalUrl = $loc
                return 'offline'
            }
            return 'online'
        }
        $script:PortalUrl = $loc
        return 'offline'
    }
    return 'unknown'
}

# ------------------------------------------------------------------ 登录
function Get-SavedEncrypt {
    if (Test-Path -LiteralPath $script:StateFile) {
        $t = (Get-Content -LiteralPath $script:StateFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($t -match 'ENC=(\w+)') { return $matches[1] }
    }
    return ''
}

function Save-Encrypt {
    param([string]$Mode)
    try { Set-Content -LiteralPath $script:StateFile -Value "ENC=$Mode" -Encoding ASCII } catch { }
}

function Invoke-LoginOnce {
    param([ValidateSet('rc4', 'plain')][string]$Mode)

    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    if ($Mode -eq 'plain') {
        $pwd = $script:Cfg.Password
    } else {
        $pwd = Get-Rc4Hex -Key $ts -Data $script:Cfg.Password
    }
    if (-not $pwd) { return [pscustomobject]@{ Ok = $false; Message = 'RC4 计算失败'; Body = '' } }

    $base = Get-PortalBase $script:PortalUrl
    $uri = $base + $script:Cfg.PortalPath

    $referer = if ($script:PortalUrl) { $script:PortalUrl } else { ($base + '/') }

    $body = 'opr=pwdLogin&userName={0}&pwd={1}&auth_tag={2}&rememberPwd=1' -f `
        [Uri]::EscapeDataString($script:Cfg.Username),
        [Uri]::EscapeDataString($pwd),
        $ts

    $r = Invoke-Http -Uri $uri -Method POST -Body $body -Referer $referer
    $flat = ($r.Content -replace '\s', '')

    if ($flat -match '"success":(true|1)' -or $flat -match 'login_ok' -or $r.Content -match '认证成功|登录成功') {
        return [pscustomobject]@{ Ok = $true; Message = 'success'; Body = $r.Content }
    }

    $msg = ''
    if ($r.Content -match '"msg"\s*:\s*"([^"]*)"') { $msg = $matches[1] }
    if (-not $msg) { $msg = $r.Error }
    if (-not $msg) { $msg = ($r.Content -replace '\s+', ' ').Substring(0, [Math]::Min(150, $r.Content.Length)) }
    return [pscustomobject]@{ Ok = $false; Message = $msg; Body = $r.Content }
}

function Invoke-Login {
    if (-not $script:Cfg.Username -or -not $script:Cfg.Password) {
        Write-Log 'ERROR' "未配置账号或密码，请编辑 $script:ConfigPath"
        return $false
    }

    $state = Test-OnlineState
    if ($state -eq 'online') { Write-Log 'INFO' '当前已在线，无需登录'; return $true }
    if ($state -eq 'unknown') { Write-Log 'WARN' '网络不可达（未连接 Wi-Fi/断网）'; return $false }

    $portal = if ($script:PortalUrl) { $script:PortalUrl } else { (Get-PortalBase '') + '/' }
    Write-Log 'INFO' "检测到未认证，门户：$portal"

    $order = @('rc4')
    switch ($script:Cfg.Encrypt) {
        'plain' { $order = @('plain') }
        'rc4'   { $order = @('rc4') }
        default {
            $cached = Get-SavedEncrypt
            if ($cached) {
                $other = if ($cached -eq 'rc4') { 'plain' } else { 'rc4' }
                $order = @($cached, $other)
            } else { $order = @('rc4', 'plain') }
        }
    }

    $ok = $false
    foreach ($mode in $order) {
        $res = Invoke-LoginOnce -Mode $mode
        if ($res.Ok) {
            Save-Encrypt $mode
            Write-Log 'INFO' "认证成功（加密方式：$mode）"
            $ok = $true
            break
        }
        Write-Log 'WARN' "登录失败（$mode）：$($res.Message)"
        if ($script:Cfg.Encrypt -ne 'auto') { break }
        if ($res.Message -notmatch '密码|password|账号|错误|失败|invalid|error') { break }
    }

    if (-not $ok) { return $false }

    Start-Sleep -Seconds 2
    if ((Test-OnlineState) -eq 'online') {
        Write-Log 'INFO' '联网验证通过'
    } else {
        Write-Log 'WARN' '接口返回成功，但联网验证未通过（可能分配 IP 延迟）'
    }
    return $true
}

# ------------------------------------------------------------------ 其他动作
function Invoke-Logout {
    $base = Get-PortalBase $script:PortalUrl
    $body = 'opr=logout&userName={0}' -f [Uri]::EscapeDataString($script:Cfg.Username)
    $r = Invoke-Http -Uri ($base + $script:Cfg.PortalPath) -Method POST -Body $body
    $msg = ($r.Content -replace '\s+', ' ')
    Write-Log 'INFO' "注销请求已发送：$msg"
}

function Show-Probe {
    Write-Host "== $script:AppName $script:Version  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "== 配置：$script:ConfigPath"
    Write-Host "== 账号：$(if ($script:Cfg.Username) { $script:Cfg.Username } else { '<未配置>' })   加密：$($script:Cfg.Encrypt)"
    foreach ($u in $script:Cfg.CheckUrls) {
        $r = Invoke-Http -Uri $u -Method GET
        $code = if ($r.StatusCode) { $r.StatusCode } else { '超时/' + $r.Error }
        Write-Host "-- 检测 $u => HTTP $code"
        if ($r.Location) { Write-Host "   重定向: $($r.Location)" }
        if ($r.Content) { Write-Host ("   内容: " + ($r.Content -replace '\s+', ' ').Substring(0, [Math]::Min(160, $r.Content.Length))) }
    }
    $st = Test-OnlineState
    $port = if ($script:PortalUrl) { $script:PortalUrl } else { '<未知>' }
    Write-Host "== 结论：$st  门户=$port"
}

function Show-UrlGen {
    if (-not $script:Cfg.Username) { Write-Host '错误：未配置用户名'; return }
    [void](Test-OnlineState)
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    $pwd = if ($script:Cfg.Encrypt -eq 'plain') { $script:Cfg.Password } else { Get-Rc4Hex -Key $ts -Data $script:Cfg.Password }
    $base = Get-PortalBase $script:PortalUrl
    $url = '{0}{1}?opr=pwdLogin&userName={2}&pwd={3}&auth_tag={4}&rememberPwd=1' -f `
        $base, $script:Cfg.PortalPath,
        [Uri]::EscapeDataString($script:Cfg.Username),
        [Uri]::EscapeDataString($pwd), $ts
    Write-Host $url
}

function Invoke-DaemonLoop {
    Write-Log 'INFO' "守护模式启动 v$script:Version，周期 $($script:Cfg.Interval)s"
    $fail = 0
    while ($true) {
        $state = Test-OnlineState
        if ($state -eq 'online') {
            if ($fail -gt 0) { Write-Log 'INFO' '网络已恢复在线' }
            $fail = 0
            Start-Sleep -Seconds $script:Cfg.Interval
            continue
        }
        if ($state -eq 'unknown') {
            Start-Sleep -Seconds $script:Cfg.Interval
            continue
        }
        if (Invoke-Login) {
            $fail = 0
            Start-Sleep -Seconds $script:Cfg.Interval
            continue
        }
        $fail++
        if ($fail -ge 3) {
            $wait = [Math]::Max(300, $script:Cfg.Interval * 5)
            Write-Log 'WARN' "连续失败 $fail 次（请核对账号密码），休眠 ${wait}s 后再试"
            Start-Sleep -Seconds $wait
        } else {
            Start-Sleep -Seconds $script:Cfg.Interval
        }
    }
}

# ------------------------------------------------------------------ 主体
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
} catch { }
try {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [System.Net.ServicePointManager]::Expect100Continue = $false
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 16
} catch { }

$script:Cfg = Import-Config
$script:PortalUrl = ''

switch ($Action) {
    'login'  { if (Invoke-Login) { exit 0 } else { exit 1 } }
    'logout' { Invoke-Logout }
    'status' {
        $s = Test-OnlineState
        if ($s -eq 'online') { Write-Host 'ONLINE'; exit 0 }
        else { Write-Host "OFFLINE $($script:PortalUrl)"; exit 1 }
    }
    'probe'  { Show-Probe }
    'urlgen' { Show-UrlGen }
    'daemon' { Invoke-DaemonLoop }
    default  {
        $s = Test-OnlineState
        if ($s -eq 'online') { if (-not $Quiet) { Write-Host '已在线' }; exit 0 }
        if (Invoke-Login) { exit 0 } else { exit 1 }
    }
}
