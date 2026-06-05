# ============================================================
# JDK 路径一键切换脚本
# 支持：扫描已安装JDK、手动输入路径、自动更新系统PATH
# 支持：本地缓存自定义扫描根目录
# ============================================================

# 缓存目录固定使用 AppData\Roaming，不受脚本启动方式影响
$script:CacheDir  = Join-Path ([Environment]::GetFolderPath('ApplicationData')) "switch-jdk"
$script:CacheFile = Join-Path $script:CacheDir "jdk-roots-cache.json"
$script:DefaultRoots = @(
    "C:\Program Files\Java",
    "C:\Program Files (x86)\Java",
    "D:\Java",
    "D:\ProgramFiles\Java",
    "E:\Java",
    "$env:USERPROFILE\.jdks"
)

# 自动检测版本号（从 package.json 读取，兼容 npm 全局安装和开发环境）
function Get-ScriptVersion {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    @(
        (Join-Path $scriptDir "..\package.json"),
        (Join-Path $scriptDir "package.json")
    ) | ForEach-Object {
        if (Test-Path $_) {
            try { return (Get-Content $_ -Raw | ConvertFrom-Json).version } catch {}
        }
    }
    return "unknown"
}
$script:Version = Get-ScriptVersion

# ════ 工具函数 ════════════════════════════════════════════════

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $time = Get-Date -Format "HH:mm:ss"
    switch ($Level) {
        "INFO"    { Write-Host "[$time] [INFO]    $Message" -ForegroundColor Cyan }
        "SUCCESS" { Write-Host "[$time] [SUCCESS] $Message" -ForegroundColor Green }
        "WARN"    { Write-Host "[$time] [WARN]    $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "[$time] [ERROR]   $Message" -ForegroundColor Red }
        "TITLE"   { Write-Host $Message -ForegroundColor Magenta }
    }
}

function Write-Separator {
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}

function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CurrentJdkPaths {
    $sysPaths = [Environment]::GetEnvironmentVariable("Path", "Machine") -split ";"
    return $sysPaths | Where-Object { $_ -imatch 'jdk|jre' -and $_ -ne "" }
}

function Find-JdkInstallations {
    param([string[]]$SearchRoots)
    $found = @()
    foreach ($root in $SearchRoots) {
        if (Test-PathSafe $root) {
            $dirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -imatch "^jdk" }
            foreach ($d in $dirs) {
                $binPath = Join-Path $d.FullName "bin"
                if (Test-PathSafe (Join-Path $binPath "java.exe")) {
                    $found += $d.FullName
                }
            }
        }
    }
    return $found
}

