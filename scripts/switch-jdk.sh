#!/usr/bin/env bash
# ============================================================
# JDK 路径一键切换脚本 (macOS / Linux)
# 支持：扫描已安装JDK、手动输入路径、自动更新 JAVA_HOME 和 PATH
# 支持：本地缓存自定义扫描根目录
# 版本：v1.4
# ============================================================

# 缓存目录：统一存放于 ~/.config/switch-jdk/
CACHE_DIR="$HOME/.config/switch-jdk"
CACHE_FILE="$CACHE_DIR/custom-roots.txt"

# ════ 颜色定义 ════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m'

log_info()    { echo -e "${CYAN}[$(date +%H:%M:%S)] [INFO]    $1${NC}"; }
log_success() { echo -e "${GREEN}[$(date +%H:%M:%S)] [SUCCESS] $1${NC}"; }
log_warn()    { echo -e "${YELLOW}[$(date +%H:%M:%S)] [WARN]    $1${NC}"; }
log_error()   { echo -e "${RED}[$(date +%H:%M:%S)] [ERROR]   $1${NC}"; }
log_title()   { echo -e "${MAGENTA}$1${NC}"; }
separator()   { echo -e "${GRAY}============================================================${NC}"; }

# ════ OS 检测 ════════════════════════════════════════════════
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "mac" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

OS=$(detect_os)

# ════ 路径工具函数 ══════════════════════════════════════════════

