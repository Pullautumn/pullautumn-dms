# gtk-3.0

GTK3 程序的全局外观：主题、图标、字体、光标，以及 Nautilus 侧边栏 / 文件对话框的书签。

部署到 `~/.config/gtk-3.0`。

## 文件

| 文件 | 说明 |
|---|---|
| `settings.ini` | GTK3 主题、图标主题、字体、光标、工具栏样式、抗锯齿 |
| `colors.css` | 由 matugen 生成，覆盖主题配色 |
| `bookmarks` | 侧边栏书签。**安装时按 `$HOME` 生成，不在仓库里**（见下节） |

## settings.ini 关键项

| 项 | 值 | 含义 |
|---|---|---|
| `gtk-theme-name` | `Adwaita` | 基础主题 |
| `gtk-icon-theme-name` | `Adwaita` | 图标主题 |
| `gtk-font-name` | `Adwaita Sans 11` | 界面字体与字号 |
| `gtk-cursor-theme-name` | `Adwaita` | 光标主题 |
| `gtk-cursor-theme-size` | 24 | 光标大小 |
| `gtk-toolbar-style` | `GTK_TOOLBAR_ICONS` | 工具栏只显示图标 |
| `gtk-button-images` / `gtk-menu-images` | 0 | 按钮和菜单不显示图标 |
| `gtk-enable-event-sounds` | 1 | 开启事件音效 |
| `gtk-enable-input-feedback-sounds` | 0 | 关闭输入反馈音 |
| `gtk-xft-antialias` / `gtk-xft-hinting` | 1 / 1 | 抗锯齿与微调 |

## 书签

`~/.config/gtk-3.0/bookmarks` 决定 Nautilus 侧边栏（以及 GTK 打开/保存对话框、Thunar 的侧栏）里「固定」着哪些目录。

**这个文件不在仓库里**。GTK 只认绝对 `file://` URI，不展开 `~`、也不读环境变量，内容必然跟用户名绑定 —— 所以由 `setup/steps/03-dotfiles.sh` 的 `_dotfiles_generate_bookmarks()` 在安装时按 `$HOME` 现生成，`.gitignore` 已经把它排除。

生成时**直接写仓库里这份**，而不是「`$HOME` 下那份」：`~/.config/gtk-3.0` 在这一层被 stow 折叠成指向仓库的软链，`$HOME` 下根本不存在第二份可以改的文件。这也是为什么不要用 `sed` 去替换 `~/.config` 里的用户名 —— 改的其实是仓库本身，`git status` 会脏、`git pull` 会冲突。

格式是一行一条：`file://绝对路径` 后跟一个空格和显示名（可省略，省了就显示目录名）。路径里的空格要写成 `%20`，非 ASCII 要百分号转义。**行顺序就是侧栏顺序**，GTK 不做排序。

当前清单，生成出来长这样（标 `~` 的两条只在作者机器上出现）：

```
file:///home/<user>/Code
file:///home/<user>/dotfiles dotfiles
file:///home/<user>/Downloads Downloads
file:///home/<user>/Documents Documents
file:///home/<user>/Pictures Pictures
file:///home/<user>/Music Music
file:///home/<user>/Videos Videos
file:///home/<user>/.config .config      # 仅作者
file:///home/<user>/.local .local        # 仅作者
```

两个容易踩的点：

- **`dotfiles` 一条两种路径都认**：先看 `~/dotfiles`（软链写法），不存在就退到
  `~/.dotfiles`（clone 的默认目录名）。只写死前者的话，默认装出来这条直接消失。
- **标准 XDG 目录在安装阶段通常还不存在**：它们由**首次登录**的 `xdg-user-dirs-update`
  创建，而书签是 Phase 3（`03-dotfiles.sh`）生成的。所以生成函数会先用 `xdg-user-dir`
  查真实路径（本地化目录名、自定义位置都能对上；`Downloads` 对应的常量是单数 `DOWNLOAD`），
  再 `mkdir -p` 补建，最后才写书签。早期版本只判 `[[ -d ]]` 就跳过 —— 结果侧边栏只剩
  安装途中顺带建出来的 `~/Pictures` 一项（壁纸链接建的那个），其余全丢。

**作者本人那台还多两条**：`.config`、`.local`。判定方式和壁纸、uv 镜像源一致 ——
`TARGET_USER`（`id -un`）小写后等于 `WALLPAPER_OWNER`（默认 `pullautumn`，可用环境变量覆盖）才加：

