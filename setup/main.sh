#!/bin/bash
# Pullautumn DMS Dotfiles Installer v1.0 (modular)
# 框架沿用 pullautumn（Phase 编排 / 包组 / stow / 补装清单），桌面壳换成 DMS。
#
# 目标系统：刚装好的 Arch Linux（Btrfs 根分区 + GRUB；archinstall 或手动安装均可）
# 运行方式：普通用户执行 ./install.sh（脚本内部按需 sudo）

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SETUP_DIR="$ROOT_DIR/setup"

source "$SETUP_DIR/lib/config.sh"
source "$SETUP_DIR/lib/ui.sh"
source "$SETUP_DIR/lib/exec.sh"
source "$SETUP_DIR/lib/state.sh"
source "$SETUP_DIR/lib/flatpak.sh"
source "$SETUP_DIR/lib/network.sh"

for step in "$SETUP_DIR/steps/"*.sh; do
    source "$step"
done

trap cleanup EXIT

show_help() {
    cat << EOF
Pullautumn DMS Dotfiles Installer v1.0

Usage: ./install.sh [options]

Options:
    --minimal     Install core packages only (skip optional groups & flatpak)
    --no-stow     Skip config deployment
    --no-greeter  Skip greetd + dux-greeter deployment (keep current display manager)
    --yes         Answer yes to every prompt (unattended runs)
    --no-reboot   Do not reboot automatically when finished
    --reset       Clear progress and start fresh
    --help        Show this help

Examples:
    ./install.sh                 # Full installation
    ./install.sh --no-greeter    # Install desktop but keep existing DM
    ./install.sh --minimal       # Minimal installation
    ./install.sh --reset         # Clear progress, start fresh

EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --minimal)
                INSTALL_MINIMAL=true
                shift
                ;;
            --no-stow)
                SKIP_STOW=true
                shift
                ;;
            --no-greeter)
                SKIP_GREETER=true
                shift
                ;;
            --yes|-y)
                ASSUME_YES=true
                shift
                ;;
            --no-reboot)
                NO_REBOOT=true
                shift
                ;;
            --reset)
                rm -f "$STATE_FILE"
                echo "Progress cleared."
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

main() {
    echo "Pullautumn Dotfiles Installation Log - $(date)" > "$LOG_FILE"

    parse_args "$@"

    show_banner
    sys_dashboard

    if ! confirm "Start installation?"; then
        print_info "Cancelled"
        exit 0
    fi

    [[ ! -f "$STATE_FILE" ]] && touch "$STATE_FILE"

    # --- 基础环境 ---
    check_system
    install_base
    # 装包之前先立回滚点：后面 Phase 4 起成批装包，坏了要能退回这里
    setup_btrfs_snapshots
    install_aur_helper
    clone_dotfiles

    # --- 软件包 ---
    install_packages
    install_optional_packages

    # --- 配置部署（stow）---
    apply_dotfiles

    # --- 各应用配置 ---
    # zsh 之外只有 mpv 需要额外动作：Anime4K 着色器 56 MB，仓库里不放，
    # 在这里按需下载。nvim 的 lazy.nvim 与 mason 都是首次启动自举，没有 Phase。
    setup_zsh
    setup_mpv_shaders

    # --- 系统集成 ---
    setup_locale
    setup_bash_path
    setup_local_bin
    setup_dms
    setup_matugen
    setup_desktop_tweaks
    enable_services
    if $SKIP_GREETER; then
        print_skip "Greeter (--no-greeter)"
    else
        setup_greeter
    fi
    setup_user_dirs

    show_completion
}

main "$@"
