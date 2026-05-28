# ============================================================
# 打包脚本：将 switch-jdk.ps1 编译为 switch-jdk.exe
# 依赖：ps2exe 模块（首次运行会自动安装）
# 用法：右键 -> 以管理员身份运行 PowerShell，然后执行此脚本
# ============================================================

$ErrorActionPreference = "Stop"

# 解析脚本所在目录（$PSScriptRoot 在部分启动方式下为空，依次回退）
$ScriptDir = if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -ne "") {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    "C:\switch-jdk"
}

$SrcFile  = Join-Path $ScriptDir "switch-jdk.ps1"
$OutDir   = Join-Path $ScriptDir "dist"
$OutFile  = Join-Path $OutDir "switch-jdk.exe"
$IconFile = Join-Path $ScriptDir "icon.ico"

function Write-Step {
    param([string]$Msg)
    Write-Host ""
    Write-Host (">>> " + $Msg) -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Msg)
    Write-Host ("    [OK] " + $Msg) -ForegroundColor Green
}

function Write-Fail {
    param([string]$Msg)
    Write-Host ("    [ERROR] " + $Msg) -ForegroundColor Red
}

# 1. 检查源文件
Write-Step "检查源文件..."
if (-not (Test-Path $SrcFile)) {
    Write-Fail "找不到 $SrcFile，请确认脚本与 build.ps1 在同一目录。"
    exit 1
}
Write-Ok "源文件存在：$SrcFile"

# 2. 准备输出目录
Write-Step "准备输出目录..."
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
    Write-Ok "已创建目录：$OutDir"
} else {
    Write-Ok "输出目录已存在：$OutDir"
}

# 3. 检查并安装 ps2exe
Write-Step "检查 ps2exe 模块..."
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "    ps2exe 未安装，正在安装..." -ForegroundColor Yellow
    try {
        Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
        Write-Ok "ps2exe 安装成功。"
    } catch {
        Write-Fail "安装 ps2exe 失败：$_"
        Write-Host "    请手动执行：Install-Module ps2exe -Scope CurrentUser" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Ok "ps2exe 已安装。"
}

Import-Module ps2exe -ErrorAction Stop

# 4. 构建编译参数
Write-Step "开始编译..."

$buildArgs = @{
    inputFile    = $SrcFile
    outputFile   = $OutFile
    requireAdmin = $true
    noConsole    = $false
    title        = "JDK切换工具"
    description  = "一键扫描并切换系统 JDK 版本"
    product      = "switch-jdk"
    version      = "1.2.0"
}

if (Test-Path $IconFile) {
    $buildArgs["iconFile"] = $IconFile
    Write-Ok "检测到图标文件，将嵌入 EXE：$IconFile"
} else {
    Write-Host "    (未找到 icon.ico，跳过图标嵌入)" -ForegroundColor DarkGray
}

try {
    Invoke-PS2EXE @buildArgs
} catch {
    Write-Fail "编译失败：$_"
    exit 1
}

# 5. 验证输出
Write-Step "验证输出文件..."
if (Test-Path $OutFile) {
    $size = (Get-Item $OutFile).Length / 1KB
    Write-Ok ("编译成功！输出：$OutFile (" + ("{0:F1}" -f $size) + " KB)")
} else {
    Write-Fail "输出文件不存在，编译可能失败。"
    exit 1
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  打包完成：$OutFile" -ForegroundColor Green
Write-Host "  双击即可运行，无需额外配置执行策略。" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""
Read-Host "按 Enter 退出"