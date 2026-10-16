# 架构

这份文档描述 v14 的运行时结构。场景文件几乎是空壳：每个 `.tscn` 只挂一个脚本，节点树由脚本在 `_ready()` 里按 `layout.json` 搭建。

## 场景流转

```
启动 → scenes/main.tscn（NightwalkerHome，脚本同 home_601.gd）
          │  门口 E / F7
          ▼
SceneRoutes.switch_to()  ←── autoload，登记安全屋、医院和夜街
          │
   ┌──────┴───────┐
home_601.tscn   underground_hospital.tscn
      └──────── F8 ────────┘
                  ↕
       night_street_proto.tscn
```

- `SceneRoutes`（`scripts/core/scene_routes.gd`）是唯一的 autoload。F7 保留安全屋/医院往返，F8 从两处室内进入夜街并返回来源楼层、视角和安全脚点；直接启动夜街则返回安全屋。快捷键被改键占用时不抢键；设置、剧情弹窗和楼梯过渡拦截切场。切场景前取消顿帧、清空攻击缓冲、恢复暂停和画布变换。侧视空中离开医院时返回该楼层既有安全出生点。
- `main.tscn` 和 `home_601.tscn` 都挂 `home_601.gd`。`main.tscn` 是项目入口，切回安全屋时用 `home_601.tscn`。
- `night_street_proto.tscn`（夜街原型）已接入 F8 路由，也可以用 `Run-NightStreet.cmd` 直接启动，或在编辑器里打开后按 F6。

## 每个关卡的节点

```
Home601 / UndergroundHospital (Node2D, 关卡脚本)
├─ world (Node2D)          底图 Sprite2D、碰撞体、道具
│  └─ Player               scenes/player.tscn 实例
├─ InteriorLighting       共用环境光/辉光，World 内的光源和薄雾随视角重建
├─ GameSession (Node)      scripts/core/game_session.gd
│  ├─ KeybindingsMenu      scripts/ui/keybindings_menu.gd
│  └─ 顿帧覆盖层 CanvasLayer(100)
├─ HospitalInteractions    （仅医院）对话、阅读、楼梯、出口
├─ HospitalSecurity        （仅医院）密码门、电闸
└─ UI CanvasLayer          标题、提示、DialogueBox（scripts/ui/dialogue_box.gd）
```

- **DialogueBox**（`scripts/ui/dialogue_box.gd`）：安全屋和医院共用的阅读框，80% 大小、12px 像素字体、48×64 立绘不变。每个场景自己定分页字数和打字速度（安全屋 24 字 / 每秒 28 字，医院 32 / 36）；说话人写在 layout.json 的 `speakers`（逐行）和 `speaker`（默认）里。打开时冻结玩家、向 GameSession 登记为剧情弹窗，关闭时释放。
- **pixel_ui.gd**：`label()` 是所有关卡文字标签的唯一入口；`shrink_dialogue()`、`add_portrait()`、`set_speaker()` 给对话框用。
- **LevelKit**（`scripts/levels/level_kit.gd`）：关卡共用的静态函数。`add_box` 建矩形静态碰撞体，`add_layout_collider` 按 layout.json 条目建碰撞体（矩形或多边形，`one_way`、`stair_only`），`follow` 把镜头放到取整后的主角位置并限制在世界范围内。安全屋、医院、医院门禁和测试场 arena 都用它，新关卡不要再自己写一份。

