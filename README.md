# 校园网自动登录 · 装在路由器上，全屋设备一起上网

深信服 Sangfor AC 网页认证的自动登录工具。**主角是 OpenWrt 版**：在路由器上跑一次，手机、电脑、平板、电视、Switch、音箱、摄像头全部直接联网，不用每台设备各装一遍、各登录一次。

> 适用于所有使用深信服 AC / `ac_portal/login.php` 的门户（含广州新华学院东莞校区）。
> 同时附带 Windows 与 Android 单设备版本，作为「路由器动不了」时的备用方案。

---

## 为什么主角是 OpenWrt 版

校园网认证是**按 IP 走的**：谁上网，谁就要认证。这意味着「每台设备装一个脚本」的方案，设备越多越麻烦，而且很多设备（电视、游戏机、智能家居）根本装不了脚本。

把认证放在路由器上，情况就完全不同：

| | 每台设备各装一份 | **路由器装一次** |
|---|---|---|
| 配置量 | N 台设备 × 各填一次账号密码 | 1 份配置 |
| 新增设备 | 重新装、重新登录 | 连上 WiFi 就能上网 |
| 电视 / Switch / 音箱 / 摄像头 | 装不了，永远登不上 | 过路由器，自动可用 |
| 掉线、IP 变化 | 每台设备各自卡住、各自恢复 | 路由器统一补登录 |
| 家人/室友的设备 | 得挨个帮忙装 | 什么都不用做 |
| 维护 | 改密码要改 N 处 | 改 1 处 |

一句话：**路由器版把「每台设备都要处理」变成「全屋只处理一次」**，这才是校园网自动登录的正确用法。Windows / Android 版本只在「路由器刷不了固件」「只用自己的笔记本」这类场景才需要。

---

## 30 秒看效果

```
装之前：连上 WiFi → 打开浏览器 → 等认证页跳出来 → 输账号密码 → 才能上网
        换个设备，以上流程再来一遍；电脑休眠唤醒，再来一遍

装之后：连上 WiFi → 直接上网
        新买的平板、客厅的电视、吃灰的 Switch，开机就能用
```

---

## 快速开始（OpenWrt）

**前提**：路由器能刷 OpenWrt / ImmortalWrt / iStoreOS 等（需带 `procd`、`curl`、`awk`，官方固件基本都自带），并且由它拨号或作为主路由。

### 1. 上传

```bash
scp -r openwrt root@192.168.1.1:/tmp/campus
```

### 2. 安装

```bash
ssh root@192.168.1.1
cd /tmp/campus
sh install.sh
```

装完会有这些文件：

| 路径 | 作用 |
|---|---|
| `/usr/bin/campus-login.sh` | 主脚本（检测 + 登录 + 守护） |
| `/etc/campus-login.conf` | 配置（权限 600，只有 root 能读） |
| `/etc/init.d/campus-login` | procd 开机服务，常驻守护 |
| `/etc/hotplug.d/iface/99-campus-login` | WAN 拨号成功时立刻登录一次 |
| `/www/cgi-bin/campus-login` | **HTTP 触发接口，给 URL 插件用** |

### 3. 填账号密码

```bash
vi /etc/campus-login.conf
```

```ini
USERNAME="你的学号"
PASSWORD="你的密码"
```

### 4. 先手动测通

```bash
/usr/bin/campus-login.sh login     # 看到「认证成功」「联网验证通过」就成了
/usr/bin/campus-login.sh status    # 输出 ONLINE
```

> 第一次一定先手动测通再开自启，避免密码填错后整晚重试。

### 5. 开机自启

```bash
/etc/init.d/campus-login enable
/etc/init.d/campus-login start
```

到这里就完事了。之后**全屋设备连上 WiFi 直接上网**，路由器自己维持认证：每 60 秒自检一次，掉线就补登录，拨号重连也会立刻触发一次。

---

## 接「URL 插件」

很多固件/插件只允许填一个网址（在线检测、URL 认证、定时任务、Watchcat 之类），这正是 OpenWrt 版的优势——**认证逻辑做成了一条 URL**。