# 规范化路径：去除首尾空白、引号、尾随斜杠
normalize_path() {
    local p="$1"
    # 去除首尾空白
    p=$(echo "$p" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    # 去除首尾引号
    p="${p#\"}"; p="${p%\"}"
    p="${p#\'}"; p="${p%\'}"
    # 去除尾随斜杠（保留根路径 /）
    while [[ "$p" != "/" && ( "$p" == */ || "$p" == *\\ ) ]]; do
        p="${p%/}"
        p="${p%\\}"
    done
    echo "$p"
}

# 检查路径是否存在（双重检查：-d + ls）
test_path_safe() {
    local p="$1"
    [ -z "$p" ] && return 1
    [ -d "$p" ] && return 0
    # Fallback: 尝试 ls（有时能处理 -d 无法处理的情况）
    ls "$p" >/dev/null 2>&1 && return 0
    return 1
}

# ════ 默认扫描根目录（按 OS 区分）════════════════════════════
get_default_roots() {
    if [ "$OS" = "mac" ]; then
        echo "/Library/Java/JavaVirtualMachines"
        echo "$HOME/Library/Java/JavaVirtualMachines"
        echo "/usr/local/opt"
        echo "/opt/homebrew/opt"
        echo "$HOME/.sdkman/candidates/java"
        echo "$HOME/.jdks"
    else
        echo "/usr/lib/jvm"
        echo "/usr/local/java"
        echo "/usr/local/jdk"
        echo "/opt/java"
        echo "/opt/jdk"
        echo "$HOME/.sdkman/candidates/java"
        echo "$HOME/.jdks"
    fi
}

# ════ JDK 发现逻辑 ════════════════════════════════════════════

# 在单个根目录下查找 JDK，输出每个合法的 JDK Home 路径（每行一个）
_find_jdk_in_root() {
    local root="$1"
    [ -d "$root" ] || return

    if [ "$OS" = "mac" ]; then
        # macOS 标准 .jdk 包结构：xxx.jdk/Contents/Home
        for bundle in "$root"/*.jdk; do
            [ -d "$bundle" ] || continue
            local home="$bundle/Contents/Home"
            [ -x "$home/bin/java" ] && echo "$home"
        done
        # 扁平结构（SDKMAN、Homebrew opt、.jdks 等）：直接包含 bin/java
        for dir in "$root"/*/; do
            dir="${dir%/}"
            [ -d "$dir" ] || continue
            [[ "$dir" == *.jdk ]] && continue   # 已在上面处理
            # Homebrew: opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
            if [ -d "$dir/libexec" ]; then
                for inner in "$dir/libexec"/*.jdk; do
                    local h="$inner/Contents/Home"
                    [ -x "$h/bin/java" ] && echo "$h"
                done
            fi
            [ -x "$dir/bin/java" ] && echo "$dir"
        done
    else
        # Linux：子目录直接含 bin/java
        for dir in "$root"/*/; do
            dir="${dir%/}"
            [ -d "$dir" ] || continue
            [ -x "$dir/bin/java" ] && echo "$dir"
        done
        # 根目录本身也可能是 JDK（手动安装场景）
        [ -x "$root/bin/java" ] && echo "$root"
    fi
}

find_jdk_installations() {
    local -a roots=("$@")
    local tmp
    tmp=$(mktemp)
    for root in "${roots[@]}"; do
        _find_jdk_in_root "$root" >> "$tmp"
    done
    # 去重排序后输出
    sort -u "$tmp"
    rm -f "$tmp"
}

# macOS 使用系统 java_home 工具补充扫描
_macos_java_home_list() {
    command -v /usr/libexec/java_home &>/dev/null || return
    /usr/libexec/java_home -V 2>&1 | grep -E '^\s+[0-9]' | awk '{print $NF}'
}

# ════ 缓存读写 ════════════════════════════════════════════════
read_cached_roots() {
    [ -f "$CACHE_FILE" ] || return
    while IFS= read -r line; do
        [[ -n "$line" && "$line" != \#* ]] && normalize_path "$line"
    done < "$CACHE_FILE"
}

save_cached_roots() {
    mkdir -p "$CACHE_DIR"
    # 规范化所有路径后再保存
    local normalized=()
    local p
    for p in "$@"; do
        p=$(normalize_path "$p")
        [ -n "$p" ] && normalized+=("$p")
    done
    # 去重
    printf '%s\n' "${normalized[@]}" | awk '!seen[$0]++' > "$CACHE_FILE"
    log_success "已保存到：$CACHE_FILE"
}

get_all_search_roots() {
    {
        get_default_roots
        read_cached_roots
    } | awk '!seen[$0]++'
}

# ════ PATH / JAVA_HOME 更新逻辑 ══════════════════════════════

# 写入系统级配置（需要 sudo）
_write_system_profile() {
    local content="$1"
    local target="/etc/profile.d/switch-jdk.sh"

    if sudo -n true 2>/dev/null || sudo true 2>/dev/null; then
        echo -e "$content" | sudo tee "$target" > /dev/null
        sudo chmod 644 "$target"
        log_success "系统配置已写入：$target"
    else
        log_warn "sudo 授权失败，跳过系统级配置，仅更新用户配置文件。"
    fi
}

# 更新用户 Shell 配置文件，替换 switch-jdk 托管块
_update_user_profile() {
    local content="$1"
    local pfile="$2"
    local begin_mark="# switch-jdk: managed block - do not edit"
    local end_mark="# switch-jdk: end"

    # 若文件不存在则创建
    [ -f "$pfile" ] || touch "$pfile"

    # 删除旧托管块
    local tmp
    tmp=$(mktemp)
    awk "
        /$begin_mark/ { skip=1 }
        !skip { print }
        /$end_mark/ { skip=0 }
    " "$pfile" > "$tmp" && mv "$tmp" "$pfile"

    # 追加新块
    {
        echo ""
        echo -e "$content"
    } >> "$pfile"

    log_success "用户配置已更新：$pfile"
}

update_system_jdk_path() {
    local new_jdk_root="$1"
    local new_bin="$new_jdk_root/bin"

    if [ ! -d "$new_bin" ]; then
        log_error "bin 目录不存在：$new_bin"
        return 1
    fi

    local block
    block="# switch-jdk: managed block - do not edit
export JAVA_HOME=\"$new_jdk_root\"
export PATH=\"\$JAVA_HOME/bin:\$PATH\"
# switch-jdk: end"

    # 系统级（/etc/profile.d/，对所有用户生效）
    _write_system_profile "$block"

    # 用户级：根据当前 Shell 选择合适的配置文件
    local shell_name
    shell_name=$(basename "${SHELL:-bash}")
    case "$shell_name" in
        zsh)
            _update_user_profile "$block" "$HOME/.zshrc"
            ;;
        bash)
            _update_user_profile "$block" "$HOME/.bashrc"
            # macOS bash 还需更新 .bash_profile
            [ "$OS" = "mac" ] && _update_user_profile "$block" "$HOME/.bash_profile"
            ;;
        *)
            _update_user_profile "$block" "$HOME/.profile"
            ;;
    esac

    # 立即在当前会话生效
    export JAVA_HOME="$new_jdk_root"
    export PATH="$new_bin:$PATH"
    log_success "当前会话 JAVA_HOME 和 PATH 已立即生效。"

    echo "$new_bin"
}