- **GameSession**：所有有玩家的场景共用，测试夹具 combat_lab 也挂同一个（夹具里原来那份顿帧副本已删除，测到的就是正式代码）。负责 F1/Esc 改键菜单（关闭后发 `keybindings_closed`，场景据此重写带按键名的提示）；对话框、密码门这类剧情弹窗用 `push_modal(owner)` / `pop_modal(owner)` 登记，有弹窗时 F1/Esc 归弹窗；监听玩家的 `impact(档位, 方向)` 信号，按 `STOPS` 表做全屏顿帧：light 4 帧 / 至少 0.0667 秒、critical 6 帧 / 至少 0.1 秒（这两档是原作保证）、heavy 10 帧偏移 2 像素并闪白，critical 和 heavy 结束后镜头有几帧余震。对外有 `hit_stop_started / hit_stop_frame / hit_stop_finished` 信号和帧数、时长等观测字段。
- **CombatFeedback**（`scripts/core/combat_feedback.gd`）：GameSession 的子节点，`PROCESS_MODE_ALWAYS`，所以顿帧暂停时命中声不被截断。只听玩家主动发的信号：`move_started(招式)` 决定挥刀声，`impact(档位)` 决定命中声，`charge_started / charge_ready / charge_ended` 决定蓄力声，不读玩家内部字段；`played` 记录播放顺序供测试和录屏使用。音效是 `tools/audio/gen_combat_sfx.py` 合成的占位 WAV（`assets/audio/sfx/`），同名替换即可换成正式音效。无头模式下只记录不播放。
- **NightwalkerStoryState**（`scripts/core/story_state.gd`）：由 `hospital_security.gd` 按需挂到 `/root`，存放本次进程内的物品和标记（`grant_item`、`has_item`、`set_flag`、`has_flag`）。没有存档，退出游戏就清空。
- **Controls**（`scripts/core/controls.gd`）：静态类，持有当前按键方案，读写 `user://keybindings.cfg`，把方案应用到 InputMap。各脚本通过 `CONTROLS.binding_pressed(slot)` 读输入。交互键 E（`INTERACT_KEY`）是保留键，不在改键表里，`validate` 不允许其他动作用它；场景用 `is_interact(event)` 判断，提示文字用 `binding_text` / `hint_text` 按当前键位生成（场景提示用 `hint_text`：空格写成「空格」，鼠标键写成「左键 / 右键 / 中键 / 侧键1 / 侧键2」；改键界面用 `binding_text`，是 Space、LMB 这类英文名）。

## 玩家

`scenes/player.tscn` = `CharacterBody2D` + `AnimatedSprite2D` + 脚底碰撞盒。玩家代码分三块：

- `scripts/player/player.gd`：移动、状态机、按键意图、出招和命中判定。
- `scripts/player/moves_long_blade.gd`：**招式表**。每个招式的动画、帧速、起始帧、判定帧、判定框、前冲、暴击规则、顿帧档位、命中反应、空中滞空、收招等都写在 `MOVES` 里，连段图写在 `STRINGS` 里（当前招式 → 输入 light / heavy → 下一招，或按优先顺序排的几个候选，玩家取第一个当前允许的：`side_only` 只在侧视、`ground` 只在地面、`air_only` 只在空中）。多段招式用 `then` 串起下一段，`end` 截掉片段后半，`rehit` 让同一目标在一招里再被打一次，`cancel` 是新招式命中后提前接下一招的帧，`arc` 是代码画的整圈刀光，`shockwave` 是下劈落地冲击波，`knockback` 击退，`dmg_mult` 伤害倍数，`jump` 起跳速度，`swing`/`pitch` 挥刀音效，`dash_cancel` 是轻击可被突刺取消的起始帧，`dodge` 标出突刺本身，`resumes`/`as` 让一个招式在连段图里顶替另一个。字段说明在文件头。加新招式只在这里加数据，`tests/test_moveset.gd` 会检查动画、判定帧和刀尖路径是否齐全。招式表的 fps 才是实际帧率：player.gd 出招时把 `speed_scale` 设成 fps ÷ 动画在 tres 里的速度，所以 tres 里的数（例如 attack1/2/3 写的 40/44/40，实际播放是 36/40/42）只是被约掉的除数，改它不会改出招速度。不要动 tres 里这些数：`speed_scale` 是 float32，改了会让帧边界移动 1 个物理帧，判定时机跟着变。test_moveset 会让每个招式在两个视角、各个朝向下各起一次（有空中动画的再起一次空中），检查精灵的实际播放速度等于招式 fps。
- `scripts/player/player_fx.gd`：特效层（尘土、火花、斩痕和冲击线、气流、蓄力光粒、刀光轨迹、残影），玩家的第一个子节点，画在人物身后，由玩家的物理帧驱动，装饰随机数和暴击判定分开。

