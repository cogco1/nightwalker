# 架构

这份文档描述 v14 的运行时结构。场景文件几乎是空壳：每个 `.tscn` 只挂一个脚本，节点树由脚本在 `_ready()` 里按 `layout.json` 搭建。

## 场景流转

```
启动 → scenes/boot.tscn → SceneRoutes.travel(start_step) → home_601.tscn
       （默认 d1_wake：601安全屋；-- --sandbox 则进入 main.tscn 自由模式）
          │  章节：剧情步骤 SceneRoutes.travel(step)   自由模式：门口 E / F7
          ▼
SceneRoutes.switch_to()  ←── autoload，登记安全屋、医院、夜街和屏息
          │
   ┌──────┴───────┐
home_601.tscn   underground_hospital.tscn
      └──────── F8 ────────┘
                  ↕
       night_street_proto.tscn
```

- 正式入口是 `boot.tscn`（`scripts/core/boot.gd`）：开始第一章并按 `chapter1.json.start_step` 路由，当前默认 `d1_wake`，打开601安全屋，播放标题卡、电视新闻、独白和敲门；玩家在电脑读完乔伦委托后，由门口进入 `d1_hospital`（12:30，俯视医院1F脚点566,78）；`Run-Sandbox.cmd` 直接打开 `main.tscn`，没有章节，就是原来的自由模式。章节里 `SceneRoutes.travel(step)` 进入步骤并打开它的 `scene`（home / hospital / breath），不受玩家冻结影响；F7、F8 和医院的 Tab 只有带 `-- --nw-debug` 才生效。`-- --nw-step=<步骤>`（`Run-Game.ps1 -Step <步骤>`）可覆盖默认入口，`d1_hospital` 用于跳过安全屋直接调试医院，`d1_night` 直接进第一夜；只认写了 `scene` 的步骤。
- `SceneRoutes`（`scripts/core/scene_routes.gd`）是唯一的 autoload。F7 保留安全屋/医院往返，F8 从两处室内进入夜街并返回来源楼层、视角和安全脚点；直接启动夜街则返回安全屋。快捷键被改键占用时不抢键；设置、剧情弹窗和楼梯过渡拦截切场。切场景前取消顿帧、清空攻击缓冲、恢复暂停和画布变换。侧视空中离开医院时返回该楼层既有安全出生点。
- `main.tscn` 和 `home_601.tscn` 都挂 `home_601.gd`。`main.tscn` 是自由模式入口；章节与场景路由回安全屋时用 `home_601.tscn`，正式项目入口是 `boot.tscn`。
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

- **GameSession**：所有有玩家的场景共用，测试夹具 combat_lab 也挂同一个（夹具里原来那份顿帧副本已删除，测到的就是正式代码）。负责 F1/Esc 改键菜单（关闭后发 `keybindings_closed`，场景据此重写带按键名的提示）；对话框、密码门这类剧情弹窗用 `push_modal(owner)` / `pop_modal(owner)` 登记，有弹窗时 F1/Esc 归弹窗；监听玩家的 `impact(档位, 方向)` 信号，按 `STOPS` 表做全屏顿帧：light 2 帧 / 至少 0.0333 秒、critical 6 帧 / 至少 0.1 秒、heavy/kill 10帧偏移3像素；所有档位结束后都有按60Hz时间轴采样的小幅镜头回弹，不使用全屏闪白或反相。对外有 `hit_stop_started / hit_stop_frame / hit_stop_finished` 信号和帧数、时长等观测字段。
- **ImpactBurst**（`scripts/core/impact_burst.gd`，打击感原型，2026-10-18，默认开，F10 开关，说明见 [打击感原型_剑气破屏](prototypes/打击感原型_剑气破屏.md)）：GameSession 的子节点，`PROCESS_MODE_ALWAYS`，按真实时间走（顿帧期间照样动）。听玩家的 `swing_released`（重招放出越飞越大、冲出屏幕边的月牙剑气，只是画面）和新的 `struck(点, 档位, 方向, 击杀)`（记下命中点）；听 GameSession 的 `hit_stop_started`（藏起自己的图层，不进定格照片）、`hit_stop_frame(1)`（暴击/重击/击杀从第 2 帧起画贯穿全屏的斩线，`shaders/screen_cut.gdshader` 把线两侧画面反向错开 2 像素）和 `hit_stop_finished`（合上）。顿帧结束后的镜头位移由 `tremor(档位, 原回弹)` 给出：开着时是来回抖几帧的 `TREMORS`（横向 ≤3、纵向 ≤1 像素），关掉时是原回弹。它的两个 CanvasLayer（108、109）在 `no_stop_shift` 组里，顿帧平移跳过它们。
- **CombatFeedback**（`scripts/core/combat_feedback.gd`）：GameSession 的子节点，`PROCESS_MODE_ALWAYS`，所以顿帧暂停时命中声不被截断。只听玩家主动发的信号：普通攻击由 `swing_released(招式)` 决定挥刀声，特殊招式由 `move_started` 在起跳/动作提交时发声，`impact(档位)` 决定命中声，`charge_started / charge_ready / charge_ended` 决定蓄力声，不读玩家内部字段；`played` 记录播放顺序供测试和录屏使用。新6段短合成WAV由 `tools/audio/gen_impact_sfx_v2.py` 生成到 `assets/audio/sfx/impact_v2/`，原音频保留。单次同帧多目标只播放最强命中档位，击杀优先；每路3复音和音量余量减少截尾与叠加削顶。无头模式下只记录不播放。
- **NightwalkerStoryState**（`scripts/core/story_state.gd`）：用 `ensure(tree)` 按需挂到 `/root`，存放本次进程内的物品和标记（`grant_item`、`has_item`、`set_flag`、`has_flag`），以及章节进度：`start_chapter()` 读 `assets/story/chapter1.json`，`set_step(id)` 按步骤数据设天数和时钟并发 `step_changed`；`chapter_active` 为假就是自由模式，`allows_debug_routes()` 决定 F7 / F8 / Tab。没有存档，退出游戏就清空。
- **Controls**（`scripts/core/controls.gd`）：静态类，持有当前按键方案，读写 `user://keybindings.cfg`，把方案应用到 InputMap。各脚本通过 `CONTROLS.binding_pressed(slot)` 读输入。交互键 E（`INTERACT_KEY`）和俯视处决键 F（`EXECUTE_KEY`）是保留键，不在改键表里，`validate` 不允许其他动作用它们；场景分别用 `is_interact(event)` / `is_execute(event)` 判断，提示文字用 `binding_text` / `hint_text` 按当前键位生成（场景提示用 `hint_text`：空格写成「空格」，鼠标键写成「左键 / 右键 / 中键 / 侧键1 / 侧键2」；改键界面用 `binding_text`，是 Space、LMB 这类英文名）。

