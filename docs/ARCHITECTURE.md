# 架构

这份文档描述 v14 的运行时结构。场景文件几乎是空壳：每个 `.tscn` 只挂一个脚本，节点树由脚本在 `_ready()` 里按 `layout.json` 搭建。

## 场景流转

```
启动 → scenes/main.tscn（NightwalkerHome，脚本同 home_601.gd）
          │  门口 E / F7
          ▼
SceneRoutes.switch_to()  ←── autoload，只允许在安全屋和医院之间切换
          │
   ┌──────┴───────┐
home_601.tscn   underground_hospital.tscn
```

- `SceneRoutes`（`scripts/core/scene_routes.gd`）是唯一的 autoload。它处理 F7 快捷往返（F7 被玩家改键占用时不抢键），切场景前取消顿帧、恢复暂停和画布变换。
- `main.tscn` 和 `home_601.tscn` 都挂 `home_601.gd`。`main.tscn` 是项目入口，切回安全屋时用 `home_601.tscn`。

## 每个关卡的节点

```
Home601 / UndergroundHospital (Node2D, 关卡脚本)
├─ world (Node2D)          底图 Sprite2D、碰撞体、道具
│  └─ Player               scenes/player.tscn 实例
├─ GameSession (Node)      scripts/core/game_session.gd
│  ├─ KeybindingsMenu      scripts/ui/keybindings_menu.gd
│  └─ 顿帧覆盖层 CanvasLayer(100)
├─ HospitalInteractions    （仅医院）对话、阅读、楼梯、出口
├─ HospitalSecurity        （仅医院）密码门、电闸
└─ UI CanvasLayer          标题、提示、对话框（pixel_ui.gd 统一字体和立绘）
```

- **GameSession**：所有有玩家的场景共用，测试夹具 combat_lab 也挂同一个（夹具里原来那份顿帧副本已删除，测到的就是正式代码）。负责 F1/Esc 改键菜单；监听玩家的 `impact(档位, 方向)` 信号，按 `STOPS` 表做全屏顿帧：light 4 帧 / 至少 0.0667 秒、critical 6 帧 / 至少 0.1 秒（这两档是原作保证）、heavy 10 帧偏移 2 像素并闪白，critical 和 heavy 结束后镜头有几帧余震。对外有 `hit_stop_started / hit_stop_frame / hit_stop_finished` 信号和帧数、时长等观测字段。
- **CombatFeedback**（`scripts/core/combat_feedback.gd`）：GameSession 的子节点，`PROCESS_MODE_ALWAYS`，所以顿帧暂停时命中声不被截断。只听玩家主动发的信号：`move_started(招式)` 决定挥刀声，`impact(档位)` 决定命中声，`charge_started / charge_ready / charge_ended` 决定蓄力声，不读玩家内部字段；`played` 记录播放顺序供测试和录屏使用。音效是 `tools/audio/gen_combat_sfx.py` 合成的占位 WAV（`assets/audio/sfx/`），同名替换即可换成正式音效。无头模式下只记录不播放。
- **NightwalkerStoryState**（`scripts/core/story_state.gd`）：由 `hospital_security.gd` 按需挂到 `/root`，存放本次进程内的物品和标记（`grant_item`、`has_item`、`set_flag`、`has_flag`）。没有存档，退出游戏就清空。
- **Controls**（`scripts/core/controls.gd`）：静态类，持有当前按键方案，读写 `user://keybindings.cfg`，把方案应用到 InputMap。各脚本通过 `CONTROLS.binding_pressed(slot)` 读输入。

## 玩家

`scenes/player.tscn` = `CharacterBody2D` + `AnimatedSprite2D` + 脚底碰撞盒。玩家代码分三块：

- `scripts/player/player.gd`：移动、状态机、按键意图、出招和命中判定。
- `scripts/player/moves_long_blade.gd`：**招式表**。每个招式的动画、帧速、起始帧、判定帧、判定框、前冲、暴击规则、顿帧档位、命中反应、空中滞空、收招等都写在 `MOVES` 里，连段图写在 `STRINGS` 里（当前招式 → 输入 → 下一招）。加新招式只在这里加数据，`tests/test_moveset.gd` 会检查动画、判定帧和刀尖路径是否齐全。
- `scripts/player/player_fx.gd`：特效层（尘土、火花、斩痕和冲击线、气流、蓄力光粒、刀光轨迹、残影），玩家的第一个子节点，画在人物身后，由玩家的物理帧驱动，装饰随机数和暴击判定分开。

状态：`state` 是一个枚举 FREE / ATTACK / CHARGE / RECOVERY / HURT；`move_id`、`move` 是当前招式，`move_ticks` 是它走过的物理帧数。`is_attacking`、`is_charging`、`special_kind`、`combo_stage` 都是从 `state` 和 `move` 算出来的只读值。

按键意图：每次按键记成一条意图（`_intents`），时间按玩家自己的战斗时钟 `combat_time` 计，这个时钟只在玩家的物理帧里走，所以顿帧期间不走。左键按下先记为"刚按下"，下一个物理帧按原规则转成"排队的下一段"（缓冲 0.22 秒，最长延到这一刀结束、上限 0.55 秒）、"收招后开新连段"，或者丢掉；按住不会自动连段。突刺键记 0.15 秒缓冲。顿帧期间转发进来的 S 只记意图，冻结结束后才下劈。`queued_attack`、`pending_new_attack`、`attack_buffer_left`、`_mouse_attack_pending` 是从意图表算出来的只读值。