状态：`state` 是一个枚举 FREE / ATTACK / CHARGE / RECOVERY / HURT；`move_id`、`move` 是当前招式，`move_ticks` 是它走过的物理帧数。`is_attacking`、`is_charging`、`special_kind`、`combo_stage` 都是从 `state` 和 `move` 算出来的只读值。

按键意图：每次按键记成一条意图（`_intents`），时间按玩家自己的战斗时钟 `combat_time` 计，这个时钟只在玩家的物理帧里走，所以顿帧期间不走。左键（light）和右键（heavy）按下先记为"刚按下"，下一个物理帧按原规则转成"排队的下一段"（缓冲 0.22 秒，最长延到这一刀结束、上限 0.55 秒）、"收招后开新连段"，或者丢掉；按住不会自动连段。轻重两种排队的下一段只留一个，后按的算数。原三连仍在这一刀播完时接下一招，新招式到 `cancel` 帧就接。突刺键记 0.15 秒缓冲。顿帧期间转发进来的 S 只记意图，冻结结束后才下劈。`queued_attack`、`pending_new_attack`、`attack_buffer_left`、`_mouse_attack_pending` 是从意图表算出来的只读值。

具体动作：

- `view_mode`：0 = 俯视（`assets/top_down.tres`），1 = 侧视（`assets/side_view.tres`）。关卡在实例化时设置，医院 Tab 切换时重建。
- 地面连段（侧视）：左键五连（原三连 + 四段刺 + 两段回旋），任一段后按右键出终结技：第 0/1 段后突进重劈（击退）、第 2 段后挑空斩、第 3 段后回旋重斩（三段判定，末段暴击）、第 4 段后裂地斩（小跳下劈，落地冲击波）；突进重劈后再按右键接挑空斩。俯视只有原三连，没有重击。
- 跃步劈（侧视，10-16 用户定）：地面按住 W（上挑修饰键）再按右键。和 W+左键上挑对应：上挑是往上挑，跃步劈是向前跃起、落下时劈砍。前跃约 53 像素，最高约 16 像素，滞空约 0.45 秒。起跳时 air_attack2 举刀过顶，过顶点后同一套帧往下劈；落地用 dive_slash 第 14 帧，落地时沿地面放冲击波（左右各 24 像素）。劈砍和冲击波都是 2 倍伤害、10 帧重顿帧，并把目标挑起；劈砍已经打中的目标，冲击波不再打一次。落地时的冲击线、圆环和尘柱没打中也照样出。招式表新字段：`lands`（像下劈一样落地结束，但按正常重力下落）、`carry`（空中水平速度）、冲击波的 `again` / `ring`、`swing: none`。
- 空中旋转斩（侧视）：空中按右键，或空中三连后再按左键：air_attack1 → air_attack2 → air_attack1 以 60 fps 连播，三段判定，每段重新给 0.25 秒滞空，一共约 0.6 秒，整圈刀光；中间两段用 2 帧的 `tick` 顿帧，末段必暴击、6 帧顿帧；结束后再滞空 0.3 秒，可以接 S 下劈。
- 闪避派生（侧视）：轻击从判定帧起按突刺键会取消剩下的收招直接突刺（攻击前段按下的突刺会等到这一帧）；突刺中按键在突刺第 10 帧接出，突刺结束 0.25 秒（`DODGE_OFFSET_SECONDS`）内按键也算：左键是穿影斩（attack1 52 fps，判定长 8 像素，带残影），顶替被打断的连段的下一段，之后接着原连段走；右键是追影重斩（前冲 24 像素，算作突进重劈，可再接挑空斩）。玩家用 `_string_id` 记当前招式在连段图里算哪一招。按键槽 `heavy_mouse`（默认右键），旧存档读入时自动补上，和攻击键冲突就换一个鼠标键；改键界面里两个鼠标槽互抢按键时互换。
- 地面：步行/跑步加减速、三连击（第三刀 30% 三倍暴击）、W+左键上挑、按一下突刺键（`dash_modifier`，默认 Shift）朝按住的方向或面向突刺 48 像素（攻击中按下有 `DASH_BUFFER_SECONDS` 0.15 秒缓冲）、下蹲。`dash_modifier` 这个 slot 名为兼容旧存档保留，现在是单按键；读档时它若和跑步键相同，`controls.gd` 只把它挪到空闲键。
- 蓄力重斩：一段地面轻击结束时左键仍按着，就进入 `is_charging`：前 60%（`CHARGE_COIL_PORTION`）从 attack3 第 0 帧逐帧收到第 3 帧并后撤 `CHARGE_BACKSTEP` 3 像素，之后原地不动，蓄满后 sprite 左右 1 像素微颤；`charge_time` 到 `CHARGE_FULL_SECONDS` 发 `charge_ready`；松开时蓄满就以 `special_kind = "heavy_slash"` 从第 4 帧播 attack3（46 fps，第 4–9 帧前冲 `HEAVY_LUNGE` 32 像素并留 2 个残影，判定加长 10、加宽 8，固定暴击、不掷骰），否则取消。离地、`clear_input_buffer()` 都会取消蓄力。
- 空中：二段跳、空中三连、S 下劈和落地冲击、空中突刺（结束接 `air_idle`，0.30 秒、6 像素/秒缓降）。
- 刀尖命中区按 `assets/blade_paths.json` 逐帧取刀刃位置，和画面上的钢刃一致。
- 顿帧档位（GameSession `STOPS`）：tick 2 帧（空中旋转斩中段）、light 4 帧、critical 6 帧、heavy 10 帧。
- 对外信号：`impact(档位, 方向)`（每段攻击第一次命中时发一次）、`move_started(招式)`、`attack_started`、`attack_hit`、`combo_changed`、`hit_resolved`、`critical_hit`、`normal_contact_stop`、`special_started`、`landing_impact`、`charge_started`、`charge_ready`、`charge_ended(released)`。外部输入走 `handle_input(event)`，回到待机用 `show_idle()`。对话框、密码门和改键菜单用 `freeze(owner)` / `unfreeze(owner)` 暂停玩家，按持有者计数，最后一个持有者释放时才恢复；改键菜单冻结时不清速度。
- 命中特效分三档（轻、暴击、重斩）：沿挥刀方向的斩痕、放射冲击线、火花；顿帧会冻结在这一帧上。
- 受击：敌人调用 `receive_attack(attack)`，返回 `AttackResult` HIT / EVADE / PERFECT，同时发 `attack_received(result, attack)`。突刺开始不早于敌人判定生效前 `PERFECT_LEAD_SECONDS` 0.2 秒（或在判定期间）算完美闪避；突刺中的无敌或人已不在攻击线上算 EVADE；否则 HIT：打断招式和蓄力，进入 HURT，0.25 秒内滑退约 20 像素，0.3 秒硬直、红闪，硬直中的按键等硬直结束再出。v1 不扣血。`hurtbox()` 是身体矩形。
- 完美闪避反击：GameSession 收到 PERFECT 就进入慢动作（`start_slowmo`）：`world_time_scale` 0.25，持续 `SLOWMO_SECONDS` 1.2 秒实际时间，顿帧和改键菜单期间计时不走，`Engine.time_scale` 始终是 1；画面边缘泛青（单独一层 CanvasLayer，在顿帧快照层下面），主角 `invulnerable`。慢动作中按左键或右键是反击：瞬移到那台敌人的另一侧 18 像素（那边是墙就落在这一侧），面向它出 `counter_slash`（必暴击 3 倍、10 帧顿帧），反击命中时慢动作结束。玩家只认 `open_counter(敌人)` / `close_counter()`，不知道世界时钟。

