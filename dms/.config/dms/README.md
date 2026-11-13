# dms（dux-shell 的状态栏 / dock / 启动器 / 锁屏设置）

这个包只有两份文件：

```
~/.config/dms/settings.json      主设置（barConfigs / dockConfigs / launcher* / lock* / osd* …）
~/.config/dms/clsettings.json    剪贴板面板策略（历史上限、条目上限、自动清理天数）
```

## 为什么是「整目录软链」

`dms/` 里只有一个 `.config/dms/`，所以 stow 会把它**折叠**成一条目录软链：

```
~/.config/dms -> <仓库>/dms/.config/dms
```

这不是顺手为之，是唯一可行的形态。DMS 写 `settings.json` 走的是
`Common/SettingsData.qml` 里的 `FileView`，而它设了 `atomicWrites: true`
（Quickshell 的实现是 `QSaveFile` → 临时文件 + rename）。rename 到一条**文件**软链上，
POSIX 语义是把软链本身替换成普通文件 —— 也就是第一次改设置就静默断链，仓库那份再也不更新。
目录软链则不受影响：rename 发生在仓库目录内部，写的就是仓库里的真文件。

所以：**别把 `settings.json` 单独 `ln -s` 或手动改成普通文件**，那会悄无声息地让同步失效。

## 改设置 = 改仓库

在 DMS 面板里拖一个 widget、改一次 dock 图标尺寸，`git status` 就会出现
`dms/.config/dms/settings.json`。这是设计目标，不是 bug：

```bash
git add dms/.config/dms/settings.json
git commit -m "dms: 状态栏加网速监控"
```

反过来，`git checkout -- dms/.config/dms/settings.json` 就是「把设置退回上次提交的样子」；
`git clean -fdx dms/` 会把运行时文件连同未跟踪的设置一起删掉。**这两个命令都会立刻改变桌面外观。**

## 谁进 git，谁不进

白名单在根 `.gitignore`（`dms/.config/dms/*` + 三条 `!`），只跟踪
`settings.json`、`clsettings.json`、这个 README。其余一律不跟踪，包括：

| 文件 | 为什么不能进仓库 |
|---|---|
| `.firstlaunch` | 「首启向导已完成」标记。带上它，新机器不走向导，没有壁纸也没有显示器布局 |
| `firefox.css` | DMS 的 matugen 产物，换一次壁纸就重写 |
| `plugins/`、`plugins.lock.json` | 第三方插件本体与版本锁，应由插件管理器负责 |
| `plugin_settings.json` | 插件私有数据，可能含 API key、天气城市坐标 |
| `themes/` | 装过的第三方主题，体积不可控 |

用白名单而不是黑名单，是为了 DMS 以后新增文件时不会污染仓库。

## 这里**没有**的东西

- **壁纸、明暗模式、每显示器的布局**在 `~/.local/state/dms/session.json`，不在
  `~/.config/dms` 下，所以 stow 这个包不会还原它们 —— 这是有意的：它们跟机器强相关，
  应该由安装者在自己机器上选一次。
- **配色不是安装器写的**。首次安装只跑 `matugen-restore.sh --configs-only` 落地仓库自带的
  默认配色；之后换壁纸由 DMS 自己 spawn matugen（`settings.json` 里的
  `currentThemeName: dynamic` + `matugenSourceMode: dominant` + `runUserMatugenTemplates: true`
  就是让它跟随壁纸并使用本仓库 `~/.config/matugen/` 下的模板）。想立刻回到仓库默认配色，
  手动跑一次 `bash ~/.config/scripts/matugen-restore.sh`。

## 升级

`settings.json` 里的 `configVersion` **不要删**。DMS 升级到新 schema 时靠它跑迁移链
（改名/新增的键会被搬过去）；没有这个字段时 DMS 会把文件当成当前格式，改名的键就静默失效了。

升级后第一次启动，DMS 可能就地改写这个文件（补新键、迁移旧键），表现为 `git status` 变脏 ——
看一眼 `git diff`，确认是你想要的结果再提交。