```
http://192.168.1.1/cgi-bin/campus-login
```

- **默认异步**：立刻返回 `result=triggered`，后台去登录，插件不会因为等待而超时；
- **要结果**：加 `?sync=1`，登录完成后返回 `result=ok` / `result=fail`；
- 端口跟路由器管理页面一致（默认 80，改过就跟着改）。

如果插件支持执行命令/脚本（比 URL 更灵活），直接写：

```
/usr/bin/campus-login.sh login
```

### 三种触发方式可以叠加，互不冲突

| 方式 | 触发时机 | 安装情况 |
|---|---|---|
| `init.d` 服务 | 开机常驻，每 60 秒自检 | `install.sh` 已自动装好 |
| `hotplug` | WAN 拨号成功 / 重连 | 已自动装好 |
| cron | `*/2 * * * *` 定时兜底 | 可选，见下 |

```bash
echo '*/2 * * * * /usr/bin/campus-login.sh login >/dev/null 2>&1' >> /etc/crontabs/root
/etc/init.d/cron restart
```

谁先触发都行：脚本自带「已在线就跳过」，不会重复登录、不会刷密码。

---

## 它是怎么工作的

学校的认证页是**深信服 AC**（页面里 `wengine`、`ac_portal` 就是这个厂商的标志）。点「登录」时浏览器实际发出的请求是：

```http
POST /ac_portal/login.php HTTP/1.1
Host: dgauth.xhsysu.cn
Content-Type: application/x-www-form-urlencoded

opr=pwdLogin&userName=账号&pwd=8554a893831318fc&auth_tag=1709788455684&rememberPwd=1
```

| 参数 | 含义 |
|---|---|
| `opr` | 操作，`pwdLogin`=登录，`logout`=注销 |
| `userName` | 学号 |
| `pwd` | **RC4 加密后的密码**（十六进制小写） |
| `auth_tag` | 13 位毫秒时间戳，同时作为 RC4 的密钥 |
| `rememberPwd` | 1 |

`pwd = RC4(明文密码, key=auth_tag)`，所以每次登录的 `pwd` 都不同。
成功返回 `{"success":true,"msg":"认证成功"}`，失败返回 `{"success":false,"msg":"密码错误"}`。

脚本的循环就四步：**检测是否在线 → 不在线就算 RC4 → POST 上面这个请求 → 再检测一次确认**。

门户地址不是写死的：脚本从未认证时的 302 跳转里取 `ip` / `nasId`，**换校区、换 IP、换 NAS 都不用改配置**。

