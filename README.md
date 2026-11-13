# pullautumn

用旧 pullautumn（**同一 GitHub 仓库，旧内容后续从本机移除**）的安装框架（Phase 编排 / 包组 /
stow 部署 / 补装清单 / 中断续跑），搭一套以 **DMS（Dux Modular Shell，即 DankMaterialShell
的当前形态）** 为桌面壳的 niri 环境。

一句话区别：**旧 pullautumn 用 waybar + quickshell 拼状态栏，本仓库让 DMS 一个进程
把状态栏、通知、锁屏、启动器、剪贴板、电源菜单、OSD、壁纸全包了。**

三块来源说清楚，免得看配置时迷惑：

| 部分 | 来源 |
|---|---|
| 安装框架（Phase / 包组 / stow / 断点续跑） | pullautumn、jswysnemc |
| niri 配置结构、布局、动画、模糊、窗口规则 | [shorin-dux-niri](https://github.com/SHORiN-KiWATA/shorin-dux-niri) |
| 键位表 | pullautumn（命令换成 DMS 的 IPC） |

## 为什么是 DMS

DMS 在 **官方 extra 仓库**（`dux-shell`，2.1.x，`provides dms-shell`），不需要 AUR 元包，
也不需要 `shorindms init` 那套「把别人的 dotfiles 拷进 $HOME」的分发器：

```bash
pacman -S dux-shell        # 二进制叫 dms，自带 dms.service（用户单元）
dms setup                  # 交互式部署合成器配置（我们不用它，见下）
dms ipc call <目标> <函数>  # 所有面板都靠 IPC 调
```

它的依赖只有 `quickshell` 和 `accountsservice`，配套的可选件（`dux-gop` 进程监控、
`dux-search-bin` 文件搜索、`dux-greeter-bin` 登录界面）各自独立。

## 与旧 pullautumn 的差异

下表左列是即将退役的旧方案，右列是本仓库。

| 角色 | 旧 pullautumn | 本项目 |
|---|---|---|
| 状态栏 | waybar ×3（主 / Win11Like / quickshell） | DMS bar |
| 通知 | swaync / mako | DMS 控制中心 + toast |
| 锁屏 | quickshell `lockscreen`（`qs-lock`） | DMS 锁屏（`dms ipc call lock lock`） |
| 空闲策略 | `swayidle.sh`（180s 锁 / 300s 熄屏 / 600s 挂起） | DMS 自己管；`Mod+Ctrl+F1` 咖啡模式 |
| 启动器 | rofi / fuzzel | DMS spotlight（fuzzel 仅兜底） |
| 剪贴板 | cliphist + `cliphist-tui` | DMS 剪贴板面板（仍读 cliphist 库） |
| 电源菜单 | wlogout | DMS powermenu |
| OSD | swayosd | DMS 自带 |
| 壁纸 | waypaper + `wallpaper-rotate.sh` + awww | DMS 壁纸面板（含轮换） |
| 配色 | matugen 自己跑，写 waybar/kitty/niri… | **DMS 自己跑 matugen**，我们只管它不管的（btop/fastfetch/fcitx5/fuzzel/pywalfox） |
| 登录 | SDDM + lunar-glass | greetd + dux-greeter |
| niri 配置结构 | `conf.d/` 九个拆分文件 | shorin 的扁平结构（layout/animations/blur/windowrules） |
| 窗口切换 | `Alt+Tab` → fuzzel 列表脚本 | `Alt+Tab` → niri 原生缩略图（supertab） |
| 配置目录 | `~/.dotfiles` | `~/.dotfiles`（已与旧方案同名，两者不能并存） |

**与旧 pullautumn 相比，本仓库仍然少了一批东西**：没有 yazi、obs-studio 的配置，
没有各 IDE 的 `.desktop`。这几样跟桌面壳无关，属于 pullautumn 的个人配置；
砍掉之后剩下的都是「把 niri + DMS 跑起来」需要的部分。

**大体积资源一律不进 git**，改成安装时按需下载，这样别人 clone 仓库只要 1 MB 出头：

| 资源 | 体积 | 谁需要 | 怎么来 |
| --- | --- | --- | --- |
| 壁纸 `wallpaper/` | ~50 MB | 只有作者本人 | `WALLPAPER_OWNER` 之外的人跳过，并清空工作副本里的残留 |
| mpv Anime4K 着色器 | ~56 MB | 想要实时超分的所有人 | 安装器 Phase 6b 询问后下载 |

保留下来的底座：kitty、zsh、starship、Thunar、fcitx5、btop、fastfetch、
fontconfig、mimeapps。**niri 是例外** —— 配置结构、布局参数、动画、模糊、
窗口规则都换成了 shorin 的，只有键位表和 `conf.d/` 里那几项机器相关配置
还是旧 pullautumn 的。

## 安装

```bash
git clone https://github.com/Pullautumn/dotfiles ~/.dotfiles
cd ~/.dotfiles && ./install.sh
```

可选参数：

| 参数 | 作用 |
|---|---|
| `--minimal` | 只装核心包组，跳过可选软件与 flatpak |
| `--no-stow` | 不部署配置（只装包） |
| `--no-greeter` | 不安装 greetd + dux-greeter，保留现有显示管理器 |
| `--yes` | 全程不问（无人值守） |
| `--no-reboot` | 装完不自动重启 |
| `--reset` | 清空进度重新开始 |

装完有包没装上，会生成 `~/pullautumn-missing-packages.txt`，重启联网后整段复制粘贴即可补装。

## 快捷键（常用）

niri 的配置结构来自 **shorin-dux-niri**，但**键位表是 pullautumn 的**。
全部键位在 `niri/.config/niri/dms/binds.kdl`（文件头有「pullautumn 原命令 → DMS 命令」对照）。

| 键位 | 作用 |
|---|---|
| `Mod+A` | 启动器（DMS spotlight，失败退回 fuzzel） |
| `Mod+N` | 通知栏 |
| `Mod+V` | 剪贴板历史（DMS 面板；`Mod+Shift+V` 不绑定） |
| `Mod+Alt+L` | 锁屏 |
| `Mod+Ctrl+Alt+L` | 挂起（熄屏 + 锁 + 挂起） |
| `Mod+F2` / `Mod+F3` | 设置 / 录屏（`F4` 无绑定） |
| `Mod+Alt+W` | 壁纸选择 |
| `Mod+F10` / `Mod+Shift+F10` | 下一张壁纸 / 随机下载动漫壁纸 |
| `Mod+F12` | 还原仓库默认配色（btop / fastfetch / fuzzel / fcitx5 / 图标，不动明暗） |
| `Mod+F9` | 空出（护眼模式改从 DMS 控制中心点「护眼」磁贴） |
| `Mod+Shift+F4` | 隐藏 / 显示 DMS 顶栏 |
| `Mod+T` / `Mod+Return` | 终端（kitty） |
| `Mod+Slash` | 临时浮动终端 |
| `Mod+E` / `Mod+Alt+E` | 文件管理器（nautilus / thunar） |
| `Mod+B` | 浏览器 |
| `Mod+Alt+Slash` | 完整快捷键列表 |
| `Mod+O` / `Mod+G` | 总览（overview） |
| `Mod+Q` / `Alt+F4` | 关闭聚焦窗口 |
| `Alt+Tab` / `Alt+Shift+Tab` | 缩略图窗口切换（niri 原生 recent-windows） |
| `Mod+M` / `Mod+Alt+S` | 收起窗口到 niri-sidebar |
| `Mod+P` / `Mod+Alt+P` / `Mod+Ctrl+P` | 截图：选区 / 整屏 / 当前窗口（`Print` / `Alt+Print` / `Ctrl+Print` 同效） |
| `Mod+Shift+S` / `Alt+Ctrl+S` | 把剪贴板里的图交给 satty 标注 / 选区截图后直接 satty 标注 |
| `Mod+Shift+P` | `mark-shot` 选区截图并标注（自带 OCR / 贴图 / 滚动长截图） |
| `Mod+F6` | 录屏（shorin-screenrec-menu，再按一次停止） |
| `Ctrl+Alt+Delete` | 电源菜单 |
| `Mod+Alt+M`、`Mod+Alt+T`、`Mod+Shift+N`、`Mod+Ctrl+F10` | 已移除（原因见 `dms/binds.kdl` 头部） |

音量键、亮度键、播放键走 `dms ipc call audio|brightness|mpris ...`，OSD 由 DMS 弹。

## 目录结构

顶层 23 个 stow 包，就是全部：

```
niri  kitty  fuzzel  satty  gtk-3.0  fontconfig  btop  fastfetch   ← 桌面与外观
nvim  mpv                                                    ← 编辑器与播放器
zsh  zshenv  starship  scripts  local-bin                    ← shell 与脚本
fcitx5  local-share-fcitx5  Thunar  mimeapps                 ← 输入法 / 文件管理
environment.d  xdg-desktop-portal  matugen  dms              ← 系统集成、配色与桌面壳设置
setup/                                                       ← 安装器（不是 stow 包）
```

`dms` 是 `~/.config/dms`（状态栏 / dock / 启动器 / 锁屏 / 空闲策略）。它被 stow **折叠成目录
软链** —— 这是必须的，DMS 用原子写（临时文件 + rename）改 `settings.json`，rename 到文件软链
上会把链接替换成普通文件，第一次改设置就静默脱钩。副作用是「在面板里改设置 = 改仓库文件」，
`.gitignore` 用白名单只放行 `settings.json` / `clsettings.json` / `README.md`。
壁纸、明暗、显示器布局在 `~/.local/state/dms/session.json`，**不在这个包里**，安装器不还原它们。

另外有一个**条件包** `uv`（`~/.config/uv/uv.toml`，PyPI 镜像源）。它只在用户名等于
`WALLPAPER_OWNER`（默认 `pullautumn`）时才被 `STOW_PACKAGES` 追加进来 —— 镜像源跟地理
位置绑定，不该强加给别人。所以别人的机器上不会有 `~/.config/uv/` 这个目录。

`wallpaper/` **不是 stow 包**：它整目录链接到 `~/Pictures/Wallpapers`（见
`_dotfiles_link_wallpapers`），不走 `~/.config`，也不该由 stow 管。图片本身
被 `.gitignore` 忽略 —— 仓库里只留一份 `README.md` 说明目录用途。

niri 的配置结构：

```
niri/.config/niri/          ← 结构照搬 shorin-dux-niri
├── config.kdl              include 全部；顺序即生效顺序
├── layout.kdl              gaps / 预设列宽 / focus-ring / shadow
├── animations.kdl          弹簧参数与缓动曲线
├── blur.kdl                全局 xray 模糊 + fuzzel 的 layer-rule
├── shorin-windowrules.kdl  全局圆角、DMS 设置窗、浮动窗口白名单
├── conf.d/                 ★ 机器相关（名字沿用 pullautumn）
│   ├── output.kdl          显示器
│   ├── input.kdl           键盘布局 / 触摸板 / 鼠标加速
│   ├── environment.kdl     语言、输入法、缩放、screenshot-path
│   └── autostart.kdl       DMS、dsearch、polkit、portal、fcitx5、剪贴板、截图音效
├── dms/
    ├── binds.kdl           ★ 键位（pullautumn 键位表 → DMS IPC）
    ├── supertab.kdl        ★ Alt+Tab 缩略图切换
    ├── alttab.kdl          recent-windows 高亮圆角
    ├── cursor.kdl          光标主题与大小
    ├── layout.kdl          DMS 的布局补丁（gaps 4 / border 2 / 圆角 12）
    ├── colors.kdl          ← DMS 生成（matugen 配色，gitignore）
    ├── input.kdl           ← DMS 生成（输入设置面板，gitignore）
    ├── outputs.kdl         ← DMS 生成（显示器面板，gitignore）
    └── windowrules.kdl     ← DMS 生成（窗口规则面板，gitignore）
```

niri 包自带的脚本（`niri/scripts/`，只给 niri 用）：

```
niri-binds                 打印快捷键列表
niri-monitor-switch.sh     显示器切换
niri-quick-switch-fuzzel.py fuzzel 版窗口切换（备用）
screenshot-sound.sh        截图音效守护（等 SIGUSR1，确认图片进了剪贴板才响）
```

`dms/` 下**前五个进仓库**（shorin 的初始值），后四个是 DMS 的运行时产物。
注意 `dms/layout.kdl` 带 "AUTO-GENERATED" 头：你在 DMS 布局设置里调 gaps/圆角时它会被重写，
那时 `git status` 会脏 —— 这是沿用 shorin 结构换来的代价，改完提交一次即可。

## 配色是怎么走的

1. 首次安装：`scripts/matugen-restore.sh --configs-only` 把 btop / fastfetch / fuzzel
   还原成仓库自带的**深色**默认配色（Catppuccin Mocha，与主仓库 `pullautumn` 一致），
   同时 fcitx5 用自带的 `default` 主题，**不跑 matugen**。
   同时安装器把 GNOME 基调设成 `color-scheme=default` + `gtk-theme=adw-gtk3` + 图标 `Adwaita`。
   安装器**不写** DMS 的状态文件：`~/.config/dms/settings.json` 是 stow 包里的那份（主题源
   已设成 `dynamic` + `matugenSourceMode=dominant` + `matugenSmartMode=true` +
   `runUserMatugenTemplates=true`），`~/.local/state/dms/session.json` 由 DMS 自己首启创建
   —— 壁纸 / 明暗 / 显示器布局是安装者自己选的东西，不还原。
2. 之后在 DMS 里换壁纸：DMS 自己 spawn matugen，写
   `niri/dms/colors.kdl`、`kitty/dank-theme.conf`、`gtk-3|4.0/dank-colors.css`、
   `qt5ct|qt6ct/colors/matugen.conf`。因为开了 `matugenSmartMode`，**明暗也跟着壁纸走**：
   换深色壁纸整套界面转深，换回亮色壁纸再转回来。
   （亮色下 DMS 写的 `color-scheme` 是 `default` 而不是 `prefer-light`，这是它源码里的固定映射，
   新版 libadwaita 里两者等价。）
3. 我们自己的 `matugen/config.toml` 只保留了 DMS 不管的模板（btop、fastfetch、fuzzel、
   fcitx5、pywalfox、gtk 图标重着色），所以两边不会抢同一个输出文件。
4. 想整体关掉 DMS 的动态配色：DMS 设置里关「动态主题」，或设 `DMS_DISABLE_MATUGEN=1`。
5. 手动还原 `matugen-restore.sh`（不带参数）**不改明暗**。DMS 的明暗是
   「手动 / 定时 / 按位置 / 跟随壁纸」四选一（`ThemeScheduleTab.qml`），改任何一档
   都要动 `matugenSmartMode` 并触发一次全量重新生成，而那次生成会覆盖脚本刚写的文件。
   所以脚本只等 `dms ipc call matugen status` 报空闲，然后开始写文件：
   还原后是什么明暗，由你在 DMS 设置里选的那个模式决定。
   （旧版本在这里「切亮 → 写回 smart」，会生成两遍、界面要闪一次「暗→亮→暗」，
   而且深色壁纸下必然判回 dark —— 已删掉，不要加回来。）
6. `matugen-restore.sh` 会把 **kitty** 的 `dank-theme.conf` 覆盖成仓库自带的
   `colors.conf`（Mocha），`dank-tabs.conf` 清成一行注释 —— 因为这两份是 DMS 在
   `colors.conf` 之后 include 的覆盖层，不清掉的话「还原」后终端仍是上次壁纸的配色。
   下次在 DMS 里换壁纸时 DMS 会重新生成，属预期行为。
7. 图标（`Adwaita-Matugen-A/B`）在脚本**最后**才清理，顺序是「等重着色停下 → 掐掉 →
   写 `icon-theme=Adwaita` → 再删目录」。DMS 的图标重着色是 matugen 的 `post_hook`
   分离进程（`recoloricons.sh &`），最后一行才改 gsettings；先删目录再让它落地就会得到
   一个指向不存在主题的 gsettings —— 表现为图标一片灰、但设置程序里看着是对的。

## 首次登录后建议做的四件事

1. **空闲/锁屏超时**：这套配置里**没有 swayidle**，锁屏、关屏、挂起全由 DMS 自己计时。
   进 设置 → 电源/锁屏，把 AC 和电池两套都设一遍
   （`acLockTimeout` / `batteryLockTimeout`、锁屏后关屏用 `*PostLockMonitorTimeout`，
   别用普通关屏超时否则会被锁屏事件重新计时）。`lockBeforeSuspend` 和
   `loginctlLockIntegration` 默认已开。
2. **换壁纸**：`Mod+Alt+W` 或面板里的壁纸页。DMS 首次启动就会按当前壁纸生成一次
   `dms/colors.kdl`；之后每次换图都会重算配色，并按壁纸亮度可能连带切换明暗。
3. **看一眼缺包清单**：`~/pullautumn-missing-packages.txt`（有才会生成）。
4. **确认回滚点存在**：`sudo snapper -c root list` 里应有一条
   `Before Dotfiles Setup`。安装器只配 snapper，**不会**把快照列进 GRUB 菜单
   （不碰 bootloader）—— 回滚走 `sudo snapper -c root undochange <pre>..<post>`
   或 btrfs-assistant。想开机就能选快照，再装 `grub-btrfs` + `inotify-tools`、
   `systemctl enable --now grub-btrfsd`，最后 `grub-mkconfig -o /boot/grub/grub.cfg`。

## 已知限制

- **需要 niri ≥ 26.04**：`config.kdl` 用了 `include optional=true`，低于该版本会解析报错。
  `blur.kdl` / `shorin-windowrules.kdl` 里的 `blur` / `background-effect` 同样要求 26.04。
- **`layout.kdl` 的 gaps / `dms/layout.kdl` 会打架**：前者写 `gaps 12`，后者写 `gaps 4`，
  后者在后所以实际生效 4。这是 shorin 的设计（DMS 布局设置优先），不是配置写错了。
- **`dms/layout.kdl` 会被 DMS 重写**：它带 AUTO-GENERATED 头，你在 DMS 布局设置里
  调 gaps / 圆角 / 边框，文件就会变，`git status` 跟着脏。沿用 shorin 结构的代价。
- **`dms setup` 在纯 TTY 里会失败**：它要检测合成器。安装器只对 `colors` 做处理，
  失败只 warn，首次登录后换一次壁纸就会补上。
- **锁屏认证走 PAM 的 `login`**：DMS 的 PAM 解析器按 `login → system-auth` 顺序找，
  Arch 一定有 `/etc/pam.d/login`，所以不额外写 service 文件。
- **`dms ipc call lock lock` 这个 target 不在 `DMSShellIPC.qml` 里**：由锁屏模块单独注册。
  只 grep 那一个文件会误判成"DMS 没有 lock target"。
- **greetd 会顶掉现有显示管理器**：`setup_greeter` 会 disable sddm / gdm / lightdm / ly。
  不想动就用 `--no-greeter`。
- **必须 enable `seatd`，否则登录界面是黑屏**：niri 经 libseat 取 DRM 设备，后端顺序是
  `seatd socket → logind → builtin`。greeter 会话 `class=greeter`，logind 的 `TakeDevice` 会拒
  （controller 是 greetd 的 session worker，不是 greeter 进程），libseat 退回 builtin 自己
  `open("/dev/dri/card0")`，此时设备已有 master → `drmSetMaster` 得 `EBUSY` → smithay 打一行
  `WARN Unable to become drm master, assuming unprivileged mode` 后**永久降级**：只渲染到离屏
  缓冲、从不 page flip。quickshell 画得完全正常，SSH 进去 `grim` 截图也一切正常，显示器就是黑的。
  `setup_greeter` 会 `systemctl enable seatd` + `usermod -aG seat greeter`（socket 是
  `root:seat 0770`），并给 greetd 写 `After/Wants=seatd.service` 保证顺序。
  老机器手动补这两条即可，`wq` 自己不需要进 `seat` 组（普通用户会话的 controller 就是它自己，
  logind 那条路是通的）。
- **截图一律走 niri 内置动作**，同时写 `screenshot-path` 并复制进剪贴板，没有「只复制不落盘」
  的开关；要那个行为就用 `Mod+Shift+S`（grim + wayfreeze，只进剪贴板）。
- **截图音效是一个常驻脚本**（`niri/scripts/screenshot-sound.sh`）：键位截图后给它发 `SIGUSR1`
  「上膛」，它靠自己的 `wl-paste --watch` 确认真有图片进了剪贴板才响，所以手动复制的图片
  不会误响。缺 `sound-theme-freedesktop` 时它会在启动日志里报错并退出。
- **壁纸目录是整目录软链**：`_dotfiles_link_wallpapers` 把仓库的
  `wallpaper/Pictures/Wallpapers` 链到 `~/Pictures/Wallpapers`（原目录会先改名备份）。
  图片不进 git，所以函数先判断 `id -un` 是否等于 `WALLPAPER_OWNER`（默认 `pullautumn`）：
  不是就**把仓库里残留的图全部删掉**（只留被跟踪的 `README.md`），再建一个空目录给 DMS
  的壁纸选择器 —— `git pull` 不会清理已在工作副本里的文件，老 clone 或手工拷进来的 50 MB
  得靠这一步清掉，且**不碰 `~/Pictures/Wallpapers`（用户自己的目录）**。是作者才链接，
  仓库里没图且设了 `WALLPAPERS_REPO` 就 clone 一份。DMS 里「随机下载动漫壁纸」写的图
  会直接落进仓库，同样被忽略。
- **仓库里没有 `gtk-4.0` 包，这是有意的**：shorin-dux-niri 的 `gtk-4.0/settings.ini`
  整份只有 `[Settings]` + `gtk-im-module=fcitx` 两行，而本仓库已经用
  `GTK_IM_MODULE=fcitx` 环境变量覆盖（`environment.d` 和 `niri/conf.d/environment.kdl`
  各一份），Wayland 下 GTK4 走 text-input-v3，不靠这个键。GTK4 的 matugen 配色由
  **DMS 自己**写 `~/.config/gtk-4.0/{gtk.css,dank-colors.css}`，目录不存在它会自建。
  真做成 stow 包的话 `~/.config/gtk-4.0` 会变成仓库软链，这两份运行时产物就落进仓库，
  又得加两条 gitignore —— `gtk-3.0` 现在就是这个代价。
- **nvim 的插件与 LSP 在首次启动时自己装**：`init.lua` 会拉起 lazy.nvim，mason 再装
  pyright / stylua / black 等。安装器只负责装 `neovim` 本体和 treesitter 编译链
  （`clang` / `tree-sitter-cli`），不跑 `:Lazy sync`，免得安装阶段卡在网络上。
  首次 `nvim` 打开会下载插件，属正常现象。
- **mpv 的 Anime4K 着色器由安装器下载**（Phase 6b，约 56 MB，会先问）。从
  `ANIME4K_REPO` clone 后把 `glsl_4.0/*.glsl` 拷进 `~/.config/mpv/shaders/`，
  再校验 `Ctrl+1`…`Ctrl+6` 引用的 10 个文件是否齐全。下载失败只 warn，
  不影响播放；手动装法见 `mpv/.config/mpv/README.md`。
- `shorin-windowrules.kdl` 里有一批 shorin 自家的 app-id（`shorinclip`、`niri-hotkey-menu`、
  `proton_wrapper_configure` 等），本项目没有这些程序，规则留着不影响任何东西。

## 相关

- [DMS 文档](https://duxlabs.dev/docs)
- [niri 配置文档](https://yalter.github.io/niri/Configuration:-Introduction)
- pullautumn —— 安装框架与键位来源（旧内容，仓库地址与本项目相同，已由其接管）
- [shorin-dux-niri](https://github.com/SHORiN-KiWATA/shorin-dux-niri) —— niri 配置结构来源