## 玩家

`scenes/player.tscn` = `CharacterBody2D` + `AnimatedSprite2D` + 脚底碰撞盒。玩家代码分三块：

- `scripts/player/player.gd`：移动、状态机、按键意图、出招和命中判定。
- `scripts/player/moves_long_blade.gd`：**招式表**。每个招式的动画、帧速、起始帧、判定帧、判定框、前冲、暴击规则、顿帧档位、命中反应、空中滞空、收招等都写在 `MOVES` 里，连段图写在 `STRINGS` 里（当前招式 → 输入 light / heavy → 下一招，或按优先顺序排的几个候选，玩家取第一个当前允许的：`side_only` 只在侧视、`ground` 只在地面、`air_only` 只在空中）。多段招式用 `then` 串起下一段，`end` 截掉片段后半，`rehit` 让同一目标在一招里再被打一次，`cancel` 是新招式命中后提前接下一招的帧，`arc` 是代码画的整圈刀光，`shockwave` 是下劈落地冲击波，`knockback` 击退，`dmg_mult` 伤害倍数，`jump` 起跳速度，`swing`/`pitch` 挥刀音效，`dash_cancel` 是轻击可被突刺取消的起始帧，`dodge` 标出突刺本身，`resumes`/`as` 让一个招式在连段图里顶替另一个。字段说明在文件头。加新招式只在这里加数据，`tests/test_moveset.gd` 会检查动画、判定帧和刀尖路径是否齐全。招式表的 fps 才是实际帧率：player.gd 出招时把 `speed_scale` 设成 fps ÷ 动画在 tres 里的速度，所以 tres 里的数（例如 attack1/2/3 写的 40/44/40，实际播放是 36/40/42）只是被约掉的除数，改它不会改出招速度。不要动 tres 里这些数：`speed_scale` 是 float32，改了会让帧边界移动 1 个物理帧，判定时机跟着变。test_moveset 会让每个招式在两个视角、各个朝向下各起一次（有空中动画的再起一次空中），检查精灵的实际播放速度等于招式 fps。
- `scripts/player/player_fx.gd`：特效层（尘土、火花、斩痕和冲击线、气流、蓄力光粒、刀光轨迹、残影），玩家的第一个子节点，画在人物身后，由玩家的物理帧驱动，装饰随机数和暴击判定分开。

状态：`state` 是一个枚举 FREE / ATTACK / CHARGE / RECOVERY / HURT / DODGE；`move_id`、`move` 是当前招式，`move_ticks` 是它走过的物理帧数。`is_attacking`、`is_charging`、`special_kind`、`combo_stage` 都是从 `state` 和 `move` 算出来的只读值。

按键意图：每次按键记成一条意图（`_intents`），时间按玩家自己的战斗时钟 `combat_time` 计，这个时钟只在玩家的物理帧里走，所以顿帧期间不走。左键（light）和右键（heavy）按下先记为"刚按下"，下一个物理帧按原规则转成"排队的下一段"（缓冲 0.22 秒，最长延到这一刀结束、上限 0.55 秒）、"收招后开新连段"，或者丢掉；按住不会自动连段。轻重两种排队的下一段只留一个，后按的算数。原三连仍在这一刀播完时接下一招，新招式到 `cancel` 帧就接。突刺键记 0.15 秒缓冲。顿帧期间转发进来的 S 只记意图，冻结结束后才下劈。`queued_attack`、`pending_new_attack`、`attack_buffer_left`、`_mouse_attack_pending` 是从意图表算出来的只读值。

具体动作：

