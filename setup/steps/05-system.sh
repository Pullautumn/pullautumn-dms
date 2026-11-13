# shellcheck shell=bash

setup_locale() {
    section "Phase 7a" "Locale Configuration"

    if is_done "setup_locale"; then
        print_skip "Locale setup (already done)"
        return
    fi

    local need_gen=false

    # en_US.UTF-8：LC_CTYPE 用它，规避 fcitx5 漏字
    if ! locale -a 2>/dev/null | grep -qi "en_US.utf8"; then
        print_info "Enabling en_US.UTF-8..."
        if grep -q "^#en_US.UTF-8" /etc/locale.gen; then
            sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        elif ! grep -q "^en_US.UTF-8" /etc/locale.gen; then
            echo "en_US.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen > /dev/null
        fi
        need_gen=true
    else
        print_ok "en_US.UTF-8 locale available"
    fi

    # zh_CN.UTF-8：niri environment.kdl 里 LANG 用它
    if ! locale -a 2>/dev/null | grep -qi "zh_CN.utf8"; then
        print_info "Enabling zh_CN.UTF-8..."
        if grep -q "^#zh_CN.UTF-8" /etc/locale.gen; then
            sudo sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
        elif ! grep -q "^zh_CN.UTF-8" /etc/locale.gen; then
            echo "zh_CN.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen > /dev/null
        fi
        need_gen=true
    else
        print_ok "zh_CN.UTF-8 locale available"
    fi

    if $need_gen; then
        print_info "Generating locales..."
        if sudo locale-gen >> "$LOG_FILE" 2>&1; then
            print_ok "Locales generated"
        else
            print_warn "locale-gen failed"
        fi
    fi

    # 系统 locale 保持英文，中文由 niri 的 environment.kdl 设置
    print_info "System locale: en_US.UTF-8 (Chinese set via niri environment)"

    mark_done "setup_locale"
    log "Locale configured"
}

setup_bash_path() {
    section "Phase 7b" "Bash PATH Configuration"

    if is_done "setup_bash_path"; then
        print_skip "Bash PATH (already done)"
        return
    fi

    local bash_profile="$HOME/.bash_profile"
    local bashrc="$HOME/.bashrc"
    local path_line='export PATH="$HOME/.local/bin:$PATH"'

    if [[ -f "$bash_profile" ]]; then
        if ! grep -q '\.local/bin' "$bash_profile"; then
            printf '\n# Add local bin to PATH\n%s\n' "$path_line" >> "$bash_profile"
            print_ok "Updated .bash_profile"
        else
            print_info ".bash_profile already has PATH"
        fi
    else
        cat > "$bash_profile" << 'BASHPROFILE'
# ~/.bash_profile - Bash login shell configuration

# Add local bin to PATH
export PATH="$HOME/.local/bin:$PATH"

# Source .bashrc if it exists
[[ -f ~/.bashrc ]] && source ~/.bashrc
BASHPROFILE
        print_ok "Created .bash_profile"
    fi

    if [[ -f "$bashrc" ]]; then
        if ! grep -q '\.local/bin' "$bashrc"; then
            printf '\n# Add local bin to PATH\n%s\n' "$path_line" >> "$bashrc"
            print_ok "Updated .bashrc"
        else
            print_info ".bashrc already has PATH"
        fi
    fi

    mark_done "setup_bash_path"
    log "Bash PATH configured"
}

# ~/.local/bin 里的脚本（niri-session-wlroots / quickload / quicksave 等）
setup_local_bin() {
    section "Phase 7c" "Local Binaries"

    if is_done "setup_local_bin"; then
        print_skip "Local binaries (already done)"
        return
    fi

    mkdir -p "$HOME/.local/bin"

    local count=0
    if [[ -d "$HOME/.local/bin" ]]; then
        # -L 是必须的：stow 把 local-bin 折叠成指向仓库的目录软链，
        # 不加 -L 的 find 不会往下走，count 永远是 0、chmod 也一个都碰不到。
        # 末尾的 || true 必不可少：find -L 碰到断链会返回非零，
        # pipefail 会把它升级成整个管道的退出码，set -e 随即杀掉安装脚本。
        # wc 已经输出了数字，这里只是不让退出码继续往下传。
        count=$(find -L "$HOME/.local/bin" -maxdepth 1 -type f 2>/dev/null | wc -l) || true
        find -L "$HOME/.local/bin" -maxdepth 1 -type f -exec chmod +x {} + 2>/dev/null || true
    fi

    print_ok "$count 个本地脚本已就绪 (~/.local/bin)"
    mark_done "setup_local_bin"
    log "Local binaries ready"
}

