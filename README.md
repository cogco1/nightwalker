# 夜行者 Nightwalker

Godot 4.7.2 像素动作游戏（SK 项目）。设定在 2040 年的佩特拉新城：白天俯视潜行，夜晚侧视长刀战斗。当前基线是 **v14**：601 安全屋 + 地下医院（俯视/侧视双视角）+ v10 人物（64 个动作 × 16 帧 = 1024 帧，含左右空中突刺）。

## 快速开始

1. 把 `godot-path.example.txt` 复制成 `godot-path.txt`，写入本机 Godot 4.7.2 的路径（这个文件不入库）。也可以设环境变量 `NIGHTWALKER_GODOT`。
2. 双击 `Run-Demo.cmd` 试玩，`Open-Editor.cmd` 打开编辑器，`Test-Game.cmd` 跑完整回归。
3. 操作见 [docs/操作说明.txt](docs/操作说明.txt) 和 [docs/游戏内改键说明.txt](docs/游戏内改键说明.txt)。

已验证引擎版本：`4.7.2.stable.official.ed1daf0bf`，GL Compatibility 渲染器。

## 目录

```
Nightwalker/
├─ Run-Demo.cmd / Open-Editor.cmd / Test-Game.cmd   双击入口，都调用 tools/ 里的脚本
├─ godot-path.example.txt                           本机 Godot 路径模板
├─ game/                                            Godot 工程（res:// 根目录）
│  ├─ project.godot                                 320×180 原生分辨率，整数缩放；autoload：SceneRoutes
│  ├─ scenes/                                       main / home_601 / underground_hospital / player
│  ├─ scripts/
│  │  ├─ core/        controls · game_session · scene_routes · story_state
│  │  ├─ player/      player.gd（移动、轻击连招、蓄力重斩、突刺、空战、顿帧信号）
│  │  ├─ ui/          pixel_ui · keybindings_menu
│  │  └─ levels/
│  │     ├─ home_601/   home_601 · home_prop_fx
│  │     └─ hospital/   underground_hospital · hospital_interactions · hospital_security
│  ├─ assets/                                       SpriteFrames、刀尖路径、场景底图与 layout.json、字体、立绘
│  ├─ frames/                                       人物动作帧：<视角>_<方向>_<动作>/00–15.png
│  ├─ art_metadata/                                 原画、提示词、遮罩、导入与校验记录（.gdignore，不参与导入）
│  ├─ tests/                                        回归套件（Test-Game 全部运行）
│  │  ├─ fixtures/      历史战斗环境 combat_lab，只供测试
│  │  ├─ recorders/     录屏、截图脚本（生成 evidence/ 里的图和 GIF）
│  │  └─ legacy/        v02–v06 旧套件，已被 test_v07 取代，不再运行
│  └─ evidence/                                     测试和录制输出（不入库）
├─ tools/
│  ├─ Run-Game.ps1 / Test-Game.ps1 / common.ps1     运行、编辑器、回归
│  └─ art_qa/                                       动作帧和刀光的 Python 校验、预览合成脚本
└─ docs/
   ├─ ARCHITECTURE.md                               运行时结构、脚本职责、扩展点
   ├─ 给下一位开发者或AI的接手说明.txt                必须保留的手感和像素约束
   ├─ 操作说明.txt / 游戏内改键说明.txt / 本版更新.txt
   └─ history/                                      旧版招式说明、v14 交接包的原始说明和验证记录
```

## 测试

`Test-Game.cmd` 先做一次素材导入，再依次跑 13 组套件，日志写到 `game/evidence/logs/`，最后打印每组检查数和总数，有失败时返回非零退出码。

| 套件 | 内容 |
|---|---|
| core_v07 | 移动、三连击、暴击、顿帧、突刺、上挑、1024 帧资源 |
| keybindings / keybindings_reload | 改键保存、冲突、重启读取 |
| air_combat / air_dash_animation_v14 | 二段跳、空中三连、下劈、空中突刺 |
| scene_integration_v14 | 安全屋与医院里的实际玩家、顿帧和改键 |
| hospital_* (5 组) | 医院交互、环境、实体楼梯、病房布局、门禁与电闸 |
| contact_refresh_v07 | 高刷新率下的命中停顿 |
| charged_slash | 点击仍是轻击；按住转蓄力、蓄满松开重斩（3 倍伤害、暴击顿帧）、早松取消、蓄力定身、跳跃和清空输入会打断、突刺和空中不蓄力 |

## 开发约束（摘要）

完整内容见 [docs/给下一位开发者或AI的接手说明.txt](docs/给下一位开发者或AI的接手说明.txt)。

- 320×180 逻辑世界，最近邻整数放大，玩家 `scale = 1`；不要靠缩放人物做动作。
- `project.godot` 里的项目名仍带 v07：`user://` 改键配置目录跟着项目名走，改名会丢掉玩家已有的改键。
- 输入动作 `reset_arena` 现在的意思是“重置位置”，为了兼容已有改键配置保留原名。
- 原画、提示词和校验记录在 `art_metadata/`，不要只留导出帧。
- 正式流程只有安全屋和医院，不放 NPC 和训练木桩；`tests/fixtures` 只供回归。

## 和 v14 交接包的对应关系

| 交接包 | 仓库 |
|---|---|
| `Current_Game/` | `game/` |
| `Current_Game/scripts/*.gd` | `game/scripts/{core,player,ui,levels/…}/` |
| `Current_Game/tests/*.py` | `tools/art_qa/` |
| `Current_Game/Run-Game.ps1`、`Test-Game.ps1` | `tools/` |
| 根目录 `先读我.txt`、`运行验证/` 等 | `docs/history/v14_交接包/` |
| `修改前备份/` 两个 zip | 不入库，原件在 `夜行者_v14_完整转接包.zip` 里 |

`art_metadata/` 里的历史流水线脚本（如 `air_dash_v14/*.py`）保留了原开发机上的绝对路径和旧目录名，只当记录看，不再直接运行。
