# 安装器说明

`setup/` 是安装器的实现。架构沿用 [jswysnemc/dotfiles](https://github.com/jswysnemc/dotfiles)
的模块化设计，由 pullautumn 移植，桌面壳换成 DMS（dux-shell）。

## 目录结构

```
install.sh              引导层：校验环境 → 定位仓库 → 转交 setup/main.sh
setup/
  main.sh               编排层：解析参数 → 按顺序调用各阶段函数
  lib/
    config.sh           仓库地址、stow 包清单、必需软件包、AUR 包
    ui.sh               banner、section、print_*、confirm、dashboard
    exec.sh             exe / exe_live（带 spinner、写日志）
    state.sh            mark_done / is_done（断点续跑）
    flatpak.sh          按需装 flatpak、加 flathub 源、选国内镜像
    network.sh          GitHub 真实 GET 探测、/etc/hosts 修复（带备份回滚）、gh_clone / gh_retry 下载重试
  steps/
    01-preflight.sh     系统检查、基础工具、paru、定位仓库
    02-packages.sh      必需软件分组安装、AUR、可选软件 fzf 勾选（装包带转圈进度）
    03-dotfiles.sh      备份旧配置、stow 部署、GTK 书签生成
    04-apps.sh          zsh
    05-system.sh        locale、PATH、DMS 初始化、matugen、系统服务、greetd、用户目录
    99-completion.sh    完成提示与重启
  common-applist.txt    可选软件清单：安装时用 fzf 勾选，改这里就能增删
```

## 执行阶段

| 阶段函数 | 所在文件 | 作用 |
|---|---|---|
| `check_system` | 01 | 校验 Arch、非 root、pacman、网络；真实 GET 探测 GitHub 直连（含 Releases 下载域与吞吐记录），不通则用 `/etc/hosts` 修（`lib/network.sh`），写后仍不通自动回滚 |
| `install_base` | 01 | `pacman -Syu`，装 git / stow / base-devel |
| `setup_btrfs_snapshots` | 01 | Phase 1b：根分区是 btrfs 时装 snapper，`create-config` root（`/home` 独立子卷时再加 home）、写策略（每小时 3 个 / 共 10 个）、开两个 timer、打一个 `Before Dotfiles Setup` 基线快照。**不碰引导程序**（不装 grub-btrfs、不跑 `grub-mkconfig`）；失败只 warn，不标记完成 |
| `install_aur_helper` | 01 | 添加 archlinuxcn 源，装 paru |
| `clone_dotfiles` | 01 | 本地运行直接用当前仓库，否则克隆到 `~/.dotfiles` |
| `install_packages` | 02 | 按 `PKG_GROUPS` 分组装必需包（已装的组直接记 OK），再逐包装必需的 AUR 包，全程不询问；失败包名上屏并写 `~/pullautumn-missing-packages.txt`，末尾用 `pacman -T` 复核（包组先展开，避免组名误报） |
| `install_optional_packages` | 02 | 读 `common-applist.txt`，fzf 勾选后按 repo / AUR / flatpak 分类安装（`--yes` 则全装） |
| `apply_dotfiles` | 03 | 备份会被替换的 `~/.config/*`，逐个 `stow -R`，修脚本执行位，生成 GTK 书签，放行 flatpak 主题权限（壁纸只对 `WALLPAPER_OWNER` 链接；其他人先清空仓库里的残留图，再建空目录跳过） |
| `setup_zsh` | 04 | 装 zsh、核对配置就位、把默认 shell 改过去（走 `sudo chsh`，它自己验 PAM 密码） |
| `setup_mpv_shaders` | 04 | Phase 6b：询问后 clone `ANIME4K_REPO`，把 `glsl_4.0/*.glsl` 拷进 `~/.config/mpv/shaders/`，校验 `Ctrl+1..6` 引用的 10 个文件；已有则跳过，失败只 warn |
| `setup_locale` | 05 | `locale.gen` + `locale-gen`，`/etc/locale.conf` |
| `setup_bash_path` | 05 | 给 bash 登录 shell 补 `~/.local/bin` |
| `setup_local_bin` | 05 | `~/.local/bin` 建目录 + 执行位 |
| `setup_dms` | 05 | 确认 `dms` 可执行、`mkdir ~/.config/niri/dms`、只让 DMS 生成 `colors.kdl`（其余 `dms/*.kdl` 由仓库提供）、核对 5 份仓库自带的 kdl 就位、加入 `input` 组、检查 `/etc/pam.d/login` |
| `setup_matugen` | 05 | 首次安装只跑 `matugen-restore.sh --configs-only`，落仓库默认的**深色**配色（Catppuccin Mocha），**不跑 matugen**；写 GNOME 亮色基调（`default` + `adw-gtk3` + `Adwaita`）。**不碰 DMS 的状态文件**：`~/.config/dms/settings.json` 由 stow 包提供，`~/.local/state/dms/session.json`（壁纸 / 明暗 / 显示器布局）由 DMS 自己首启创建 |
| `setup_desktop_tweaks` | 05 | 默认终端（kitty）、Nautilus 右键终端、窗口按钮、i2c 权限 |
| `enable_services` | 05 | NetworkManager / bluetooth / power-profiles-daemon（拆成 enable + start，避免 `--now` 掩盖条件不满足的跳过） |
| `setup_greeter` | 05 | 装 greetd + dux-greeter-bin，`dms-greeter install --yes`，**enable seatd + `greeter` 进 `seat` 组**（缺这条登录界面必黑屏），disable 其它显示管理器，enable greetd，写 greetd 的 `After/Wants=seatd` drop-in，自检 |
| `setup_user_dirs` | 05 | `xdg-user-dirs-update` |
| `show_completion` | 99 | 完成页；写待补装清单；GitHub 镜像收尾；自检失败时保留进度 |

## 断点续跑

每完成一个阶段就 `mark_done <name>` 写进 `~/.pullautumn_install_progress`，
重跑时 `is_done` 直接跳过。`--reset` 清空。

几个刻意的例外：

- `apply_dotfiles` 即使已 done 也会补一次执行位 —— 从 Windows 拷文件、`tar` 不带 `-p`、
  编辑器另存都会丢 `+x`，症状是「快捷键按了没反应」，很难查。
- `setup_dms` / `setup_greeter` 自检没过时**不**标记完成，下次重跑只补这一阶段。
- `setup_btrfs_snapshots` 失败（非 btrfs、snapper 装不上、create-config 报错）只 warn，
  **不**标记完成也不中断安装 —— 快照是附加保险，但下次重跑要能重试。
- `setup_matugen` 是幂等的，重跑会把配色再还原一次默认值。

## 包清单

`lib/config.sh` 里三处：

- `PKG_GROUPS` + `PKG_GROUP_NAMES`：18 组官方仓库包，逐组 `paru -S --needed`
- `AUR_PACKAGES`：配置直接依赖的 AUR 包（matugen、dux-search-bin、dux-greeter-bin 等），
  逐包装、逐包显示进度
- `common-applist.txt`：可选软件，fzf 勾选

`dux-shell` 在官方 extra 仓库（2.1.x，`provides dms-shell`），所以不需要
`shorin-dux-niri-git` 那类 AUR 元包，也不需要 `shorindms init` 分发 dotfiles。

## 与上游（pullautumn）的区别

1. 桌面壳换成 DMS：删掉 `setup_quickshell`、`setup_qs_lock_pam`（DMS 锁屏用 PAM 的 `login`
   service，不需要自建），加 `setup_dms`。
2. 登录管理器从 SDDM + lunar-glass 换成 greetd + dux-greeter（`--no-greeter` 可跳过）。
3. 包组删掉 waybar / swaync / mako / rofi / wlogout / swayidle / swayosd / waypaper，
   加入 dux-shell / dux-gop / dux-search / qt6ct / power-profiles-daemon / wtype 等。
4. stow 包清单 23 个（drop 掉 waybar×3 / quickshell / swaync / mako / rofi / wlogout /
   waypaper / systemd，再砍掉 yazi / obs-studio / local-share-applications 和 IDE 的
   `.desktop`；后来加回 `dms`，即 `~/.config/dms`）。`setup_nvim` / `setup_mpv` /
   `setup_yazi` 三个 Phase 一并删除。
   另有条件包 `uv`：只有 `TARGET_USER` 等于 `WALLPAPER_OWNER` 时才追加进 `STOW_PACKAGES`。
5. **nvim / mpv / 壁纸后来又搬回来了**，但大体积资源不进 git：
   - `neovim` + `tree-sitter-cli` + `clang` 进 `PKG_GROUPS[dev]`；插件与 LSP（pyright、
     stylua、black…）由 lazy.nvim 与 mason 在首次启动时自己装，安装器不跑 `:Lazy sync`。
   - mpv 的配置在仓库里，Anime4K 着色器（56 MB）由 **`setup_mpv_shaders`（Phase 6b）**
     询问后下载 —— 提交进仓库会让每个 clone 的人白付这份体积。
   - 壁纸（50 MB）同理整个 gitignore；`_dotfiles_link_wallpapers` 先比
     `id -un` 与 `WALLPAPER_OWNER`（默认 `pullautumn`），不是作者就调
     `_dotfiles_clear_repo_wallpapers` 把工作副本里残留的图删干净（只留 `README.md`），
     再建空目录、不下载。是作者且仓库里没图时，可用 `WALLPAPERS_REPO` 指定一个仓库
     clone 回来。
6. 配置目录 `~/.dotfiles`、进度文件 `~/.pullautumn_install_progress`、日志目录
   `~/.local/state/pullautumn` —— 已不再区分「旧方案 / 本项目」，两者**不能装在同一台机器上**
   （会互相覆盖）。旧方案退役前若要并存，用 `DOTFILES_DIR` 显式指定不同目录。

## 可调环境变量

都在 `lib/config.sh` 里，全部支持用同名环境变量覆盖，直接写在 `./install.sh` 前面即可。

| 变量 | 默认 | 作用 |
| --- | --- | --- |
| `WALLPAPER_OWNER` | `pullautumn` | 「作者本人」的判定基准（`id -un` 小写后比较），三处生效：① 只有它才链接/拉取壁纸，其他人清空仓库里的残留图并只建空目录；② 只有它才追加 `uv` 条件 stow 包；③ 只有它的 GTK 书签会多 `~/.config`、`~/.local` 两条 |
| `WALLPAPERS_REPO` | 空 | 作者的壁纸仓库。仓库里没图时从这个地址 clone 一份；留空则只认本地已有的图 |
| `ANIME4K_REPO` | `github.com/bloc97/Anime4K` | Phase 6b 的着色器来源，换镜像时改这里 |

```bash
WALLPAPERS_REPO="git@github.com:someone/wallpapers.git" ./install.sh
```

## 需要 sudo 的地方

只有这些：pacman 装包、写 `/etc/locale.conf`、`gpasswd`/`usermod` 加组、
写 `/etc/modules-load.d/`、`systemctl enable`、`dms-greeter install`、`systemctl reboot`。
sudo 保活在 `01-preflight.sh` 的 `start_sudo_keepalive()`（50 秒一刷），
清理挂在 `ui.sh` 的 `cleanup()`（`main.sh` 已有 `trap cleanup EXIT`）。