# ==============================================================================
# DMS（dux-shell）
# ==============================================================================
# niri 侧的配置结构来自 shorin-dux-niri，仓库**自带**这些文件：
#   dms/binds.kdl      键位（pullautumn 的键位表，命令换成 DMS IPC）
#   dms/supertab.kdl   Alt+Tab 缩略图切换
#   dms/alttab.kdl     recent-windows 的圆角
#   dms/cursor.kdl     光标主题与大小
#   dms/layout.kdl     gaps / 边框 / 圆角（DMS 的布局设置会重写它）
# 下面三个由 DMS 运行时生成，不进仓库（见 .gitignore）：
#   dms/colors.kdl     matugen 配色
#   dms/input.kdl      输入设置面板
#   dms/outputs.kdl    显示器面板
#   dms/windowrules.kdl 窗口规则面板
#
# `dms setup <name>` 遇到已存在的非空文件会拒绝覆盖，所以这里只补 colors，
# 其余交给仓库里那份，不会被上游模板冲掉。
setup_dms() {
    section "Phase 7d" "DMS (dux-shell)"

    if is_done "setup_dms"; then
        print_skip "DMS setup (already done)"
        return
    fi

    if ! command_exists dms; then
        print_warn "找不到 dms 命令（dux-shell 没装上？）"
        print_info "手动补装: paru -S --needed dux-shell dux-gop"
        return
    fi

    # 版本号只是装饰，拿不到就显示「已安装」，绝不能因此中断安装。
    #
    # 这里**不能**写成裸的 $(dms --version | head -n 1)：
    #   main.sh 开了 set -euo pipefail，
    #   dms 是 cobra 程序，对没注册的 flag 会返回非零（unknown flag），
    #   2>/dev/null 又把那条报错吞了 —— 于是整个安装脚本在这里静默退出，
    #   Phase 8 及以后（配色还原 / 服务 enable / greetd）全部丢失，
    #   而 trap cleanup 还会把现场收拾干净，看起来像正常跑完。
    # 不用管道也顺便避开了 head 提前关闭导致的 SIGPIPE（141）。
    local ver=""
    ver=$(dms --version 2>/dev/null) || ver=$(dms version 2>/dev/null) || ver=""
    # 多行输出只取第一行
    if [[ "$ver" == *$'\n'* ]]; then
        ver=${ver%%$'\n'*}
    fi
    print_ok "DMS ${ver:-已安装}"

    mkdir -p "$HOME/.config/niri/dms"

    # 只让 DMS 生成配色。安装期通常没有图形会话，detectCompositorForSetup 可能
    # 认不出 niri；认不出就只 warn —— 首次登录后换一次壁纸，DMS 自己会写。
    #
    # DMS_PRIVESC 必须显式给出：dms 同时检测到 sudo 和 run0 时会弹一个交互菜单
    # 问用哪个，而 exe() 把 stdout/stderr 全吞进日志 —— 那个菜单你在屏幕上看不见，
    # 命令却挂在 stdin 上等输入，装到一半就像卡死，只有翻日志才知道它在问什么。
    # 走到这里说明 dms 已安装，两个工具通常都有，优先 sudo；没有就退到 run0。
    local privesc="sudo"
    command_exists sudo || privesc="run0"
    if [[ -s "$HOME/.config/niri/dms/colors.kdl" ]]; then
        print_skip "dms/colors.kdl 已存在"
    elif exe "DMS_PRIVESC=$privesc dms setup colors < /dev/null"; then
        print_ok "dms/colors.kdl 已生成"
    else
        print_info "colors.kdl 没生成：安装期没有图形会话时属正常，登录后换壁纸会自动补齐"
    fi

    # 仓库自带的 dms/*.kdl 是否就位（stow 之后才有）
    local name missing=0
    for name in binds supertab alttab cursor layout; do
        [[ -s "$HOME/.config/niri/dms/$name.kdl" ]] || { missing=$((missing + 1)); print_warn "缺少 dms/$name.kdl（stow 没跑到？）"; }
    done
    (( missing == 0 )) && print_ok "dms/*.kdl 已就绪（binds / supertab 来自仓库）"

    # niri 配置自检。
    # stow 是软链，仓库里写错一个字符当场生效，而 niri 对某些错误是**硬失败**的
    # （例如 keybind 花括号里挂了两个 action → "only one action is allowed per keybind"），
    # 结果就是装完重启进不去桌面。这一步在 Phase 7 末尾跑，出问题能当场看见。
    #
    # 只用 if，不用裸赋值/管道：nv=$(...) 失败会走 else，不会被 set -e 杀掉。
    if command_exists niri; then
        local nv=""
        if nv=$(niri validate 2>&1); then
            print_ok "niri validate 通过"
        else
            print_warn "niri validate 失败 —— niri 可能起不来，请先修好再重启："
            # 用 herestring + awk，不用 printf|head：head 提前关闭会让管道返回非零，
            # 在 pipefail 下同样会静默杀掉脚本。
            awk 'NR<=12 {print "       " $0}' <<< "$nv"
            log "niri validate failed: $nv"
        fi
    fi

    # 输入组：DMS 的大写锁定 OSD 需要读 /dev/input
    if getent group input >/dev/null 2>&1 && ! id -nG "$TARGET_USER" | grep -qw input; then
        sudo usermod -aG input "$TARGET_USER" >/dev/null 2>&1 \
            && print_ok "已加入 input 组（大写锁定指示，重新登录生效）" \
            || print_warn "加入 input 组失败（可忽略）"
    fi

    # 锁屏认证：DMS 的 PAM 解析器按 login → system-auth 的顺序找，
    # Arch 一定有 /etc/pam.d/login，所以不需要额外建 service 文件。
    if [[ ! -f /etc/pam.d/login ]]; then
        print_warn "没有 /etc/pam.d/login，DMS 锁屏可能无法验证密码"
        print_info "可用 `sudo nano /etc/pam.d/dankshell` 写一份 auth/account/session include system-auth"
    fi

    mark_done "setup_dms"
    log "DMS configured"
}