function Test-IsJdkEntry {
    param([string]$Entry)
    $e = $Entry.TrimEnd('\')
    return ($e -imatch '\\jdk[^\\]*\\bin$') -or
           ($e -imatch '\\jdk[^\\]*\\jre\\bin$') -or
           ($e -imatch '\\jre[^\\]*\\bin$')
}

# 规范化路径：去除首尾空白/引号/尾随反斜杠，解析为绝对路径
function Normalize-Path {
    param([string]$RawPath)
    if ([string]::IsNullOrWhiteSpace($RawPath)) { return "" }
    # 去除首尾空白、引号、尾随反斜杠
    $p = $RawPath.Trim().Trim('"').TrimEnd('\').TrimEnd('/')
    if ($p -eq "") { return "" }
    # 如果路径存在，解析为规范绝对路径；否则使用 GetFullPath
    try {
        if (Test-Path -LiteralPath $p) {
            return (Resolve-Path -LiteralPath $p).Path
        }
    } catch { }
    try {
        return [System.IO.Path]::GetFullPath($p)
    } catch {
        return $p
    }
}

# 检查路径是否存在（-LiteralPath 避免 [] 等被当作通配符；双重检查 Test-Path + .NET）
function Test-PathSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $p = [System.Environment]::ExpandEnvironmentVariables($Path.Trim())
    if (Test-Path -LiteralPath $p) { return $true }
    try { return [System.IO.Directory]::Exists($p) } catch { return $false }
}

function Update-SystemJdkPath {
    param([string]$NewJdkRoot)

    $newBin = Join-Path $NewJdkRoot "bin"
    $newJre = Join-Path $NewJdkRoot "jre\bin"

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $parts       = $machinePath -split ";" | Where-Object { $_ -ne "" }

    $toRemove = $parts | Where-Object { Test-IsJdkEntry $_ }
    $cleaned  = $parts | Where-Object { -not (Test-IsJdkEntry $_) }

    if ($toRemove.Count -gt 0) {
        Write-Log "将移除以下旧 JDK 条目：" "WARN"
        $toRemove | ForEach-Object { Write-Log "  移除: $_" "WARN" }
    } else {
        Write-Log "PATH 中未发现旧 JDK 条目，直接追加新条目。" "INFO"
    }

    $newEntries = @($newBin)
    if (Test-Path $newJre) { $newEntries += $newJre }

    $finalParts     = $newEntries + $cleaned
    $newMachinePath = ($finalParts | Select-Object -Unique) -join ";"

    [Environment]::SetEnvironmentVariable("Path", $newMachinePath, "Machine")
    Write-Log "系统 PATH(Machine) 已更新，其他条目未改动。" "SUCCESS"

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath) {
        $env:Path = "$newMachinePath;$userPath"
    } else {
        $env:Path = $newMachinePath
    }
    Write-Log "当前会话 PATH 已同步 (Machine + User)。" "SUCCESS"

    return $newBin
}

# ════ 缓存读写函数 ════════════════════════════════════════════

function Read-CachedRoots {
    if (Test-Path $script:CacheFile) {
        try {
            $json = [System.IO.File]::ReadAllText($script:CacheFile, [System.Text.Encoding]::UTF8)
            $obj  = $json | ConvertFrom-Json
            $raw  = $obj.customRoots
            if ($null -eq $raw) { return @() }
            # ConvertFrom-Json 仅一条时返回 string，多条时返回 array；@($raw) 统一为列表
            # 注意：不要用 `return ,$arr` 这种“包一层”的写法，否则会把 string[] 变成 object[]{string[]}，
            # 显示时会出现 System.String[] 之类的异常。
            $rawList = @($raw)
            $paths = @(
                $rawList |
                    ForEach-Object { Normalize-Path $_ } |
                    Where-Object { $_ -ne "" } |
                    # 过滤历史异常：曾被错误写入为 "System.String[]"（或其被 GetFullPath 拼成的绝对路径）
                    Where-Object { $_ -notmatch '(^|\\)System\.String\[\]$' }
            )

            # 若发现异常条目，自动清理缓存文件，避免 UI 再次显示脏数据
            if ($paths.Count -ne $rawList.Count) {
                Write-Log "检测到异常缓存项，已自动清理。" "WARN"
                Save-CachedRoots -Roots ([string[]]$paths)
            }
            return [string[]]$paths
        } catch {
            Write-Log "读取缓存失败：$_" "WARN"
        }
    }
    return @()
}

function Save-CachedRoots {
    param([string[]]$Roots)
    try {
        if (-not (Test-Path $script:CacheDir)) {
            New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
        }
        # 规范化所有路径后再保存，确保缓存格式一致
        $normalized = $Roots |
            ForEach-Object { Normalize-Path $_ } |
            Where-Object { $_ -ne "" } |
            Where-Object { $_ -notmatch '(^|\\)System\.String\[\]$' } |
            Select-Object -Unique
        $obj  = [ordered]@{ customRoots = @($normalized) }
        $json = $obj | ConvertTo-Json -Depth 3
        [System.IO.File]::WriteAllText($script:CacheFile, $json, [System.Text.Encoding]::UTF8)
        Write-Log "已保存到：$script:CacheFile" "SUCCESS"
    } catch {
        Write-Log "保存缓存失败：$_" "ERROR"
    }
}

