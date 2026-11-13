# btop

系统监控（CPU / 内存 / 磁盘 / 网络 / 进程），终端里的「任务管理器」。

部署到 `~/.config/btop`。

## 文件

| 文件 | 说明 |
|---|---|
| `btop.conf` | 主配置：主题、排序方式、背景、键位方案 |
| `themes/catppuccin_mocha.theme` | 备用配色（深色 Catppuccin Mocha，手动切过去用），不随壁纸变 |
| `themes/matugen.theme` | **当前生效**。仓库里没有这个文件（`gitignore`）：首次安装由 `matugen-restore.sh` 写入默认色，之后每次换壁纸由 matugen 覆盖 |

## 关键配置

| 项 | 值 | 含义 |
|---|---|---|
| `color_theme` | `matugen.theme` | 当前主题。**必须和 matugen 的输出同名**，写成别的名字就会一直显示那份固定配色 |
| `theme_background` | `true` | 用主题背景色（关掉则透明） |
| `proc_sorting` | `memory` | 进程默认按内存排序 |
| `vim_keys` | `false` | 用方向键而不是 hjkl |

## 主题切换

```bash
# 交互式换主题
btop  # 按 Esc → Options → color_theme
# 或者直接改 btop.conf 里的 color_theme
```

matugen 会把配色写到 `~/.config/btop/themes/matugen.theme`，并在 `post_hook` 里给 btop 发 `SIGUSR1` / `SIGUSR2` 让它热重载。这个文件**不在仓库里**（被 `.gitignore` 忽略，否则每次换壁纸都会弄脏 git）：

- 首次安装：`matugen-restore.sh --configs-only` 从 `matugen/custom/btop/themes/matugen.theme` 拷一份默认色进来（内容沿用 Catppuccin Mocha，深色；文件名必须是 `matugen.theme`）；
- 之后换壁纸：matugen 覆盖同一个文件，不需要再改 `color_theme`；
- 想固定成深色不再跟壁纸变：跑 `matugen-restore.sh`，它会把 `matugen.theme` 还原成仓库自带的 Mocha。

## 常用键

| 键 | 作用 |
|---|---|
| `Esc` | 菜单 / 退出菜单 |
| `f` | 切换 CPU 频率显示 |
| `p` | 进程树 |
| `+` / `-` | 调整刷新间隔 |
| `/` | 搜索进程 |

## 注意

- `theme_background = true` 配合终端 85% 透明度（kitty 配置）效果最好；终端不透明时建议设成 `false`。
- matugen 的模板里 `theme[main_bg]=""`，所以切到 `matugen.theme` 之后背景走终端底色，不再有 `#1e1e2e` 那种实心底。想要实心背景就把 `matugen/templates/btop.theme` 第 13 行改成
  `theme[main_bg]="{{colors.background.default.hex}}"`。
- 进程排序改成 `memory` 后，CPU 占用高的进程不在最上面，找卡顿时按 `c` 临时切 CPU 排序。
