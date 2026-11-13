# matugen

Material You 配色生成器：从壁纸提取主色，按模板渲染出一整套配置写回各应用的配置目录。
换壁纸就等于换整套主题。

## 本项目里的分工

**DMS（dux-shell）自己会跑 matugen**，生成这些文件，本仓库不重复做：

| 输出 | 消费者 |
|---|---|
| `~/.config/niri/dms/colors.kdl` | niri 边框 / focus-ring / shadow |
| `~/.config/kitty/dank-theme.conf`、`dank-tabs.conf` | kitty（`kitty.conf` 的 `BEGIN_KITTY_THEME` 标记块 include） |
| `~/.config/gtk-3.0/dank-colors.css`、`gtk-4.0/…` | GTK3/GTK4 |
| `~/.config/qt5ct|qt6ct/colors/matugen.conf` | Qt 应用 |

所以 `config.toml` 只保留 DMS 不管的部分：

| 模板 | 输出 | 备注 |
|---|---|---|
| btop | `~/.config/btop/themes/matugen.theme` | `SIGUSR1/2` 让 btop 重载 |
| fastfetch | `~/.config/fastfetch/config.jsonc` | |
| fuzzel | `~/.config/fuzzel/colors.ini` | fuzzel 只当 spotlight 的兜底 |
| fcitx5 | `~/.local/share/fcitx5/themes/Matugen/theme.conf` | post_hook 走 `busctl ... ReloadAddonConfig classicui`，**不用** `fcitx5 -r`（会拉起第二个实例） |
| pywalfox | `~/.cache/wal/colors.json` | `pywalfox update` 推给 Firefox |
| gtk-folder | `~/.cache/matugen/recoloricons.sh` | 把 Adwaita 图标目录重染色（A/B 两套轮换） |

gtk3 / gtk4 / kitty / niri / qt5ct / qt6ct 这几个模板**已经从仓库删掉**了 ——
它们的输出文件由 DMS 写，留着只会让人误以为可以开。

想整体关掉 DMS 的动态配色：DMS 设置里关「动态主题」，或设环境变量 `DMS_DISABLE_MATUGEN=1`。

## 手动跑一次

```bash
matugen image ~/Pictures/Wallpapers/xxx.png            # 按 config.toml 全部渲染
matugen image ~/Pictures/Wallpapers/xxx.png -m dark    # 指定明暗
```

注意：手动跑**不会**更新 DMS 的那几份文件。想连 DMS 一起换，请用 DMS 的壁纸面板换图。

## 首次安装的配色

安装器**不跑 matugen**，只执行 `~/.config/scripts/matugen-restore.sh --configs-only`，
把 btop / fastfetch / fuzzel / fcitx5 还原成仓库自带的默认配色（`custom/` 目录里的那几份，
Catppuccin Mocha 深色，与主仓库 `pullautumn` 一致）。
这样刚装完就有一套能看的配色，不依赖任何壁纸。

`custom/` 的目录结构与还原目标：

| 文件 | 还原到 | 备注 |
|---|---|---|
| `custom/btop/themes/matugen.theme` | `~/.config/btop/themes/matugen.theme` | 文件名必须是 `matugen.theme` —— `btop.conf` 的 `color_theme` 指向它，名字不对 btop 就永远读不到壁纸配色 |
| `custom/fastfetch/config.jsonc` | `~/.config/fastfetch/config.jsonc` | |
| `custom/fuzzel/colors.ini` | `~/.config/fuzzel/colors.ini` | |
| `custom/fcitx5/theme.conf` | `~/.local/share/fcitx5/themes/Matugen/theme.conf` | 不在 `~/.config` 下，脚本里用 `源:目标` 写法单独指定。**注意**：`classicui.conf` 的 `Theme=default`，所以这份文件写进去但当前不生效，留着是为了将来切回 `Theme=Matugen` 时直接能用 |

前三个按「`~/.config` + 相对路径」自动推导，第四项要在 `RESTORE_LIST` 里写成
`"fcitx5/theme.conf:.local/share/fcitx5/themes/Matugen/theme.conf"`。
复原 fcitx5 时同时会把 `classicui.conf` 的 `Theme=` 拉回 `default`（fcitx5 自带主题，
与主仓库的还原态一致），再用
`busctl ... ReloadAddonConfig classicui` 让插件重载 —— **不用** `fcitx5 -r`，那会起第二个实例。
选了 `default` 之后 fcitx5 就不再跟壁纸变色；想重新跟随，把 `classicui.conf` 的 `Theme`
改成 `Matugen`（matugen 仍在写那份 theme.conf）。

这里**只放 matugen 真的会生成的文件**。跟配色无关的个人配置（VS Code 设置、Python 镜像源
之类）不要往 `custom/` 里塞 —— 它叫 matugen 的 custom，语义就是配色产物的仓库。
这类东西走各自的 stow 包，需要按用户分流就在 `setup/lib/config.sh` 的 `STOW_PACKAGES`
上做条件追加（`uv` 就是这么处理的）。