setup_matugen() {
    section "Phase 8" "Theme System (Matugen)"

    if is_done "setup_matugen"; then
        print_skip "Matugen setup (already done)"
        return
    fi

    # 首次安装不依赖 matugen，它只在以后换壁纸时用；缺了也不影响这一步
    if ! command_exists matugen; then
        print_warn "matugen 未安装，换壁纸时的配色生成会不可用（首次部署不依赖它）"
    fi

    # 首次部署**不跑 matugen**。
    # matugen 生成的是「当前那张壁纸」的配色，而全新安装应该先用仓库自带的
    # 默认配色（btop / fastfetch / fuzzel / fcitx5 各有一份），等用户真正换壁纸时
    # 由 DMS 自己 spawn matugen 接管 —— 本仓库不再有 matugen-update.sh 这类外部触发器。
    # niri 窗口边框色不在这里管：它来自 DMS 生成的 dms/colors.kdl，
    # 首次登录换一次壁纸才有，在那之前用 niri 默认色（与 shorin 一致）。
    # --configs-only 只做文件还原，不碰 GSettings / 图标缓存 / 服务刷新 ——
    # 那几段里有 sed -i 直接改 ~/.config 下的文件，等于改写 stow 软链背后的仓库。
    # fcitx5 的配色文件同样在这一步落盘，被跳过的只是「重载 classicui」。
    local restore_script="$HOME/.config/scripts/matugen-restore.sh"
    if [[ -f "$restore_script" ]]; then
        print_info "应用仓库自带的默认配色（不生成壁纸配色）"
        if exe "bash '$restore_script' --configs-only"; then
            print_ok "Default colors restored"
        else
            print_warn "还原默认配色失败（看 $LOG_FILE）"
            print_info "可手动重试: bash ~/.config/scripts/matugen-restore.sh --configs-only"
        fi
    else
        print_warn "找不到 matugen-restore.sh，跳过配色还原"
    fi

    # 同步 GNOME 的明暗基调 + DMS 的亮暗状态。
    #
    # 三个键各有各的消费者，缺一不可：
    #   color-scheme  libadwaita（GTK4 / GNOME 系程序）认它。亮色写 "default"
    #                 —— DMS 的 syncColorScheme 也用 "default" 表示 light，
    #                 两边一致才不会每次换壁纸都来回改写。
    #   gtk-theme     GTK3 认它。亮色变体是 adw-gtk3（不带 -dark），
    #                 由 PKG_GROUPS[theme] 的 adw-gtk-theme 提供。
    #   icon-theme    图标主题。DMS 的 iconThemeDark/Light 默认 "System Default"
    #                 （只恢复、不接管），所以这里设一次就固定下来。
    if command_exists gsettings; then
        if _gsettings_set org.gnome.desktop.interface color-scheme "default" \
            && _gsettings_set org.gnome.desktop.interface gtk-theme "adw-gtk3" \
            && _gsettings_set org.gnome.desktop.interface icon-theme "Adwaita"; then
            print_ok "系统基调: light (adw-gtk3 + Adwaita)"
        else
            print_warn "gsettings 写入失败（可能不在图形会话）"
            print_info "登录后可在 DMS 设置 → 外观 里切换明暗，会自动补上"
        fi
    fi

    # DMS 的设置不在这里管：它是 stow 包（dms/.config/dms），随 Phase 5 落地。
    # 壁纸 / 明暗 / 显示器布局在 ~/.local/state/dms/session.json，不在包里，也就不会被还原
    # —— 那是安装者自己选的东西，安装器不假设。

    mark_done "setup_matugen"
    log "Default colors restored (matugen not run on first install)"
}