```bash
if [[ "${TARGET_USER,,}" == "${WALLPAPER_OWNER,,}" ]]; then
    rels+=(.config .local)
fi
```

这不是发行版该有的默认 —— 直接跳进 `~/.config` 是改配置时的个人习惯，对别的用户只是噪音，还容易误点删东西。所以别人的机器上侧栏只有 7 项，作者的是 9 项。

### XDG 目录到底是不是 GTK 自动加的

旧版本（Nautilus 43–4x）的 `GtkPlacesSidebar` 确实会按 `~/.config/user-dirs.dirs` 自己加
Documents / Downloads / Music / Pictures / Videos，那时 `bookmarks` 里写它们属于冗余
（`_gtk_bookmarks_manager_get_is_builtin()` 判成 builtin 直接跳过）。

**但 Nautilus 51.1 实测不是这样**：书签里只写 `Pictures` 时，侧边栏就只有
Home / Recent / Starred / Network / Trash + **Pictures** 一项，`Downloads`/`Documents`/
`Music`/`Videos` 全都不出现。也就是说现在的「固定目录」完全由这份文件决定。

所以清单里保留这些行是必需的，不是可删的冗余。多写也无副作用（认得 builtin 的版本会去重）。

侧栏显示英文目录名而不是「下载」「文档」，跟这份文件无关 —— 那是首次登录时
`xdg-user-dirs-update` 按 locale 生成的 `user-dirs.dirs` 决定的（系统 locale 英文，所以是
英文名）。安装器跑在登录之前，这一步不归它管。

### GTK4 也读这个路径

Nautilus 43+ 已经是 GTK4，但 `GtkBookmarksManager` 里明写着 *"Use gtk-3.0's bookmarks file as the format didn't change"* —— 路径仍然是 `~/.config/gtk-3.0/bookmarks`，不需要（也没有）`gtk-4.0/bookmarks`。只有在它不存在时，才会读一次 GTK2 时代的 `~/.gtk-bookmarks` 并迁移过来。

### 怎么改

- **改清单**：编辑 `_dotfiles_generate_bookmarks()` 里那个 `local -a rels=(...)` 数组，加一项就多一个候选目录。标准 XDG 目录（Downloads/Documents/Pictures/Music/Videos）会自动查路径并补建，其余目录写成 `$HOME/<名字>`，不存在就跳过。想让 `.config`/`.local` 对所有人生效，把 `WALLPAPER_OWNER` 那段判断去掉即可。
- **临时加一个**：Nautilus 里右键目录 →「Add to Bookmarks」（`Ctrl+D`），写的就是这个文件；取消用右键菜单里的「Remove from Bookmarks」。
- **不要只在 GUI 里点**：改的是仓库那份（软链），重装或重跑 Phase 3 时又会被生成函数覆盖。想长期保留就改生成函数的清单。
- 改完存盘即生效，不用重启 Nautilus —— GTK 用 `GFileMonitor` 盯着这个文件（只对已经打开的应用有效，新开的应用读的是最新内容）。

## 配色

matugen 的 `gtk3` 模板会写 `~/.config/gtk-3.0/colors.css`，GTK 应用启动时读取它覆盖主题色。也就是说**换个壁纸，GTK 程序的主色就变了**。

## 注意

- 默认图标主题是自带的 `Adwaita`（安装器也会 `gsettings set ... icon-theme "Adwaita"`）。DMS 的 `iconThemeDark/Light` 默认是 `"System Default"`、`iconThemePerMode=false`，所以**换壁纸不会被 DMS 改掉**。
- 但**我们自己的** matugen 模板 `gtk-folder` 会改：每次生成配色都会跑
  `recoloricons.sh`，把文件夹图标重着色到 `Adwaita-Matugen-A` / `Adwaita-Matugen-B`
  （按当前主题交替，用来强制 GTK 重读缓存），最后 `gsettings set icon-theme <那个>`。
  `matugen-restore.sh` 会把它切回 `Adwaita` 并删掉这两个目录 —— 注意该脚本把这一步放在
  **最后**（等重着色进程停下、掐掉、再写 gsettings、最后删），原因见 `scripts/README.md`。
- `gtk-4.0` 目录不在本仓库里，但 matugen 会往 `~/.config/gtk-4.0/colors.css` 写配色；想让 GTK4 程序也跟随，自己建个目录放一份 `gtk.css` 引用它。
- Flatpak 应用默认读不到 `~/.config/gtk-3.0`，安装器 Phase 5 已给 flatpak 放行 `xdg-config/gtk-3.0` 等路径。
