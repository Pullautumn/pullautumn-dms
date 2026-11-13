# shellcheck shell=bash

# ==============================================================================
# 辅助函数
# ==============================================================================

# 列出一个 stow 包会落到 $HOME 的目标相对路径
#   x/.config/niri/...      -> .config/niri
#   x/.local/bin/...        -> .local/bin
#   x/.zshenv               -> .zshenv
_pkg_targets() {
    local pkg="$1"
    local top name child
    while IFS= read -r -d '' top; do
        name=$(basename "$top")
        case "$name" in
            .config|.local)
                while IFS= read -r -d '' child; do
                    printf '%s\n' "${child#"$DOTFILES_DIR/$pkg/"}"
                done < <(find "$top" -mindepth 1 -maxdepth 1 -print0)
                ;;
            *)
                printf '%s\n' "${top#"$DOTFILES_DIR/$pkg/"}"
                ;;
        esac
    done < <(find "$DOTFILES_DIR/$pkg" -mindepth 1 -maxdepth 1 -print0)
}

# 备份并移走会被整体替换的现有配置（只处理 .config/* 与 .zshenv）
_dotfiles_backup_existing() {
    print_info "Backing up existing configs..."

    local backup_dir="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
    local pkg target abs real moved=false

    for pkg in "${STOW_PACKAGES[@]}"; do
        [[ -d "$DOTFILES_DIR/$pkg" ]] || continue
        while IFS= read -r target; do
            # 共享目录（.local/bin 等）交给 stow 合并，不整体搬走
            case "$target" in
                .config/*) ;;
                .zshenv)   ;;
                *) continue ;;
            esac

            abs="$HOME/$target"
            [[ -e "$abs" || -L "$abs" ]] || continue

            # 已经是指向本仓库的链接就不动
            if [[ -L "$abs" ]]; then
                real=$(readlink -f "$abs" 2>/dev/null || true)
                if [[ -n "$real" && "$real" == "$DOTFILES_DIR"/* ]]; then
                    continue
                fi
            fi

            mkdir -p "$backup_dir/$(dirname "$target")"
            if mv "$abs" "$backup_dir/$target" 2>/dev/null; then
                moved=true
            else
                print_warn "无法备份 $abs"
            fi
        done < <(_pkg_targets "$pkg")
    done

    if $moved; then
        print_ok "Backed up to: $backup_dir"
        log "Backup dir: $backup_dir"
        BACKUP_DIR="$backup_dir"
    fi
}

# 逐个 stow
_dotfiles_stow_all() {
    print_info "Applying configs with stow..."

    local pkg
    for pkg in "${STOW_PACKAGES[@]}"; do
        if [[ ! -d "$DOTFILES_DIR/$pkg" ]]; then
            print_warn "missing package: $pkg"
            continue
        fi

        # mimeapps 用绝对路径链接：系统/桌面环境会写入该文件，避免写穿 stow 链接
        if [[ "$pkg" == "mimeapps" ]]; then
            mkdir -p "$HOME/.config"
            rm -f "$HOME/.config/mimeapps.list"
            if ln -sfn "$DOTFILES_DIR/mimeapps/.config/mimeapps.list" "$HOME/.config/mimeapps.list"; then
                print_ok "mimeapps ${DIM}(absolute link)${NC}"
            else
                print_warn "mimeapps link failed"
            fi
            continue
        fi

        if stow -d "$DOTFILES_DIR" -t "$HOME" -R "$pkg" >> "$LOG_FILE" 2>&1; then
            print_ok "$pkg"
        else
            print_warn "stow failed: $pkg ${DIM}(see log)${NC}"
        fi
    done
}

# 清空仓库里的壁纸目录，只留 README.md（它被 git 跟踪，删掉会弄脏工作区）。
#
# 为什么需要：git 只能整仓下载，所以壁纸**不进 git**（见 .gitignore）。但「现在不进 git」
# 不等于「别人电脑上没有」—— 老版本 clone 过、手工拷过、或者早期 commit 里跟踪过的，
# 那 50 MB 会一直躺在工作副本里，白白占空间。非作者装这套配置时直接清掉。
#
# 只删 $DOTFILES_DIR 下的这个目录，**绝不碰 ~/Pictures/Wallpapers** —— 那是用户自己的目录。
_dotfiles_clear_repo_wallpapers() {
    local dir="$1"
    local owner="$2"

    [[ -d "$dir" && ! -L "$dir" ]] || return 0

    local n=0
    n=$(find "$dir" -mindepth 1 -maxdepth 1 ! -name 'README.md' 2>/dev/null | wc -l || true)
    if (( n == 0 )); then
        return 0
    fi

    if find "$dir" -mindepth 1 -maxdepth 1 ! -name 'README.md' -exec rm -rf {} + 2>/dev/null; then
        print_info "壁纸: 已清空仓库内的 $n 项（非 $owner 用户不需要）"
    else
        print_warn "壁纸: 清空仓库内壁纸失败，可手动删除 $dir"
    fi
}

# 壁纸目录：单独链接，不作为 stow 包。
#
# 壁纸图片**不进 git**（50 MB，见 .gitignore）。原因：git 的下载粒度是整个仓库，
# 只要图提交进去了，每个 clone 的人都要付这 50 MB —— 没法按用户名分流。
# 所以这里是「仓库作者本地保留一份，别人装的时候完全看不到」的做法：
#   - $WALLPAPER_OWNER（默认 pullautumn）以外的人：清空仓库里残留的图，只建一个
#     空目录给 DMS 用
#   - 作者本人：仓库里有图就直接链接；没有（换机器 / 重新 clone）且设了
#     $WALLPAPERS_REPO 就 clone 一份下来，否则提示把备份放回去
_dotfiles_link_wallpapers() {
    local src="$DOTFILES_DIR/wallpaper/Pictures/Wallpapers"
    local dst="$HOME/Pictures/Wallpapers"
    local owner="${WALLPAPER_OWNER:-pullautumn}"
    local me="${TARGET_USER:-$(id -un)}"

    mkdir -p "$HOME/Pictures"

    # DMS 的壁纸选择器要求这个目录存在；不是作者就到此为止，一个字节都不下载
    if [[ "${me,,}" != "${owner,,}" ]]; then
        _dotfiles_clear_repo_wallpapers "$src" "$owner"
        mkdir -p "$dst"
        print_skip "壁纸 (仅 $owner 使用，跳过；用 DMS 自带的壁纸)"
        return 0
    fi

    # 作者本人：先确保仓库里有图
    local count=0
    count=$(find "$src" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \) 2>/dev/null | wc -l || true)

    if (( count == 0 )) && [[ -n "${WALLPAPERS_REPO:-}" ]]; then
        print_info "壁纸: 仓库里没有图，从 $WALLPAPERS_REPO 拉取..."
        local tmp
        tmp=$(mktemp -d) || return 0
        if gh_clone "$WALLPAPERS_REPO" "$tmp/wallpapers"; then
            mkdir -p "$src"
            # 兼容两种结构：仓库根直接放图，或放在 Pictures/Wallpapers/ 下
            local from="$tmp/wallpapers"
            [[ -d "$from/Pictures/Wallpapers" ]] && from="$from/Pictures/Wallpapers"
            find "$from" -maxdepth 1 -type f \
                \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \) \
                -exec cp -f {} "$src"/ \; 2>/dev/null || true
            count=$(find "$src" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \) 2>/dev/null | wc -l || true)
        else
            print_warn "壁纸拉取失败（$WALLPAPERS_REPO）"
        fi
        rm -rf "$tmp"
    fi

    if (( count == 0 )); then
        mkdir -p "$dst"
        print_info "壁纸: 仓库里没有图 ${DIM}(把备份放回 wallpaper/Pictures/Wallpapers/ 再跑一次)${NC}"
        return 0
    fi

    print_info "壁纸: 检测到 $count 张图，链接到 $dst"

    # 已存在的真实目录先改名备份；移不动就放弃建链，绝不动用户原目录
    if [[ -d "$dst" && ! -L "$dst" ]]; then
        local bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
        if mv "$dst" "$bak"; then
            print_ok "原壁纸目录已备份: $bak"
        else
            print_warn "无法移开 $dst，跳过壁纸链接（原有目录保持不动）"
            return 0
        fi
    fi

    # ln -sfn 可覆盖已存在的软链，无需先删
    if ln -sfn "$src" "$dst"; then
        print_ok "壁纸目录已链接: $dst"
    else
        print_warn "壁纸链接失败"
    fi
}

# 脚本可执行权限
_dotfiles_fix_permissions() {
    local dirs=(
        "$HOME/.local/bin"
        "$HOME/.config/scripts"
        "$HOME/.config/niri/scripts"
    )
    local d
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] || continue
        find -L "$d" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true
    done

    # 无后缀的可执行脚本：quickload / quicksave / niri-session-wlroots /
    # terminal-launcher / gh-mirror 都属于这类。
    #
    # 判据不用「目录白名单」，而是看文件首行是不是 shebang —— 早期版本维护过一份
    # 白名单，它自己过期了（留着早已没内容的目录，却漏掉真的有脚本的目录）。
    # 后果是 spawn 时 execve 拿到 EACCES：Mod+Alt+Slash 按了毫无反应、
    # 某个按钮点了没动静，而 niri 只在日志里留一行，极难定位。
    #
    # 两个实现细节：
    #   - 不加 -maxdepth，子目录里的入口一并覆盖。
    #   - -print0 + read -d '' 处理带空格的文件名；! -name "*.*" 只挑没有扩展名
    #     的文件（.sh / .py 已由上一段批量处理，图片等带扩展名的顺带排掉）。
    local f
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r -d '' f; do
            if [[ "$(head -c 2 "$f" 2>/dev/null)" == "#!" ]]; then
                chmod +x "$f" 2>/dev/null || true
            fi
        done < <(find -L "$d" -type f ! -name "*.*" -print0 2>/dev/null)
    done

    print_ok "脚本可执行权限已设置"
}

# ==============================================================================
# GTK 书签（唯一一个「路径无法自解析」的配置）
# ==============================================================================
# GTK 的 bookmarks 只认绝对 file:// URI，不支持 ~、也不展开环境变量，内容必然
# 跟用户名绑定，只能在安装时按 $HOME 生成。
#
# 为什么是「写仓库里那份」而不是「改 ~/.config 下那份」：
# stow 会把 ~/.config/gtk-3.0 整个目录折叠成指向仓库的软链（和 colors.css、
# gtk.css 一样，运行时产物都落在仓库里，已 gitignore）。所以根本不存在「$HOME
# 下单独一份 bookmarks」可以改，只能像其它生成物一样直接写仓库里这份。
#
# 早期版本用「find ~/.config -type l → sed readlink -f 的结果」替换用户名，
# 等于把仓库里所有配置文件改写成对方用户名：git status 变脏、git pull 冲突，
# 还会把 pullautumn-screenrec 这类标识符一起改掉。已废弃。
_dotfiles_generate_bookmarks() {
    local out="$DOTFILES_DIR/gtk-3.0/.config/gtk-3.0/bookmarks"
    local out_dir
    out_dir=$(dirname "$out")
    [[ -d "$out_dir" ]] || return 0

    local -a rels=(Code dotfiles Downloads Documents Pictures Music Videos)

    # 作者机器上额外固定 ~/.config 和 ~/.local（改配置时一步点到）。这是个人习惯而不是
    # 发行版该有的默认，所以按 WALLPAPER_OWNER 判断，别人的机器上不塞这两条 ——
    # .config/.local 对普通用户只是噪音，还容易被误点删掉东西。
    if [[ "${TARGET_USER,,}" == "${WALLPAPER_OWNER,,}" ]]; then
        rels+=(.config .local)
    fi

    local -a lines=()
    local rel p const
    for rel in "${rels[@]}"; do
        case "$rel" in
            Downloads|Documents|Pictures|Music|Videos)
                # 标准 XDG 目录**在安装阶段通常还不存在** —— 它们由首次登录时的
                # xdg-user-dirs-update 创建，而书签是 Phase 3 生成的。原实现只判
                # `[[ -d ]]` 就跳过，于是侧边栏只剩安装途中顺带建出来的 ~/Pictures
                # 一项（壁纸链接那个），其余全丢。这里问 xdg-user-dir 要真实路径
                # （本地化目录名也能对上），再补建目录，不依赖登录时机。
                case "$rel" in
                    Downloads) const=DOWNLOAD ;;                       # 单数，别想当然
                    *)          const=$(printf '%s' "$rel" | tr '[:lower:]' '[:upper:]') ;;
                esac
                p=""
                if command_exists xdg-user-dir; then
                    p=$(xdg-user-dir "$const" 2>/dev/null) || p=""
                fi
                # xdg-user-dir 查不到会返回 $HOME，那等于没配这个目录
                [[ -n "$p" && "$p" != "$HOME" ]] || p="$HOME/$rel"
                mkdir -p "$p" 2>/dev/null || continue
                ;;
            dotfiles)
                # 仓库目录两种习惯都认：~/dotfiles（软链）和 ~/.dotfiles（clone 默认名）
                p="$HOME/dotfiles"
                [[ -d "$p" ]] || p="$HOME/.dotfiles"
                ;;
            *)
                p="$HOME/$rel"
                ;;
        esac
        [[ -d "$p" ]] && lines+=("file://$p $rel")
    done

    if (( ${#lines[@]} == 0 )); then
        print_warn "没有可用的书签目录，跳过 GTK 书签生成"
        return 0
    fi

    printf '%s\n' "${lines[@]}" > "$out"
    print_ok "已生成 GTK 书签 ${#lines[@]} 项（路径基于 $HOME）"
    log "bookmarks generated: $out"
}

# Flatpak 权限覆盖（装了 flatpak 才有意义）
_dotfiles_flatpak_overrides() {
    command_exists flatpak || return 0

    flatpak override --user --filesystem=xdg-config/gtk-3.0 >/dev/null 2>&1 || true
    flatpak override --user --filesystem=xdg-config/gtk-4.0 >/dev/null 2>&1 || true
    flatpak override --user --filesystem=xdg-config/fontconfig >/dev/null 2>&1 || true
    flatpak override --user --filesystem=xdg-data/themes >/dev/null 2>&1 || true
    flatpak override --user --filesystem="$HOME/.themes" >/dev/null 2>&1 || true
    print_ok "Flatpak 主题/字体权限已放行"
}

# 把仓库里的使用说明复制到用户主目录
# ==============================================================================
# 主流程
# ==============================================================================
apply_dotfiles() {
    section "Phase 5" "Apply Configurations"

    if $SKIP_STOW; then
        print_skip "Config deployment (--no-stow)"
        return
    fi

    # 已部署过：stow 不重跑（免得覆盖用户改过的配置），但执行位要补一次。
    # 权限修复本身幂等，而 x 位又极容易丢 —— 从 Windows 拷过来的文件、tar 不带 -p、
    # 手动编辑保存，都会让它消失，表现是「快捷键按了没反应」这种查不出所以然的症状。
    # 放在 is_done 之前，重跑安装器就能修好，不必 --reset 清掉全部标记。
    if is_done "apply_dotfiles"; then
        _dotfiles_fix_permissions
        # 书签同理：纯生成物、幂等、不依赖 stow。放这里，早期版本装出来的半截书签
        # （只有 ~/Pictures 一项）重跑一次安装器就能补齐。
        _dotfiles_generate_bookmarks
        print_skip "Dotfiles applied (already done)"
        return
    fi

    if [[ ! -d "$DOTFILES_DIR" ]]; then
        print_fail "Dotfiles not found: $DOTFILES_DIR"
        return 1
    fi

    if ! command_exists stow; then
        print_info "Installing stow..."
        sudo pacman -S --needed --noconfirm stow >> "$LOG_FILE" 2>&1 || true
    fi
    if ! command_exists stow; then
        print_fail "stow 不可用，跳过配置部署"
        return 1
    fi

    cd "$DOTFILES_DIR" || return 1

    _dotfiles_backup_existing
    _dotfiles_stow_all
    _dotfiles_link_wallpapers
    _dotfiles_fix_permissions
    _dotfiles_generate_bookmarks
    _dotfiles_flatpak_overrides

    # dms 包必须是**目录**软链。DMS 用原子写（QSaveFile → 临时文件 + rename）改
    # settings.json，rename 到单文件软链上会把链接替换成普通文件 —— 之后仓库那份再也
    # 不更新，而 git status 一直是干净的（最难查的一种失败）。只有折叠成
    # ~/.config/dms -> 仓库目录 才会写穿。折叠的前提是该目录先被备份步骤整个搬走，
    # 所以这里只做断言，不改任何东西。
    if [[ -L "$HOME/.config/dms" ]]; then
        print_info "dms: ~/.config/dms -> $(readlink "$HOME/.config/dms")"
    elif [[ -e "$HOME/.config/dms" ]]; then
        print_warn "~/.config/dms 不是软链，DMS 设置不会同步回仓库（多半是备份步骤没搬走旧目录）"
    fi

    # niri 显示器配置：写死在仓库里，换机器时需要按实际输出改名
    if [[ -f "$HOME/.config/niri/conf.d/output.kdl" ]]; then
        print_info "显示器配置: ~/.config/niri/conf.d/output.kdl ${DIM}(按实际输出名调整)${NC}"
    fi

    # 截图路径用 ~，niri 自己会展开并创建目录，不需要提示用户手改

    # 桌面壳是 DMS，快捷键提示只留真正会用到的
    if [[ -d "$HOME/.config/niri/dms" ]]; then
        print_info "桌面: DMS ${DIM}Mod+A 启动器 · Mod+N 控制中心 · Mod+F2 设置 · Mod+Alt+L 锁屏${NC}"
    fi

    mark_done "apply_dotfiles"
    print_ok "Configs applied"
    log "Dotfiles applied"
}