# gsettings 的容错封装：安装器可能跑在纯 TTY（没有 dconf 会话连接），
# 直连失败时套一层 dbus-run-session 再试一次。成功返回 0。
_gsettings_set() {
    gsettings set "$@" 2>/dev/null && return 0
    command_exists dbus-run-session || return 1
    dbus-run-session -- gsettings set "$@" 2>/dev/null
}

# Nautilus 右键「在终端中打开」→ kitty
#
# Nautilus 43 之后原生菜单项不可配置，改由 nautilus-open-any-terminal 自己注册一个，
# 终端名由它的 gsettings 键决定（schema 由该 AUR 包装到 /usr/share/glib-2.0/schemas）。
#
# 这一段单独成函数、并且放在 is_done 判断之前：它出过一次「只打印一句 WARN 就跳过」的事故
# （包其实已经装好，但那一刻 gsettings 还看不见 schema → 走了 else 分支），
# 结果右键菜单一直指向默认的 gnome-terminal —— 而 gnome-terminal 根本没装，点了毫无反应。
# 单独拎出来（不受 setup_desktop_tweaks 的 is_done 短路约束）是为了让**重跑安装器**能把它修回来，
# 而不是只在全新安装时试一次。
setup_nautilus_terminal() {
    command_exists gsettings || return 0

    local naut_schema=com.github.stunkymonkey.nautilus-open-any-terminal
    local naut_xml="/usr/share/glib-2.0/schemas/${naut_schema}.gschema.xml"

    # 能不能用，以 gsettings 看得见为准（扩展读的也是这个）。
    # 包装好但 gschemas.compiled 还是旧的（pacman 钩子没跑 / 缓存被覆盖）时，
    # list-schemas 会漏掉它，这里补一次编译再判。
    if ! gsettings list-schemas 2>/dev/null | grep -qx "$naut_schema"; then
        if [[ -f "$naut_xml" ]]; then
            print_info "schema 缓存里没有 $naut_schema，重新编译 ..."
            sudo glib-compile-schemas /usr/share/glib-2.0/schemas >/dev/null 2>&1 || true
        fi
    fi

    if ! gsettings list-schemas 2>/dev/null | grep -qx "$naut_schema"; then
        print_warn "未找到 nautilus-open-any-terminal 的 schema（包可能没装上）"
        print_info "补装: paru -S nautilus-open-any-terminal"
        print_info "仍看不到就手动 sudo glib-compile-schemas /usr/share/glib-2.0/schemas"
        return 0
    fi

    if ! _gsettings_set "$naut_schema" terminal kitty; then
        print_warn "Nautilus 右键终端设置失败，登录后手动执行："
        print_info "gsettings set $naut_schema terminal kitty"
        return 0
    fi

    # 菜单文案统一成「打开终端」，不显示具体终端名
    _gsettings_set "$naut_schema" use-generic-terminal-name true || true

    # 以读回值为准：set 返回 0 但 dconf 没落地的情况也见过（纯 TTY 装机走的是
    # dbus-run-session 兜底，写的是临时会话的 dconf）。
    local cur
    cur=$(gsettings get "$naut_schema" terminal 2>/dev/null)
    if [[ "$cur" == "'kitty'" ]]; then
        print_ok "Nautilus 右键终端已设为 kitty"
    else
        print_warn "Nautilus 右键终端读回为 ${cur:-空}，未生效"
        print_info "登录图形会话后手动执行: gsettings set $naut_schema terminal kitty"
    fi
}

