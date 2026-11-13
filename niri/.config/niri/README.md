# niri

[niri](https://github.com/YaLTeR/niri) 是 Wayland 原生的**滚动式平铺**合成器：工作区横向无限延伸，
窗口按列纵向排列，新开窗口只会挤占列内空间，不会把已有窗口压缩变形。

本仓库的 niri 配置结构来自 **[shorin-dux-niri](https://github.com/SHORiN-KiWATA/shorin-dux-niri)**
（AUR `shorin-dux-niri-git`），键位表来自 **pullautumn** 主仓库。
桌面壳是 DMS（dux-shell），状态栏/通知/锁屏/启动器全由它提供，niri 只管窗口管理。

## 文件

```
config.kdl              include 全部；顺序即生效顺序（后 include 覆盖同名属性）
layout.kdl              gaps / 预设列宽 / focus-ring / border / shadow      ← shorin
animations.kdl          各动作的弹簧参数与曲线                              ← shorin
blur.kdl                全局 xray 模糊 + fuzzel 的 layer-rule                ← shorin
shorin-windowrules.kdl  全局圆角 8、DMS 设置窗、imv/satty/quickterminal 浮动 ← shorin
conf.d/                 ★ 机器相关的部分，名字沿用 pullautumn
  output.kdl            显示器（换机器时按实际输出名改）
  input.kdl             键盘布局、caps 只灭灯、触摸板 tap、鼠标 flat 加速
  environment.kdl       语言、输入法、Qt/GTK 缩放、screenshot-path
  autostart.kdl         DMS、dsearch、polkit、portal、fcitx5、剪贴板监听、xhost
dms/
  binds.kdl             ★ 键位（pullautumn 的键位表，命令换成 DMS IPC）
  supertab.kdl          ★ Alt+Tab 缩略图切换
  alttab.kdl            recent-windows 的 highlight 圆角
  cursor.kdl            光标主题 breeze_cursors / 30px
  layout.kdl            DMS 的布局补丁（gaps 4、border 2、圆角 12）
scripts/
  niri-binds            打印快捷键列表（Mod+Alt+Slash）
  niri-monitor-switch.sh 显示器切换
  niri-quick-switch-fuzzel.py  fuzzel 版窗口切换（当前未绑键，备用）
  screenshot-sound.sh   截图音效守护：等键位发来的 SIGUSR1，确认图片真进了剪贴板才响
```

## 为什么 include 顺序是这样

`config.kdl` 里先 `conf.d/`（我们的显示器/输入/环境），再 `layout.kdl` / `animations.kdl`
（shorin 的视觉参数），然后窗口规则，最后 `dms/*`。原因：

- `layout.kdl` 写 `gaps 12`，但 `dms/layout.kdl` 写 `gaps 4` —— 后者在后，实际生效 4。
  这是 shorin 的设计（DMS 的布局设置说了算），不是笔误。
- `shorin-windowrules.kdl` 的全局圆角 8 会被 `dms/layout.kdl` 的圆角 12 覆盖。
- `dms/colors.kdl` 最后加载，DMS 换壁纸时重写它来盖掉默认边框色。

## 与 DMS 的接缝

| 事项 | 做法 |
|---|---|
| 启动 DMS | `conf.d/autostart.kdl` 里 `spawn-at-startup "dms" "run"` |
| 为什么不用 systemd | `dms.service` 有 `Requisite=graphical-session.target`，greetd 直接起 niri 时该 target 不一定是 active，`systemctl start` 会失败 |
| 圆角 / gaps | `dms/layout.kdl`（DMS 首次启动或你调布局设置时可能重写） |
| 模糊 | `blur.kdl` 的全局 xray 模糊；窗口透明度不在这里，DMS 面板控制 |
| 边框色 | `dms/colors.kdl`，DMS 换壁纸时生成 |
| 空闲/锁屏 | DMS 自己管（设置 → 电源/锁屏），本仓库没有 swayidle |
| 媒体键 | `dms/binds.kdl` 里走 `dms ipc call audio|brightness|mpris` |
| Alt+Tab | `dms/supertab.kdl`（niri 原生 recent-windows 缩略图） |

## 键位

完整列表见 `dms/binds.kdl`（文件头有「pullautumn 原命令 → DMS 命令」对照表），
运行 `Mod+Alt+Slash` 或 `niri-binds` 也能看到。

三处和 pullautumn 主仓库不同，都是因为 DMS 接管了对应组件：

| 键位 | pullautumn | 本项目 |
|---|---|---|
| `Mod+F2` 及其余 `F` 键 | 切三套 waybar（`F2`/`F3`/`F4` = 设置 / 进程管理器 / 电源菜单） | 三套 waybar 已不存在：`F2` = DMS 设置；`F3`、`F6` 都是 `shorin-screenrec-menu` 录屏；`F4` 没有绑定，`Shift+F4` 才是隐藏顶栏 |
| `Mod+V` | `Mod+V` = cliphist-tui、`Mod+Shift+V` = waybar 面板 | 合并成 `Mod+V` 一个键（DMS 只有一个剪贴板面板），`Mod+Shift+V` 不绑定 |
| `Alt+Tab` | fuzzel 列表脚本 | niri 原生缩略图（`dms/supertab.kdl`） |

删掉的键位：`Mod+Alt+M` / `Mod+Alt+T`（配色策略，DMS 设置里选）、
`Mod+Shift+N`（NiriMod，shorin 结构下有两条全局 window-rule 会让它显示错误值）、
`Mod+Ctrl+F10`（自动换壁纸，DMS 的壁纸页里开关）。

## 校验配置

```bash
niri validate                        # 语法 + 语义检查
niri msg action load-config-file     # 改完热重载（注意是 load-config-file，不是 reload-config）
```

`include optional=true` 需要 niri ≥ 26.04；低于该版本把 `config.kdl` 里带 `optional=true`
的行去掉（并保证对应文件存在）。`blur { }` 与 `background-effect` 同样要求 26.04。