- `view_mode`：0 = 俯视（`assets/top_down.tres`），1 = 侧视（`assets/side_view.tres`）。关卡在实例化时设置，医院 Tab 切换时重建。
- 地面连段（侧视）：左键五连（原三连 + 四段刺 + 两段回旋），任一段后按右键出终结技：第 0/1 段后突进重劈（击退）、第 2 段后挑空斩、第 3 段后回旋重斩（三段判定，末段暴击）、第 4 段后裂地斩（小跳下劈，落地冲击波）；突进重劈后再按右键接挑空斩。俯视只有原三连，没有重击。
- 跃步劈（侧视，10-16 用户定）：地面按住 W（上挑修饰键）再按右键。和 W+左键上挑对应：上挑是往上挑，跃步劈是向前跃起、落下时劈砍。前跃约 53 像素，最高约 16 像素，滞空约 0.45 秒。起跳时 air_attack2 举刀过顶，过顶点后同一套帧往下劈；落地用 dive_slash 第 14 帧，落地时沿地面放冲击波（左右各 24 像素）。劈砍和冲击波都是 2 倍伤害、10 帧重顿帧，并把目标挑起；劈砍已经打中的目标，冲击波不再打一次。落地时的冲击线、圆环和尘柱没打中也照样出。招式表新字段：`lands`（像下劈一样落地结束，但按正常重力下落）、`carry`（空中水平速度）、冲击波的 `again` / `ring`、`swing: none`。
- 空中旋转斩（侧视）：空中按右键，或空中三连后再按左键：air_attack1 → air_attack2 → air_attack1 以 60 fps 连播，三段判定，每段重新给 0.25 秒滞空，一共约 0.6 秒，整圈刀光；中间两段用 2 帧的 `tick` 顿帧，末段必暴击、6 帧顿帧；结束后再滞空 0.3 秒，可以接 S 下劈。
- 闪避派生（侧视）：轻击从判定帧起按突刺键会取消剩下的收招直接突刺（攻击前段按下的突刺会等到这一帧）；突刺中按键在突刺第 14 帧且连续位移完成后接出，突刺结束 0.25 秒（`DODGE_OFFSET_SECONDS`）内按键也算：左键是穿影斩（attack1 52 fps，判定长 8 像素，带残影），顶替被打断的连段的下一段，之后接着原连段走；右键是追影重斩（前冲 24 像素，算作突进重劈，可再接挑空斩）。玩家用 `_string_id` 记当前招式在连段图里算哪一招。按键槽 `heavy_mouse`（默认右键），旧存档读入时自动补上，和攻击键冲突就换一个鼠标键；改键界面里两个鼠标槽互抢按键时互换。
- 地面：步行/跑步加减速、点按闪避、左右蹲行、三连击（第三刀 30% 三倍暴击）、W+左键上挑、按住修饰键（`dash_modifier`，默认 Shift）和左右方向后，新点击攻击键突刺 48 像素（攻击中按下有 `DASH_BUFFER_SECONDS` 0.15 秒缓冲）、下蹲。`dash_modifier` 这个 slot 名为兼容旧存档保留，现在是修饰键；v4 允许与跑步共享，并通过点按/长按/新点击手势区分。
- 蓄力重斩：地面按下普通左键先进入无伤害蓄势；0.14秒内松开转换为轻击，继续按住直接蓄力，无需预先轻击；0.55秒蓄满，前60%后撤约3像素并收刀。侧视使用独立charged_draw左右各16帧，0–6帧蓄势，满蓄力停在6；松开从6开始、8–10判定，40fps配独立时长，释放后约0.05–0.083秒命中。固定暴击并叠加dmg_mult=2，共6倍伤害，不掷骰；侧视判定从56×28增至120×56、前方最远114像素（未计前冲），前冲参数36、击退20、收招0.22秒，保留10帧卡肉。黑红刀气0.14秒、普通非加法混合，按墙体射线缩短；逐目标射线继续阻止隔墙伤害。离地、受击、clear_input_buffer或未满松开都取消蓄力，未增加霸体和无敌。
- 空中：二段跳、空中三连、S 下劈和落地冲击、空中突刺（结束接 `air_idle`，0.30 秒、6 像素/秒缓降）。
- 刀尖命中区按 `assets/blade_paths.json` 逐帧取刀刃位置，和画面上的钢刃一致。
- 顿帧档位（GameSession `STOPS`）：tick 2 帧（空中旋转斩中段）、light 2 帧、critical 6 帧、heavy 10帧、kill 10帧；同帧击杀只升级现有暂停，独立后续命中波次重新允许击杀反馈。普攻镜头回弹缩短为单次1像素偏移后归位，不往返摇晃，保持连段输入缓存和原有挥刀／收势时序。
- 对外信号：`impact(档位, 方向)`（每段攻击第一次命中时发一次）、`move_started(招式)`、`attack_started`、`attack_hit`、`combo_changed`、`hit_resolved`、`critical_hit`、`normal_contact_stop`、`special_started`、`landing_impact`、`charge_started`、`charge_ready`、`charge_ended(released)`。外部输入走 `handle_input(event)`，回到待机用 `show_idle()`。对话框、密码门和改键菜单用 `freeze(owner)` / `unfreeze(owner)` 暂停玩家，按持有者计数，最后一个持有者释放时才恢复；改键菜单冻结时不清速度。
- 命中特效 v2：`impact_v2.gd` 是普通无光照混合的 ContactInk 层。宽幅弯月刀光主体0.045–0.09秒，白核只在接触点附近；肉身用暗红小滴、机械用暖金碎屑和深色润滑液，击杀追加断环。最多8个刀光、96颗飞溅，避免密集目标淹没画面。旧 `player_fx.legacy_impact` 和 `legacy_dash_hit_feedback.gd` 可独立调用。
- 动作节奏：24个普通／空中三连动画按帧时长调整（0–5:1.14，6–9:0.85，10–12:1.05，13–15:0.95），不改原PNG或tres基础fps。`_attack_lunge_speed` 按各帧实际时长加权相位，普攻前冲8/8/10像素、刀光沿原刀尖轨迹扩大20%，蓄力重斩36像素。保留原足点、比例、碰撞与逐帧姿势。
- 突刺反馈：`dash_stab.hit_feedback=true`、stop=tick。每次有效伤害生成新版ContactInk材质刀痕与飞溅；整招首次接触发2帧轻顿帧、1像素镜头和命中声，击杀升级为10帧并有专用音效，同一波不反复叠加。旧视觉仍可调用legacy_dash_hit_feedback.emit_visual，旧音频与四份完整旧源码继续保留。
- 受击：敌人调用 `receive_attack(attack)`，返回 `AttackResult` HIT / EVADE / PERFECT，同时发 `attack_received(result, attack)`。突刺开始不早于敌人判定生效前 `PERFECT_LEAD_SECONDS` 0.2 秒（或在判定期间）算完美闪避；突刺中的无敌或人已不在攻击线上算 EVADE；否则 HIT：打断招式和蓄力，进入 HURT，0.25 秒内滑退约 20 像素，0.3 秒硬直、红闪，硬直中的按键等硬直结束再出。玩家本身不记血：章节的战斗夜晚由 `night_fight.gd` 听 `attack_received`，按 `attack.damage` 扣 `hero_vitals`；自由模式和测试夹具照旧不扣血。`hurtbox()` 是身体矩形，`seconds_since_dash()` 是距上次突刺开始的战斗时钟秒数。
- 完美闪避反击：GameSession 收到 PERFECT 就进入慢动作（`start_slowmo`）：`world_time_scale` 0.25，持续 `SLOWMO_SECONDS` 1.2 秒实际时间，顿帧和改键菜单期间计时不走，`Engine.time_scale` 始终是 1；画面边缘泛青（单独一层 CanvasLayer，在顿帧快照层下面），主角 `invulnerable`。慢动作中按左键或右键是反击：瞬移到那台敌人的另一侧 18 像素（那边是墙就落在这一侧），面向它出 `counter_slash`（必暴击 3 倍、10 帧顿帧），反击命中时慢动作结束。玩家只认 `open_counter(敌人)` / `close_counter()`，不知道世界时钟。

