<#
账号资产盘点（本机）
只盘点账号的存在与元信息，不解密、不导出任何密码：
  1. 本机 Windows 用户账户
  2. Windows 凭据管理器里保存的目标与用户名（cmdkey 只显示目标/类型/用户名，不含密码）
  3. Chrome / Edge / Brave 浏览器里保存过的登录账号（只读 Login Data 的 origin_url 与 username_value）
  4. 常见聊天与办公客户端留下的账号目录线索
产物：out\account-audit-report.html 与 out\account-audit.json
#>

param(
    [string]$OutDir = (Join-Path $PSScriptRoot 'out'),
    [string]$SqliteExe = ''
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

function Section($name, $items, $note) {
    return [pscustomobject]@{ section = $name; note = $note; items = @($items) }
}

# ---------- 1. 本机 Windows 账户 ----------
$winUsers = @()
Get-LocalUser | ForEach-Object {
    $winUsers += [pscustomobject]@{
        account  = $_.Name
        enabled  = if ($_.Enabled) { '启用' } else { '禁用' }
        desc     = $_.Description
        source   = '本地账户'
    }
}
$currentUser = [pscustomobject]@{
    account = ($env:USERDOMAIN + '\' + $env:USERNAME)
    enabled = '当前会话'
    desc    = 'whoami: ' + ((whoami) -join ' ')
    source  = '当前登录'
}

# ---------- 2. 凭据管理器 ----------
$credItems = @()
$cmdkey = 'cmdkey.exe'
if (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\cmdkey.exe')) {
    $cmdkey = Join-Path $env:SystemRoot 'System32\cmdkey.exe'
}
$cmdkeyOut = (& $cmdkey /list | Out-String)
$blocks = $cmdkeyOut -split "(?m)^\s*$"
foreach ($b in $blocks) {
    $target = ([regex]::Match($b, '(?:目标|Target)\s*[:：]\s*(.+)')).Groups[1].Value.Trim()
    if (-not $target) { continue }
    $type = ([regex]::Match($b, '(?:类型|Type)\s*[:：]\s*(.+)')).Groups[1].Value.Trim()
    $user = ([regex]::Match($b, '(?:用户名|User)\s*[:：]\s*(.+)')).Groups[1].Value.Trim()
    $credItems += [pscustomobject]@{ account = $user; target = $target; type = $type }
}

# ---------- 3. 浏览器保存的登录账号 ----------
$loginRows = @()
$browserNotes = @()
$profilesRoots = @(
    @{ name = 'Chrome'; root = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') },
    @{ name = 'Edge'; root = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') },
    @{ name = 'Brave'; root = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data') }
)

$sqlite = $SqliteExe
if (-not $sqlite) {
    foreach ($c in @((Join-Path $PSScriptRoot 'sqlite3.exe'), (Join-Path $PSScriptRoot 'bin\sqlite3.exe'))) {
        if (Test-Path -LiteralPath $c) { $sqlite = $c; break }
    }
}
if (-not $sqlite) {
    $onPath = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
    if ($onPath) { $sqlite = $onPath.Source }
}

foreach ($br in $profilesRoots) {
    if (-not (Test-Path -LiteralPath $br.root)) { continue }
    $profiles = Get-ChildItem -LiteralPath $br.root -Directory | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile*' }
    foreach ($p in $profiles) {
        $db = Join-Path $p.FullName 'Login Data'
        if (-not (Test-Path -LiteralPath $db)) { continue }
        if (-not $sqlite) { $browserNotes += ($br.name + ' ' + $p.Name + '：缺少 sqlite3.exe，跳过'); continue }
        $tmp = Join-Path $OutDir ('_login_' + $br.name + '_' + $p.Name + '.db')
        Copy-Item -LiteralPath $db -Destination $tmp -Force
        $q = "select origin_url, username_value, case when last_used=0 then '' else datetime(last_used,'unixepoch','localtime') end from logins where blacklisted_by_user=0 order by origin_url;"
        $rows = & $sqlite $tmp $q
        if (($rows -join ' ') -match 'no such column') {
            # 旧版 Chromium 没有 last_used 列，退回只取站点与账号
            $q = "select origin_url, username_value, '' from logins where blacklisted_by_user=0 order by origin_url;"
            $rows = & $sqlite $tmp $q
        }
        Remove-Item -LiteralPath $tmp -Force
        foreach ($r in $rows) {
            if (-not $r -or $r -match '^(Error|no such)') { continue }
            $parts = $r -split '\|'
            if ($parts.Count -lt 2) { continue }
            $loginRows += [pscustomobject]@{
                account = $parts[1]
                target  = $parts[0]
                type    = $br.name + ' / ' + $p.Name + ' / 上次使用 ' + $parts[2]
            }
        }
    }
}

# ---------- 4. 客户端账号目录线索 ----------
$appItems = @()
$knownDirs = @(
    @{ name = '微信'; path = (Join-Path $env:USERPROFILE 'Documents\WeChat Files') },
    @{ name = '微信(新版)'; path = (Join-Path $env:USERPROFILE 'Documents\xwechat_files') },
    @{ name = 'QQ'; path = (Join-Path $env:APPDATA 'Tencent') },
    @{ name = '钉钉'; path = (Join-Path $env:APPDATA 'DingTalk') },
    @{ name = '飞书'; path = (Join-Path $env:APPDATA 'LarkShell') }
)
foreach ($k in $knownDirs) {
    if (-not (Test-Path -LiteralPath $k.path)) { continue }
    $subs = Get-ChildItem -LiteralPath $k.path -Directory | Where-Object { $_.Name -match '^(wxid_|o[0-9A-Za-z]{6,}|[0-9]{5,}|u_|c_|[A-Za-z0-9]{8,})' }
    foreach ($s in $subs) {
        $appItems += [pscustomobject]@{ account = $s.Name; target = $k.path; type = $k.name + ' / 最后修改 ' + $s.LastWriteTime.ToString('yyyy-MM-dd') }
    }
}

$sections = @(
    (Section '本机 Windows 账户' (@($winUsers) + @($currentUser)) '来自 Get-LocalUser 与 whoami'),
    (Section '凭据管理器保存的条目' $credItems '来自 cmdkey /list，只含目标/类型/用户名，不含密码'),
    (Section '浏览器保存的登录账号' $loginRows '来自 Login Data 的 origin_url 与 username_value，不含密码密文'),
    (Section '客户端账号目录' $appItems '按已知客户端的账号目录命名规则推断')
)

$result = [pscustomobject]@{
    generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    computer    = $env:COMPUTERNAME
    user        = $env:USERNAME
    sections    = $sections
    notes       = $browserNotes
}

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'account-audit.json') -Encoding UTF8

# ---------- HTML ----------
function Esc($s) {
    return ([string]$s).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append('<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><title>账号资产盘点</title>')
[void]$sb.Append('<style>body{margin:0;padding:28px;background:#f4f5f7;font:15px/1.6 -apple-system,"Segoe UI","Microsoft YaHei",sans-serif;color:#222}h1{font-size:22px;margin:0 0 6px}.sub{color:#777;font-size:13px;margin-bottom:18px}.card{background:#fff;border-radius:10px;padding:14px 20px;margin-bottom:14px;box-shadow:0 1px 3px rgba(0,0,0,.07)}.card h2{font-size:16px;margin:0 0 4px}.note{color:#999;font-size:12px;margin-bottom:10px}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:6px 10px;border-bottom:1px solid #eee;vertical-align:top}th{color:#666;font-weight:600}td.k{white-space:nowrap;color:#1A6FD8}.empty{color:#999}</style></head><body>')
[void]$sb.Append('<h1>账号资产盘点</h1><div class="sub">')
[void]$sb.Append((Esc ($result.computer + ' / ' + $result.user + ' / ' + $result.generatedAt)))
[void]$sb.Append('</div>')
foreach ($sec in $sections) {
    [void]$sb.Append('<div class="card"><h2>' + (Esc $sec.section) + ' <span style="color:#d4380d;font-size:13px">' + $sec.items.Count + '</span></h2>')
    [void]$sb.Append('<div class="note">' + (Esc $sec.note) + '</div>')
    if ($sec.items.Count -eq 0) {
        [void]$sb.Append('<div class="empty">没有发现条目</div>')
    }
    else {
        [void]$sb.Append('<table><tr><th>账号</th><th>目标 / 来源</th><th>类型 / 状态</th></tr>')
        foreach ($it in $sec.items) {
            [void]$sb.Append('<tr><td class="k">' + (Esc $it.account) + '</td><td>' + (Esc $it.target) + '</td><td>' + (Esc $it.type) + '</td></tr>')
        }
        [void]$sb.Append('</table>')
    }
    [void]$sb.Append('</div>')
}
if ($browserNotes.Count -gt 0) {
    [void]$sb.Append('<div class="card"><h2>处理提示</h2><div class="note">' + (Esc ($browserNotes -join '；')) + '</div></div>')
}
[void]$sb.Append('<div class="sub" style="margin-top:22px">本报告只记录账号标识，不含任何密码或密码密文；文件留在本机 out 目录，请勿提交到公共仓库。</div></body></html>')

$htmlPath = Join-Path $OutDir 'account-audit-report.html'
$sb.ToString() | Set-Content -LiteralPath $htmlPath -Encoding UTF8

Write-Output ('账号 ' + ($credItems.Count + $loginRows.Count + $appItems.Count + $winUsers.Count) + ' 条，报告：' + $htmlPath)
