# shellcheck shell=bash

# ------------------------------------------------------------------------------
# sudo 保活
# 整个安装流程远超 sudo 默认的 15 分钟时间戳，中途会反复要密码。这里只在**本次
# 运行内**缓存凭证：不改 /etc/sudoers、不做免密，脚本退出后行为完全恢复默认。
# ------------------------------------------------------------------------------
SUDO_KEEPALIVE_PID=""

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

start_sudo_keepalive() {
    print_info "接下来只需输入一次 sudo 密码（仅本次安装有效）"
    if ! sudo -v; then
        print_fail "sudo 验证失败"
        exit 1
    fi

    # sudo -n 不交互，失败也不会弹密码，只用来刷新时间戳
    ( while true; do sudo -n true 2>/dev/null || true; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
    print_ok "sudo 凭证已缓存"
}

# ------------------------------------------------------------------------------
# pacman 残留锁
# 强制重启留下的 db.lck 可以直接删；但真有包管理器在跑时删锁会损坏数据库，
# 所以先确认没有活进程，等 60 秒仍不结束就报错退出，绝不强删。
# ------------------------------------------------------------------------------
_pkg_manager_running() {
    pgrep -x pacman >/dev/null 2>&1 \
        || pgrep -x paru >/dev/null 2>&1 \
        || pgrep -x yay >/dev/null 2>&1 \
        || pgrep -x pamac >/dev/null 2>&1
}

clear_pacman_lock() {
    local lock=/var/lib/pacman/db.lck
    [[ -f "$lock" ]] || return 0

    if _pkg_manager_running; then
        print_warn "检测到包管理器正在运行，等待其结束（最多 60 秒）"
        local i
        for i in $(seq 1 60); do
            _pkg_manager_running || break
            sleep 1
        done
        if _pkg_manager_running; then
            print_fail "包管理器仍在运行，不删除锁文件（强删会损坏数据库）"
            print_info "等它结束后重跑：./install.sh"
            exit 1
        fi
        print_ok "包管理器已结束"
    fi

    print_warn "清理 pacman 残留锁（上次强制重启遗留）"
    sudo rm -f "$lock"
    print_ok "Lock removed"
}

check_system() {
    section "Pre-Flight" "System Check"

    local checks=(
        "Arch Linux:/etc/arch-release:file"
        "Non-root:0:notroot"
        "Pacman:pacman:cmd"
    )

    local failed=false

    for check in "${checks[@]}"; do
        IFS=':' read -r name target type <<< "$check"

        local result=false
        case "$type" in
            file)   [[ -f "$target" ]] && result=true ;;
            notroot) [[ $EUID -ne 0 ]] && result=true ;;
            ping)   ping -c 1 -W 3 "$target" &>/dev/null && result=true ;;
            cmd)    command_exists "$target" && result=true ;;
        esac

        if $result; then
            print_ok "$name"
        else
            print_fail "$name"
            failed=true
        fi
    done

    # 网络单独判断：国内优先探测阿里 DNS，不通再试 Google DNS
    if ping -c 1 -W 3 223.5.5.5 &>/dev/null || ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        print_ok "Network"
    else
        print_warn "Network unreachable (可以继续，但 pacman 会失败)"
    fi

    if $failed; then
        echo ""
        print_fail "System check failed. Exiting."
        print_info "请以普通用户（非 root）在 Arch Linux 上运行：./install.sh"
        exit 1
    fi

    if [[ $EUID -eq 0 ]]; then
        print_fail "Do not run this script as root."
        exit 1
    fi

    # 锁在装任何东西之前处理；凭证也只在这里问一次，后面全程复用
    clear_pacman_lock
    start_sudo_keepalive

    # 上一轮若中断（断电 / kill -9 / 强制关窗）会留下镜像配置，
    # 本轮没打算启用就先清掉，避免「偷偷常驻」到用户察觉不到的地步。
    if [[ -f "$ROOT_DIR/local-bin/.local/bin/gh-mirror" ]]; then
        if bash "$ROOT_DIR/local-bin/.local/bin/gh-mirror" stale-check --quiet; then
            print_warn "检测到上次安装遗留的 GitHub 镜像配置，已自动清除"
            log "Stale gh-mirror config cleaned"
        fi
    fi

    # AUR 包（makepkg 的 curl + *-git 包的 git clone）全都依赖 github.com。在这里一次性修好，后面所有阶段都受益；
    # 修不好也不中断，交给 Phase 4b 的交互闸门决定是否跳过 AUR。
    #
    # 镜像与 hosts 是两种不同的药，不能互相替代：
    #   · hosts 治 DNS 污染（解析到错 IP，curl 报 (6)）
    #   · 镜像治链路阻断（能解析但连不上，curl 报 (7)）
    # 镜像已开着就说明走的是另一条路，hosts 修补没有意义，跳过。
    if [[ "${PULLAUTUMN_MIRROR:-off}" == "on" ]]; then
        print_ok "GitHub 镜像加速已启用，跳过 /etc/hosts 修补"
        log "GitHub mirror active; skip hosts patch"
    else
        ensure_github_reachable || true
    fi

    log "System check passed"
}

