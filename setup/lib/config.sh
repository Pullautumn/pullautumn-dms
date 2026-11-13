# shellcheck shell=bash

# ==============================================================================
# Colors & Styles
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# ==============================================================================
# Configuration
# ==============================================================================
DOTFILES_REPO="https://github.com/Pullautumn/dotfiles"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pullautumn"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
STATE_FILE="$HOME/.pullautumn_install_progress"

# 装失败的包会落盘成一份可直接复制粘贴的清单（重启后照着补装）
PENDING_LIST_FILE="$HOME/pullautumn-missing-packages.txt"
declare -ga FAILED_PACKAGES=()   # 逐包安装时失败的包名
declare -ga MISSING_PACKAGES=()  # 末尾 pacman -T 核对出的缺失包名（包组已展开）

# Install options
INSTALL_MINIMAL=false
SKIP_STOW=false
ASSUME_YES=false
NO_REBOOT=false
AUR_HELPER=""

# 脚本以普通用户身份运行，内部通过 sudo 提权
TARGET_USER="$(id -un)"
TARGET_HOME="$HOME"

# 允许安装器跳过 greetd / dux-greeter 的部署（已有显示管理器时有用）
SKIP_GREETER=false

# 壁纸只有仓库作者本人用（图片不进 git，~50 MB）。
# WALLPAPER_OWNER: 用户名，只有它安装时才会链接/拉取壁纸；其他人直接跳过。
# WALLPAPERS_REPO: 可选，作者换机器时用来把壁纸 clone 回来（留空则只认本地已有的图）。
WALLPAPER_OWNER="${WALLPAPER_OWNER:-pullautumn}"
WALLPAPERS_REPO="${WALLPAPERS_REPO:-}"

# mpv 的 Anime4K 着色器（~56 MB）来源，安装时按需 clone 到 ~/.config/mpv/shaders/
ANIME4K_REPO="https://github.com/bloc97/Anime4K"
# setup_mpv_shaders 真正装成后置 true，完成页据此决定要不要提 Ctrl+1..6
MPV_SHADERS_OK=false

# ==============================================================================
# Stow Packages
# ==============================================================================
# 顶层目录即 stow 包。以下几个不是包：
#   setup/      安装器本体
#   wallpaper/  只放 README，图由 _dotfiles_link_wallpapers 单独处理
#
# `uv` 是**条件包**，不在下面的数组里，见数组之后的追加逻辑。
#
# 与 pullautumn 主仓库相比，这里没有 waybar / waybar-niri-Win11Like /
# waybar-quickshell / quickshell / swaync / mako / rofi / wlogout / waypaper /
# systemd（通知单元）—— 这些角色全部由 DMS 一个进程接管。
#
# 也没有 yazi / obs-studio / 各 IDE 的 .desktop：那几套纯粹是个人配置，跟桌面壳无关。
# nvim / mpv 的配置在仓库里（23 包里有），但只放配置、不放二进制资源 ——
# mpv 的 Anime4K 着色器 56 MB，由 setup_mpv_shaders 在安装时按需下载。
# 壁纸同样不进 git，见 WALLPAPER_OWNER。
STOW_PACKAGES=(
    niri
    fuzzel
    kitty starship zsh zshenv
    Thunar btop fastfetch
    nvim mpv
    fcitx5 fontconfig environment.d gtk-3.0 mimeapps
    matugen scripts local-bin
    satty
    xdg-desktop-portal
    local-share-fcitx5
    # DMS 自己的设置（状态栏 / dock / 启动器 / 锁屏 / 空闲策略）。包会折叠成
    # ~/.config/dms -> 仓库/dms/.config/dms 的**目录**软链，这是必须的：
    # DMS 用 QSaveFile 原子写 settings.json，rename 到文件软链上会把链接替换成
    # 普通文件，第一次改设置就静默脱钩。目录软链没有这个问题（写的是仓库里的真文件）。
    # 副作用是「改设置 = 改仓库」，gitignore 里用白名单只放行三份文件。
    dms
)