具体动作：

- `view_mode`：0 = 俯视（`assets/top_down.tres`），1 = 侧视（`assets/side_view.tres`）。关卡在实例化时设置，医院 Tab 切换时重建。
- 地面：步行/跑步加减速、三连击（第三刀 30% 三倍暴击）、W+左键上挑、按一下突刺键（`dash_modifier`，默认 Shift）朝按住的方向或面向突刺 48 像素（攻击中按下有 `DASH_BUFFER_SECONDS` 0.15 秒缓冲）、下蹲。`dash_modifier` 这个 slot 名为兼容旧存档保留，现在是单按键；读档时它若和跑步键相同，`controls.gd` 只把它挪到空闲键。
- 蓄力重斩：一段地面轻击结束时左键仍按着，就进入 `is_charging`：前 60%（`CHARGE_COIL_PORTION`）从 attack3 第 0 帧逐帧收到第 3 帧并后撤 `CHARGE_BACKSTEP` 3 像素，之后原地不动，蓄满后 sprite 左右 1 像素微颤；`charge_time` 到 `CHARGE_FULL_SECONDS` 发 `charge_ready`；松开时蓄满就以 `special_kind = "heavy_slash"` 从第 4 帧播 attack3（46 fps，第 4–9 帧前冲 `HEAVY_LUNGE` 32 像素并留 2 个残影，判定加长 10、加宽 8，固定暴击、不掷骰），否则取消。离地、`clear_input_buffer()` 都会取消蓄力。
- 空中：二段跳、空中三连、S 下劈和落地冲击、空中突刺（结束接 `air_idle`，0.30 秒、6 像素/秒缓降）。
- 刀尖命中区按 `assets/blade_paths.json` 逐帧取刀刃位置，和画面上的钢刃一致。
- 对外信号：`impact(档位, 方向)`（每段攻击第一次命中时发一次）、`move_started(招式)`、`attack_started`、`attack_hit`、`combo_changed`、`hit_resolved`、`critical_hit`、`normal_contact_stop`、`special_started`、`landing_impact`、`charge_started`、`charge_ready`、`charge_ended(released)`。外部输入走 `handle_input(event)`，回到待机用 `show_idle()`。
- 命中特效分三档（轻、暴击、重斩）：沿挥刀方向的斩痕、放射冲击线、火花；顿帧会冻结在这一帧上。

## 数据和素材

| 位置 | 内容 |
|---|---|
| `frames/<视角>_<方向>_<动作>/NN.png` | 64 个动作 × 16 帧。原 992 帧保持原字节，v14 新增 `air_dash_stab_*` 32 帧（112×96 画布，足点 56,84） |
| `assets/side_view.tres`、`top_down.tres` | 把 frames 组装成 SpriteFrames |
| `assets/home_601/layout.json` | 安全屋碰撞、可交互物、对话文本 |
| `assets/underground_hospital/layout.json` | 医院俯视两层和侧视的房间、墙、楼梯、门禁、交互点 |
| `assets/fonts/` | fusion-pixel 10/12px 中文像素字体（OFL） |
| `art_metadata/` | 原画、提示词、遮罩、导入脚本和校验报告；有 `.gdignore`，Godot 不导入 |

## 测试

- `tests/test_*.gd` 都是继承 `tests/support/isolated_suite.gd` 的无头脚本，用 `--script` 运行，输出 JSON（`checks`、`failures`、`status`），报告写进 `evidence/`。基类把改键文件指到测试专用路径，玩家本机的改键不影响测试结果。`tools/Test-Game.ps1` 每组可以单独设帧率（contact_refresh 在 144 fps 下跑），每次运行有 300 秒超时。
- 战斗类套件加载 `tests/fixtures/combat_lab.tscn`（旧训练场 + 木桩），不进入正式流程。
- 改键测试使用独立的 `settings_path`，不会覆盖玩家真实的 `user://keybindings.cfg`。
- `tests/recorders/` 用真实渲染录制截图和 GIF，`tools/art_qa/` 的 Python 脚本再拿这些输出做像素校验和预览合成。
- `tests/legacy/` 是 v02–v06 的旧套件，针对旧美术和旧操作，现在会失败，只作参考。

## 扩展点

- **新关卡**：脚本放 `scripts/levels/<名字>/`，场景放 `scenes/<名字>.tscn`，素材放 `assets/<名字>/`；在 `scene_routes.gd` 里登记路径；关卡里实例化 `player.tscn` 并挂一个 `GameSession`，就能拿到改键和顿帧。
- **剧情物品**：NPC 对话完成后调用 `/root/NightwalkerStoryState.grant_item("breaker_key")`，医院电闸就能打开。
- **新动作**：帧放 `frames/`，在 `side_view.tres`/`top_down.tres` 登记，原画和提示词放 `art_metadata/<版本>/`，刀刃路径更新到 `blade_paths.json`。

## 已知问题

- `player.gd` 约 930 行。招式数据、特效已经拆出去；移动和动画选择还在里面。
- `main.tscn` 和 `home_601.tscn` 内容相同，只是节点名不同。
- 门锁、物品、电源状态只在当前进程内有效，还没有存档系统。
- `art_metadata/` 里的流水线脚本写死了原开发机路径。