# 桌面环境的一次性系统设置（不属于 dotfiles）
setup_desktop_tweaks() {
    section "Phase 8b" "Desktop Tweaks"

    # 放在 is_done 判断**之前**：已装机的机器上这个函数早就是 done 了，
    # 放后面等于新加的修正永远轮不到执行。
    setup_nautilus_terminal

    if is_done "setup_desktop_tweaks"; then
        print_skip "Desktop tweaks (already done)"
        return
    fi

    # 默认终端（xdg-terminal-exec 读取）
    mkdir -p "$HOME/.config"
    local term_list="$HOME/.config/xdg-terminals.list"
    # 该文件是按优先级排序的候选列表，第一行即默认终端。
    # 只把 kitty 提到第一行，其余条目原样保留（不覆盖用户自己排过的顺序）。
    if [[ -f "$term_list" ]] && [[ "$(head -n 1 "$term_list" 2>/dev/null)" == "kitty.desktop" ]]; then
        print_info "默认终端已是 kitty"
    else
        if [[ -f "$term_list" ]]; then
            cp "$term_list" "$term_list.bak.$(date +%Y%m%d%H%M%S)"
        fi
        {
            echo "kitty.desktop"
            grep -vx "kitty.desktop" "$term_list" 2>/dev/null || true
        } > "$term_list.tmp"
        mv "$term_list.tmp" "$term_list"
        print_ok "默认终端设为 kitty（原有条目已保留）"
    fi

    # Nautilus 右键终端见上方 setup_nautilus_terminal（不受 is_done 约束）

    # 去掉窗口标题栏的按钮（niri 无边框）
    # 同样走 _gsettings_set：纯 TTY 装机时直连 dconf 会失败，靠 dbus-run-session 兜底。
    if command_exists gsettings; then
        if _gsettings_set org.gnome.desktop.wm.preferences button-layout ":close"; then
            print_ok "窗口按钮布局已设置"
        else
            print_warn "窗口按钮布局设置失败，登录后手动执行："
            print_info "gsettings set org.gnome.desktop.wm.preferences button-layout ':close'"
        fi
    fi

    # ddcutil 外接显示器亮度控制需要 i2c 权限
    if command_exists ddcutil; then
        if ! id -nG "$TARGET_USER" | grep -qw i2c; then
            sudo gpasswd -a "$TARGET_USER" i2c >/dev/null 2>&1 \
                && print_ok "已加入 i2c 组（重新登录生效）" \
                || print_warn "加入 i2c 组失败"
        else
            print_ok "已在 i2c 组"
        fi
        if ! lsmod 2>/dev/null | grep -q "^i2c_dev"; then
            echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
            print_info "已配置开机加载 i2c-dev"
        fi
    fi

    mark_done "setup_desktop_tweaks"
    log "Desktop tweaks applied"
}

# 蓝牙服务自检：单元 enabled ≠ 单元正在跑。
#
# bluez 的 unit 带 `ConditionPathIsDirectory=/sys/class/bluetooth` 且**没有** `Restart=`。
# 内核模块（btusb 等）还没加载时该目录不存在，systemd 会直接跳过启动，而
# `systemctl enable --now` 依然返回 0 —— 于是安装器打印「Enabled bluetooth」，
# 实际没有任何守护进程。之后打开 blueman 就会看到「蓝牙守护进程没有运行」。
#
# 这里只负责如实记账，补救提示交给完成页（99-completion.sh）。
_bluetooth_selfcheck() {
    BT_SELFCHECK_FAILED=false
    systemctl list-unit-files 2>/dev/null | grep -q "^bluetooth.service" || return 0

    if systemctl is-active --quiet bluetooth.service; then
        print_ok "Bluetooth daemon running"
        return 0
    fi

    BT_SELFCHECK_FAILED=true
    print_warn "蓝牙已启用但未运行（内核模块可能晚于服务加载），重启后仍不行就手动重启一次服务"
    log "bluetooth.service enabled but not active"
}