## Shift 手势与蹲行（2026-10-18）

`scripts/player/shift_gesture.gd` 只记录一次修饰键手势，使用玩家的 combat_time：松开前短于 0.18 秒是闪避，保持超过阈值是奔跑。默认 run 与 dash_modifier 均为 Shift，v4 允许共享并迁移旧默认 Caps/Shift；自定义键仍由 controls.gd 提供。

新左键按下时，侧视有修饰键和非零左右方向才记录突刺意图，并消耗本次点按；已经按住的鼠标不补造点击。完美闪避反击优先于突刺组合。菜单冻结与 clear_input_buffer 清理未完成手势，顿帧只冻结 combat_time 而不改变点按/长按类别。

无伤害闪避使用独立 DODGE 状态，侧视 ROLL_SECONDS=0.30 秒、俯视 DODGE_SECONDS=0.22 秒内沿实际碰撞移动36像素，只暂时忽略敌人碰撞，保留墙和地板；不发送攻击开始或伤害信号。结束时恢复安全站姿或保持必要的蹲姿；保留原完美闪避与连段偏移接口。侧视使用 roll_left/right 的16帧翻滚，按已流逝时间取帧，地面沿用低碰撞体，空中保持原重力；原 dash_stab 使用连续48像素突刺及其独立空中动画。

S+A/D 使用 crouch_walk_left/right，各 16 帧、14 fps，速度 20 像素/秒，碰撞盒 12×14；无方向时沿用原蹲姿，头顶受阻时不恢复 12×26 站姿。新32帧独立增加，原1024帧未改。原画、提示词和单一全局尺度导入记录在 art_metadata/crouch_walk_20261018，导入入口 tools/art/import_crouch_walk.py。

连续突刺：`DASH_SECONDS=0.18`，从动画第6帧起，取 smoothstep 累计距离的相邻差分计算 velocity.x，只用正常 move_and_slide 移动；每个物理帧将本段起止点交给 `_apply_dash_hits`。hit_targets 跨整招去重、射线阻挡墙后目标；撞墙或累计时间达到时才置 dash_executed。第14帧派生还要求位移已完成，防止排队攻击截断最后一段。顿帧暂停物理与动画，所以没有补跳；S空中下劈等中断离开pierce招式后不再执行残留位移。空中QA使用已浮空的目标检查后续连段，并另测自由下落目标提前离开路径不会被打中。

翻滚32帧来自内置image_gen，原画与提示词随工程保存。`tools/art/import_roll.py`按统一比例缩回原生像素、量化原18色、移除洋红导入标记并对齐足点，左向绕x=56镜像；不按各姿势高度分别缩放。素材校验入口 `tools/art_qa/validate_roll_art.py`。

## 敌人

- `scripts/enemies/enemy_attacker.gd`：挂在敌人身体下的攻击组件。主角进入范围后身体红闪预警 0.5 秒（结束前 0.2 秒锁定位置），然后 0.18 秒直线突袭到锁定点，最后 0.12 秒是判定；碰到主角就调用它的 `receive_attack`，判定结束没碰到也报告一次（contact = false），这样闪开的突刺也能判完美闪避。之后停顿、飘回原位、冷却 1.2 秒。时间按世界时钟走：delta 乘 `GameSession.world_time_scale`，顿帧时整棵树暂停。身体和主角之间加了碰撞例外，突袭穿过主角而不是推开它。
  贴地的人形敌人（第一章安保）另设：`horizontal`（突袭沿地面，不跟主角的高度）、`standoff`（停在主角身前）、`returns = false`（不飘回原位，停在哪儿就从哪儿再来）、`mirror_hitbox`（判定框按朝向翻转）、`damage`（随攻击传给主角）；`armed = false` 时不起手，`stagger(秒)` 取消正在举的这一下。