function Get-AllSearchRoots {
    $cached = @(Read-CachedRoots)
    $all    = $script:DefaultRoots + $cached | Select-Object -Unique
    return [string[]]$all
}

# ════ CLI 命令：-list（列出所有 JDK 环境）═════════════════════
function Invoke-ListCommand {
    $allRoots = Get-AllSearchRoots
    $jdkList = Find-JdkInstallations -SearchRoots $allRoots

    Write-Host ""
    Write-Log "当前 JAVA_HOME：$($env:JAVA_HOME)" "INFO"
    Write-Host ""

    if ($jdkList.Count -gt 0) {
        Write-Log "扫描到 $($jdkList.Count) 个 JDK 环境：" "SUCCESS"
        Write-Host ""
        for ($i = 0; $i -lt $jdkList.Count; $i++) {
            $marker = if ($jdkList[$i] -eq $env:JAVA_HOME) { "*" } else { " " }
            Write-Host ("  $marker [{0}] {1}" -f ($i + 1), $jdkList[$i]) -ForegroundColor White
        }
        Write-Host ""
        Write-Host "  (* 表示当前使用的 JDK)" -ForegroundColor DarkGray
    } else {
        Write-Log "未扫描到 JDK 环境。" "WARN"
        Write-Host ""
        Write-Host "  请使用 switch-jdk -set <路径> 添加扫描根目录。" -ForegroundColor Green
    }
    Write-Host ""
}

# ════ CLI 命令：-set <路径>（添加扫描根目录）═══════════════════
function Invoke-SetCommand {
    param([string]$NewPath)

    if ([string]::IsNullOrWhiteSpace($NewPath)) {
        Write-Log "缺少路径参数。用法：switch-jdk -set <路径>" "ERROR"
        Write-Host ""
        exit 1
    }

    $normalized = Normalize-Path $NewPath

    if (-not (Test-PathSafe $normalized)) {
        Write-Log "路径不存在：$normalized" "ERROR"
        exit 1
    }

    $cached = @(Read-CachedRoots)

    if ($cached -contains $normalized -or $script:DefaultRoots -contains $normalized) {
        Write-Log "该路径已在缓存中，无需重复添加。" "WARN"
        exit 0
    }

    $newList = [System.Collections.Generic.List[string]]@($cached)
    $newList.Add($normalized)
    Save-CachedRoots -Roots $newList.ToArray()
    Write-Log "已添加扫描根目录：$normalized" "SUCCESS"
}

