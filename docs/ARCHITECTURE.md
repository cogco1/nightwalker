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

- **GameSession**：两个关卡共用。负责 F1/Esc 改键菜单，并监听玩家的 `normal_contact_stop`、`critical_hit` 信号做全屏顿帧（普通 4 帧、至少 0.0667 秒；暴击 6 帧、至少 0.1 秒），顿帧期间整体偏移 1 个原生像素。蓄力重斩用 `HEAVY_STOP_FRAMES`（10 帧）、偏移 2 像素、冻结画面前 2 帧闪白；暴击和重斩结束后镜头 `offset` 有几帧余震（`AFTERSHOCK`）。
- **CombatFeedback**（`scripts/core/combat_feedback.gd`）：GameSession 的子节点，`PROCESS_MODE_ALWAYS`，所以顿帧暂停时命中声不被截断。监听玩家的 `attack_started`、`hit_resolved`、`charge_started`、`charge_ready`、`charge_ended` 播挥刀、轻击/暴击/重斩命中、蓄力、蓄满音效；`played` 记录播放顺序供测试和录屏使用。音效是 `tools/audio/gen_combat_sfx.py` 合成的占位 WAV（`assets/audio/sfx/`），同名替换即可换成正式音效。无头模式下只记录不播放。
- **NightwalkerStoryState**（`scripts/core/story_state.gd`）：由 `hospital_security.gd` 按需挂到 `/root`，存放本次进程内的物品和标记（`grant_item`、`has_item`、`set_flag`、`has_flag`）。没有存档，退出游戏就清空。
- **Controls**（`scripts/core/controls.gd`）：静态类，持有当前按键方案，读写 `user://keybindings.cfg`，把方案应用到 InputMap。各脚本通过 `CONTROLS.binding_pressed(slot)` 读输入。

## 玩家

`scenes/player.tscn` = `CharacterBody2D` + `AnimatedSprite2D` + 脚底碰撞盒。`scripts/player/player.gd` 包含全部移动和战斗：

- `view_mode`：0 = 俯视（`assets/top_down.tres`），1 = 侧视（`assets/side_view.tres`）。关卡在实例化时设置，医院 Tab 切换时重建。
- 地面：步行/跑步加减速、三连击（第三刀 30% 三倍暴击）、W+左键上挑、Shift+A/D+新点击突刺 48 像素、下蹲。
- 蓄力重斩：一段地面轻击结束时左键仍按着，就进入 `is_charging`（停在 attack3 第 3 帧，原地不动）；`charge_time` 到 `CHARGE_FULL_SECONDS` 发 `charge_ready`；松开时蓄满就以 `special_kind = "heavy_slash"` 从第 4 帧播 attack3（46 fps，前冲 14 像素，判定加长 10、加宽 8，固定暴击、不掷骰），否则取消。离地、`clear_input_buffer()` 都会取消蓄力。
- 空中：二段跳、空中三连、S 下劈和落地冲击、空中突刺（结束接 `air_idle`，0.30 秒、6 像素/秒缓降）。
- 刀尖命中区按 `assets/blade_paths.json` 逐帧取刀刃位置，和画面上的钢刃一致。
- 对外信号：`attack_started`、`attack_hit`、`combo_changed`、`hit_resolved`、`critical_hit`、`normal_contact_stop`、`special_started`、`landing_impact`、`charge_started`、`charge_ready`、`charge_ended(released)`。
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

- `tests/test_*.gd` 都是 `extends SceneTree` 的无头脚本，用 `--script` 运行，输出 JSON（`checks`、`failures`、`status`），报告写进 `evidence/`。
- 战斗类套件加载 `tests/fixtures/combat_lab.tscn`（旧训练场 + 木桩），不进入正式流程。
- 改键测试使用独立的 `settings_path`，不会覆盖玩家真实的 `user://keybindings.cfg`。
- `tests/recorders/` 用真实渲染录制截图和 GIF，`tools/art_qa/` 的 Python 脚本再拿这些输出做像素校验和预览合成。
- `tests/legacy/` 是 v02–v06 的旧套件，针对旧美术和旧操作，现在会失败，只作参考。

## 扩展点

- **新关卡**：脚本放 `scripts/levels/<名字>/`，场景放 `scenes/<名字>.tscn`，素材放 `assets/<名字>/`；在 `scene_routes.gd` 里登记路径；关卡里实例化 `player.tscn` 并挂一个 `GameSession`，就能拿到改键和顿帧。
- **剧情物品**：NPC 对话完成后调用 `/root/NightwalkerStoryState.grant_item("breaker_key")`，医院电闸就能打开。
- **新动作**：帧放 `frames/`，在 `side_view.tres`/`top_down.tres` 登记，原画和提示词放 `art_metadata/<版本>/`，刀刃路径更新到 `blade_paths.json`。

## 已知问题

- `player.gd` 约 860 行，移动、连招、空战、动画选择都在一个文件里；继续加动作前值得按状态拆分。
- `main.tscn` 和 `home_601.tscn` 内容相同，只是节点名不同。
- 门锁、物品、电源状态只在当前进程内有效，还没有存档系统。
- `art_metadata/` 里的流水线脚本写死了原开发机路径。
