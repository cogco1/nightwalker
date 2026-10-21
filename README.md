# 夜行者 · 工厂黄沙与战斗白盒

双击 `Run-Demo.cmd`，选择“序章 · 工厂黄沙”或“进入白盒测试”。也可用 `Run-Battlefield.cmd`、`Run-Whitebox.cmd` 直接启动对应地图。使用 Godot 4.7.2；首次启动会导入素材。本机路径写在不入库的 `godot-path.txt`，更换电脑按 `godot-path.example.txt` 配置。

“工厂黄沙”使用仓库现有的6144像素工业地图，远景、中景、近景、前景一起接入，保留原视差、地形碰撞、破车、建筑通路、升降机和环境动画。原图未重绘、未压平或缩放。地图左上角可返回入口，再进入白盒。

白盒只生成用户要求的狙击手和机炮无人机：

- 狙击手远距离卧射、中距离站姿射击、近距离枪托攻击，瞄准激光、曳光弹和出生区域驻守保留。枪托动作完成收招后直接回待机，修正误接站姿开火动作造成的停顿。
- 无人机自然悬浮、曳光机炮、命中击退、区域内追击、低血自爆及撤远后加速冲撞自爆保留。
- 玩家受击保护、正背面大幅受击动作、轻微受击镜头震动、完美闪避专用动作与反击、近战前后摇及防连续硬直保留。
- 屏幕切割、破屏裂口、飞行剑气、蓄力黑红刀气及F10开关已删除。
- 近战安保、持枪保镖、夜战买家与医生、旧巡光/近战无人机和其他未指定敌怪的运行内容已删除；敌人动作预览只保留狙击手与无人机。
- 地下医院场景、地图素材、脚本及其旧测试入口已删除。旧章节设计和验证记录为历史资料，不能当作当前功能说明。

操作：AD移动，空格跳跃，鼠标左右键攻击，短按并松开Shift闪避，长按Shift奔跑；F1/Esc设置。工厂地图靠近升降机按E呼叫/启动，R回起点。白盒按1到狙击手附近、2到无人机区域、R重置角色和敌人；右上按钮返回启动页。`Run-Melee.cmd`为狙击手近战练习，`Run-Sniper.cmd`、`Run-Drone.cmd`保留单独试玩。

## 当前功能清单

清单里的每一项都有启动入口和 `Test-Game.cmd` 里的回归。不在清单里的玩法、场景和代码不算现行功能；新增或删除一项时同时改这张表和 `tools/Test-Game.ps1`。

| 内容 | 入口 | 回归（`game/tests/`） |
|---|---|---|
| 启动页：“序章 · 工厂黄沙”和“进入白盒测试”两个按钮 | `Run-Demo.cmd`（`scenes/boot.tscn`） | `test_map_entry_v07` |
| 序章 · 工厂黄沙：6144 像素工厂地图、视差、地形碰撞、通路、升降机、环境动画 | 启动页，或 `Run-Battlefield.cmd` | `test_battlefield_run_test` |
| 战斗白盒：狙击手和机炮无人机，1/2 传送，R 重置 | 启动页，或 `Run-Whitebox.cmd` | `test_map_entry_v07` |
| 狙击手、机炮无人机、狙击手近战的单独试玩 | `Run-Sniper.cmd`、`Run-Drone.cmd`、`Run-Melee.cmd` | `test_sniper_combat`、`test_drone_combat`、`test_enemy_territory_v05`、`test_melee_rhythm_v06` |
| 玩家：移动、跳跃、攻击与蓄力、闪避与突刺、完美闪避与反击、受击保护 | 以上所有场景 | `test_v07`、`test_moveset`、`test_player_hurt`、`test_perfect_dodge_v05`、`test_perfect_counter` 等 |
| F1 / Esc 设置与改键（E 固定为交互键） | 所有场景 | `test_keybindings`、`test_level_shared` |
| 601 安全屋：俯视，E 调查家具，屏幕和台灯照到主角，R 回出生点 | `Run-Sandbox.cmd`（`scenes/main.tscn`） | `test_scene_integration_v14`、`test_home_furniture`、`test_interior_lighting`、`test_level_shared` |
| 夜街原型：侧视地图探索，没有敌人 | `Run-NightStreet.cmd` | `test_night_street_proto` |
| F8 在安全屋和夜街之间往返，回到离开时的位置 | 安全屋或夜街里按 F8 | `test_scene_routes` |
| 敌人动作预览（狙击手、无人机） | 编辑器打开 `scenes/enemy_animation_gallery.tscn` | `test_enemy_animation_gallery` |

地下医院、第一章剧情（章节进度、暗网终端、屏息过场、教学提示）、F 键处决和旧敌人已删除，最后一版在归档分支 `archive/hospital-chapter-20261021`（main `1699a05`）。

修改范围约定见 [AGENTS.md](AGENTS.md)。运行 `Test-Game.cmd` 检查当前保留功能；验证详情见 [combat-v07.json](docs/verification/combat-v07.json)。