# uv 的 PyPI 镜像源只在作者机器上链接，理由和 WALLPAPER_OWNER 一样：
# 清华源跟地理位置绑定，对海外用户是减分项，而 stow 是整包链接 —— 放进上面的主列表，
# 等于给每个 clone 这份 dotfiles 的人都塞一个国内源。
# 放在数组**之后**追加而不是加条件判断包体，是因为 stow 只认目录，没法在包里设开关。
if [[ "${TARGET_USER,,}" == "${WALLPAPER_OWNER,,}" ]]; then
    STOW_PACKAGES+=(uv)
fi

# ==============================================================================
# Package Groups (仓库包，用 paru/pacman 静默安装)
# ==============================================================================
declare -A PKG_GROUPS

# fuzzel 不只是配置包：它是 Mod+A 启动器的兜底，也是 shorin-screenrec-menu 的菜单后端
# （脚本按 fuzzel → wofi → rofi → bemenu 找，一个都没有就 `none`，表现为「按了没反应」）。
# DMS 用自家的 spotlight，不会把 fuzzel 带进来，必须显式列上。
PKG_GROUPS[wm]="niri xwayland-satellite fuzzel"
PKG_GROUPS[portal]="xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome"
# 桌面壳。dux-shell 在官方 extra（2.1.x，provides dms-shell），二进制叫 dms；
# dux-gop 是它的进程/资源监控后端（processlist 小组件要用）。
# quickshell 是 dux-shell 的硬依赖，会随之装上，不在这里重复列。
# geoclue：天气小组件的定位（settings.json 里 useAutoLocation=true）走 dms 的
# geolocation 客户端，它先试 GeoClue2、失败才退回 IP —— 而 IP 兜底是明文请求
# http://ip-api.com/json/（境外 + 限流，国内经常拿不到）。装了 geoclue 至少多一条路。
# 注意：GeoClue2 在 Arch 上需要 agent 授权才返回 fix，没有 agent 时仍会静默退回 IP。
PKG_GROUPS[dms]="dux-shell dux-gop geoclue"
# 截图：satty 负责标注（配置在 satty/ 包），gpu-screen-recorder 是录屏首选后端
# （shorin-screenrec-menu 会按 gpu-screen-recorder → wl-screenrec → wf-recorder 顺序降级）
PKG_GROUPS[screenshot]="grim slurp satty wayfreeze wf-recorder imv ffmpeg gpu-screen-recorder"
# 剪贴板：DMS 的 clipboard 面板读 cliphist 的库，不需要 cliphist-tui
PKG_GROUPS[clipboard]="cliphist wl-clipboard"
PKG_GROUPS[terminal]="kitty starship xdg-terminal-exec"
PKG_GROUPS[shell]="zsh atuin zoxide fzf thefuck fnm"
# nautilus-python（官方仓库，provides python-nautilus）：Nautilus 43 之后原生「在终端中打开」
# 不可配置，靠它加载 nautilus-open-any-terminal（AUR，见 AUR_PACKAGES）补一个可指定终端的右键项。
PKG_GROUPS[files]="thunar thunar-volman thunar-archive-plugin tumbler nautilus gnome-text-editor gvfs gvfs-mtp gvfs-smb ffmpegthumbnailer poppler-glib file-roller webp-pixbuf-loader gnome-keyring nautilus-python"
PKG_GROUPS[input]="fcitx5 fcitx5-im fcitx5-chinese-addons fcitx5-rime rime-ice-git"
# DMS 的可选依赖里 cava 做音频可视化、qt6-multimedia 做音效、
# cups-pk-helper 做打印机、i2c-tools 管外接显示器亮度、wtype 负责「从剪贴板历史粘贴」
# sound-theme-freedesktop 提供截图音效用的 camera-shutter.oga
PKG_GROUPS[audio]="pipewire wireplumber pipewire-pulse pipewire-alsa pavucontrol playerctl cava qt6-multimedia sound-theme-freedesktop"
PKG_GROUPS[network]="networkmanager network-manager-applet nm-connection-editor bluez bluez-utils blueman"
PKG_GROUPS[cli]="ripgrep fd bat eza jq libnotify curl wget unzip bc duf fastfetch prettyping pacman-contrib unarchiver lazygit lazydocker btop wtype imagemagick file"
PKG_GROUPS[fonts]="noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation otf-font-awesome ttf-jetbrains-mono-nerd ttf-cascadia-code-nerd"
# 编辑器：neovim 本体 + treesitter 编译链。LSP / 格式化工具（pyright、stylua、
# black、shellcheck…）由 mason 在首次启动时自己装，不需要在这里列。
PKG_GROUPS[dev]="python python-pip nodejs npm neovim tree-sitter-cli clang"
PKG_GROUPS[media]="mpv yazi"
PKG_GROUPS[power]="brightnessctl power-profiles-daemon i2c-tools cups-pk-helper"
PKG_GROUPS[browser]="google-chrome firefox"
PKG_GROUPS[theme]="adw-gtk-theme qt6ct"

