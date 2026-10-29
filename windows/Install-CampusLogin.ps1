<#
.SYNOPSIS
    注册 / 卸载「校园网自动登录」计划任务（Windows）
.DESCRIPTION
    每 5 分钟 + 每次登录时静默执行一次检测，未认证就自动登录。
    不需要管理员权限；如果提示拒绝访问，请右键「以管理员身份运行」。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-CampusLogin.ps1
    powershell -ExecutionPolicy Bypass -File .\Install-CampusLogin.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$RunNow
)

$ErrorActionPreference = 'Stop'

$taskName = 'CampusNetLogin'
$dir      = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ps1      = Join-Path $dir 'CampusLogin.ps1'
$vbs      = Join-Path $dir 'Start-CampusLogin.vbs'
$cfg      = Join-Path $dir 'config.ini'

function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }

if ($Uninstall) {
    Write-Step "删除计划任务 $taskName"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host '已卸载（脚本文件与日志保留，可手动删除）' -ForegroundColor Green
    return
}

if (-not (Test-Path -LiteralPath $ps1)) { throw "找不到 CampusLogin.ps1（应与本脚本同目录）" }
if (-not (Test-Path -LiteralPath $vbs)) { throw "找不到 Start-CampusLogin.vbs（应与本脚本同目录）" }

if (-not (Test-Path -LiteralPath $cfg)) {
    Write-Step '生成 config.ini'
    Copy-Item (Join-Path $dir 'config.ini.example') $cfg
}

# 提醒填写密码
$content = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8
if ($content -match 'PASSWORD\s*=\s*""' -or $content -match '在这里填') {
    Write-Host ''
    Write-Host '注意：还没有填写密码！请用记事本打开：' -ForegroundColor Yellow
    Write-Host "      $cfg" -ForegroundColor Yellow
    Write-Host ''
}

Write-Step "注册计划任务 $taskName"
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//nologo "{0}"' -f $vbs)

$trigger = New-ScheduledTaskTrigger -AtLogOn
try {
    $once = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 5) `
        -RepetitionDuration ([TimeSpan]::MaxValue)
    $trigger.Repetition = $once.Repetition
} catch {
    Write-Host '    提示：无法设置 5 分钟重复，仅保留登录时触发' -ForegroundColor Yellow
}

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

try {
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal `
        -Description '校园网（深信服 AC 认证）自动登录' -Force | Out-Null
} catch {
    Write-Host "注册失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host '请右键本脚本 → 以管理员身份运行。' -ForegroundColor Yellow
    exit 1
}

Write-Host ''
Write-Host "完成。任务名：$taskName（开机登录后自动运行，每 5 分钟检查一次）" -ForegroundColor Green
Write-Host "日志：$env:LOCALAPPDATA\CampusLogin\campus-login.log"

if ($RunNow) {
    Write-Step '立即试运行'
    & wscript.exe ('//nologo "{0}"' -f $vbs)
    Start-Sleep -Seconds 3
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 -Action status
}
