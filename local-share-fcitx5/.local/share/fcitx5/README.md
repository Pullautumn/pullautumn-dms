# local-share-fcitx5

fcitx5 的**用户级数据**，目前只有两份 Rime 定制补丁，整套来自 **shorin-dux-niri**。

部署到 `~/.local/share/fcitx5`。

## 文件

| 文件 | 说明 |
|---|---|
| `rime/default.custom.yaml` | 对 Rime 默认方案的补丁：方案列表、候选数、Shift 键让位 |
| `rime/rime_ice.custom.yaml` | 对 `rime_ice` 方案的补丁：启用万象语法模型 |

## default.custom.yaml 做了什么

```yaml
patch:
  schema_list:                       # 5 个方案，rime_ice 打头即默认
    - schema: rime_ice
    - schema: luna_pinyin_simp
    - schema: double_pinyin_flypy
    - schema: wubi86
    - schema: bopomofo
  "menu/page_size": 6                # 每页 6 个候选
  "ascii_composer/switch_key/Shift_L": noop   # Shift 交给 fcitx5 的 TriggerKeys / AltTriggerKeys
  "ascii_composer/switch_key/Shift_R": noop
```

`Shift_L` / `Shift_R` 设成 `noop` 之后，Rime 内部不再用 Shift 切中英，判断权交给
fcitx5 的 `[Hotkey/TriggerKeys]`（`Shift_L`）和 `[Hotkey/AltTriggerKeys]`（`Shift_R`）。
单按后 250ms 内不接别的键才会切换，所以正常打字时按 Shift 输大写不会被误判。

这里**故意没有写 `good_old_caps_lock`**。不写就走 Rime 默认的 `false`，CapsLock 由 Rime 接管，
按下去切 ASCII 模式并弹提示；写成 `true` 则 CapsLock 交还系统、只切大小写、完全不弹提示。

## rime_ice.custom.yaml 做了什么

```yaml
patch:
  "grammar/language": wanxiang-lts-zh-hans
```

启用万象语法模型给雾凇拼音做长句调序。**需要模型文件**（`wanxiang-lts-zh-hans.gram` 之类，
放在 `~/.local/share/fcitx5/rime/` 或共享数据目录）。没装的话 Rime 会忽略这一行，
在 `rime.INFO` / `rime.ERROR` 日志里留一条 warning，输入本身不受影响。

## 生效

Rime 的补丁文件改完必须重新部署：

```bash
fcitx5-remote -r        # 重启输入法
```

或在托盘图标右键 →「重新部署」。只重启 fcitx5 不重新部署的话，补丁不会生效。

## 前置条件

`default.custom.yaml` 里的 5 个方案来自两处：

| 来源 | 提供的方案 |
|---|---|
| `librime`（`fcitx5-rime` 的依赖） | `luna_pinyin_simp`、`double_pinyin_flypy`、`wubi86`、`bopomofo` |
| `rime-ice-git`（AUR） | `rime_ice`（雾凇拼音） |

两个都在核心包清单的 `input` 组里，一键安装会一起装上。方案文件装到系统共享目录
（`/usr/share/rime-data/`），Rime 直接从那里加载，**不需要**手工往 `~/.local/share/fcitx5/rime/`
里拷任何东西 —— 这个用户目录只放你自己的补丁和 `*.custom.yaml`。

首次启动会自动编译词库，可能要十几秒；没编完就 `fcitx5-remote -r`，或在托盘菜单里点「重新部署」。

## 注意

- Rime 的自定义文件命名规则是「原名 + `.custom`」：想改 `rime_ice` 的参数就建
  `rime_ice.custom.yaml`，不要往 `default.custom.yaml` 里塞不属于它的键。
- `default.custom.yaml` 会和 `~/.local/share/fcitx5/rime/default.yaml` 合并，后者是自动生成的，别手改。
- Rime 报错时看 `~/.local/share/fcitx5/rime/` 下的 `*.log`，比界面提示有用。
- `installation.yaml`、`user.yaml`、`sync/`、`rime_ice.userdb/`、`themes/` 都是运行期产物，已进 `.gitignore`。