# ════ CLI 命令：-change（选择并切换 JDK）════════════════════════
function Invoke-ChangeCommand {
    if (-not (Test-Admin)) {
        Write-Log "未检测到管理员权限！修改系统 PATH 需要管理员身份运行。" "ERROR"
        Write-Log "请以管理员身份运行 PowerShell 后重试。" "WARN"
        exit 1
    }

    $allRoots = Get-AllSearchRoots

    Write-Host ""
    Write-Log "正在扫描 JDK 环境..." "INFO"

    $jdkList = Find-JdkInstallations -SearchRoots $allRoots

    if ($jdkList.Count -eq 0) {
        Write-Log "未扫描到 JDK 环境。" "WARN"
        Write-Host ""
        Write-Host "  请使用 switch-jdk -set <路径> 添加扫描根目录后重试。" -ForegroundColor Green
        exit 1
    }

    Write-Host ""
    Write-Log "当前 JAVA_HOME：$($env:JAVA_HOME)" "INFO"
    Write-Host ""

    Write-Log "扫描到以下 JDK 版本：" "SUCCESS"
    Write-Host ""
    for ($i = 0; $i -lt $jdkList.Count; $i++) {
        $marker = if ($jdkList[$i] -eq $env:JAVA_HOME) { "*" } else { " " }
        Write-Host ("  $marker [{0}] {1}" -f ($i + 1), $jdkList[$i]) -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  (* 表示当前使用的 JDK)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "请输入要切换的 JDK 序号（输入 Q 取消）：" -ForegroundColor Yellow

    while ($true) {
        $userInput = (Read-Host ">>> ").Trim()
        if ($userInput -eq "") {
            Write-Log "输入为空，请重新输入。" "ERROR"
            continue
        }
        if ($userInput.ToUpper() -eq "Q") {
            Write-Log "已取消。" "INFO"
            exit 0
        }

        if ($userInput -match "^\d+$") {
            $idx = [int]$userInput - 1
            if ($idx -ge 0 -and $idx -lt $jdkList.Count) {
                $selected = $jdkList[$idx]

                if (-not (Test-PathSafe $selected)) {
                    Write-Log "路径不存在：$selected" "ERROR"
                    exit 1
                }

                $javaBin = Join-Path $selected "bin\java.exe"
                if (-not (Test-Path -LiteralPath $javaBin)) {
                    Write-Log "bin\java.exe 不存在，请确认选择的是 JDK 根目录。" "ERROR"
                    exit 1
                }

                Write-Host ""
                Write-Separator
                Write-Log "正在切换 JDK 到：$selected" "INFO"

                $newBinPath = Update-SystemJdkPath -NewJdkRoot $selected

                $oldJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
                [Environment]::SetEnvironmentVariable("JAVA_HOME", $selected, "Machine")
                $env:JAVA_HOME = $selected
                Write-Log "JAVA_HOME 已设置为：$selected" "SUCCESS"

                Write-Host ""
                Write-Separator
                Write-Log "正在验证 java -version..." "INFO"
                Write-Host ""
                try {
                    $javaExe = Join-Path $selected "bin\java.exe"
                    & $javaExe -version 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
                    Write-Host ""
                    Write-Log "java -version 执行成功！" "SUCCESS"
                } catch {
                    Write-Log "执行 java -version 时出错：$_" "ERROR"
                }

                Write-Separator
                Write-Log "JDK 切换完成！新开命令窗口将自动生效。" "SUCCESS"
                Write-Log "当前窗口已立即生效，无需重启。" "INFO"
                exit 0
            } else {
                Write-Log "序号无效，请重新输入。" "ERROR"
            }
        } else {
            Write-Log "请输入数字序号。" "ERROR"
        }
    }
}

# ════ 帮助信息 ══════════════════════════════════════════════════
function Show-Help {
    Write-Host ""
    Write-Host "  switch-jdk v$script:Version — JDK 版本一键切换工具" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  用法:" -ForegroundColor Green
    Write-Host ""
    Write-Host "    switch-jdk -v                查看版本号"
    Write-Host "    switch-jdk -list             列出所有扫描到的 JDK 环境"
    Write-Host "    switch-jdk -set <路径>       添加自定义扫描根目录"
    Write-Host "    switch-jdk -change           列出所有 JDK 版本并选择切换"
    Write-Host ""
    Write-Host "  缓存文件：$script:CacheFile" -ForegroundColor DarkGray
    Write-Host ""
}

# ════ CLI 参数分发 ══════════════════════════════════════════════
$Command = if ($args.Count -gt 0) { $args[0] } else { "" }
$Value   = if ($args.Count -gt 1) { $args[1] } else { "" }

switch ($Command) {
    "-v" {
        Write-Host "v$script:Version"
    }
    "--version" {
        Write-Host "v$script:Version"
    }
    "-list" {
        Invoke-ListCommand
    }
    "-set" {
        Invoke-SetCommand -NewPath $Value
    }
    "-change" {
        Invoke-ChangeCommand
    }
    "" {
        Show-Help
    }
    default {
        Write-Host "未知参数: $Command"
        Write-Host ""
        Show-Help
        exit 1
    }
}