- 第一章的人形敌人（`scripts/enemies/humanoid.gd` 和四个子类，代码画的占位剪影，脚底为原点，约 28 像素高）：碰撞层 2（主角的刀能砍到），只和地形碰撞，和主角之间有碰撞例外（主角能从人中间穿过）；时间也按世界时钟走（`move_and_slide` 前按 `world_time_scale` 缩放速度）。挨刀的接口和训练木桩相同（`take_damage`、`damage_point`、`receive_hit_reaction`、`knock_up`、`knock_back`）：挨打硬直 0.28 秒、挑空上天、空中连击吊住；血到 0 躺下，碰撞层清空。`active` 由夜晚唤醒，`held` 让剧情时刻全员定住，`think()` 是醒着时每帧的决定，`figure()` / `glow_figure()` 是姿势的矩形（发光部分画在不受光照的子节点上）。
  - `guard.gd` 近战安保：走近，挂一个 `enemy_attacker`（举棍红闪 0.5 秒 → 0.16 秒贴地突袭，10 点伤害）。
  - `gunner.gd` 持枪保镖：保持 64–150 像素；瞄准 0.8 秒（激光瞄准线，最后 0.25 秒锁定快闪）后发射 `enemy_bullet.gd`。子弹在胸口高度水平飞，走世界时钟；碰到主角身体就 `receive_attack(contact = true)`，从主角身体中线另一侧穿过去（被跳过、蹲过、冲刺穿过）报告 contact = false；判定窗口就是到达主角的那一刻（`window_age` 0），所以到达前 0.2 秒内开始的突刺是完美闪避，反击瞬移到 `attack.source`（开枪的人）身边。撞墙或飞满 420 像素消失。
  - `buyer.gd` 逃跑的买家、`doctor.gd` 求饶的医生：不攻击。最后一个医生（`last`）在 `executable` 之前 `take_damage` 返回 false，之后任意一刀毙命。
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
| `frames/<视角>_<方向>_<动作>/NN.png` | 68 个动作 × 16 帧。含历史64组、crouch_walk_left/right和roll_left/right，新增翻滚32帧（112×96画布，足点56,84）；本轮原1056帧保持原字节 |
| `assets/side_view.tres`、`top_down.tres` | 把 frames 组装成 SpriteFrames |
| `assets/home_601/layout.json` | 安全屋碰撞、可交互物、对话文本 |
| `assets/home_601/home_601_furnished_native.png` | 当前安全屋底图；旧图 `home_601_native.png` 保留，场景和 PropEffects 统一读取 layout.background |
| `assets/underground_hospital/layout.json` | 医院俯视两层与侧视的房间、墙、家具地面占地、楼梯、门禁和交互点；`top_down_trigger_rect` 扩展俯视楼梯入口，`drawer_rect` 指定可开合抽屉正面 |
| `assets/lighting/hospital_patrols.json` | 第一章白天俯视二楼3束巡光的路线、周期、半径与亮度 |
| `assets/fonts/` | fusion-pixel 10/12px 中文像素字体（OFL） |
| `art_metadata/` | 原画、提示词、遮罩、导入脚本和校验报告；有 `.gdignore`，Godot 不导入 |

## 测试

- `tests/test_*.gd` 都是继承 `tests/support/isolated_suite.gd` 的无头脚本，用 `--script` 运行，输出 JSON（`checks`、`failures`、`status`），报告写进 `evidence/`。基类把改键文件指到测试专用路径，玩家本机的改键不影响测试结果。`tools/Test-Game.ps1` 每组可以单独设帧率（contact_refresh 在 144 fps 下跑），每次运行有 300 秒超时。
- 战斗类套件加载 `tests/fixtures/combat_lab.tscn`（旧训练场 + 木桩），不进入正式流程。
- 改键测试使用独立的 `settings_path`，不会覆盖玩家真实的 `user://keybindings.cfg`。
- `tests/test_perfect_counter.gd` 覆盖慢动作和反击：世界时钟是主角的 1/4、主角全速、无敌、1.2 秒实际时间、顿帧时计时不走且仍冻结满帧、左右键反击的落点和朝向、3 倍伤害、10 帧顿帧、反击命中结束慢动作。
- `tests/test_enemy_attack.gd` 覆盖敌人攻击和受击：预警红闪和时长、HIT 的击退距离和硬直、打断挥刀和蓄力、过早突刺和跳过是 EVADE、判定前 0.14 秒和判定中的突刺是 PERFECT、被打坏的无人机不再攻击。
- `tests/test_chapter_flow.gd` 用真实按键（在实际碰撞体上寻路后按住 WASD）覆盖默认601开场、接单、医院锁定、不可关闸、密码、背后暗杀、回家购物、睡觉暴走、第一夜（`night_bot` 打完五课、两层、三句台词和处决）、屏息、第 2 天，并检查章节 HUD 和调试键。`tests/test_hospital_opening.gd` 覆盖默认正式入口601开场与接单、真实出门后医院指定出生点、独白/提示、医生、禁用配电箱及移动光照，同时保留显式跳入医院与第一夜的调试入口检查；`tests/test_light_sense.gd` 保留自由模式逐盏灯范围、断电变暗和遮罩，并验证章节暴露涨落、锁定和 R 回检查点。
- `tests/test_night_fight.gd`（Test-Game 带 `-- --nw-step=d1_night` 运行，从 `boot.tscn` 进第一夜）用真实按键逐项查第一夜：人员、生命条、五课图标和学会条件、求饶的医生、安保一棍的伤害和击退、0.35 秒内不重复扣血、过量生命先扣、死亡后本层重来、一楼没清楼梯不开、一楼跳起来不会惊动二楼、买家逃到墙边、枪手瞄准线时长和锁定、子弹命中 / 跳过 / 蹲过 / 完美闪避和反击、上楼、最后一个医生的保护和三句台词、处决的重顿帧和黑场、自由模式医院没有这些。`tests/support/night_bot.gd` 是两个套件共用的“玩家”：只看屏幕上能看到的东西（人站在哪、举棍的红闪、激光、飞着的子弹），按真实键鼠操作。
- `tests/recorders/capture_chapter1.gd` 用真实渲染截 23 张第一章画面到 `evidence/chapter1/`；`tests/recorders/capture_chapter1_night.gd` 截第一夜 22 张（死亡重来、过量生命，然后 night_bot 实打一遍时的各课、红闪、慢动作、激光、子弹、买家、医生、上楼、三句台词、处决、屏息）到 `evidence/chapter1_night/`。
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

## 第一章（章节模式）

