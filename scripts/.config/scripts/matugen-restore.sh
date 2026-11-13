#!/usr/bin/env bash

# ==============================================================================
# Matugen 系统全方位还原脚本 (包含图标缓存深度清理)
#
# 与 pullautumn 主仓库的区别：
#   本项目的桌面壳是 DMS（dux-shell），它自己会跑 matugen 并写：
#     ~/.config/niri/dms/colors.kdl      niri 边框色
#     ~/.config/kitty/dank-theme.conf    kitty 配色
#     ~/.config/gtk-3.0|gtk-4.0/dank-colors.css
#     ~/.config/qt5ct|qt6ct/colors/matugen.conf
#   所以下面不再「还原」这些文件（DMS 一手管到底），只处理 DMS 不管的：
#   btop / fastfetch / fuzzel / fcitx5 / 图标缓存 / 图标 gsettings。
#   唯一例外是 kitty：它的 dank-theme.conf 在 colors.conf 之后加载，是盖在默认色上面
#   的覆盖层，不处理的话「还原」之后终端还是壁纸色 —— 见下文 kitty 那段。
#   完整模式**不改变明暗**。DMS 的明暗是「手动 / 定时 / 按位置 / 跟随壁纸」四选一
#   （ThemeScheduleTab.qml:24），改任何一档都要动 matugenSmartMode 并触发一次全量
#   重新生成，而那次生成会把本脚本刚写的文件覆盖掉。所以这里只做两件事：等 DMS 的
#   matugen 队列空闲，然后写文件；明暗完全交给 DMS 按它自己的设置决定。
# ==============================================================================

CUSTOM_DIR="$HOME/.config/matugen/custom"

# 每一项是 "自定义目录下的相对路径"，默认还原到 ~/.config/<第一段>/<其余部分>。
# 写成 "源相对路径:.目标相对路径" 时，目标相对路径按 $HOME 展开 ——
# fcitx5 的主题不在 ~/.config 下，必须用这种写法。
RESTORE_LIST=(
    "btop/themes/matugen.theme"
    "fastfetch/config.jsonc"
    "fuzzel/colors.ini"
    "fcitx5/theme.conf:.local/share/fcitx5/themes/Matugen/theme.conf"
)

# --configs-only：安装器首次部署时用。
# 只做 Step 1（把上面这些文件还原成默认配色），跳过图标清理 / 服务刷新 ——
# 那几段里有 sed -i 直接改 ~/.config 下的文件，而 stow 已经把目录折叠成软链，
# 改它等于改写仓库；安装阶段也没有桌面会话可刷新。
# fcitx5 的配色文件本身在 Step 1 里就会落盘，被跳过的只是「重载 classicui」那一步。
CONFIGS_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --configs-only) CONFIGS_ONLY=true ;;
        -h|--help)
            echo "用法: matugen-restore.sh [--configs-only]"
            echo "  --configs-only  只还原配色文件（含 fcitx5），跳过图标清理、GSettings 与服务刷新"
            exit 0
            ;;
    esac
done

# 检测语言环境
if env | grep -q "zh_CN"; then IS_CN=true; else IS_CN=false; fi

function notify() {
    if [ "$IS_CN" = true ]; then
        notify-send "Matugen 还原" "$1"
    else
        notify-send "Matugen Restore" "$2"
    fi
}

if [ "$CONFIGS_ONLY" = false ]; then
    notify "正在启动深度还原程序..." "Starting deep restoration..."
fi

# ------------------------------------------------------------------------------
# [零] 等 DMS 的 matugen 队列空闲（仅完整模式）
# ------------------------------------------------------------------------------
# 本段只读不写：不切明暗、不碰 gsettings、不调 settings set。
# 旧版本在这里「切亮 → 写回 matugenSmartMode」，代价是两次全量生成：
#   · theme light 会硬关 matugenSmartMode（Theme.qml:1467，没有参数能跳过）；
#   · 写回 true 时该键的 onChange=regenSystemThemes 又生成一次，
#     且深色壁纸下会把明暗判回 dark，表现为「暗→亮→暗」闪一下。
# 两次生成意味着 gtk/qt/niri/kitty 被重写两遍、recoloricons.sh 被拉起两遍。
# 现在改成等队列空闲就直接写文件，明暗由 DMS 自己的模式设置决定。
#
# 用 matugen.status IPC（返回 {"running":..,"pending":..}）判断，不用 pgrep：
# DMS 的 matugen 是 dux 二进制的子命令，进程名不叫 matugen，抓不到。
if [ "$CONFIGS_ONLY" = false ]; then
    echo "Step 0: Waiting for DMS matugen queue to settle..."

    if command -v dms >/dev/null 2>&1 && dms ipc call matugen status >/dev/null 2>&1; then
        # 最多等 20 秒（40 × 0.5s）：正在跑的生成和排队中的请求都算忙
        for _ in $(seq 1 40); do
            mt_status=$(dms ipc call matugen status 2>/dev/null)
            if echo "$mt_status" | grep -qE \
                '"running"[[:space:]]*:[[:space:]]*true|"pending"[[:space:]]*:[[:space:]]*true'; then
                sleep 0.5
            else
                break
            fi
        done
        echo "  - DMS matugen 空闲"
    else
        # 老版本没有 matugen.status：给一次生成留个缓冲，不做精确等待
        sleep 2
        echo "  - 无 matugen.status IPC，固定等待 2s"
    fi
    echo
