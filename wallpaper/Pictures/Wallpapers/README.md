# Wallpapers

这个目录是 `~/Pictures/Wallpapers` 的链接目标（由 `_dotfiles_link_wallpapers` 建立），
**图片本身不进 git**：28 张约 50 MB，而 git 只能整仓下载，提交进去就等于让每个
clone 的人都付这份体积，没法按用户分流。

## 安装器怎么处理它

| 安装者 | 行为 |
| --- | --- |
| `pullautumn`（`WALLPAPER_OWNER`） | 目录里有图 → 链接到 `~/Pictures/Wallpapers`；没图且设了 `WALLPAPERS_REPO` → clone 一份 |
| 其他人 | 先清空本目录（只留这份 `README.md`），再建一个空的 `~/Pictures/Wallpapers` 给 DMS 的壁纸选择器用 |

其他人想用自己的壁纸，直接把图丢进 `~/Pictures/Wallpapers` 即可，跟本仓库无关。

清空只针对**仓库里的这个目录**：`git pull` 不会删掉已经在工作副本里的图，所以老 clone
或手工拷贝进来的 50 MB 会在这一步被清掉。`~/Pictures/Wallpapers` 属于用户自己，安装器
不删它（作者链接时若已存在实体目录，也只改名备份成 `Wallpapers.bak.<时间戳>`）。

## 作者换机器时

壁纸不在 git 里，所以新机器 clone 下来这个目录是空的。两种办法：

1. 把备份（网盘 / 移动硬盘）放回本目录，再跑一次 `./install.sh`；
2. 先设环境变量再安装：

   ```bash
   export WALLPAPERS_REPO="git@github.com:<你的壁纸仓库>.git"
   ./install.sh
   ```

   安装器会 clone 到临时目录，把根目录下（或 `Pictures/Wallpapers/` 下）的
   `jpg/jpeg/png/webp` 拷进来。

DMS 的「随机下载动漫壁纸」会直接往这里写图，那些文件同样被 `.gitignore` 忽略。