只在 `chapter_active` 时挂上，自由模式的安全屋和医院不变。台词、时间点、商店和屏息文字都在 `assets/story/chapter1.json`；计划和拍板记录见 [第一章_实现计划](design/第一章_实现计划.md)。

- `story_state.gd` 的本轮账户：`balance` 和 `balance_changed` 跨场景共享，`award_once(id, amount)` 用奖励标记去重，`spend(amount)` 原子扣款，`purchase(id, price)` 先检查已有物品和余额再一次性赋物扣款；重新 `start_chapter` 清零，尚无持久化存档。
- `home_601/home_chapter.gd`：安全屋的章节逻辑。进入步骤时播 `enter_sequence`（标题卡、醒来、音效、对白，按顺序）；电视按天播新闻；电脑打开暗网终端（`scripts/ui/terminal_menu.gd`：信息推进剧情，购物原子扣费并记录物品）；冰箱、哑铃记当晚标记；真实撤离到 `d1_return` 且 `coburn_dead` 时仅结算一次50元，HUD显示到账；电脑结算需完整翻页，Esc关闭不推进，完成进入 `d1_resupply` 并自动打开购物；成功购买才到 `d1_shopped`，床在允许的步骤睡到 22:00 并播暴走转场；门按步骤的 `door` 出发。
- `hospital/hospital_chapter.gd`：医院的章节逻辑。步骤决定视角（白天俯视、夜晚侧视），`hospital.arrival_room/arrival_position` 决定从601接单、出门后进入医院时的白天出生点（当前一楼药品库门旁566,78），不改变 `d1_wake` 的601正式开场，位置走原有碰撞校验。`_arrive()` 淡入后用现有带主角立绘的 DialogueBox 播“光粒子监控，真是麻烦...”，关闭后解冻并显示“请尽快躲避光线，shift奔跑。”8秒；`sequence:hospital_opening` 标记避免重复。这两句来自用户要求，不是SK原文。每个物理帧读取灯光（阈值0.06）和 `day_staff.visible_by(player)`，`in_light or in_sight` 共用一条暴露进度，每秒 +0.8 / -0.3，约1.25秒满后锁定并回本层检查点。`_input_blocked()` 阻止模态、冻结和过渡期间累计；被医生看到时表头为“目击”，扫描反馈开启，锁定显示“医生发现了你”。F处决实时核对阶段、楼层、距离、背后、灯光、医生目击和模态；E保留普通调查。处决后推进 `d1_target_down` 并由出口回家；夜战原流程保留。章节白天配电箱仍禁止关闭，即使已有钥匙或解锁标记。`line_overrides` 的密码只在 `treatment_drawer`，接待电脑只留值班表。
- `hospital/hospital_day_staff.gd`、`day_doctor.gd`、`doctor_sight.gd`：白天俯视一楼3人、二楼2人，沿巡逻点行走并转向，保持轻微呼吸。`doctor.sees_player(player)` / 容器 `visible_by(player)` 依据同层、距离、朝向和真实墙体/家具射线，开放门洞两侧可互相看到；可见视野扇形同样裁掉遮挡。医生巡逻在模态期间暂停，无攻击、伤害接口或碰撞，不进 `enemies` 组，夜战与自由模式不生成。
- `hospital_interactions.gd` 的俯视楼梯在 `top_down_trigger_rect` 内优先选择，让一楼顶部靠近即显示E，同时保留原底部入口。`treatment_drawer` 用现有0.3秒反馈计时，将背景里的 `drawer_rect` 正面整数下移3像素再合回，不另建贴图或循环。`hospital_security.is_door_unlocked()` 在章节白天将非办公室门视为开放，不写共享解锁标记；办公室仍保留真实密码门碰撞，自由模式仍用原三门锁。家具沿墙脚布置，碰撞使用地面占地，不按整段立面阻挡玩家。
- 光照判定和画面一致：`interior_lighting.gd` 给每个光源记 `reach`（俯视医院按 `layout.json` 的 `light_zones`，墙上的灯用 `zone` 指明照哪边；侧视是楼层上下界），光照贴图在 `reach` 外是黑的，`light_level()` 用同一套 `band()` 衰减和 `reach` 算亮度。二楼走廊的光斑画在底图里，断电时显示 `assets/underground_hospital/lamp_off/` 的遮罩（`tools/art/gen_lamp_off_covers.py` 生成并写进 layout 的 `off_cover`）。
- 第一章白天俯视二楼额外创建3个巡光 PointLight2D，来自 `hospital_patrols.json`，共用 `_sources`、`band()`、`reach` 和 `light_level()`，画面与曝光同步；本轮扩大光斑、移除发光灯芯，整数像素移动，临床分区断电不影响巡光。复用光照助手的 `_process()`，阅读、密码、设置、顿帧、开场和楼梯忙时暂停路线时钟；自由模式、1F和夜战不创建巡光。本章2F固定灯亮度0.19，需结合巡光移开的时机穿行。
- `levels/breath_interlude.gd`（`scenes/breath_interlude.tscn`）：屏息过场，黑屏、呼吸声，按步骤的 `breath_round` 逐行打出乱码口号，然后进 `next` 步骤。
- `ui/story_overlay.gd`：标题卡、淡入淡出、22:00 暴走、锁定提示和剧情音效（`assets/audio/story/`，`tools/audio/gen_story_sfx.py` 合成的占位）。
- `hospital/night_fight.gd`：步骤带 `fight`（第一夜 `d1_night` → `nights.night1`）时由 `hospital_chapter` 挂上，管一整夜：按 `chapter1.json` 放人（`enemies` 的 `kind`、`floor`、`x`、`faces`、`last`），主角在同层 150 像素内就唤醒；`hero_vitals.gd`（血量、临时过量生命 `grant_overheal`、`died`）和 `ui/health_hud.gd`（右上生命条，占暴露条的位置）；五课教学（`ui/tutorial_plate.gd`，只有按键图标）按真实动作判定学会；一楼清空前 `stairs_open()` 为假（`underground_hospital._begin_stairs` 和键帽都看它），屏幕边缘的青色箭头指路；血到 0 时 `restart_floor()` 让这层的人回原位、主角回本层起点（`floors.<层>.start`，写进 `hospital_chapter.checkpoint`，R 也回这里）；只剩最后一个医生且主角走近时用医院的对话框打出 `last_words`，读完后下一刀触发 `_execute()`：`GameSession.hit_stop(&"heavy")`（新增的公开方法，剧情要的顿帧）→ `story_overlay.execution()`（白一帧、黑场）→ `SceneRoutes.travel(next)`。战斗夜晚 `hospital_chapter.interactions()` 只留楼梯（夜里没有可读的东西），出口也不再用。
- UI“冷光终端”：`ui/hud_style.gd` 是颜色和底板；`ui/chapter_hud.gd` 是状态牌（左上）、交互键帽（底部居中）、提示气泡和操作提示（6 秒后淡出）；`ui/exposure_hud.gd` 是暴露条和扫描牌（夜街也用）。章节模式下安全屋和医院原来的标题、操作提示、交互提示都隐藏，由这些组件代替。HUD 用 10px 像素字体（`pixel_ui.small_font()`），对白仍是 12px。

