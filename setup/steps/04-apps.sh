# shellcheck shell=bash

setup_zsh() {
    section "Phase 6" "Zsh Shell"

    if is_done "setup_zsh"; then
        print_skip "Zsh setup (already done)"
        return
    fi

    echo ""
    echo -e "   ${WHITE}Zsh 配置位于 ~/.config/zsh，由 zsh 包 stow 部署${NC}"
    echo -e "   ${DIM}~/.zshenv 由 zshenv 包提供，安装器不再另行生成。${NC}"
    echo ""

    # 只问一次：装 Zsh 和设默认 shell 是同一件事，分成两次问没有意义
    if ! confirm "安装 Zsh 并设为默认 shell?"; then
        print_skip "Zsh installation (user declined)"
        mark_done "setup_zsh"
        return
    fi

    print_info "Installing Zsh..."
    if sudo pacman -S --needed --noconfirm zsh >> "$LOG_FILE" 2>&1; then
        print_ok "Zsh installed"
    else
        print_fail "Failed to install Zsh"
        return
    fi

    if [[ -f "$HOME/.config/zsh/.zshrc" ]]; then
        print_ok "Zsh configuration present"
    else
        print_warn "~/.config/zsh/.zshrc 缺失，检查 stow 是否成功"
    fi

    # ~/.zshenv 必须指向 ZDOTDIR
    if [[ -f "$HOME/.zshenv" ]]; then
        print_ok "~/.zshenv 已存在"
    else
        print_warn "~/.zshenv 缺失（zshenv 包未部署？）"
    fi

    # 默认 shell：不再单独询问，上面已经确认过
    local zsh_bin
    zsh_bin=$(command -v zsh || true)
    if [[ -n "$zsh_bin" ]]; then
        if [[ "$SHELL" != *"zsh"* ]]; then
            # 必须走 sudo：chsh 自己用 PAM 验密码，不吃 sudo 的时间戳缓存，
            # 直接裸调会在这里再弹一次 Password:
            if sudo chsh -s "$zsh_bin" "$USER"; then
                print_ok "Default shell changed to zsh (重新登录生效)"
            else
                print_warn "Failed to change shell"
            fi
        else
            print_ok "Zsh is already default"
        fi
    fi

    mark_done "setup_zsh"
    log "Zsh configured"
}

# ==============================================================================
# MPV：Anime4K 着色器
# ==============================================================================
# 着色器约 56 MB，官方只发在 git 仓库里（没有 release 包），进 dotfiles 仓库
# 会让每个 clone 的人白付这份体积，所以默认不随仓库分发、安装时下载。
#
# 落点 ~/.config/mpv/shaders/ —— 这个目录是 stow 软链指向仓库，所以文件会写进
# 仓库的 mpv/.config/mpv/shaders/，已在 .gitignore 里忽略。
#
# 装失败不是致命错误：mpv 照常播放，只有 input.conf 里的 Ctrl+1..6 会提示
# 找不到着色器文件。
setup_mpv_shaders() {
    section "Phase 6b" "MPV Anime4K Shaders"

    local dst="$HOME/.config/mpv/shaders"

    # 目录不存在说明 stow 没落地（mpv 包没装 / 用户 --no-stow），
    # 不 mark_done —— 下次重跑还要再试
    if [[ ! -d "$HOME/.config/mpv" ]]; then
        print_skip "~/.config/mpv 不存在（mpv 未部署，跳过）"
        return 0
    fi

    # input.conf 里 Ctrl+1..6 实际引用到的文件，缺任何一个那组模式就会报错
    local wanted=(
        Anime4K_Clamp_Highlights.glsl
        Anime4K_Restore_CNN_VL.glsl
        Anime4K_Upscale_CNN_x2_VL.glsl
        Anime4K_AutoDownscalePre_x2.glsl
        Anime4K_AutoDownscalePre_x4.glsl
        Anime4K_Upscale_CNN_x2_M.glsl
        Anime4K_Restore_CNN_M.glsl
        Anime4K_Restore_CNN_Soft_VL.glsl
        Anime4K_Restore_CNN_Soft_M.glsl
        Anime4K_Upscale_Denoise_CNN_x2_VL.glsl
    )

    # 幂等：全部到位就跳过
    local f missing_pre=()
    for f in "${wanted[@]}"; do
        [[ -f "$dst/$f" ]] || missing_pre+=("$f")
    done
    if (( ${#missing_pre[@]} == 0 )); then
        print_ok "Anime4K 着色器已就绪 (${#wanted[@]} 个文件)"
        MPV_SHADERS_OK=true
        mark_done "setup_mpv_shaders"
        return
    fi

    echo ""
    echo -e "   ${WHITE}Anime4K 是 mpv 的实时超分/降噪着色器${NC}"
    echo -e "   ${DIM}下载约 56 MB 到 ~/.config/mpv/shaders/；不装也能正常播放，只是 Ctrl+1..6 无效${NC}"
    echo ""

    # 拒绝就不记状态：下次重跑会再问一次。着色器可能被用户删掉，
    # 「记下拒绝」会让文件缺失后永远装不回来，而多问一次没有成本。
    if ! confirm "下载 Anime4K 着色器?"; then
        print_skip "Anime4K shaders (user declined)"
        return
    fi

    local tmp
    tmp=$(mktemp -d) || {
        print_fail "mktemp 失败"
        return
    }

    print_info "Cloning Anime4K..."
    if ! gh_clone "$ANIME4K_REPO" "$tmp/Anime4K"; then
        print_warn "Anime4K 下载失败，跳过（mpv 仍可正常播放）"
        rm -rf "$tmp"
        return 0   # 非致命：别让 set -e 把整个安装带下去
    fi

    # v4 的着色器在 glsl_4.0/；上游若改目录名，退回第一个 glsl_* 目录
    local srcdir="$tmp/Anime4K/glsl_4.0"
    if [[ ! -d "$srcdir" ]]; then
        srcdir=$(find "$tmp/Anime4K" -maxdepth 1 -type d -name 'glsl_*' 2>/dev/null | sort -r | head -n 1 || true)
        [[ -n "$srcdir" ]] || {
            print_warn "Anime4K 仓库结构异常，找不到 glsl_* 目录"
            rm -rf "$tmp"
            return 0
        }
    fi

    mkdir -p "$dst"
    find "$srcdir" -maxdepth 1 -type f -name '*.glsl' -exec cp -f {} "$dst"/ \; 2>/dev/null || true
    rm -rf "$tmp"

    # 校验：真装齐了才算成功
    local missing=()
    for f in "${wanted[@]}"; do
        [[ -f "$dst/$f" ]] || missing+=("$f")
    done

    if (( ${#missing[@]} == 0 )); then
        local n
        n=$(find "$dst" -maxdepth 1 -type f -name '*.glsl' 2>/dev/null | wc -l || true)
        print_ok "Anime4K 着色器已安装 ($n 个文件) ${DIM}mpv 里 Ctrl+1..6 切换画质模式${NC}"
        MPV_SHADERS_OK=true
        mark_done "setup_mpv_shaders"
        log "Anime4K shaders installed to $dst ($n files)"
    else
        print_warn "Anime4K 缺 ${#missing[@]} 个文件: ${missing[*]}"
        print_info "重跑安装器会重试；也可以手动 clone 后拷进 $dst"
    fi
}

