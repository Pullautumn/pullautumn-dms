# fcitx5

中文输入法。配置整套来自 **shorin-dux-niri**。默认方案 Rime（雾凇拼音 `rime_ice`），
组内另有英文键盘和拼音引擎备用。

部署到 `~/.config/fcitx5`。Rime 补丁与主题在 `local-share-fcitx5` 包里（`~/.local/share/fcitx5`）。

## 文件

| 文件 | 说明 |
|---|---|
| `config` | 全局开关：触发键、行为、输入法提示、插件启停 |
| `profile` | 输入法组与顺序：`keyboard-us` → `rime` → `pinyin`，默认 `rime` |
| `conf/classicui.conf` | 皮肤：主题 `Matugen`、字体、候选方向、DPI |
| `conf/pinyin.conf` | 拼音引擎参数（备用） |
| `conf/chttrans.conf` | 简繁转换 |
| `conf/punctuation.conf` | 标点映射 |
| `conf/notifications.conf` | 通知隐藏列表（空 = 全部显示） |

## 关键设置

| 项 | 值 | 含义 |
|---|---|---|
| `DefaultIM` | `rime` | 默认输入法 |
| `TriggerKeys` | `Shift_L` | 单按左 Shift 切中英（主触发键） |
| `AltTriggerKeys` | `Shift_R` | 单按右 Shift 切中英（备用，判定比前者严格） |
| `ModifierOnlyKeyTimeout` | `250` | 单按修饰键的判定窗口（毫秒） |
| `EnumerateWithTriggerKeys` | `True` | 按住切换键轮换输入法 |
| `Vertical Candidate List` | `True` | 候选词竖排 |
| `Font` | `Sans Serif 11` | 候选词字体 |
| `Theme` | `Matugen` | 皮肤，由 matugen 按壁纸生成 |
| `DarkTheme` | `default-dark` | 深色兜底皮肤 |
| `UseDarkTheme` | `False` | 不强制深色 |
| `ForceWaylandDPI` | `0` | 不强制 DPI |
| `EnableFractionalScale` | `True` | Wayland 下启用分数缩放 |
| `ShowInputMethodInformation` | `True` | 切换时弹状态提示 |
| `CompactInputMethodInformation` | `True` | 提示只显示一个状态字（中 / 英） |
| `AutoSavePeriod` | `0` | 不定时存盘，退出时存 |

## 与 shorin 原版的两处差异

| 项 | shorin | 本仓库 | 原因 |
|---|---|---|---|
| `TriggerKeys` | `Super+space` | `Shift_L` | 直接单按左 Shift 切中英；`Super+Space` 会被 niri 的 `Mod+Space`（当前窗口浮动）先吃掉 |
| `profile` 第 3 项 | `mozc` | `pinyin` | 没装 `fcitx5-mozc`，配了也是「不可用」；`pinyin` 由 `fcitx5-chinese-addons` 提供 |

`AltTriggerKeys` 的 `Shift_L` 挪进了 `TriggerKeys`，只留 `Shift_R`，避免同一个键在两个列表里各写一遍。

`EnumerateGroupForwardKeys` / `EnumerateGroupBackwardKeys` 仍是
`Control+space` / `Shift+Control+space`。`profile` 只有一个输入法组，
`canChangeGroup()` 恒为假，这两条实际不会被触发。

## Rime 定制

`local-share-fcitx5` 里有两份补丁：

`rime/default.custom.yaml`

- 方案列表：`rime_ice` / `luna_pinyin_simp` / `double_pinyin_flypy` / `wubi86` / `bopomofo`
- 候选每页 **6 个**
- `Shift_L` / `Shift_R` 设为 `noop`，把 Shift 让给 fcitx5 的 `TriggerKeys` / `AltTriggerKeys`
- **没有设置 `good_old_caps_lock`**，走 Rime 默认值 `false`

`rime/rime_ice.custom.yaml`

- `grammar/language: wanxiang-lts-zh-hans`，启用万象语法模型

改完必须重新部署：

```bash
fcitx5-remote -r
```

## 依赖

| 包 | 用途 |
|---|---|
| `fcitx5` | 本体 |
| `fcitx5-im` | 集成包（GTK / Qt 输入模块） |
| `fcitx5-chinese-addons` | `chttrans` / `punctuation` addon，以及 `pinyin` 引擎 |
| `fcitx5-rime` | Rime 引擎，`DefaultIM=rime` 靠它加载 |
| `rime-ice-git` | 雾凇拼音（AUR），提供 `rime_ice` 方案 |

都在核心包清单的 `input` 组里，一键安装会一起装上。`rime-ice-git` 是 AUR 包，走 AUR helper。

## 用法

```bash
fcitx5-configtool      # 图形配置界面
fcitx5-remote -o       # 打开输入法
fcitx5-remote -c       # 关闭
fcitx5-remote -t       # 切换中英
fcitx5-remote -r       # 重启并重新部署
```

## 注意

- **左 Shift 是主触发键，右 Shift 只是备用。** 两者在 fcitx5 里走不同的判定：
  `TriggerKeys`（左 Shift）任何时候都能切；`AltTriggerKeys`（右 Shift）要过 `canAltTrigger()`——
  输入法已经关闭、且上一次关闭不是它自己造成的时候直接返回 false，按了没反应。
  所以主用左手，右手只作补充。判定窗口由 `ModifierOnlyKeyTimeout=250` 控制：
  按下后 250 ms 内没接别的键才算「单按」，`Shift+A` 这类组合不会误触发。
- **CapsLock 的行为和以前不一样了。** 因为不再写 `good_old_caps_lock: true`，Rime 会接管 CapsLock：
  按下去是切 ASCII 模式（中 → 英），不再切字母大小写，同时会弹 fcitx5 的状态提示。
  想回到「切大小写 + 完全静默」，把 `good_old_caps_lock: true` 加回 `default.custom.yaml` 即可 ——
  但那样就没有提示了，这两件事在 Rime 里互斥。
- `rime_ice.custom.yaml` 的 `grammar/language` 指向万象语法模型。没装模型文件时 Rime 会忽略该行，
  并在 `~/.local/share/fcitx5/rime/*.log` 里记一条 warning，不影响输入。
- 本目录经 stow 软链到 `~/.config/fcitx5`，**`fcitx5-configtool` 保存会把整份运行时配置写回这里**
  （等于直接改仓库）。改完用 `git diff` 核对，别把别的键一起带脏。
- `Theme=Matugen` 需要 matugen 生成同名主题：`matugen/config.toml` 的 `fcitx5` 段 + 模板
  `matugen/templates/fcitx5-theme.conf`（`Name=Matugen`）。没生成过会回落到 `default`。
- 全新安装首次启动要编译雾凇词库，可能卡十几秒；没编完就 `fcitx5-remote -r`，或在托盘菜单点「重新部署」。