## 已知问题

- `player.gd` 约 930 行。招式数据、特效已经拆出去；移动和动画选择还在里面。
- `main.tscn` 和 `home_601.tscn` 内容相同，只是节点名不同。
- 门锁、物品、电源状态只在当前进程内有效，还没有存档系统。
- `art_metadata/` 里的流水线脚本写死了原开发机路径。

### 2026-10-18 右键重击与轻顿帧

`rush_cleave` 改用专用 `heavy_cleave_left/right`，每侧16帧，112×96画布、足点56/84；以同一比例导入生成姿势，旧1088帧不改，现70动作/1120帧。32fps配独立帧时长：前8帧11.6单位约0.3625秒，8–10帧2.2单位约0.06875秒，11–15帧顺势收刀，整段约0.639秒。实际物理命中约0.383秒；挥刀声由 `swing_released` 在第7帧释放时发出，不在按键瞬间播放。

收益：3倍伤害（原2倍），50×32的宽判定、reach24；前冲参数24像素（60Hz实际约20.7），击退14像素（原10），`stop=heavy` 保留10帧命中卡肉。风险：不增加霸体、无敌或闪避取消；朝向锁定，前摇可被实际敌人攻击打断，挥空仍走0.16秒恢复。第二次右键可在输入缓存内等待第13帧派生上挑，不能跳过蓄势和出刀。普攻改为2帧并保留1像素短回弹，暴击6帧、重击／击杀10帧。

`tests/test_heavy_cleave.gd` 覆盖双向真实右键输入、前摇无伤害/无滑步、方向承诺、受击打断、单次3倍伤害、声音释放、10帧卡肉、挥空恢复与恢复期间输入缓存，以及完整原生帧。原画、提示词、独立刀尖轨迹与导入报告保存于 `art_metadata/heavy_cleave_20261018`；可运行 `tools/art/import_heavy_cleave.py` 重建。录制器 `record_heavy_cleave.gd` 仅在独立实例摆放受控目标，不改正式关卡。

### 蓄力拔刀斩（2026-10-18）

借鉴“不死斩”的蓄势反差与黑红斩痕，角色与武器沿用本工程形象，新增独立32帧而不改此前1120帧。招式表 `side_anim` 为侧视动画，`anim` 保留俯视兼容；俯视也使用增强伤害与108×56判定，仍使用原attack3帧。`_charge_animation/_charge_pose_limit` 将蓄势与释放的同一第6帧衔接，避免满蓄力释放时跳回旧攻击。

`charged_draw.gd` 是独立普通混合特效层，首个实际判定帧且完成本帧物理移动后只释放一次，未命中也有刀气；墙体缩短视觉延伸，命中受击斩痕切为深红，飞溅/击杀仍按材质与击杀档位。上限2道刀气，无满屏闪白，不改变普攻2帧、右键重击3倍伤害及10帧卡肉。测试 `test_charged_draw.gd` 在60/144Hz覆盖双向、远近/高位多目标、各目标只伤一次、一次卡肉、墙体阻挡、提前松开/受击取消及全16姿势。

生成原画、完整提示词、单一全局比例与刀尖注册记录在 `game/art_metadata/charged_draw_20261018/`，导入入口 `tools/art/import_charged_draw.py`。透明原画按连通人物提取，避免越过名义网格的刀尖被截断或混入相邻动作；保留原图。当前72动作/1152帧。

### 直接蓄力与击飞（2026-10-18）

`_primary_press` 保存按下的战斗时钟和连段来源。普通地面左键按下只记录蓄势；持续达到PRIMARY_TAP_SECONDS后物理帧进入CHARGE，短按松开转成带primary_tap的轻击意图，满蓄力松开出heavy_slash。短按不播放蓄力声音/特效，也不发生蓄力后撤；长按的声音/后撤在0.14秒确认后开始，蓄满时间仍从直接蓄势开始计0.55秒。未满长按松开取消。当前攻击期间的新短按保留连段，跨越收招的短按仍使用保存的连段来源；长按可以在原刀结束后蓄力，不补一刀。特殊组合键、空中、蹲姿和反击继续即时处理，顿帧只记录边沿，菜单/受击清理手势。