## 敌人

- `scripts/enemies/enemy_attacker.gd`：挂在敌人身体下的攻击组件。主角进入范围后身体红闪预警 0.5 秒（结束前 0.2 秒锁定位置），然后 0.18 秒直线突袭到锁定点，最后 0.12 秒是判定；碰到主角就调用它的 `receive_attack`，判定结束没碰到也报告一次（contact = false），这样闪开的突刺也能判完美闪避。之后停顿、飘回原位、冷却 1.2 秒。时间按世界时钟走：delta 乘 `GameSession.world_time_scale`，顿帧时整棵树暂停。身体和主角之间加了碰撞例外，突袭穿过主角而不是推开它。
- 测试夹具 `tests/fixtures/attack_drone.gd`：会攻击的悬浮无人机（木桩不攻击），由 `arena.add_attacker(位置)` 按需加入，默认场地里没有。

## 人物材质（所有场景）

`player.tscn` 的 Sprite 挂 `assets/fx/character_cyber.tres`（`resource_local_to_scene`，每个玩家实例一份），shader 是 `shaders/character_cyber.gdshader`：

- **换色**：`assets/fx/cyber_palette.png` 是 18 × 4 查找表。第 0 行是 1024 帧里出现的全部 18 种原色，第 1 行是换成的颜色，第 2 行 rgb 是光晕颜色、alpha 是自发光强度，第 3 行 alpha 是反光度（目前只有斜挎带的 #533729）。改色只改这张图（或 `tools/art/gen_cyber_palette.py`）；`tools/art_qa/validate_cyber_palette.py` 检查新帧有没有表外颜色。
- **轮廓光**：`rim_a_*`、`rim_b_*` 是两个屏幕空间的光源方向和颜色。只有朝向光源、且外侧是透明像素的边缘被上色；没被照到的边缘往 `shade_edge_color` 压暗。夜街与室内均按人物位置选取影响最强的两盏灯，关闭的灯不参与轮廓光或反光条计算。
- **自发光**：刀刃三种钢色（#e5e8e0 / #bbc2c3 / #8e999f）和脸部两种肤色是自发光像素，在帧内画半径 3 像素的光晕，成了刀光和目镜。按颜色识别刀刃，不需要逐帧遮罩：v07 的 24 个侧视动作里，这三种钢色 99.6% 落在刀刃遮罩里。
- **暗场景补偿**：`emission_lift`（= 1 / CanvasModulate 颜色）让自发光、轮廓光不被压暗；`emission_gain` > 1 把它们推过 1.0，WorldEnvironment 辉光才会把它们晕开。`body_lift` 提亮身体，免得人物在暗处糊成一团。
- `look` = 0 时完全是原配色（夜街里按 F9 切换）。