fi

# ------------------------------------------------------------------------------
# [一] 还原物理配置文件
# ------------------------------------------------------------------------------
echo "Step 1: Restoring configuration files..."
for entry in "${RESTORE_LIST[@]}"; do
    rel_path="${entry%%:*}"
    dest_rel="${entry#*:}"
    src_file="$CUSTOM_DIR/$rel_path"
    [ -f "$src_file" ] || continue

    if [ "$dest_rel" = "$entry" ]; then
        # 没写目标：按 ~/.config/<包里第一层目录>/<其余路径> 还原
        first_dir=$(echo "$rel_path" | cut -d'/' -f1)
        rest_path=$(echo "$rel_path" | cut -d'/' -f2-)
        dest="$HOME/.config/$first_dir/$rest_path"
    else
        # 写了目标：冒号后面按 $HOME 展开
        dest="$HOME/$dest_rel"
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$src_file" "$dest"
    echo "  - Restored: $dest"
done

# ------------------------------------------------------------------------------
# kitty：把 DMS 生成的覆盖层改回默认色
# ------------------------------------------------------------------------------
# kitty 的颜色有两层，后加载的盖前面的：
#   colors.conf        仓库跟踪，Catppuccin Mocha（默认深色）
#   dank-theme.conf    DMS 换壁纸时生成，在 colors.conf 之后 include
# 所以只还原 colors.conf 是无效的 —— 它还停在 Mocha，但 DMS 那份壁纸色压在上面。
# 这里把 dank-theme.conf 覆盖成 colors.conf 的内容（= 仓库默认色），
# dank-tabs.conf 写成空注释（标签栏回落到由背景/前景派生）。
# 两个文件都在 .gitignore 里、是运行时产物，写它们不会弄脏仓库；
# 下次在 DMS 里换壁纸时，DMS 会重新生成这两份，属于预期行为。
# 必须放在 [零] 之后：等 DMS 的生成队列空闲之后再写，否则那次生成会盖掉这两份。
KITTY_DIR="$HOME/.config/kitty"
if [ -f "$KITTY_DIR/colors.conf" ]; then
    cp "$KITTY_DIR/colors.conf" "$KITTY_DIR/dank-theme.conf"
    printf '# 已还原为仓库默认配色；在 DMS 里换壁纸时会被重新生成。\n' \
        > "$KITTY_DIR/dank-tabs.conf"
    echo "  - Restored: $KITTY_DIR/dank-theme.conf (= colors.conf)"
fi

# niri 的配色（niri/dms/colors.kdl）不在这里还原：窗口边框色归 DMS 管，
# 且该文件带 AUTO-GENERATED 头，DMS 面板随时会重写。想回默认色就在 DMS 里重新应用主题。

if [ "$CONFIGS_ONLY" = true ]; then
    echo "Done (--configs-only): 配色已还原为默认值"
    exit 0
fi

# ------------------------------------------------------------------------------
# [二] 深度清理图标主题 (解决 GTK 顽固样式问题)
# ------------------------------------------------------------------------------
echo "Step 2: Cleaning up icon themes and caches..."

# 1. 删掉 Adwaita-Matugen-A/B 目录、撤销 Flatpak 的 ICON_THEME 覆盖 —— 这两件事
#    **不能在这里做**，挪到最后的 Step 6 了。原因：
#    DMS 的图标重着色是我们自己模板 gtk-folder 的 post_hook（`recoloricons.sh &`，
#    带 & 的分离进程，matugen 根本不等待它），它最后一行才
#    `gsettings set ... icon-theme Adwaita-Matugen-A|B`。
#    如果这里先删、它随后落地，gsettings 就会指向一个不存在的主题 —— 图标全部
#    回落到占位图形（文件管理器里一片灰线条），而设置程序里看 gsettings 又是对的。
#    所以顺序必须是：等它停下 → 掐掉 → 写 gsettings=Adwaita → 最后才删目录。

# 2. 不改 gtk-3.0/settings.ini
#    Wayland 下 GTK3 的主题/图标读的是 gsettings，settings.ini 里同名项**被忽略**
#    （Sway wiki 明文），改了也不生效。而 gtk-3.0 是 stow 折叠软链包，
#    `sed -i ~/.config/gtk-3.0/settings.ini` 写的就是仓库里那个文件 —— 会直接把
#    仓库的 gtk-icon-theme-name 改掉、git status 变脏。真正的切换在 Step 6（图标）。