# ════ 菜单1：管理扫描根目录 ══════════════════════════════════
show_manage_roots_menu() {
    while true; do
        clear
        separator
        log_title "   管理扫描根目录"
        separator

        local -a cached=()
        while IFS= read -r line; do
            [ -n "$line" ] && cached+=("$line")
        done < <(read_cached_roots)

        echo ""
        echo -e "${GRAY}  [内置默认路径]（只读）${NC}"
        while IFS= read -r r; do
            echo -e "${GRAY}    $r${NC}"
        done < <(get_default_roots)

        echo ""
        echo -e "  [自定义缓存路径]  缓存文件：${GRAY}$CACHE_FILE${NC}"
        if [ ${#cached[@]} -eq 0 ]; then
            echo -e "${GRAY}    (暂无自定义路径)${NC}"
        else
            for i in "${!cached[@]}"; do
                local exists_flag=""
                test_path_safe "${cached[$i]}" || exists_flag=" ${RED}[路径不存在]${NC}"
                echo -e "    [$((i+1))] ${cached[$i]}${exists_flag}"
            done
        fi

        echo ""
        separator
        echo -e "  ${GREEN}[A] 添加新路径${NC}"
        echo -e "  ${YELLOW}[D] 删除已有路径${NC}"
        echo -e "  ${CYAN}[Q] 返回主菜单${NC}"
        separator
        echo ""
        read -rp "请输入操作: " action
        action=$(echo "$action" | tr '[:lower:]' '[:upper:]')

        case "$action" in
            A)
                echo ""
                echo -e "${YELLOW}请输入要添加的扫描根目录路径（如 /opt/java）。输入 Q 取消：${NC}"
                while true; do
                    read -rp ">>> " new_path
                    new_path=$(normalize_path "$new_path")

                    if [ -z "$new_path" ]; then
                        log_warn "输入为空，已取消。"
                        break
                    fi
                    if [ "$(echo "$new_path" | tr '[:lower:]' '[:upper:]')" = "Q" ]; then
                        log_info "已取消添加。"
                        break
                    fi
                    if printf '%s\n' "${cached[@]}" | grep -qx "$new_path"; then
                        log_warn "该路径已存在，无需重复添加。"
                        break
                    fi
                    if ! test_path_safe "$new_path"; then
                        log_error "路径不存在：$new_path，请重新输入。"
                        continue
                    fi

                    cached+=("$new_path")
                    save_cached_roots "${cached[@]}"
                    log_success "已添加：$new_path"
                    break
                done
                sleep 1
                ;;
            D)
                if [ ${#cached[@]} -eq 0 ]; then
                    log_warn "没有可删除的自定义路径。"
                    sleep 1
                else
                    echo ""
                    echo -e "${YELLOW}请输入要删除的路径序号（如 1）：${NC}"
                    read -rp ">>> " del_input
                    if [[ "$del_input" =~ ^[0-9]+$ ]]; then
                        local del_idx=$((del_input - 1))
                        if [ "$del_idx" -ge 0 ] && [ "$del_idx" -lt ${#cached[@]} ]; then
                            local removed="${cached[$del_idx]}"
                            unset 'cached[$del_idx]'
                            cached=("${cached[@]}")
                            save_cached_roots "${cached[@]}"
                            log_success "已删除：$removed"
                        else
                            log_error "序号无效。"
                        fi
                    else
                        log_error "输入无效，请输入数字序号。"
                    fi
                    sleep 1
                fi
                ;;
            Q) return ;;
            *)
                log_error "无效输入，请重新选择。"
                sleep 1
                ;;
        esac
    done
}

# ════ 菜单2：切换 JDK ════════════════════════════════════════
start_switch_jdk() {
    clear
    separator
    log_title "   JDK 路径切换工具  v1.4  [$OS]"
    separator

    separator
    log_info "当前 JAVA_HOME：${JAVA_HOME:-(未设置)}"
    if command -v java &>/dev/null; then
        log_info "当前 java 版本："
        java -version 2>&1 | while IFS= read -r line; do echo "    $line"; done
    else
        log_warn "(当前未配置 java 命令)"
    fi

    separator
    local -a all_roots=()
    while IFS= read -r line; do
        [ -n "$line" ] && all_roots+=("$line")
    done < <(get_all_search_roots)

    log_info "正在扫描以下根目录（共 ${#all_roots[@]} 个）..."
    for r in "${all_roots[@]}"; do
        local flag="N"
        [ -d "$r" ] && flag="Y"
        echo -e "${GRAY}    [$flag] $r${NC}"
    done
    echo ""

    local -a jdk_list=()
    while IFS= read -r line; do
        [ -n "$line" ] && jdk_list+=("$line")
    done < <(find_jdk_installations "${all_roots[@]}")

    # macOS：借助系统 java_home 工具补充（去重）
    if [ "$OS" = "mac" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            local dup=0
            for existing in "${jdk_list[@]}"; do
                [ "$existing" = "$line" ] && dup=1 && break
            done
            [ $dup -eq 0 ] && jdk_list+=("$line")
        done < <(_macos_java_home_list)
    fi

    if [ ${#jdk_list[@]} -gt 0 ]; then
        log_success "扫描到以下 JDK 版本："
        for i in "${!jdk_list[@]}"; do
            echo -e "  [${CYAN}$((i+1))${NC}] ${jdk_list[$i]}"
        done
    else
        log_warn "未扫描到 JDK，请手动输入路径。"
    fi

    separator
    echo ""
    if [ ${#jdk_list[@]} -gt 0 ]; then
        echo -e "${YELLOW}输入序号选择上方 JDK，或直接粘贴完整 JDK 根目录路径（输入 Q 返回）：${NC}"
    else
        echo -e "${YELLOW}请输入完整 JDK 根目录路径（例如 /usr/lib/jvm/java-17-openjdk-amd64）（输入 Q 返回）：${NC}"
    fi

    local selected_jdk=""
    while true; do
        read -rp ">>> " user_input
        user_input="$(echo "$user_input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        if [ -z "$user_input" ]; then
            log_error "输入为空，请重新输入。"
            continue
        fi
        if [ "$(echo "$user_input" | tr '[:lower:]' '[:upper:]')" = "Q" ]; then
            return
        fi

        if [[ "$user_input" =~ ^[0-9]+$ ]]; then
            local idx=$((user_input - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#jdk_list[@]} ]; then
                selected_jdk="${jdk_list[$idx]}"
                log_info "已选择：$selected_jdk"
            else
                log_error "序号无效，请重新输入。"
                continue
            fi
        else
            selected_jdk="${user_input//\"/}"
            selected_jdk="${selected_jdk#"${selected_jdk%%[![:space:]]*}"}"
            selected_jdk="${selected_jdk%"${selected_jdk##*[![:space:]]}"}"
            selected_jdk=$(normalize_path "$selected_jdk")
            log_info "手动输入路径：$selected_jdk"
        fi

        separator
        log_info "正在校验 JDK 路径..."

        if [ ! -d "$selected_jdk" ]; then
            log_error "路径不存在：$selected_jdk，请重新输入。"
            continue
        fi
        log_success "目录存在：$selected_jdk"

        if [ ! -x "$selected_jdk/bin/java" ]; then
            log_error "bin/java 不存在，请确认输入的是 JDK 根目录（不是 bin）。"
            continue
        fi
        log_success "java 可执行文件存在：$selected_jdk/bin/java"

        if [ -x "$selected_jdk/bin/javac" ]; then
            log_success "javac 存在，确认为完整 JDK。"
        else
            log_warn "未找到 javac，可能是 JRE，继续设置..."
        fi

        break
    done

    separator
    log_info "正在更新 JAVA_HOME 和系统 PATH..."
    update_system_jdk_path "$selected_jdk"

    separator
    log_info "正在验证，执行 java -version..."
    echo ""
    "$selected_jdk/bin/java" -version 2>&1 | while IFS= read -r line; do echo "  $line"; done
    echo ""
    log_success "java -version 执行成功！"

    separator
    log_success "JDK 切换完成！"
    log_info "新开终端将自动生效（已写入 Shell 配置文件）。"
    log_info "当前终端立即生效，已完成 export 设置。"
    case "$(basename "${SHELL:-bash}")" in
        zsh)  log_info "如需手动刷新：source ~/.zshrc" ;;
        bash) log_info "如需手动刷新：source ~/.bashrc" ;;
        *)    log_info "如需手动刷新：source ~/.profile" ;;
    esac
    separator
    echo ""
    read -rp "按 Enter 返回主菜单"
}

# ════ 主菜单 ══════════════════════════════════════════════════
main_menu() {
    while true; do
        clear
        separator
        log_title "   JDK 路径切换工具  v1.3  [$OS]"
        separator
        echo ""

        local cached_count=0
        while IFS= read -r line; do
            [ -n "$line" ] && ((cached_count++))
        done < <(read_cached_roots)

        local default_count
        default_count=$(get_default_roots | wc -l | tr -d ' ')

        echo -e "${GRAY}  扫描根目录：内置 $default_count 个 + 自定义 $cached_count 个 = 共 $((default_count + cached_count)) 个${NC}"
        echo ""
        echo -e "  ${GREEN}[1] 管理扫描根目录（添加 / 删除自定义路径）${NC}"
        echo -e "  ${CYAN}[2] 切换 JDK 版本${NC}"
        echo -e "  ${GRAY}[Q] 退出${NC}"
        echo ""
        separator
        echo ""
        read -rp "请选择操作: " choice
        choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')

        case "$choice" in
            1) show_manage_roots_menu ;;
            2) start_switch_jdk ;;
            Q) exit 0 ;;
            *)
                log_error "无效输入，请输入 1、2 或 Q。"
                sleep 1
                ;;
        esac
    done
}

main_menu