install_base() {
    section "Phase 1" "Base Tools"

    if is_done "base_tools"; then
        print_skip "Base tools (already done)"
        return
    fi

    # 锁与 sudo 凭证已在 check_system 处理，这里不再重复询问

    exe_live "Updating system" "sudo pacman -Syu --noconfirm"
    exe_live "Installing base tools" "sudo pacman -S --needed --noconfirm git stow base-devel"

    mark_done "base_tools"
    log "Base tools installed"
}

install_aur_helper() {
    section "Phase 2" "AUR Helper (paru)"

    if command_exists paru; then
        print_ok "paru already installed"
        AUR_HELPER="paru"
        return
    elif command_exists yay; then
        print_ok "yay already installed"
        AUR_HELPER="yay"
        return
    fi

    if is_done "aur_helper"; then
        print_skip "AUR helper (already done)"
        AUR_HELPER="paru"
        return
    fi

    print_info "Adding archlinuxcn repository (BFSU mirror)..."

    # Add archlinuxcn repo if not exists
    if ! grep -q "\[archlinuxcn\]" /etc/pacman.conf; then
        sudo tee -a /etc/pacman.conf > /dev/null << 'REPO'

[archlinuxcn]
Server = https://mirrors.bfsu.edu.cn/archlinuxcn/$arch
REPO
        print_ok "archlinuxcn repo added"
    else
        print_info "archlinuxcn repo exists"
    fi

    exe_live "Syncing pacman database" "sudo pacman -Syu"
    exe_live "Installing archlinuxcn-keyring" "sudo pacman -S --noconfirm archlinuxcn-keyring"
    exe_live "Installing paru" "sudo pacman -S --noconfirm paru"

    AUR_HELPER="paru"
    mark_done "aur_helper"
    print_ok "paru installed via archlinuxcn"
    log "AUR helper installed"
}