## 夜街原型的渲染分层

```
NightStreetProto
├─ Glow (WorldEnvironment)      canvas 背景 + 辉光，阈值 1.0：只有超过 1.0 的自发光像素会晕开
├─ NightAmbient (CanvasModulate) 压暗主画布
├─ Layer_sky / far_towers / petra / district_c / street   每层一张底图 + 一张 _emit 自发光图
│                                视差系数 0 / 0.15 / 0.34 / 0.7 / 1.0；底图只有 street 受街灯照射
├─ World                         地面碰撞、PointLight2D、巡逻无人机光束、悬浮无人机、玩家
├─ StreetCamera
├─ WetStreet   (CanvasLayer 1)   BackBufferCopy + 湿地反光（读屏幕纹理，按世界坐标定水洼）
├─ Weather     (CanvasLayer 2)   低雾 + 雨
├─ ExposurePost (CanvasLayer 30) BackBufferCopy + 暴露度色差、暗角
├─ StreetUI    (CanvasLayer 31)  标题、提示、暴露条
└─ GameSession                   改键菜单 (200)、顿帧覆盖层 (100)
```

- 自发光的东西（`_emit` 图、光束、光粒子、无人机灯）都用 `shaders/emissive_add.gdshader`：`unshaded` 不受 CanvasModulate 影响，叠加混合，`gain` 推过 1.0 触发辉光。
- 实测（4.7.2，Compatibility，RTX 4090 Laptop）：CanvasModulate 会压暗普通物体，不影响 `unshaded` 物体和其他 CanvasLayer；WorldEnvironment 辉光在 2D 下可用，超过 1.0 的颜色晕得更开，所以不需要另写假辉光。
- 夜街保持 `CONTENT_SCALE_MODE_VIEWPORT`（原生 320 × 180 渲染），湿地反光、雾和色差都以原生像素为单位。

