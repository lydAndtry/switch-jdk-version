# ============================================================
# JDK 路径一键切换脚本
# 支持：扫描已安装JDK、手动输入路径、自动更新系统PATH
# ============================================================

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
        if (Test-Path $root) {
            $dirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -imatch "^jdk" }
            foreach ($d in $dirs) {
                $binPath = Join-Path $d.FullName "bin"
                if (Test-Path (Join-Path $binPath "java.exe")) {
                    $found += $d.FullName
                }
            }
        }
    }
    return $found
}

# 精确判断：只匹配 JDK/JRE 的 bin 目录，不影响其他 PATH 条目
function Test-IsJdkEntry {
    param([string]$Entry)
    $e = $Entry.TrimEnd('\')
    return ($e -imatch '\\jdk[^\\]*\\bin$') -or
           ($e -imatch '\\jdk[^\\]*\\jre\\bin$') -or
           ($e -imatch '\\jre[^\\]*\\bin$')
}

function Update-SystemJdkPath {
    param([string]$NewJdkRoot)

    $newBin = Join-Path $NewJdkRoot "bin"
    $newJre = Join-Path $NewJdkRoot "jre\bin"

    # 只操作 Machine 级别 PATH，User PATH 完全不碰
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $parts       = $machinePath -split ";" | Where-Object { $_ -ne "" }

    # 找出旧 JDK 条目（精确匹配）
    $toRemove = $parts | Where-Object { Test-IsJdkEntry $_ }
    $cleaned  = $parts | Where-Object { -not (Test-IsJdkEntry $_) }

    if ($toRemove.Count -gt 0) {
        Write-Log "将移除以下旧 JDK 条目：" "WARN"
        $toRemove | ForEach-Object { Write-Log "  移除: $_" "WARN" }
    } else {
        Write-Log "PATH 中未发现旧 JDK 条目，直接追加新条目。" "INFO"
    }

    # 新条目插在最前面
    $newEntries = @($newBin)
    if (Test-Path $newJre) { $newEntries += $newJre }

    $finalParts     = $newEntries + $cleaned
    $newMachinePath = ($finalParts | Select-Object -Unique) -join ";"

    [Environment]::SetEnvironmentVariable("Path", $newMachinePath, "Machine")
    Write-Log "系统 PATH(Machine) 已更新，其他条目未改动。" "SUCCESS"

    # 会话 PATH = 新 Machine PATH + 原 User PATH（完整保留）
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath) {
        $env:Path = "$newMachinePath;$userPath"
    } else {
        $env:Path = $newMachinePath
    }
    Write-Log "当前会话 PATH 已同步 (Machine + User)。" "SUCCESS"

    return $newBin
}

# ════ 主流程 ════════════════════════════════════════════════
Clear-Host
Write-Separator
Write-Log "   JDK 路径切换工具  v1.1" "TITLE"
Write-Separator

# 1. 管理员权限检查
if (-not (Test-Admin)) {
    Write-Log "未检测到管理员权限！修改系统 PATH 需要管理员身份运行。" "ERROR"
    Write-Log "请关闭此窗口，右键脚本选择 [以管理员身份运行 PowerShell]。" "WARN"
    Read-Host "按 Enter 退出"
    exit 1
}
Write-Log "已检测到管理员权限" "SUCCESS"

# 2. 显示当前 JDK 相关路径
Write-Separator
Write-Log "当前系统 PATH 中的 Java 相关路径：" "INFO"
$currentJdkPaths = Get-CurrentJdkPaths
if ($currentJdkPaths.Count -eq 0) {
    Write-Log "  (未找到任何 JDK/JRE 路径)" "WARN"
} else {
    $currentJdkPaths | ForEach-Object { Write-Log "  -> $_" "INFO" }
}

# 3. 扫描常见安装目录
Write-Separator
Write-Log "正在扫描常见 JDK 安装位置..." "INFO"
$searchRoots = @(
    "C:\Program Files\Java",
    "C:\Program Files (x86)\Java",
    "D:\Java",
    "D:\ProgramFiles\Java",
    "E:\Java",
    "$env:USERPROFILE\.jdks"
)
$jdkList = Find-JdkInstallations -SearchRoots $searchRoots

if ($jdkList.Count -gt 0) {
    Write-Log "扫描到以下 JDK 版本：" "SUCCESS"
    for ($i = 0; $i -lt $jdkList.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $jdkList[$i]) -ForegroundColor White
    }
} else {
    Write-Log "未扫描到 JDK，请手动输入路径。" "WARN"
}

# 4. 用户选择
Write-Separator
Write-Host ""
if ($jdkList.Count -gt 0) {
    Write-Host "输入序号选择上方 JDK，或直接粘贴完整 JDK 根目录路径：" -ForegroundColor Yellow
} else {
    Write-Host "请输入完整 JDK 根目录路径（例如 D:\ProgramFiles\Java\jdk1.8.0_131）：" -ForegroundColor Yellow
}
$userInput = Read-Host ">>> "

$selectedJdk = ""
if ($userInput -match "^\d+$") {
    $idx = [int]$userInput - 1
    if ($idx -ge 0 -and $idx -lt $jdkList.Count) {
        $selectedJdk = $jdkList[$idx]
        Write-Log "已选择：$selectedJdk" "INFO"
    } else {
        Write-Log "序号无效，请重新运行脚本。" "ERROR"
        Read-Host "按 Enter 退出"
        exit 1
    }
} else {
    $selectedJdk = $userInput.Trim().Trim('"')
    Write-Log "手动输入路径：$selectedJdk" "INFO"
}

# 5. 路径校验
Write-Separator
Write-Log "正在校验 JDK 路径..." "INFO"

if (-not (Test-Path $selectedJdk)) {
    Write-Log "路径不存在：$selectedJdk" "ERROR"
    Read-Host "按 Enter 退出"
    exit 1
}
Write-Log "目录存在：$selectedJdk" "SUCCESS"

$javaBin = Join-Path $selectedJdk "bin\java.exe"
if (-not (Test-Path $javaBin)) {
    Write-Log "bin\java.exe 不存在，请确认输入的是 JDK 根目录。" "ERROR"
    Read-Host "按 Enter 退出"
    exit 1
}
Write-Log "java.exe 存在：$javaBin" "SUCCESS"

$javacBin = Join-Path $selectedJdk "bin\javac.exe"
if (Test-Path $javacBin) {
    Write-Log "javac.exe 存在，确认为完整 JDK。" "SUCCESS"
} else {
    Write-Log "未找到 javac.exe，可能是 JRE，继续设置..." "WARN"
}

# 6. 更新系统 PATH
Write-Separator
Write-Log "正在更新系统 PATH..." "INFO"
$newBinPath = Update-SystemJdkPath -NewJdkRoot $selectedJdk

# 7. 设置 JAVA_HOME
Write-Log "正在设置 JAVA_HOME..." "INFO"
$oldJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
if ($oldJavaHome) {
    Write-Log "原 JAVA_HOME：$oldJavaHome" "WARN"
}
[Environment]::SetEnvironmentVariable("JAVA_HOME", $selectedJdk, "Machine")
$env:JAVA_HOME = $selectedJdk
Write-Log "JAVA_HOME 已设置为：$selectedJdk" "SUCCESS"

# 8. 验证 java -version
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

# 9. 确认更新后的 PATH Java 条目
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
Read-Host "按 Enter 退出"