clone_dotfiles() {
    section "Phase 3" "Locate Dotfiles"

    # 脚本本身就在仓库里运行（本地安装）：直接使用当前仓库，避免重复克隆
    if [[ -f "$ROOT_DIR/install.sh" && -d "$ROOT_DIR/niri/.config/niri" ]]; then
        DOTFILES_DIR="$ROOT_DIR"
        print_ok "使用本地仓库: $DOTFILES_DIR"
        mark_done "clone_dotfiles"
        return
    fi

    # 由 install.sh 引导克隆而来
    if [[ "${DOTFILES_JUST_CLONED:-}" == "1" ]]; then
        print_ok "Repository cloned (bootstrap)"
        mark_done "clone_dotfiles"
        return
    fi

    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        print_info "Directory exists: $DOTFILES_DIR"
        if confirm "Update existing repo?"; then
            if exe "cd '$DOTFILES_DIR' && git pull --ff-only"; then
                print_ok "Repository updated"
            else
                print_warn "Update failed, continuing with local copy..."
            fi
        fi
        return
    fi

    # 目录存在但不是 git 仓库：非空则拒绝处理，避免掉进下面的重试逻辑被 rm -rf 清掉
    if [[ -d "$DOTFILES_DIR" ]]; then
        if [[ -n "$(ls -A "$DOTFILES_DIR" 2>/dev/null)" ]]; then
            print_fail "$DOTFILES_DIR 已存在但不是 git 仓库，且非空"
            print_info "请先手动移走它（如 mv '$DOTFILES_DIR' '$DOTFILES_DIR.bak'）后重跑"
            exit 1
        fi
        rmdir "$DOTFILES_DIR" 2>/dev/null || true
    fi

    if is_done "clone_dotfiles"; then
        print_skip "Clone dotfiles (already done)"
        return
    fi

    # 大仓库 / 网络不稳时的 git 参数
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 1000
    git config --global http.lowSpeedTime 60

    local max_retries=3
    local retry=0
    # 记录 clone 前该目录是否存在，重试清理时只删本次新建的半成品
    local dst_preexisted=false
    if [[ -e "$DOTFILES_DIR" ]]; then
        dst_preexisted=true
    fi

    while [[ $retry -lt $max_retries ]]; do
        retry=$((retry + 1))
        print_info "Clone attempt $retry/$max_retries"

        if exe "git clone --depth 1 '$DOTFILES_REPO' '$DOTFILES_DIR'"; then
            exe "cd '$DOTFILES_DIR' && git fetch --unshallow" || true
            print_ok "Repository cloned"
            mark_done "clone_dotfiles"
            log "Dotfiles cloned"
            return 0
        fi

        # 只清理本次 clone 留下的半成品，绝不碰用户原有目录
        if [[ "$dst_preexisted" == "false" ]]; then
            rm -rf "$DOTFILES_DIR" 2>/dev/null || true
        fi
        if [[ $retry -lt $max_retries ]]; then
            sleep 3
        fi
    done

    print_fail "Clone failed after $max_retries attempts"
    print_info "Try: git clone $DOTFILES_REPO $DOTFILES_DIR"
    exit 1
}

# ------------------------------------------------------------------------------
# BTRFS 快照（snapper）
#
# 为什么放在 Phase 1 而不是 Phase 5：后面 Phase 4 起开始成批装包，一旦装坏
# （依赖冲突、驱动选错、niri 起不来），回滚点必须是「装包之前」。放到最后
# 等于没有回滚点，只能回滚到一个已经坏掉的状态。
#
# 只配 snapper 本体，刻意不碰引导程序：
#   · grub-btrfs（把快照列进 GRUB 菜单）要求 GRUB，且必须跑 grub-mkconfig。
#     那是整个安装里唯一可能把机器写成开不了机的动作，而快照可用性并不依赖它
#     —— 事后单独补装 grub-btrfs，历史快照会自动全部出现在菜单里。
#   · 也不写 GRUB 的 stub 跳板。那个补丁针对 archinstall「ESP 挂 /boot」的布局；
#     ESP 挂 /efi 时 grub.cfg 本来就在 btrfs 的 @ 里，天然跟着快照回滚。
#
# 失败一律不影响主流程（return 0）：快照是附加保险，装不上不该拦住安装。
# 但也因此不 mark_done，下次重跑会重新尝试。
# ------------------------------------------------------------------------------

_snapper_has_config() {
    sudo snapper list-configs 2>/dev/null | awk 'NR>2 {print $1}' | grep -qx "$1"
}

# snapper create-config 要求目标下没有现成的 .snapshots 目录（它要自己建子卷）。
# 已挂载 = 之前配过，原样保留；空目录 = 上次失败留下的壳，删掉；非空 = 有数据，
# 绝不 rm -rf，交给调用方跳过这个配置。
_snapper_prepare_dir() {
    local dir="$1"

    if findmnt -n "$dir" >/dev/null 2>&1; then
        return 0
    fi

    [[ -e "$dir" ]] || return 0

    if [[ -d "$dir" ]] && [[ -z "$(sudo ls -A "$dir" 2>/dev/null)" ]]; then
        sudo rmdir "$dir"
        return 0
    fi

    print_warn "$dir 已存在且非空，跳过该配置（不删除已有数据）"
    return 1
}