## 数据和素材

室内光照由 `scripts/levels/interior_lighting.gd` 统一管理，参数在 `assets/lighting/interiors.json`。宿主只保存一个 `lighting`，调用 `refresh_context(world, player, context)` 绑定当前楼层/视角；旧 World 的灯、发光层和雾随之释放，人物材质重新绑定。`set_power_states()` 接收医院既有供电分区，`set_source_power()` 控制单个设备；安全屋 `set_device_power()` 同时控制原屏幕动画、光锥和新增光照。医院灯位取当前 layout 的 fluorescents/monitors，应急光由参数表单列。`interior_fog.gdshader` 按世界原生坐标量化，避免清晰 UI 的 CANVAS_ITEMS 合成模式把雾变成窗口像素。室内未加入街景的雨、无人机或暴露度后处理。

| 位置 | 内容 |
|---|---|
| `frames/<视角>_<方向>_<动作>/NN.png` | 64 个动作 × 16 帧。原 992 帧保持原字节，v14 新增 `air_dash_stab_*` 32 帧（112×96 画布，足点 56,84） |
| `assets/side_view.tres`、`top_down.tres` | 把 frames 组装成 SpriteFrames |
| `assets/home_601/layout.json` | 安全屋碰撞、可交互物、对话文本 |
| `assets/home_601/home_601_furnished_native.png` | 当前安全屋底图；旧图 `home_601_native.png` 保留，场景和 PropEffects 统一读取 layout.background |
| `assets/underground_hospital/layout.json` | 医院俯视两层和侧视的房间、墙、楼梯（`stairs.side_flight`：侧视楼梯两端平台高度和上下楼判定区间）、门禁、交互点 |
| `assets/fonts/` | fusion-pixel 10/12px 中文像素字体（OFL） |
| `art_metadata/` | 原画、提示词、遮罩、导入脚本和校验报告；有 `.gdignore`，Godot 不导入 |

## 测试

