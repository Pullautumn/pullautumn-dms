# local-bin

自定义命令入口，放几个脚本到 `~/.local/bin`。这个目录已经在 PATH 里（`setup_bash_path` 负责），
所以脚本名可以直接当命令用。

## 脚本

| 文件 | 作用 |
|---|---|
| `gh-mirror` | GitHub 镜像加速开关（安装期 / 补装期用，`on` / `off` / `status` / `probe`） |
| `niri-session-wlroots` | 用 `wlroots` 作为 `XDG_CURRENT_DESKTOP` 启动 niri |
| `quicksave` | 创建 Btrfs 快照（存档） |
| `quickload` | 从 Btrfs 快照恢复（读档） |
| `random-anime-wallpaper` | 随机下载一张壁纸并用 `dms ipc call wallpaper set` 应用（`Mod+Shift+F10`）；下载到 `~/Pictures/Wallpapers/api-random-download/`，仓库不自带壁纸也照常工作 |

`random-anime-wallpaper` 来自 shorin-dux-niri（上游原名 `random-anime-wallpaper-dms`），剪掉了两个本仓库不存在的钩子
（`matugen-update.sh` / `niri_set_overview_blur_dark_bg.sh`）—— DMS 的 `wallpaper set`
自己会 spawn matugen。依赖 `imagemagick` / `file` / `curl`，都在 `PKG_GROUPS[cli]` 里。
下载的图存在 `~/Pictures/Wallpapers/api-random-download/`（默认只留最近 40 张，`-k` 关掉清理）。

## 没有的东西

pullautumn 主仓库这里还有 `qs-lock`、`qs-popup`、`toggle-wlsunset`。本项目都删掉了：

- `qs-lock` —— 锁屏改由 DMS 的 lock 模块负责，`Mod+Alt+L` 调 `dms ipc call lock lock`
  （`lock` target 由 DMS 的锁屏模块注册，不在 `DMSShellIPC.qml` 里，但官方文档和实际
  `--help` 都能查到；同 target 下还有 `lockAndOutputsOff` / `isLocked` / `demo`）。
  不再需要 `/etc/pam.d/qs-lock`，DMS 的 PAM 解析器会从 `/etc/pam.d/login` 开始找。
- `qs-popup` —— 那是 waybar-quickshell 的弹窗调度器，本项目没有 waybar。
- `toggle-wlsunset` —— 护眼模式不再挂键位：DMS v2.1.2 的 `DMSShellIPC.qml` 里没有 `night`
  target（`NightModeService` 的 `IpcHandler` 没写 `target:`），`dms ipc call night toggle` 只会
  报错；而且 `toggle()` 第一句就是 `if (!gammaControlAvailable) { toast; return; }`。
  现在统一从 DMS 控制中心点「护眼」磁贴（同样有 gamma 控制、OSD、按时间 / 经纬度自动）。
  也**不要**再挂 wlsunset —— 会和 DMS 抢 `wlr-gamma-control`。

空闲锁屏也不再用 `swayidle`：DMS 设置 → 电源/锁屏 里有 `acLockTimeout` / `batteryLockTimeout`、
锁屏后关屏 `*PostLockMonitorTimeout`、挂起前锁屏 `lockBeforeSuspend`、以及
`loginctlLockIntegration`（默认开，`loginctl lock-session` 能触发 DMS 锁屏）。

## 脚本放置的取舍

进这里（T0）的标准只有一个：**会被裸名调用**，或者需要出现在 PATH 里给外部程序找。
只在图形会话内部、且调用方明确的脚本放 `~/.config/scripts`（T1），
只服务单个组件的放组件自己的 `scripts/`（T2）。详见 `~/.config/scripts/README.md`。
