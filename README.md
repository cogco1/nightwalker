# 夜行者 Nightwalker

Godot 4.7.2 像素动作游戏（SK 项目）。设定在 2040 年的佩特拉新城：白天俯视潜行，夜晚侧视长刀战斗。当前基线是 **v14**：601 安全屋 + 地下医院（俯视/侧视双视角）+ v10 人物（64 个动作 × 16 帧 = 1024 帧，含左右空中突刺）。

## 快速开始

1. 把 `godot-path.example.txt` 复制成 `godot-path.txt`，写入本机 Godot 4.7.2 的路径（这个文件不入库）。也可以设环境变量 `NIGHTWALKER_GODOT`。
2. 双击 `Run-Demo.cmd` 试玩，`Open-Editor.cmd` 打开编辑器，`Test-Game.cmd` 跑完整回归。`Run-NightStreet.cmd` 直接进夜街赛博原型（不在正式流程里）。
3. 操作见 [docs/操作说明.txt](docs/操作说明.txt) 和 [docs/游戏内改键说明.txt](docs/游戏内改键说明.txt)。

已验证引擎版本：`4.7.2.stable.official.ed1daf0bf`，GL Compatibility 渲染器。

## 目录

```
Nightwalker/
├─ Run-Demo.cmd / Open-Editor.cmd / Test-Game.cmd   双击入口，都调用 tools/ 里的脚本
├─ Run-NightStreet.cmd                              直接启动夜街原型场景
├─ godot-path.example.txt                           本机 Godot 路径模板
├─ game/                                            Godot 工程（res:// 根目录）
│  ├─ project.godot                                 320×180 原生分辨率，整数缩放；autoload：SceneRoutes
│  ├─ scenes/                                       main / home_601 / underground_hospital / player / night_street_proto
│  ├─ shaders/                                      人物赛博配色、发光层、湿地反光、低雾、暴露度色差
│  ├─ scripts/
│  │  ├─ core/        controls · game_session · scene_routes · story_state
│  │  ├─ player/      player.gd（移动、轻击连招、蓄力重斩、突刺、空战、顿帧信号）
│  │  ├─ ui/          pixel_ui · keybindings_menu
│  │  └─ levels/
│  │     ├─ level_kit.gd 关卡共用：碰撞体、镜头跟随
│  │     ├─ home_601/   home_601 · home_prop_fx
│  │     ├─ hospital/   underground_hospital · hospital_interactions · hospital_security
│  │     └─ night_street/ night_street · beam_drone · hover_target · rain（原型）
│  ├─ assets/                                       SpriteFrames、刀尖路径、场景底图与 layout.json、字体、立绘；
│  │                                                fx/ 人物查找表、材质和义体锚点，night_street/ 夜街分层底图和灯光表；
│  │                                                audio/sfx/ 战斗音效（合成占位）
│  ├─ frames/                                       人物动作帧：<视角>_<方向>_<动作>/00–15.png
│  ├─ art_metadata/                                 原画、提示词、遮罩、导入与校验记录（.gdignore，不参与导入）
│  ├─ tests/                                        回归套件（Test-Game 全部运行）
│  │  ├─ fixtures/      历史战斗环境 combat_lab，只供测试
│  │  ├─ recorders/     录屏、截图脚本（生成 evidence/ 里的图和 GIF）
│  │  └─ legacy/        v02–v06 旧套件，已被 test_v07 取代，不再运行
│  └─ evidence/                                     测试和录制输出（不入库）
├─ tools/
│  ├─ Run-Game.ps1 / Test-Game.ps1 / common.ps1     运行、编辑器、回归
│  ├─ art/                                          夜街底图和人物查找表的生成脚本（可重复生成）
│  ├─ audio/                                        战斗音效合成脚本 gen_combat_sfx.py
│  └─ art_qa/                                       动作帧和刀光的 Python 校验、预览合成脚本；compose_combat_capture.py 把录屏帧和音效时间线合成带声音的 MP4
└─ docs/
   ├─ ARCHITECTURE.md                               运行时结构、脚本职责、扩展点
   ├─ 给下一位开发者或AI的接手说明.txt                必须保留的手感和像素约束
   ├─ 操作说明.txt / 游戏内改键说明.txt / 本版更新.txt
   └─ history/                                      旧版招式说明、v14 交接包的原始说明和验证记录
```