# ==============================================================================
# docker：只在装了之后收尾
# ==============================================================================
# docker 在可选清单里，安装器不主动装。但装完不 enable 就不会开机自启，
# 不把用户加进 docker 组则每条命令都要 sudo —— 等于装了个不能用。
# 两步都幂等，所以放在 enable_services 的 is_done 之前：后补装 docker 再重跑也能补上。
_docker_setup() {
    command -v docker >/dev/null 2>&1 || return 0

    if sudo systemctl enable docker.service >> "$LOG_FILE" 2>&1; then
        print_ok "Enabled docker"
    else
        print_warn "Failed to enable docker"
    fi

    if ! systemctl is-active --quiet docker.service; then
        sudo systemctl start docker.service >> "$LOG_FILE" 2>&1 || true
    fi

    if id -nG "$TARGET_USER" 2>/dev/null | grep -qw docker; then
        return 0
    fi

    if sudo usermod -aG docker "$TARGET_USER" >> "$LOG_FILE" 2>&1; then
        print_info "$TARGET_USER 已加入 docker 组（重新登录后免 sudo）"
    else
        print_warn "Failed to add $TARGET_USER to docker group"
    fi
}

enable_services() {
    section "Phase 9" "System Services"

    _docker_setup

    if is_done "enable_services"; then
        print_skip "Services enabled (already done)"
        _bluetooth_selfcheck
        return
    fi

    local services=("NetworkManager" "bluetooth")

    local service unit
    for service in "${services[@]}"; do
        unit="$service.service"
        systemctl list-unit-files 2>/dev/null | grep -q "^$unit" || continue

        # 拆成 enable + start 两步，不用 `enable --now`：
        # ConditionPathIsDirectory 不满足时启动会被 systemd 静默跳过，但 `enable --now`
        # 仍返回 0，失败会被掩盖成成功（详见 _bluetooth_selfcheck 的注释）。
        if ! sudo systemctl enable "$unit" >> "$LOG_FILE" 2>&1; then
            print_warn "Failed to enable $service"
            continue
        fi
        if ! systemctl is-active --quiet "$unit"; then
            sudo systemctl start "$unit" >> "$LOG_FILE" 2>&1 || true
        fi

        if systemctl is-active --quiet "$unit"; then
            print_ok "Enabled $service"
        else
            print_warn "Enabled $service（已设为开机自启）"
        fi
    done

    # 电源配置服务：DMS 的电源小部件通过它切换「性能 / 平衡 / 省电」
    if systemctl list-unit-files 2>/dev/null | grep -q "^power-profiles-daemon.service"; then
        if sudo systemctl enable --now power-profiles-daemon.service >> "$LOG_FILE" 2>&1; then
            print_ok "Enabled power-profiles-daemon"
        else
            print_warn "Failed to enable power-profiles-daemon"
        fi
    fi

    mark_done "enable_services"
    _bluetooth_selfcheck
    log "Services enabled"
}

# ==============================================================================
# 登录管理器：greetd + dux-greeter
# ==============================================================================
# dux-greeter 是 DMS 官方的 greetd 前端（AUR dux-greeter-bin，提供 dms-greeter 命令），
# 登录界面的风格与桌面一致。它自己会写 /etc/greetd/config.toml 并处理会话启动，
# 所以安装器负责：装包、调它自己的 install、补齐 seatd 授权、把 greetd 设为开机自启。
#
# ★ seatd 是必须的一步，不是可选项 —— 漏了它，全新机器装完必然是一块黑屏：
#   niri 通过 libseat 取 DRM 设备，libseat 的后端顺序是
#       seatd socket → logind → builtin
#   greeter 会话的 class 是 `greeter`，logind 的 TakeDevice 会回
#       "You are not in control of this session"
#   （controller 是 greetd 的 session worker，不是 greeter 进程），于是 libseat 退到
#   builtin 后端自己去 open("/dev/dri/card0")；此时设备上若已有 master，
#   drmSetMaster 直接返回 EBUSY，smithay 打一行
#       WARN Unable to become drm master, assuming unprivileged mode
#   就永久降级：只渲染到离屏 buffer、从不 page flip。quickshell 画得完全正常，
#   屏幕上却什么都没有。niri 只在启动时试一次，失败后不会重试，VT 切换也救不回来。
#   dux-greeter 自己只把 greeter 塞进 video 组（能 open 设备），并没有解决 master 归属。
#
# 两个刻意的选择：
#   1. 只 enable 不 start —— 安装过程中 start 会把当前图形会话当场踢掉。
#   2. 顺手 disable 掉其它显示管理器（sddm / gdm / lightdm / ly）。
#      两条 DM 同时 enabled 会抢 tty，开机会互相踢。
GREETER_SELFCHECK_FAILED=false

