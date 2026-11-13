# scripts

跨组件共用的胶水脚本，放在 `~/.config/scripts`。不放任何「只有一个组件用」的东西 ——
那类脚本留在组件自己的 `scripts/` 目录里。

## 放置规则

| 层 | 位置 | 判据 | 例子 |
|---|---|---|---|
| **T0 · 入口** | `~/.local/bin` | 手敲、被系统/其它程序按裸名调用 | `gh-mirror`、`quickload`、`quicksave` |
| **T1 · 跨组件** | `~/.config/scripts`（这里） | 调用方 ≥ 2，且只在图形会话里用 | `terminal-launcher`、`matugen-restore.sh` |
| **T2 · 私有** | 组件自己的 `scripts/` | 只有本组件调用 | `niri/scripts/niri-binds`、`niri/scripts/screenshot-sound.sh` |

T1 的调用一律写**绝对路径**：niri 的 `spawn` 和 DMS 的 IPC 都不走登录 shell，
拿不到 zsh 里加的 PATH。

## 现有脚本

| 脚本 | 作用 | 调用方 |
|---|---|---|
| `terminal-launcher` | 在指定目录起终端；`--float` 走固定 app-id 的浮动窗口 | 文件管理器右键、脚本 |
| `matugen-restore.sh` | 把配色还原成仓库默认值；`--configs-only` 给安装器用 | 安装器 Phase 8、`Mod+F12`、手动 |

截图和录屏**不在这里**：截图直接用 niri 内置动作（键位在 `niri/dms/binds.kdl`），
标注交给 `satty`，录屏交给 AUR 的 `shorin-screenrec-menu`。
原本放在这里的 `screenshot.sh` / `wf-recorder.sh`（约 1200 行）已删除 ——
它们的行为都绑在 waybar 上，而本项目的状态栏是 DMS，没有承接那套 UI 的地方。

## 关于配色：为什么这里没有 matugen-update.sh

pullautumn 主仓库里有一整套 `matugen-update.sh` / `matugen-select-type.sh` /
`wallpaper-rotate.sh` / `random-anime-wallpaper.sh` / `niri_auto_blur_bg.sh`。
本项目**全部删掉**了，因为：

- 换壁纸和跑 matugen 现在都是 **DMS 的职责**（DMS 壁纸面板 → 它自己 spawn matugen →
  写 `niri/dms/colors.kdl`、`kitty/dank-theme.conf`、`gtk-*/dank-colors.css`）。
- 再让外部脚本跑一遍 matugen，会写出第二套互相打架的配色，还会把已停用的模板重新生成。
- overview 的模糊背景也由 DMS 渲染层负责，不需要预糊图缓存。

`matugen/config.toml` 里只留下 DMS 不管的模板（btop、fastfetch、fuzzel、fcitx5、
pywalfox、gtk 图标重着色），所以两边不会抢同一个输出文件。

## matugen-restore.sh

```bash
~/.config/scripts/matugen-restore.sh                # 完整还原：配色（含 fcitx5）+ 图标缓存 + gsettings + 服务刷新
~/.config/scripts/matugen-restore.sh --configs-only # 只还原配色文件（安装器用）
```

还原清单来自 `~/.config/matugen/custom/`：btop、fastfetch、fuzzel 按「`~/.config` + 相对路径」
自动推导，fcitx5 因为落在 `~/.local/share` 下，在 `RESTORE_LIST` 里用
`"fcitx5/theme.conf:.local/share/fcitx5/themes/Matugen/theme.conf"` 单独指定目标。
还原 fcitx5 时还会把 `classicui.conf` 的 `Theme=` 拉回 `default`（fcitx5 自带主题，
与主仓库 `pullautumn` 的还原态一致），再用
`busctl ... ReloadAddonConfig classicui` 重载插件（不用 `fcitx5 -r`，那会起第二个实例）。
注意：`Theme=default` 之后 fcitx5 **不再跟壁纸变色**，这是刻意选的还原态；
想重新跟随，把 `classicui.conf` 的 `Theme` 改成 `Matugen`（matugen 仍在写那份 theme.conf）。

清单按原样全量还原，没有「只对作者生效」的条目 —— 那份清单里每一项都是配色产物，
对谁都成立。跟配色无关的个人配置走自己的 stow 包（见 `setup/lib/config.sh` 的
`STOW_PACKAGES`），不要在这里加。

`--configs-only` 会跳过图标清理、gsettings 与服务刷新 —— 那几段里有 `sed -i`
直接改 `~/.config` 下的文件，而 stow 已经把目录折叠成软链，改它等于改写仓库。
配色文件本身（含 fcitx5 那份）在第一步就会写入，不受这个开关影响。