# 策略：每小时 3 个 + 总共留 10 个，足够覆盖「刚装完就出事」这个窗口；
# 日/周/月/年全关，避免长期堆积把磁盘吃满。
_snapper_set_policy() {
    local name="$1"
    sudo snapper -c "$name" set-config \
        ALLOW_GROUPS="wheel" \
        TIMELINE_CREATE="yes" TIMELINE_CLEANUP="yes" \
        NUMBER_LIMIT="10" NUMBER_MIN_AGE="0" NUMBER_LIMIT_IMPORTANT="5" \
        TIMELINE_LIMIT_HOURLY="3" TIMELINE_LIMIT_DAILY="0" \
        TIMELINE_LIMIT_WEEKLY="0" TIMELINE_LIMIT_MONTHLY="0" \
        TIMELINE_LIMIT_YEARLY="0"
}

_snapper_configure() {
    local name="$1"
    local target="$2"

    if _snapper_has_config "$name"; then
        # 已存在也重设一次策略：重跑的意义就是让整体回到安装器的设计值
        print_info "snapper 配置 '$name' 已存在，跳过创建"
    else
        _snapper_prepare_dir "${target%/}/.snapshots" || return 0

        if ! exe_live "Creating snapper config: $name" \
                "sudo snapper -c $name create-config $target"; then
            print_warn "创建 snapper 配置 '$name' 失败，跳过"
            return 0
        fi
    fi

    _snapper_set_policy "$name" \
        || print_warn "snapper '$name' 策略设置失败（快照功能不受影响）"
}

_snapper_baseline() {
    local name="$1"
    local desc="Before Dotfiles Setup"

    # 用描述去重，不靠 state 文件：state 被 --reset 清掉时不至于重复打点
    if sudo snapper -c "$name" list --columns description 2>/dev/null | grep -qxF "$desc"; then
        print_info "基线快照 '$name' 已存在"
        return 0
    fi

    exe_spin "Creating baseline snapshot ($name)" \
        sudo snapper -c "$name" create -d "$desc" \
        || print_warn "基线快照 '$name' 创建失败（可稍后手动 snapper -c $name create）"
}

setup_btrfs_snapshots() {
    section "Phase 1b" "BTRFS Snapshots (snapper)"

    if is_done "btrfs_snapshots"; then
        print_skip "Snapper (already done)"
        return 0
    fi

    local root_fstype
    root_fstype=$(findmnt -n -o FSTYPE / 2>/dev/null || true)
    if [[ "$root_fstype" != "btrfs" ]]; then
        print_skip "根分区是 ${root_fstype:-unknown}，不是 btrfs（不做快照）"
        return 0
    fi

    local _snapper_home=false

    if command_exists snapper; then
        print_ok "snapper already installed"
    elif ! exe_spin "Installing snapper" sudo pacman -S --needed --noconfirm snapper; then
        print_warn "snapper 安装失败，跳过快照配置（不影响后续安装）"
        return 0
    fi

    _snapper_configure root /

    # /home 只有单独挂载成子卷时才单独配：如果它只是 @ 里一个普通目录，
    # /home/.snapshots 会变成 @/.snapshots/.snapshots 的嵌套，没有任何意义。
    if [[ "$(findmnt -n -o TARGET /home 2>/dev/null || true)" == "/home" ]]; then
        _snapper_configure home /home
        _snapper_home=true
    else
        print_skip "/home 不是独立子卷，只配 root 快照"
        _snapper_home=false
    fi

    # create-config 通常会自动 enable，但重跑时配置已存在就跳过了创建，
    # 这里补一刀，保证 timer 一定是开着的。
    sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer \
        >/dev/null 2>&1 || print_warn "snapper 定时器启用失败"

    if _snapper_has_config root; then
        _snapper_baseline root
        if [[ "$_snapper_home" == "true" ]] && _snapper_has_config home; then
            _snapper_baseline home
        fi
        mark_done "btrfs_snapshots"
        print_ok "Snapshots ready（回滚点：Before Dotfiles Setup）"
        log "BTRFS snapshots configured"
    else
        print_warn "root 配置未建立，不标记完成（下次运行会重试）"
    fi

    return 0
}