- `tests/test_*.gd` 都是继承 `tests/support/isolated_suite.gd` 的无头脚本，用 `--script` 运行，输出 JSON（`checks`、`failures`、`status`），报告写进 `evidence/`。基类把改键文件指到测试专用路径，玩家本机的改键不影响测试结果。`tools/Test-Game.ps1` 每组可以单独设帧率（contact_refresh 在 144 fps 下跑），每次运行有 300 秒超时。
- 战斗类套件加载 `tests/fixtures/combat_lab.tscn`（旧训练场 + 木桩），不进入正式流程。
- 改键测试使用独立的 `settings_path`，不会覆盖玩家真实的 `user://keybindings.cfg`。
- `tests/test_perfect_counter.gd` 覆盖慢动作和反击：世界时钟是主角的 1/4、主角全速、无敌、1.2 秒实际时间、顿帧时计时不走且仍冻结满帧、左右键反击的落点和朝向、3 倍伤害、10 帧顿帧、反击命中结束慢动作。
- `tests/test_enemy_attack.gd` 覆盖敌人攻击和受击：预警红闪和时长、HIT 的击退距离和硬直、打断挥刀和蓄力、过早突刺和跳过是 EVADE、判定前 0.14 秒和判定中的突刺是 PERFECT、被打坏的无人机不再攻击。
- `tests/test_level_shared.gd` 覆盖关卡共用部分：冻结计数、剧情弹窗、对话框参数和说话人、E 键保留与旧配置迁移、提示文字跟随改键。
- `tests/recorders/capture_levels.gd` 在窗口模式下截安全屋、医院俯视和侧视、每一页对话、密码门和楼梯提示（88 张），改关卡代码前后各跑一次逐像素比对，就能确认画面没变。
- `tests/recorders/capture_interior_lighting.gd` 记录 19 张室内灯光对照：屏幕动画两时刻、开关屏、人物近光、清晰对话、真实 F8 往返、医院两层/双视角的供电切换。用非无头模式运行，图与渲染尺寸报告写入 `evidence/interior_lighting/`；测试与录制都使用隔离改键配置。
- `tests/test_home_furniture.gd` 以 12×8 足框和 0.25 像素余量核对全屋可站空间，再用真实 WASD 输入沿路径访问全部 10 处新旧交互及厨房/卧室细通道，不靠传送证明通达。`recorders/capture_home_furniture.gd` 输出 11 张家具、暖灯、关屏与新对白的 GPU 对照图。
- `tests/recorders/` 用真实渲染录制截图和 GIF，`tools/art_qa/` 的 Python 脚本再拿这些输出做像素校验和预览合成。
- `tests/legacy/` 是 v02–v06 的旧套件，针对旧美术和旧操作，现在会失败，只作参考。

## 扩展点

- **夜街原型**：街灯和霓虹的点光源来自 `assets/night_street/lights.json`（拼装脚本按街面层的自发光灯具算出）；悬浮无人机位置 `targets` 和 lights.json 缺失时用的 `fallback_lights` 在 `assets/night_street/layout.json`；环境光 `AMBIENT`、暴露速度 `EXPOSURE_RISE/FALL` 在 `scripts/levels/night_street/night_street.gd` 顶部。操作提示由 `CONTROLS.hint_text` 按当前键位生成，改键菜单关闭后重写；墙体和镜头跟随用 LevelKit。底图流程：Codex 出原图 → `tools/art/pixelize_layer.py`（共用 40 色调色板、按块取众数降采样、拆自发光层）→ `tools/art/assemble_night_street.py`（拼宽、纵向定位、灯光表），记录在 `art_metadata/night_street_v15/prompts.json`。
- **义体**：反光条由查找表第 3 行和 shader 的 `reflect_*` 参数控制；条码疤是 `player.tscn` 里 Sprite 下的 `ImplantOverlay`（`scripts/player/implant_overlay.gd`），位置读 `assets/fx/implant_anchors.json`，由 `tools/art/gen_implant_anchors.py` 从帧里算出（新增动作帧后重跑）。场景把它的 `scanned` 设为 1 时会故障闪烁。

- **新关卡**：脚本放 `scripts/levels/<名字>/`，场景放 `scenes/<名字>.tscn`，素材放 `assets/<名字>/`；在 `scene_routes.gd` 里登记路径；关卡里实例化 `player.tscn` 并挂一个 `GameSession`，就能拿到改键和顿帧。
- **剧情物品**：NPC 对话完成后调用 `/root/NightwalkerStoryState.grant_item("breaker_key")`，医院电闸就能打开。
- **新动作**：帧放 `frames/`，在 `side_view.tres`/`top_down.tres` 登记，原画和提示词放 `art_metadata/<版本>/`，刀刃路径更新到 `blade_paths.json`。

## 已知问题

- `player.gd` 约 930 行。招式数据、特效已经拆出去；移动和动画选择还在里面。
- `main.tscn` 和 `home_601.tscn` 内容相同，只是节点名不同。
- 门锁、物品、电源状态只在当前进程内有效，还没有存档系统。
- `art_metadata/` 里的流水线脚本写死了原开发机路径。