PKG_GROUP_NAMES=(
    "wm:窗口管理器 (niri/fuzzel)"
    "portal:桌面门户 (xdg-desktop-portal)"
    "dms:桌面壳 (dux-shell)"
    "screenshot:截图与录屏 (satty/screenrec-menu)"
    "clipboard:剪贴板 (cliphist，面板由 DMS 提供)"
    "terminal:终端与提示符 (kitty/starship)"
    "shell:Shell 增强 (zsh/atuin/zoxide)"
    "files:文件管理与文本编辑 (thunar/nautilus)"
    "input:输入法 (fcitx5)"
    "audio:音频 (pipewire/cava)"
    "network:网络与蓝牙"
    "cli:命令行工具"
    "fonts:字体"
    "dev:开发环境 (python/nodejs/neovim)"
    "media:播放器与文件管理 (mpv/yazi)"
    "power:电源模式与亮度"
    "browser:浏览器"
    "theme:GTK/Qt 主题"
)

# ==============================================================================
# AUR Packages (配置依赖，必须安装)
# ==============================================================================
# 注：matugen 已在官方仓库，这里一并交给 paru 处理（repo 包也装得了）。
AUR_PACKAGES=(
    matugen
    python-pywalfox
    ttf-jetbrains-maple-mono-nf-xx-xx
    ttf-lxgw-wenkai-screen
    niri-sidebar-git
    wl-screenrec-git
    # 录屏菜单（fuzzel 菜单 + 区域高亮框，后端自动降级），Mod+F6 调用
    shorin-screenrec-menu-git
    # 截图标注（Qt6 单体：自带抓屏/选区/标注/OCR/贴图/滚动长截图/录屏），Mod+Shift+P 调用。
    # 与 satty 并存而不是替换：satty 走 Alt+Ctrl+S 的轻量涂抹，mark-shot 负责 OCR、
    # 贴图、长截图这类重活。它依赖 layer-shell-qt 和 ffmpeg 的 libav*，前者由 paru 带入。
    mark-shot
    # zsh 语法高亮，由 zsh-vi-mode 的 zvm_after_init 钩子调用（见 zsh/plugins.zsh）
    zsh-patina
    # Nautilus 右键「在终端中打开」的菜单项提供者（需要 PKG_GROUPS[files] 里的 nautilus-python）。
    nautilus-open-any-terminal
    # DMS 的搜索后端：提供 dsearch 命令，niri autostart 里 `dsearch serve`
    dux-search-bin
    # DMS 风格的 greetd 登录界面：提供 dms-greeter 命令
    dux-greeter-bin
)

# ==============================================================================
# 可选软件清单
# ==============================================================================
# 安装器在「可选软件」阶段读取这个文件，用 fzf 让你多选，再按包名前缀分类：
#   AUR:包名      → 通过 AUR helper 安装
#   flatpak:包名  → 通过 flatpak 安装
#   包名          → 通过 pacman/paru 从官方仓库安装
# 改清单只改这个文件，不用动脚本。
COMMON_APPLIST="${SETUP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/common-applist.txt"