# 3. 刷新图标缓存
if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache -f -q "$HOME/.local/share/icons" 2>/dev/null
fi

# 4. 清理可能存在的缩略图缓存
rm -rf "$HOME/.cache/thumbnails"

# ------------------------------------------------------------------------------
# [四] 让 Fcitx5 重新加载主题
# ------------------------------------------------------------------------------
# 还原态用 fcitx5 自带的 default 主题（浅色），跟 pullautumn 主仓库一致：
# 那边 matugen-update.sh 换壁纸时把 Theme 切成 Matugen，matugen-restore.sh 再切回 default。
# DMS 版没有独立的 update 脚本，DMS 换壁纸时只写 Matugen/theme.conf、不改 classicui，
# 所以这里切回 default 之后，fcitx5 就不再跟壁纸变色了 —— 这是刻意选的「还原态」。
# 想让它重新跟随壁纸：把本行目标改回 Matugen，并把 classicui.conf 的 Theme 也改回 Matugen。
# classicui.conf 是 stow 软链，sed 会写进仓库 —— 但写入值就是仓库里的值，等于幂等；
# 只有当前值真的不对时才动，避免每次还原都产生一次无意义的仓库改动。
FCITX_CONF="$HOME/.config/fcitx5/conf/classicui.conf"
if [ -f "$FCITX_CONF" ]; then
    grep -qx 'Theme=default' "$FCITX_CONF" || sed -i 's/^Theme=.*/Theme=default/' "$FCITX_CONF"
    grep -qx 'DarkTheme=default-dark' "$FCITX_CONF" || sed -i 's/^DarkTheme=.*/DarkTheme=default-dark/' "$FCITX_CONF"
    # 只重载 classicui 插件，不用 fcitx5 -r（它会起第二个实例）
    busctl --user --auto-start=no call org.fcitx.Fcitx5 /controller \
        org.fcitx.Fcitx.Controller1 ReloadAddonConfig s classicui >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# [五] 刷新应用进程
# ------------------------------------------------------------------------------
# DMS 自己的面板/小组件不需要外部信号：它在换壁纸时会收到新的 colors.kdl。
echo "Step 5: Reloading services..."
niri msg action reload-config 2>/dev/null
kill -SIGUSR1 $(pgrep -x kitty) 2>/dev/null
killall -SIGUSR1 btop 2>/dev/null

# ------------------------------------------------------------------------------
# [六] 图标收尾：等重着色停下 → 掐掉 → 写 gsettings → 最后删目录
# ------------------------------------------------------------------------------
# 四步的顺序不能变，也不能提前到 Step 2：
#   我们自己模板 gtk-folder 的 post_hook 是 `bash ~/.cache/matugen/recoloricons.sh &`
#   —— 带 & 的分离进程，matugen 不等待它；而它**最后一行**才
#   `gsettings set ... icon-theme Adwaita-Matugen-A|B`。
#   先删目录再让它落地，gsettings 就指向一个不存在的主题，图标全部回落到占位图形，
#   而设置程序里看 gsettings 又是对的 —— 这就是「第一遍跑完图标全灰、第二遍才好」。
echo "Step 6: Finalizing icon theme..."

# 1. 最多等 15 秒，让已经在跑的重着色自行结束（生成队列到这时通常已空）
for _ in $(seq 1 15); do
    pgrep -f 'recoloricons\.sh' >/dev/null 2>&1 || break
    sleep 1
done

# 2. 还在跑就掐掉：还原不需要重新着色，留着它只会在我们写完之后再改一次
pkill -f 'recoloricons\.sh' 2>/dev/null || true
sleep 1

# 3. 先写 gsettings（对手已经没了，这一步才真正赢）
gsettings set org.gnome.desktop.interface icon-theme "Adwaita" 2>/dev/null || true
#    recolor.sh 会顺手给自己挂 Flatpak 的 ICON_THEME，这里再撤销一次
flatpak override --user --unset-env=ICON_THEME 2>/dev/null || true

# 4. 最后删目录：此时 gsettings 已不指向它们，删除只承担清理职责，不会造成悬空指针
rm -rf "$HOME/.local/share/icons/Adwaita-Matugen-A" \
       "$HOME/.local/share/icons/Adwaita-Matugen-B"
echo "  - icon-theme=Adwaita（Adwaita-Matugen-A/B 已清理）"

notify "还原完成！图标与配置已重置。" "Restore complete! Icons and configs reset."
echo "Done! If GTK icons still look wrong, try logging out and back in."
echo
echo "Note: 本脚本不改变明暗模式（手动 / 定时 / 按位置 / 跟随壁纸）。"
echo "      若还原后不是想要的明暗，到 DMS 设置 → 主题 → 自动控制里改；"
echo "      跟随壁纸时深色壁纸就是深色，那是壁纸亮度判的，不是还原失败。"
