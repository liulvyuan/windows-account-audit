# Windows 账号资产盘点

把“这台电脑上登录过哪些账号”一次列清楚，输出一份本地 HTML 报告。**只统计账号标识，不导出任何密码。**

## 它能查什么

| 来源 | 拿到什么 | 怎么拿 |
| --- | --- | --- |
| 本机 Windows 账户 | 用户名、启用状态、描述、当前会话 | `Get-LocalUser` + `whoami` |
| 凭据管理器 | 目标、类型、用户名 | `cmdkey /list`（本身就不输出密码） |
| 浏览器保存的登录 | 站点、账号、上次使用时间 | 复制 `Login Data` 后用 sqlite3 查 `origin_url` / `username_value` |
| 客户端账号目录 | 微信/QQ/钉钉/飞书 的账号标识 | 扫已知目录的账号命名规则 |

## 为什么没有密码

两类东西刻意没做：

- **凭据管理器的密码值**：需要 DPAPI 解密，且 `cmdkey` 本身不输出密码。
- **浏览器保存的密码列**（`password_value`）：那是密文，解密需要 DPAPI / ABE。把它导出成明文，本质上就是凭据窃取工具，这类东西不写也不发。

本项目定位是“账号资产台账”：知道自己注册过、登录过哪些账号，方便清理与对账。

## 快速开始

```powershell
# 直接跑
powershell -NoProfile -ExecutionPolicy Bypass -File .\account-audit.ps1

# 或者双击 run.bat
```

产物在 `out\`：

- `account-audit-report.html`：可直接双击打开的报告
- `account-audit.json`：结构化结果，方便再加工

浏览器那一段需要 `sqlite3.exe`。脚本会依次找：本目录 → `bin\sqlite3.exe` → PATH。没有就跳过浏览器那节，不会报错。Android platform-tools 里自带一个，可以直接拷过来。

## 参数

| 参数 | 说明 |
| --- | --- |
| `-OutDir` | 报告输出目录，默认 `out` |
| `-SqliteExe` | 指定 sqlite3.exe 路径 |

## 注意

- `out\` 已被 `.gitignore` 排除。报告里是你的真实账号，**不要提交到公共仓库**。
- 报告只记录账号标识，但账号名本身也是隐私，分享前自己脱敏。
- 只适合盘自己的机器。他人的机器上跑这个属于侵犯隐私。
- 兼容 Windows PowerShell 5.1 与 PowerShell 7。

## License

MIT，见 [LICENSE](LICENSE)。
