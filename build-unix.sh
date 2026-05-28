#!/usr/bin/env bash
# ============================================================
# 打包脚本：为 macOS / Linux 生成可分发包
#
# 方式一（推荐）：使用 shc 将 shell 脚本编译为二进制可执行文件
#   - macOS:  brew install shc
#   - Ubuntu: sudo apt install shc
#   - CentOS: sudo yum install shc
#
# 方式二（兜底）：打包为 .tar.gz 压缩包，解压后直接运行
#
# 用法：bash build-unix.sh
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_FILE="$SCRIPT_DIR/switch-jdk.sh"
OUT_DIR="$SCRIPT_DIR/dist"
VERSION="1.3"

# 检测当前 OS
case "$(uname -s)" in
    Darwin) OS="mac" ;;
    Linux)  OS="linux" ;;
    *)      OS="unknown" ;;
esac

# ════ 颜色输出 ════════════════════════════════════════════════
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

step()  { echo ""; echo -e "${CYAN}>>> $1${NC}"; }
ok()    { echo -e "${GREEN}    [OK] $1${NC}"; }
warn()  { echo -e "${YELLOW}    [WARN] $1${NC}"; }
fail()  { echo -e "${RED}    [ERROR] $1${NC}"; exit 1; }

echo ""
echo -e "${GRAY}============================================================${NC}"
echo -e "  switch-jdk 打包工具  v${VERSION}  [$OS]"
echo -e "${GRAY}============================================================${NC}"

# ── 1. 检查源文件 ─────────────────────────────────────────────
step "检查源文件..."
[ -f "$SRC_FILE" ] || fail "找不到 $SRC_FILE，请确认与 build-unix.sh 在同一目录。"
ok "源文件存在：$SRC_FILE"

# ── 2. 准备输出目录 ───────────────────────────────────────────
step "准备输出目录..."
mkdir -p "$OUT_DIR"
ok "输出目录：$OUT_DIR"

# ── 3. 尝试使用 shc 编译为二进制 ─────────────────────────────
step "检查 shc 编译器..."

BIN_NAME="switch-jdk-${OS}"
BIN_OUT="$OUT_DIR/$BIN_NAME"

if command -v shc &>/dev/null; then
    ok "检测到 shc：$(command -v shc)"

    step "开始编译（shc）..."
    # shc 输出文件名规则：源文件名 + .x（二进制）和 .x.c（C 源码）
    TMP_BIN="${SRC_FILE}.x"
    TMP_C="${SRC_FILE}.x.c"

    shc -f "$SRC_FILE" -o "$TMP_BIN" -r

    # 移动到 dist/
    mv "$TMP_BIN" "$BIN_OUT"
    rm -f "$TMP_C"
    chmod +x "$BIN_OUT"

    SIZE=$(du -sh "$BIN_OUT" | awk '{print $1}')
    ok "编译成功：$BIN_OUT ($SIZE)"
    BUILT_BIN="$BIN_OUT"
else
    warn "未检测到 shc，跳过二进制编译。"
    if [ "$OS" = "mac" ]; then
        warn "可通过 'brew install shc' 安装后重新执行此脚本。"
    else
        warn "可通过 'sudo apt install shc' 或 'sudo yum install shc' 安装。"
    fi
    BUILT_BIN=""
fi

# ── 4. 打包为 tar.gz（通用分发包）────────────────────────────
step "打包 tar.gz 分发包..."

TARBALL_NAME="switch-jdk-${OS}-v${VERSION}.tar.gz"
TARBALL_OUT="$OUT_DIR/$TARBALL_NAME"

# 临时目录，放入打包内容
TMP_DIR=$(mktemp -d)
PACKAGE_DIR="$TMP_DIR/switch-jdk-v${VERSION}"
mkdir -p "$PACKAGE_DIR"

# 复制脚本并设置权限
cp "$SRC_FILE" "$PACKAGE_DIR/switch-jdk.sh"
chmod +x "$PACKAGE_DIR/switch-jdk.sh"

# 如果有编译好的二进制，也一起打包
if [ -n "$BUILT_BIN" ] && [ -f "$BUILT_BIN" ]; then
    cp "$BUILT_BIN" "$PACKAGE_DIR/$BIN_NAME"
fi

# 写入简单的 README
cat > "$PACKAGE_DIR/README.txt" << 'INNER_EOF'
switch-jdk - JDK 路径一键切换工具
===================================

【运行方式】

方式一：直接运行 Shell 脚本（推荐，无需依赖）
  bash switch-jdk.sh

方式二：运行编译后的二进制（如果包含 switch-jdk-mac / switch-jdk-linux）
  ./switch-jdk-mac      # macOS
  ./switch-jdk-linux    # Linux

【首次运行】
  脚本会自动：
    - 扫描系统中已安装的 JDK
    - 提示选择目标版本
    - 更新 JAVA_HOME 和 PATH（写入 Shell 配置文件）
    - 在当前终端立即生效

【生效说明】
  - 新开终端自动生效（已写入 ~/.zshrc / ~/.bashrc）
  - 当前终端：source ~/.zshrc 或 source ~/.bashrc

【缓存文件】
  自定义扫描根目录保存在：~/.config/switch-jdk/custom-roots.txt
INNER_EOF

# 打 tar.gz
tar -czf "$TARBALL_OUT" -C "$TMP_DIR" "switch-jdk-v${VERSION}"
rm -rf "$TMP_DIR"

SIZE=$(du -sh "$TARBALL_OUT" | awk '{print $1}')
ok "tar.gz 打包成功：$TARBALL_OUT ($SIZE)"

# ── 5. 汇总输出 ───────────────────────────────────────────────
echo ""
echo -e "${GRAY}============================================================${NC}"
echo -e "${GREEN}  打包完成！输出文件：${NC}"
if [ -n "$BUILT_BIN" ] && [ -f "$BUILT_BIN" ]; then
    echo -e "${GREEN}    二进制：$BUILT_BIN${NC}"
fi
echo -e "${GREEN}    压缩包：$TARBALL_OUT${NC}"
echo ""
echo -e "  使用方式："
echo -e "    bash switch-jdk.sh              # 直接运行脚本"
if [ -n "$BUILT_BIN" ] && [ -f "$BUILT_BIN" ]; then
    echo -e "    ./$BIN_NAME             # 运行编译后的二进制"
fi
echo -e "${GRAY}============================================================${NC}"
echo ""