setup_greeter() {
    section "Phase 9b" "Display Manager (greetd + dux-greeter)"

    if is_done "setup_greeter"; then
        print_skip "Greeter setup (already done)"
        return
    fi

    echo ""
    echo -e "   ${WHITE}greetd + dux-greeter 是图形登录界面，风格与 DMS 一致${NC}"
    echo -e "   ${DIM}不装的话需要登录 TTY 后手动执行 niri-session${NC}"
    echo ""

    if ! confirm "Install and configure greetd + dux-greeter?"; then
        print_skip "Greeter installation (user declined)"
        mark_done "setup_greeter"
        return
    fi

    # ---- 1. greetd 本体（官方仓库）----
    if pacman -Q greetd >/dev/null 2>&1; then
        print_ok "greetd 已安装"
    else
        print_info "Installing greetd..."
        sudo pacman -S --needed --noconfirm greetd >> "$LOG_FILE" 2>&1 \
            || print_warn "greetd 安装失败（看日志）"
    fi

    # ---- 2. dux-greeter（AUR）----
    if command_exists dms-greeter; then
        print_ok "dms-greeter 已安装"
    elif [[ -n "$AUR_HELPER" ]]; then
        print_info "Installing dux-greeter-bin (AUR)..."
        local aur_cmd=($AUR_HELPER -S --needed --noconfirm)
        [[ "$AUR_HELPER" == "paru" ]] && aur_cmd=($AUR_HELPER -S --needed --skipreview --noconfirm)
        "${aur_cmd[@]}" dux-greeter-bin >> "$LOG_FILE" 2>&1 \
            || print_warn "dux-greeter-bin 安装失败（看日志）"
    fi

    if ! command_exists dms-greeter; then
        print_fail "找不到 dms-greeter，跳过登录界面配置"
        print_info "登录后手动补装：paru -S --needed dux-greeter-bin && sudo dms-greeter install"
        return 0
    fi

    # ---- 3. 部署 greetd 配置 ----
    # dms-greeter install 会问几个问题，--yes 走默认值；< /dev/null 防止它卡在读 stdin。
    # 提权前缀用环境变量 DMS_PRIVESC 指定，和上游安装脚本一致。
    if exe "DMS_PRIVESC=sudo dms-greeter install --yes < /dev/null"; then
        print_ok "dux-greeter 配置已部署"
    else
        print_warn "dms-greeter install 失败，可登录后手动执行：sudo dms-greeter install"
    fi

    # ---- 4. seatd：greeter 会话的 DRM 授权通道（漏了它 = 登录界面黑屏）----
    # seatd 是 niri 的仓库依赖，装 niri 时会被带上，但 systemd 不会替你 enable。
    # 两件事缺一不可：服务起来 + greeter 进 seat 组（socket 是 root:seat 0770）。
    # 必须在第 3 步之后：greeter 用户是 dms-greeter install 创建的。
    if ! pacman -Q seatd >/dev/null 2>&1; then
        print_info "Installing seatd..."
        sudo pacman -S --needed --noconfirm seatd >> "$LOG_FILE" 2>&1 \
            || print_warn "seatd 安装失败（看日志）"
    fi

    if systemctl is-enabled seatd >/dev/null 2>&1; then
        print_ok "seatd 已设为开机自启"
    elif sudo systemctl enable seatd >> "$LOG_FILE" 2>&1; then
        print_ok "seatd 已设为开机自启"
    else
        print_warn "seatd 设置自启失败"
        log "seatd enable FAILED"
    fi

    if id -u greeter >/dev/null 2>&1; then
        if id -nG greeter | tr ' ' '\n' | grep -qx seat; then
            print_ok "greeter 已在 seat 组"
        elif sudo usermod -aG seat greeter >> "$LOG_FILE" 2>&1; then
            print_ok "greeter 已加入 seat 组"
        else
            print_warn "greeter 加入 seat 组失败"
            log "usermod -aG seat greeter FAILED"
        fi
    else
        print_warn "找不到 greeter 用户（dms-greeter install 可能没成功）"
    fi

    # 排序保险：niri 的 libseat 只在启动时探一次 socket，seatd 晚一步就退回 builtin，
    # 再撞上 EBUSY 就永久降级。drop-in 让 greetd 拉起并排在 seatd 之后。
    local seat_dropin=/etc/systemd/system/greetd.service.d/seatd.conf
    if [[ ! -f "$seat_dropin" ]]; then
        if sudo mkdir -p "$(dirname "$seat_dropin")" \
            && printf '[Unit]\n# seatd 提供 greeter 会话的 DRM 设备授权，必须比 greeter 先就绪\nAfter=seatd.service\nWants=seatd.service\n' \
                | sudo tee "$seat_dropin" >/dev/null; then
            sudo systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
            print_ok "greetd 已声明依赖 seatd（After/Wants）"
        else
            print_warn "写 greetd drop-in 失败（不影响 seatd 本身，只是少了启动顺序保险）"
        fi
    fi

    # ---- 5. 让位给 greetd ----
    local dm
    for dm in sddm gdm lightdm ly; do
        if systemctl is-enabled "$dm" >/dev/null 2>&1; then
            sudo systemctl disable "$dm" >> "$LOG_FILE" 2>&1 \
                && print_ok "已停用旧的显示管理器：$dm" \
                || print_warn "停用 $dm 失败"
        fi
    done

    if sudo systemctl enable greetd >> "$LOG_FILE" 2>&1; then
        print_ok "greetd 已设为开机自启"
    else
        print_fail "greetd 设置自启失败"
        log "greetd enable FAILED"
    fi

    # ---- 6. 自检 ----
    local check_failed=0
    if ! systemctl is-enabled greetd >/dev/null 2>&1; then
        print_warn "自检：greetd 未设为开机自启"
        check_failed=1
    fi
    if [[ ! -f /etc/greetd/config.toml ]]; then
        print_warn "自检：没有 /etc/greetd/config.toml"
        check_failed=1
    fi
    if ! command_exists dms-greeter; then
        print_warn "自检：dms-greeter 命令不存在"
        check_failed=1
    fi
    # 这两条是黑屏的直接判据：缺任一条，niri 开机必然拿不到 DRM master，
    # 表现是登录界面「有画面但显示器全黑」，SSH 进去 grim 截图却完全正常。
    if ! systemctl is-enabled seatd >/dev/null 2>&1; then
        print_warn "自检：seatd 未设为开机自启（niri 会拿不到 DRM master，登录界面黑屏）"
        check_failed=1
    fi
    if id -u greeter >/dev/null 2>&1 \
        && ! id -nG greeter | tr ' ' '\n' | grep -qx seat; then
        print_warn "自检：greeter 不在 seat 组（连不上 seatd，会退回 builtin 后端）"
        check_failed=1
    fi

    if (( check_failed > 0 )); then
        GREETER_SELFCHECK_FAILED=true
        print_warn "Greeter 自检未全通过，不标记本阶段完成；修好后重跑安装器即可"
        log "Greeter self-check FAILED"
        return 0
    fi

    print_ok "Greeter 自检通过（greetd / config.toml / dms-greeter / seatd / seat 组）"
    log "Greeter self-check passed"
    mark_done "setup_greeter"
    log "Greeter configured"
}


setup_user_dirs() {
    section "Phase 10" "User Directories"

    if is_done "setup_user_dirs"; then
        print_skip "User directories (already done)"
        return
    fi

    local dirs=(
        "$HOME/.local/bin"
        "$HOME/.local/share"
        "$HOME/.cache"
        "$HOME/Pictures/Screenshots"
        "$HOME/Pictures/Wallpapers"
        "$HOME/Videos/Recordings"
        "$HOME/Templates"
    )

    local dir
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done

    # niri 右键"新建"菜单需要的模板
    touch "$HOME/Templates/new"
    printf '#!/bin/bash\n' > "$HOME/Templates/new.sh"
    chmod +x "$HOME/Templates/new.sh"

    print_ok "Directories created"
    mark_done "setup_user_dirs"
    log "User directories created"
}