> 接口与加密方式在同厂商门户上通用，可对照这份公开抓包记录：
> [GD-WLAN 登录页面抓包及 curl 模拟方法](https://www.cnblogs.com/sendu2wfdx/p/18490028)

### 一行命令验证

在连着校园网、但还没认证的机器上：

```bash
sh campus-login.sh urlgen        # 直接吐出一条能登录的完整 URL
curl -k "<把上面那行粘进来>"      # 成功会返回 {"success":true,...}
```

---

## 单设备备用方案

路由器动不了的时候用。逻辑与 OpenWrt 版完全一致，只是把「守护」放在设备上。

### Windows

要求 Windows 10/11 自带的 PowerShell 5.1，**不装任何软件**。

```text
1. 把 windows\config.ini.example 复制一份改名为 config.ini，记事本打开填账号密码
   （运行 install.bat 也会自动生成这个文件）
2. 双击 windows\login-now.bat      测一次
3. 双击 windows\install.bat        注册计划任务
```

计划任务 `CampusNetLogin`：登录 Windows 时跑一次，之后每 5 分钟检查一次，静默无窗口。
卸载 `install.bat uninstall`；日志在 `%LOCALAPPDATA%\CampusLogin\campus-login.log`。

### Android

```bash
# 装 Termux 与 Termux:Boot（并打开 Termux:Boot 一次）
cd ~/storage/downloads/campus-net-login/android
sh install-termux.sh
nano ~/.campus-login.conf      # 填账号密码
sh ~/bin/campus-login.sh login
```

`install-termux.sh` 会写好开机自启 `~/.termux/boot/10-campus-login.sh`，连上校园 WiFi 后 60 秒内自动认证。

---

## 命令速查

Windows 用 `CampusLogin.ps1 -Action xxx`，其余平台用 `campus-login.sh xxx`：

| 命令 | 作用 |
|---|---|
| `login` | 立即登录一次 |
| `status` | 打印 `ONLINE` / `OFFLINE` |
| `logout` | 注销 |
| `probe` | 诊断：打印重定向地址、门户地址、响应片段 |
| `urlgen` | 输出一条可直接访问的 GET 登录链接 |
| `daemon` | 常驻守护（默认） |

---

## 排错

**Q1：提示「密码错误」但密码没错**
先跑 `probe` 看门户地址和响应。常见原因：
- 账号欠费 / 已被管理员踢下线；
- 学校模板没启用 RC4 → 配置里 `ENCRYPT` 改成 `plain`（默认 `auto` 会两种都试）；
- 密码含中文/特殊字符 → 临时改成纯英文数字再试。

**Q2：`probe` 显示门户路径不是 `/ac_portal/login.php`**
学校改过模板。电脑浏览器 F12 → Network → 点一次登录 → 找到那条 POST，
把路径填进 `PORTAL_PATH`，参数名对照请求体改。

**Q3：连着校园网但脚本说「网络不可达」**
未认证时 DNS 可能被劫持。把 `CHECK_URLS` 换成网关 IP 上的地址，或先手动打开一次认证页再跑脚本。

**Q4：会不会把账号刷锁？**
失败 3 次后休眠 5 分钟，不会死循环重试。但**第一次务必先 `login` 手动测通**再装自启。

**Q5：密码明文存配置文件安全吗？**
- OpenWrt：`/etc/campus-login.conf` 权限 600，只有 root 可读；
- Windows：`%LOCALAPPDATA%` 当前用户目录；
- Android：`~/.campus-login.conf` 权限 600，其他 App 读不到。

这是「自动登录」绕不开的取舍。**别把填好密码的配置文件提交到 Git。**

---

## 已验证 / 未验证

我搭了一个**行为一致的深信服门户模拟器**（同样的接口、同样的 RC4 规则）做端到端测试，覆盖：

- ✅ RC4 实现对上标准测试向量（`Key/Plaintext → bbf316e8d940af0ad3` 等）
- ✅ 三端登录成功、二次联网校验通过
- ✅ 服务端只收明文时自动回退（`auto` 模式）
- ✅ 密码错误不崩溃、不狂刷，返回明确原因
- ✅ 断线后守护进程自动重连，并缓存「哪种加密方式可用」
- ✅ `urlgen` 生成的链接服务端可直接接受（GET 方式）
- ✅ OpenWrt 安装脚本、配置自动发现、CGI 接口（异步/同步）实测可用

**没验证的**：真实校园门户的响应。第一次请手动跑 `login` 和 `probe`，报错就带上 `probe` 输出提 issue。

---

## 目录结构

```
campus-net-login/
├── README.md
├── campus-login.conf.example        # 配置模板（Android/OpenWrt 通用）
├── openwrt/                         # ← 主力方案
│   ├── campus-login.sh              # 主脚本（BusyBox ash 兼容）
│   ├── campus-login.init            # procd 服务
│   ├── 99-campus-login              # WAN 上线触发
│   ├── campus-login.cgi             # URL 插件接口
│   ├── campus-login.conf.example
│   └── install.sh                   # 一键安装
├── windows/
│   ├── CampusLogin.ps1
│   ├── Install-CampusLogin.ps1
│   ├── Start-CampusLogin.vbs
│   ├── config.ini.example          # 复制为 config.ini 后填密码
│   ├── install.bat
│   └── login-now.bat
└── android/
    ├── campus-login.sh              # 与 openwrt 版逻辑相同，仅 shebang 适配 Termux
    ├── install-termux.sh
    └── campus-login.conf.example
```

## 免责声明

仅供个人在自己的设备 / 路由器上简化认证流程，请遵守学校网络使用规定。账号密码由使用者自行填写和保管，本项目不上传、不转发任何凭据。