完整模式里 `[二]` **不再改** `gtk-3.0/settings.ini`：Wayland 下 GTK3 读的是 gsettings，
ini 里的同名项被忽略；而 `gtk-3.0` 是折叠软链包，`sed -i` 改的就是仓库里那个文件。

`[六]`（Step 5 之后、脚本最后）负责图标收尾，顺序固定，不能提前：

- DMS 每次生成配色都会执行我们模板 `gtk-folder` 的 `post_hook` =
  `bash ~/.cache/matugen/recoloricons.sh &` —— 带 `&` 的**分离进程**，matugen 根本不
  等它（dux-shell 的 `execMatugen()` 注释里写了：后台 hook 会让管道永不关闭，issue #3901）。
  而 `recoloricons.sh` **最后一行**才 `gsettings set ... icon-theme Adwaita-Matugen-A|B`。
- 所以「删目录」绝不能留在 `[二]`：先删、它随后落地，gsettings 就指向一个不存在的主题，
  图标全部回落到占位图形（文件管理器里一片灰线条），而设置程序读 gsettings 又显示正确。
  这就是「第一遍跑完像没还原、跑第二遍才好」的竞态。
- `[六]` 的四步：① 最多等 15 秒让正在跑的重着色自己结束 → ② `pkill -f recoloricons.sh`
  再补一刀 → ③ 这时才写 `icon-theme=Adwaita`，并撤销 `flatpak override --user
  --env=ICON_THEME`（recolor 会挂上它）→ ④ 最后 `rm -rf` 两个 `Adwaita-Matugen-*` 目录。
  先删后写会翻车，先写后删只是清理，不产生悬空指针。
- 预期行为：DMS 下次换壁纸（或 DMS 重启）仍会重新生成并切回重着色主题。

`[零]`（在还原文件之前）只**读**不写：等 DMS 的 matugen 队列跑空，然后直接写文件。
它不再切明暗，原因有三：

- DMS 的明暗是「手动 / 定时 / 按位置 / 跟随壁纸」四选一（`ThemeScheduleTab.qml:24`），
  改任何一档都得动 `matugenSmartMode`：`setLightMode()` 第一句就把它关掉
  （`Theme.qml:1467`，`light()` 这个 IPC 固定传 `(true,true,true)`，没有参数能跳过）。
- 写回 `true` 时该键的 `onChange` 是 `regenSystemThemes`，会**再**生成一次；
  深色壁纸下 `resolveSmartMode` 按壁纸亮度判回 `dark`，`parseAndLoadColors()`
  再把 session 判回 dark —— 表现为「暗→亮→暗」闪一下。
- 两次生成 = gtk/qt/niri/kitty 重写两遍、`recoloricons.sh` 被拉起两遍，
  之前「第一遍跑完图标全灰」的竞态就是这里来的。

现在只等空闲就写文件，明暗由 DMS 自己的模式设置决定。判断用
`dms ipc call matugen status`（后端 `matugen_handler.go:77` 返回
`{"running":..,"pending":..}`），**不用 `pgrep matugen`**：DMS 的 matugen 是
`dux` 二进制的子命令，进程名不叫 matugen，抓不到。老版本没有这个 IPC 时退化成固定
`sleep 2`，不影响正确性。

还原文件本身与明暗无关：`RESTORE_LIST` 里那几份是静态默认色，kitty 是
`cp colors.conf → dank-theme.conf`，都不是按 light/dark 生成的。

`[一]` 末尾单独处理 **kitty**（它不写进 `RESTORE_LIST`，因为路径与目标同名会绕）：

- kitty 的颜色是两层，后加载的盖前面的：`colors.conf`（仓库跟踪的 Mocha，还没变）
  → `dank-theme.conf`（DMS 换壁纸时生成，在 `colors.conf` 之后 include）。
  所以只还原 `colors.conf` 看不出任何变化 —— 壁纸色压在上面。
- 脚本把 `dank-theme.conf` **覆盖成 `colors.conf` 的内容**，`dank-tabs.conf` 写成一行注释
  （标签栏回落到由背景/前景派生）。两份都在 `.gitignore` 里、属运行时产物，写了也不脏仓库；
  下次在 DMS 里换壁纸时 DMS 会重新生成，属预期。
- 位置必须在 `[零]` 之后：等 DMS 生成队列空闲后再写，否则那次生成会盖掉这两份。

它**不碰** `niri/dms/colors.kdl`：窗口边框色归 DMS 管，文件还带 AUTO-GENERATED 头，
DMS 面板随时重写。想回默认边框色就在 DMS 设置里重新应用一次主题。