## 测试

`Test-Game.cmd` 先做一次素材导入，再依次跑 14 组套件，日志写到 `game/evidence/logs/`，最后打印每组检查数和总数，有失败时返回非零退出码。

| 套件 | 内容 |
|---|---|
| core_v07 | 移动、三连击、暴击、顿帧、Shift 单按突刺（朝按住方向或面向）、上挑、1024 帧资源 |
| keybindings / keybindings_reload | 改键保存、冲突（突刺不能和跑步共用）、旧存档突刺键迁移、重启读取 |
| air_combat / air_dash_animation_v14 | 二段跳、空中三连、下劈、空中突刺 |
| scene_integration_v14 | 安全屋与医院里的实际玩家、顿帧和改键 |
| hospital_* (5 组) | 医院交互、环境、实体楼梯、病房布局、门禁与电闸 |
| contact_refresh_v07 | 高刷新率下的命中停顿 |
| charged_slash | 点击仍是轻击；按住转蓄力（逐帧收刀、后撤约 3 像素）、蓄满松开重斩（前冲至少 24 像素、3 倍伤害、暴击顿帧）、早松取消、蓄力定身、跳跃和清空输入会打断、突刺和空中不蓄力；真实场景里轻击 4 帧、重斩 10 帧顿帧和音效顺序 |
| night_street_proto | 人物材质覆盖所有场景、光束暴露与标记、无人机连击和顿帧、原型专用按键、正式流程没有路由到原型 |

## 赛博朋克视觉原型（分支 proto/night-street-cyber）

- 人物：`assets/fx/character_cyber.tres` 挂在 `player.tscn` 的 Sprite 上，所以安全屋、医院、夜街都生效。它按 18 色查找表（`assets/fx/cyber_palette.png`）换色，按光源方向给朝光的边缘上色、背光一侧压暗，刀刃三种钢色和脸部两种肤色做成自发光（刀光、目镜）。原帧一张没改；`look = 0` 就是原配色。
- 夜街：`scenes/night_street_proto.tscn`，只有侧视。CanvasModulate 压暗，PointLight2D 街灯和霓虹，三层视差（A 区巨塔和总控塔、佩特拉卡兹尼神殿式岩壁立面、C 区楼房和金域大厦）加街面层，巡逻无人机的监控光束（光束里飘着微光粒子），湿地反光、雨、低雾、WorldEnvironment 辉光。底图由本机 Codex 的 image_gen 生成、降到原生像素后拼装，过程记录在 `game/art_metadata/night_street_v15/`；脚本占位版留在 `game/assets/night_street_placeholder/`。
- 义体：兜帽下的洋红目镜；斜挎带、腰带和肩带是反光条，被灯照到就亮成那盏灯的颜色；握刀手的前臂上有一块被刮掉的条码疤（设定里主角没有身份序列号），偶尔闪红。站进光束时头顶弹出扫描面板，显示“ID 无法识别”。
- 光 = 被监控：站进光束，右上角暴露条上升、画面出现轻微色差；暴露满了被标记，光束变红并追人，离开光束一段时间后解除。
- 夜街操作：AD 走、空格跳、左键连斩、按住左键蓄力重斩、按一下 Shift 突刺；F9 切换赛博配色和原配色对比；R 重置；Tab 在这里不切视角。
- 改动清单：[docs/prototypes/夜街赛博原型_改动清单.md](docs/prototypes/夜街赛博原型_改动清单.md)。

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
