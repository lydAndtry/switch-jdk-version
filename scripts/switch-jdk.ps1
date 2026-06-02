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

# ════ 菜单1：管理扫描根目录 ═══════════════════════════════════

function Show-ManageRootsMenu {
    while ($true) {
        Clear-Host
        Write-Separator
        Write-Log "   管理扫描根目录" "TITLE"
        Write-Separator

        $cached = @(Read-CachedRoots)

        Write-Host ""
        Write-Host "  [内置默认路径]（只读）" -ForegroundColor DarkGray
        foreach ($r in $script:DefaultRoots) {
            Write-Host ("    $r") -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "  [自定义缓存路径]  缓存文件：$script:CacheFile" -ForegroundColor White
        if ($cached.Count -eq 0) {
            Write-Host "    (暂无自定义路径)" -ForegroundColor DarkGray
        } else {
            for ($i = 0; $i -lt $cached.Count; $i++) {
                $exists = if (Test-PathSafe $cached[$i]) { "" } else { " [路径不存在]" }
                Write-Host ("    [{0}] {1}{2}" -f ($i + 1), $cached[$i], $exists) -ForegroundColor White
            }
        }

        Write-Host ""
        Write-Separator
        Write-Host "  [A] 添加新路径" -ForegroundColor Green
        Write-Host "  [D] 删除已有路径" -ForegroundColor Yellow
        Write-Host "  [Q] 返回主菜单" -ForegroundColor Cyan
        Write-Separator
        Write-Host ""
        $action = (Read-Host "请输入操作").Trim().ToUpper()

        switch ($action) {
            "A" {
                Write-Host ""
                Write-Host "请输入要添加的扫描根目录路径（如 F:\Java）。输入 Q 取消：" -ForegroundColor Yellow
                while ($true) {
                    $rawInput = (Read-Host ">>> ").Trim()
                    if ($rawInput -eq "") {
                        Write-Log "输入为空，已取消。" "WARN"
                        break
                    }
                    if ($rawInput.Trim().ToUpper() -eq "Q") {
                        Write-Log "已取消添加。" "INFO"
                        break
                    }

                    $newPath = Normalize-Path $rawInput
                    if ($newPath -eq "") {
                        Write-Log "输入为空，已取消。" "WARN"
                        break
                    }
                    if (($cached -contains $newPath) -or ($script:DefaultRoots -contains $newPath)) {
                        Write-Log "该路径已存在，无需重复添加。" "WARN"
                        break
                    }
                    if (-not (Test-PathSafe $newPath)) {
                        Write-Log "路径不存在：$newPath，请重新输入。" "ERROR"
                        continue
                    }

                    $newList = [System.Collections.Generic.List[string]]@($cached)
                    $newList.Add($newPath)
                    Save-CachedRoots -Roots $newList.ToArray()
                    Write-Log "已添加：$newPath" "SUCCESS"
                    break
                }
                Start-Sleep -Seconds 1
            }
            "D" {
                if ($cached.Count -eq 0) {
                    Write-Log "没有可删除的自定义路径。" "WARN"
                    Start-Sleep -Seconds 1
                } else {
                    Write-Host ""
                    Write-Host "请输入要删除的路径序号（如 1）：" -ForegroundColor Yellow
                    $delInput = (Read-Host ">>> ").Trim()
                    if ($delInput -match "^\d+$") {
                        $delIdx = [int]$delInput - 1
                        if ($delIdx -ge 0 -and $delIdx -lt $cached.Count) {
                            $removed = $cached[$delIdx]
                            $newList = [System.Collections.Generic.List[string]]@($cached)
                            $newList.RemoveAt($delIdx)
                            Save-CachedRoots -Roots $newList.ToArray()
                            Write-Log "已删除：$removed" "SUCCESS"
                        } else {
                            Write-Log "序号无效。" "ERROR"
                        }
                    } else {
                        Write-Log "输入无效，请输入数字序号。" "ERROR"
                    }
                    Start-Sleep -Seconds 1
                }
            }
            "Q" { return }
            default {
                Write-Log "无效输入，请重新选择。" "ERROR"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ════ 菜单2：切换 JDK ═════════════════════════════════════════

function Start-SwitchJdk {
    Clear-Host
    Write-Separator
    Write-Log "   JDK 路径切换工具  v1.4" "TITLE"
    Write-Separator

    if (-not (Test-Admin)) {
        Write-Log "未检测到管理员权限！修改系统 PATH 需要管理员身份运行。" "ERROR"
        Write-Log "请关闭此窗口，右键脚本选择 [以管理员身份运行 PowerShell]。" "WARN"
        Read-Host "按 Enter 返回"
        return
    }
    Write-Log "已检测到管理员权限" "SUCCESS"

    Write-Separator
    Write-Log "当前系统 PATH 中的 Java 相关路径：" "INFO"
    $currentJdkPaths = Get-CurrentJdkPaths
    if ($currentJdkPaths.Count -eq 0) {
        Write-Log "  (未找到任何 JDK/JRE 路径)" "WARN"
    } else {
        $currentJdkPaths | ForEach-Object { Write-Log "  -> $_" "INFO" }
    }

    Write-Separator
    $allRoots = Get-AllSearchRoots
    Write-Log "正在扫描以下根目录（共 $($allRoots.Count) 个）..." "INFO"
    foreach ($r in $allRoots) {
        $flag = if (Test-PathSafe $r) { "Y" } else { "N" }
        Write-Host ("    [$flag] $r") -ForegroundColor DarkGray
    }
    Write-Host ""

    $jdkList = Find-JdkInstallations -SearchRoots $allRoots

    if ($jdkList.Count -gt 0) {
        Write-Log "扫描到以下 JDK 版本：" "SUCCESS"
        for ($i = 0; $i -lt $jdkList.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $jdkList[$i]) -ForegroundColor White
        }
    } else {
        Write-Log "未扫描到 JDK，请手动输入路径。" "WARN"
    }

    Write-Separator
    Write-Host ""
    if ($jdkList.Count -gt 0) {
        Write-Host "输入序号选择上方 JDK，或直接粘贴完整 JDK 根目录路径（输入 Q 返回）：" -ForegroundColor Yellow
    } else {
        Write-Host "请输入完整 JDK 根目录路径（例如 D:\ProgramFiles\Java\jdk1.8.0_131）（输入 Q 返回）：" -ForegroundColor Yellow
    }

    $selectedJdk = ""
    while ($true) {
        $userInput = (Read-Host ">>> ").Trim()
        if ($userInput -eq "") {
            Write-Log "输入为空，请重新输入。" "ERROR"
            continue
        }
        if ($userInput.ToUpper() -eq "Q") {
            return
        }

        if ($userInput -match "^\d+$") {
            $idx = [int]$userInput - 1
            if ($idx -ge 0 -and $idx -lt $jdkList.Count) {
                $selectedJdk = $jdkList[$idx]
                Write-Log "已选择：$selectedJdk" "INFO"
            } else {
                Write-Log "序号无效，请重新输入。" "ERROR"
                continue
            }
        } else {
            $selectedJdk = Normalize-Path $userInput
            Write-Log "手动输入路径：$selectedJdk" "INFO"
        }

        Write-Separator
        Write-Log "正在校验 JDK 路径..." "INFO"

        if (-not (Test-PathSafe $selectedJdk)) {
            Write-Log "路径不存在：$selectedJdk，请重新输入。" "ERROR"
            continue
        }
        Write-Log "目录存在：$selectedJdk" "SUCCESS"

        $javaBin = Join-Path $selectedJdk "bin\java.exe"
        if (-not (Test-Path -LiteralPath $javaBin)) {
            Write-Log "bin\java.exe 不存在，请确认输入的是 JDK 根目录（不是 bin）。" "ERROR"
            continue
        }
        Write-Log "java.exe 存在：$javaBin" "SUCCESS"

        $javacBin = Join-Path $selectedJdk "bin\javac.exe"
        if (Test-Path -LiteralPath $javacBin) {
            Write-Log "javac.exe 存在，确认为完整 JDK。" "SUCCESS"
        } else {
            Write-Log "未找到 javac.exe，可能是 JRE，继续设置..." "WARN"
        }

        break
    }

    Write-Separator
    Write-Log "正在更新系统 PATH..." "INFO"
    $newBinPath = Update-SystemJdkPath -NewJdkRoot $selectedJdk

    Write-Log "正在设置 JAVA_HOME..." "INFO"
    $oldJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if ($oldJavaHome) {
        Write-Log "原 JAVA_HOME：$oldJavaHome" "WARN"
    }
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $selectedJdk, "Machine")
    $env:JAVA_HOME = $selectedJdk
    Write-Log "JAVA_HOME 已设置为：$selectedJdk" "SUCCESS"

    Write-Separator
    Write-Log "正在验证，执行 java -version..." "INFO"
    Write-Host ""
    try {
        $javaExe = Join-Path $selectedJdk "bin\java.exe"
        $output  = & $javaExe -version 2>&1
        $output | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
        Write-Host ""
        Write-Log "java -version 执行成功！" "SUCCESS"
    } catch {
        Write-Log "执行 java -version 时出错：$_" "ERROR"
    }

    Write-Separator
    Write-Log "更新后系统 PATH 中的 Java 相关路径：" "INFO"
    $updatedPaths = [Environment]::GetEnvironmentVariable("Path", "Machine") -split ";" |
        Where-Object { $_ -imatch 'jdk|jre' -and $_ -ne "" }
    if ($updatedPaths.Count -eq 0) {
        Write-Log "  (未找到 Java 路径，请检查)" "WARN"
    } else {
        $updatedPaths | ForEach-Object { Write-Log "  -> $_" "SUCCESS" }
    }

    Write-Separator
    Write-Log "JDK 切换完成！新开命令窗口将自动生效。" "SUCCESS"
    Write-Log "当前窗口已立即生效，无需重启。" "INFO"
    Write-Separator
    Write-Host ""
    Read-Host "按 Enter 返回主菜单"
}

# ════ 主菜单 ══════════════════════════════════════════════════

while ($true) {
    Clear-Host
    Write-Separator
    Write-Log "   JDK 路径切换工具  v1.3" "TITLE"
    Write-Separator
    Write-Host ""

    $cached = @(Read-CachedRoots)
    $totalRoots = $script:DefaultRoots.Count + $cached.Count
    Write-Host ("  扫描根目录：内置 {0} 个 + 自定义 {1} 个 = 共 {2} 个" -f `
        $script:DefaultRoots.Count, $cached.Count, $totalRoots) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1] 管理扫描根目录（添加 / 删除自定义路径）" -ForegroundColor Green
    Write-Host "  [2] 切换 JDK 版本" -ForegroundColor Cyan
    Write-Host "  [Q] 退出" -ForegroundColor DarkGray
    Write-Host ""
    Write-Separator
    Write-Host ""
    $choice = (Read-Host "请选择操作").Trim().ToUpper()

    switch ($choice) {
        "1" { Show-ManageRootsMenu }
        "2" { Start-SwitchJdk }
        "Q" { exit 0 }
        default {
            Write-Log "无效输入，请输入 1、2 或 Q。" "ERROR"
            Start-Sleep -Seconds 1
        }
    }
}