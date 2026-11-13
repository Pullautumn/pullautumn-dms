# kitty

终端模拟器，GPU 加速，`Mod+T` / `Mod+Return` 打开的就是它。

## 文件

| 文件 | 作用 |
|---|---|
| `kitty.conf` | 手写主配置：字体、透明度、键位、标签栏 —— 仓库跟踪 |
| `colors.conf` | Catppuccin Mocha 默认配色（深色，底层兜底），被 `include` |
| `dank-theme.conf` | DMS 换壁纸时生成的配色，gitignore |
| `dank-tabs.conf` | DMS 生成的标签栏配色，gitignore |
| `themes/` | `kitten themes` 存主题的地方，gitignore |

## 配色的三层

```
colors.conf          （仓库跟踪，默认色）
      ↓ include
dank-theme.conf      （DMS 的 matugen 生成，覆盖同名选项）
      ↑ include（BEGIN_KITTY_THEME 标记块内）
```

`kitty.conf` 里的标记块长这样：

```conf
include colors.conf

# BEGIN_KITTY_THEME
# DMS
include dank-theme.conf
# END_KITTY_THEME

include dank-tabs.conf
```

**为什么必须有这对标记**：`kitten themes` 认 `# BEGIN_KITTY_THEME` / `# END_KITTY_THEME`。
有标记块时它只替换块内内容；没有时它会往 `kitty.conf` **末尾追加**一行 include ——
而 `~/.config/kitty` 是 stow 软链，追加等于直接改写仓库文件。所以标记块不能删。

`dank-theme.conf` 不存在时 kitty 只记一条 `log_error`，不阻塞启动；也就是说
DMS 一次都没换过壁纸时，你看到的就是 `colors.conf` 的默认色。

## 换配色

正常路径：**在 DMS 里换壁纸**，它会自己跑 matugen 并重写 `dank-theme.conf`，
同时给 kitty 发 reload 信号。

想手动切 `kitten themes` 的官方主题：

```bash
kitty +kitten themes                 # 交互式选
kitty +kitten themes --reload-in=all <主题名>
```

注意这会把 `dank-theme.conf` 那一行换成别的主题名（标记块仍保留），
下次 DMS 换壁纸时又会覆盖回来。

## 不要做的事

- 不要手改 `dank-theme.conf` / `dank-tabs.conf`：下次换壁纸就被覆盖。
- 想改默认配色改 `colors.conf`，但它在 `dank-theme.conf` 之前加载，
  所以同名项会被覆盖 —— 要么删掉 `dank-theme.conf`（DMS 换壁纸时又生成），
  要么在 DMS 设置里关掉动态主题。

## 还原默认色

`~/.config/scripts/matugen-restore.sh` 会做这件事，不需要手动：

```bash
cp ~/.config/kitty/colors.conf ~/.config/kitty/dank-theme.conf
printf '# 已还原为仓库默认配色；在 DMS 里换壁纸时会被重新生成。\n' > ~/.config/kitty/dank-tabs.conf
kill -SIGUSR1 $(pgrep -x kitty)     # kitty 收到 SIGUSR1 会重读配置
```

只 `cp` 而忘了 reload 的话，已经开着的终端里颜色不会变。两份文件都是 gitignore 的运行时产物，
下次在 DMS 里换壁纸会重新生成。