`heavy_slash.launch=true, charged_launch=true`。玩家优先调用receive_charged_launch，且强上挑不再被普通knock_back覆盖垂直速度。侧视实体目标使用(±105,-300)速度并按真实重力/碰撞飞行，卡肉冻结后再续行。正式hover_target使用相同初速移动实际节点，身体、碰撞盒和damage_point同步；水平与竖直墙/地面射线限制位移，必要时回到原悬浮平面。起飞将敌人攻击置冷却并暂时停用AI，落地恢复此前的process_mode，避免强行启用本来禁用的AI。

test_direct_charge在60/144Hz覆盖贴脸蓄力0预伤害、0轻击动作、一次6伤害、双向实体/正式无人机击飞与落地、卡肉冻结、同帧点击、轻连段、取消后无残留攻击。没有修改人物帧图、武器图或原有近战特效。

### 蓄力追跃与突刺扫掠（2026-10-18）

`_offer_jump_chase`只接纳受蓄力真实击飞且存活的目标，以WeakRef保留最近对象，资格随combat_time计0.50秒。`chase_jump`意图可在命中前或顿帧期间记录；物理恢复后才处理，菜单、受击、落地和闪避清理。`request_jump_chase`取消已命中的蓄力收招，设定弹道相遇初速度（-360至-225）、最多280水平速度和1400加速度；位置始终只经move_and_slide前进。0.60秒内缓和追近23像素间隔，反方向输入取消辅助；不会追踪尸体、释放对象或穿越障碍。

起跳当帧延后攻击意图一帧，使后续选中空中动画。第一刀前保留上升速度，避免空中攻击刚启动就打断追跃；与选定目标第一次juggle接触后转为0.55秒、6px/s的共同浮空。正式hover_target持有_charged_air_hold_left，飞行期间与测试实体一样可续击，落地仍恢复原AI模式。空中突刺/下劈开始时先清理追跃，使用各自原有空战规则。

`_apply_dash_hits`取整段前后刀刃矩形的凸包，前伸35、后伸4、高20原生像素，也覆盖每帧的纵向位移；查询容量随场景节点数，hit_targets跨招去重，世界层射线拦截墙后目标。30/60/120Hz和双向64目标实测只命中一次，48像素/0.18秒smoothstep位移不变。

夜街layout.json目标位置可有可选第三数值max_hp，默认3；第一只配置9生命和金色装甲条，便于正式试玩追跃。生命显示最多三段，各代表max_hp/3，避免高生命目标的提示铺满画面。test_jump_chase（60/144Hz）和test_thrust_path纳入完整回归；实机录制器为record_jump_chase.gd。

### 轻点分流与蓄力首段（2026-10-18）

`_primary_press.at`先记录战斗时钟；0.14秒之前不改变状态、动画或移动，release直接转成带primary_tap的轻击意图。确认长按才调用_begin_charge(held_seconds)，通过_charge_started_at保留最初按下时刻，_update_charge读取战斗时钟差，因此满蓄力仍为0.55秒、顿帧不会偷跑。蓄势姿势从确认长按后0开始，到0.33秒完成6帧收刀，再保持至蓄满；声音、后撤与粒子均只在确认后开始。

heavy_slash使用stage=1、as=attack1、cancel=12、followup_seconds=0.25，实际伤害、暴击、动画、特效和击飞仍来自自己的数据行。_string_id仅决定连段图与段数，后续左键attack2、右键rush_cleave；第12帧取消不早于8至10帧有效斩击。结束时保存_followup_from/_followup_until，允许在原收招及结束后0.25秒内续接同一连段，_start_move一次性消费资格；没有继续输入时保留原收招。清理输入、受击、闪避、新蓄力清除资格。

request_jump_chase继承attack1身份，保留CHASE_ASSIST_SECONDS的首段衔接；起跳当帧延后处理，下一帧正确选择air_attack2，再接air_attack3。原先缓存在蓄力招式中的queued输入在追跃起跳时转为raw，防止丢失第一次空中续击。test_primary_charge_chain在60/144Hz覆盖短按逐物理帧、待机/走路/改键、完整计时、左右/俯视、轻重二三段、收招/宽限期、命中顿帧、伤害及资格清理；test_jump_chase同步验证段数连续。

### 连贯衔接与轻击剩余蓄势修复（2026-10-18）

上轮仅避免极短点击进入CHARGE，未解决0.14秒阈值过短和attack1自身约0.25秒的抬刀停留。PRIMARY_TAP_SECONDS改为0.24，CHARGE_COIL_PORTION改为0.82，使确认长按后至0.451秒完成收刀，0.55秒蓄满不变；六条地面attack1的前七帧时长改为[.45,.45,.55,.6,.6,.6,.7]单位，侧视第7帧实斩的理论前摇0.10972秒，俯视第6帧0.09028秒。没有删除必要转身／抬臂姿势或修改PNG。

build_combat_links.py构建左右charge_link_light/heavy四条16帧动作，前两张直接引用charged_draw的11、12帧，再引用原attack2或heavy_cleave的连贯姿势及正确刀尖路径。轻准备0.0975秒，重准备0.1671875秒，首两张各至少一个60Hz显示周期。heavy_slash.cancel=11，_start_move在仍处于蓄力斩收势或其收招、侧视地面时选择move.charge_link，11/12帧从相同收势帧开始，稍晚收招从直立第2帧进入；move_id、段数、有效帧、伤害与音效释放接口不变。迟按至完全收招时和追跃空中时使用普通／空中动作，避免逆播低姿收刀。原来28+44动画改为28+48，共1216次帧引用，独立PNG仍1152张。

test_smooth_charge_links在60/144Hz覆盖0.08/0.18/0.22秒点击、左右与俯视、真实前摇、过渡首帧与刀尖路径、足点、实际两次命中间隔和正确伤害、顿帧及迟按分流；record_smooth_combat用约0.18秒普通点击和左右键连段录制正式夜街动画。
