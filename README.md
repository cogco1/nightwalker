# 夜行者 Nightwalker

**当前开发基线：`main`（含第一章 M2 与最新战斗动作）**。已发布包：[v2026.10.18](https://github.com/cogco1/nightwalker/releases/tag/v2026.10.18) · [该包更新说明](docs/releases/v2026.10.18.md)。

当前进度、待完成事项与最近验证见 [PROJECT_STATUS.md](PROJECT_STATUS.md)。

## 狙击手战斗试玩（2026-10-21）

双击 `Run-Sniper.cmd`，或用 Godot 4.7.2 运行 `game/scenes/sniper_combat_test.tscn`。
远距离卧姿狙击，中距离起身举枪射击，近距离以枪托反击。瞄准有红色激光，子弹有亮色弹芯、曳光和枪口闪光。
狙击弹、无人机机炮弹及近战会击退；步枪、霰弹枪弹不产生击退。狙击手限制在出生点左右各40原生像素内。
试玩保留真实主角的跳跃、闪避、完美闪避反击、命中停顿和生命系统。
按1/2/3快速试远/中/近距离，C切换掩体，R重来；常规操作尊重改键。详见 [狙击手战斗说明](docs/prototypes/狙击手战斗_v02.md)。
本轮先提供独立战斗试玩；第一章人员配置和默认入口保留。

Godot 4.7.2 像素动作游戏（SK 项目）。设定在 2040 年的佩特拉新城：白天俯视潜行，夜晚侧视长刀战斗。在 **v14** 人物与场景基线上继续开发：601 安全屋、地下医院（俯视/侧视双视角）、C 区夜街，以及 76 个动作入口、1152 张独立人物帧图（含重击、蓄力拔刀、左右空中突刺、蹲行和翻滚）。第一章正在按里程碑制作，M1（昼夜、家枢纽、俯视暗处潜行的最小闭环）和 M2（第一夜的器官交易战斗、血量、按键图标教学和处决）见下文“第一章”。

普通地面左键短按期间保持待机／行走姿势，松开直接出轻击；持续超过0.24秒才确认蓄力，轻击本身的抬刀改为约0.11秒；从按下到蓄满仍为0.55秒。蓄力斩计作第一段，收势直接经过专用动作接左键轻击二段或右键重击二段，空格追跃后也从空中第二段继续。

当前打击效果已更新：短促宽幅刀光、材质飞溅、击杀卡肉、小幅镜头回弹与6段新音效；蓄力击飞后0.50秒内按空格可沿连续弧线追跃并接空中连招；突刺恢复命中特效、音效与镜头反馈，整段刀刃路径可贯穿多名敌人。首只夜街无人机为9生命的金色装甲型，便于体验追跃。

## 快速开始

1. 把 `godot-path.example.txt` 复制成 `godot-path.txt`，写入本机 Godot 4.7.2 的路径（这个文件不入库）。也可以设环境变量 `NIGHTWALKER_GODOT`。
2. 双击 `Run-Demo.cmd` 从第一章601安全屋开始（7 月 27 日 12:00）：标题卡、电视新闻和敲门后，到电脑读取乔伦的委托，再从门口前往医院；医院入场位置是一楼药品库门旁走廊，原生脚点566,78。`powershell -File tools\Run-Game.ps1 -Step d1_hospital` 可跳过安全屋，直接调试医院。章节里 F7、F8、Tab 是调试键，要用就加 `-DebugKeys`；`-Step d1_night` 直接从第一夜开始。双击 `Run-Sandbox.cmd` 进原来的自由模式：从安全屋开始，F7 往返安全屋与医院，F8 进入夜街、再按返回来源室内。`Open-Editor.cmd` 打开编辑器，`Test-Game.cmd` 跑完整回归；`Run-NightStreet.cmd` 仍可直接进夜街。
3. 操作见 [docs/操作说明.txt](docs/操作说明.txt) 和 [docs/游戏内改键说明.txt](docs/游戏内改键说明.txt)。

已验证引擎版本：`4.7.2.stable.official.ed1daf0bf`，GL Compatibility 渲染器。

## 目录

```
Nightwalker/
├─ Run-Demo.cmd / Open-Editor.cmd / Test-Game.cmd   双击入口，都调用 tools/ 里的脚本
├─ Run-NightStreet.cmd                              直接启动夜街原型场景
├─ Run-Sandbox.cmd                                  自由模式（不开第一章，F7 / F8 / Tab 照旧）
├─ godot-path.example.txt                           本机 Godot 路径模板
├─ game/                                            Godot 工程（res:// 根目录）
│  ├─ project.godot                                 320×180 原生分辨率，整数缩放；autoload：SceneRoutes
│  ├─ scenes/                                       boot（正式入口，开第一章）/ main / home_601 / underground_hospital /
│  │                                                breath_interlude（屏息）/ player / night_street_proto
│  ├─ shaders/                                      人物赛博配色、发光层、湿地反光、低雾、暴露度色差
│  ├─ scripts/
│  │  ├─ core/        boot · controls · game_session · scene_routes · story_state（物品、标记、章节进度）
│  │  ├─ player/      player.gd（移动、轻击连招、蓄力重斩、突刺、空战、顿帧信号）
│  │  ├─ enemies/     enemy_attacker（预警突袭）· humanoid（第一章人形敌人：guard · gunner · buyer · doctor，代码画的占位）· enemy_bullet
│  │  ├─ ui/          pixel_ui · keybindings_menu · dialogue_box · hud_style · chapter_hud · exposure_hud ·
│  │  │               terminal_menu · story_overlay · health_hud · tutorial_plate（第一章的“冷光终端”UI）
│  │  └─ levels/
│  │     ├─ level_kit.gd 关卡共用：碰撞体、镜头跟随
│  │     ├─ interior_lighting.gd 安全屋与医院共用的像素灯光、辉光、薄雾与人物轮廓光
│  │     ├─ home_601/   home_601 · home_prop_fx
│  │     ├─ hospital/   underground_hospital · hospital_interactions · hospital_security · hospital_chapter · hospital_day_staff / day_doctor（白天医生）· night_fight（第一夜）
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

`Test-Game.cmd` 先做一次素材导入，再依次跑 49 组套件，日志写到 `game/evidence/logs/`，最后打印每组检查数和总数，有失败时返回非零退出码。套件清单以 `tools/Test-Game.ps1` 为准，最近实际执行结果见 [项目进度](PROJECT_STATUS.md#最近验证)。

| 套件 | 内容 |
|---|---|
| core_v07 | 移动、三连击、暴击、顿帧、Shift 点按无伤害闪避、长按奔跑、Shift+方向+新左键突刺、上挑、1152 帧资源 |
| keybindings / keybindings_reload | 改键保存、冲突（闪避/突刺与奔跑允许共用）、旧默认Caps/Shift迁移至v4、重启读取 |
| air_combat / air_dash_animation_v14 | 二段跳、空中三连、下劈、空中突刺 |
| scene_integration_v14 | 安全屋与医院里的实际玩家、顿帧和改键 |
| scene_routes | 真实 F8 输入、来源楼层/视角/安全脚点恢复、改键优先、弹窗/楼梯拦截和顿帧切场清理 |
| interior_lighting | 室内实际光源与人物材质、设备/分区供电、俯视楼层与侧视重建、像素规格及原交互 |
| home_furniture | 新家具实体、全屋足部空间连通、真实 WASD 访问新旧交互、冷暖灯独立供电及人物受光 |
| hospital_* (5 组) | 医院交互、环境、实体楼梯、病房布局、门禁与电闸 |
| level_shared | 共用关卡逻辑、冻结计数、剧情弹窗、对话框说话人、E 键保留和改键提示 |
| contact_refresh_v07 | 高刷新率下的命中停顿 |
| charged_slash | 点击仍是轻击；按住转蓄力（逐帧收刀、后撤约 3 像素）、蓄满松开重斩（前冲至少 24 像素、3 倍伤害、暴击顿帧）、早松取消、蓄力定身、跳跃和清空输入会打断、突刺和空中不蓄力；真实场景里轻击 4 帧、重斩 10 帧顿帧和音效顺序 |
| combat_impact_v2 / combat_impact_v2_144 | 60/144Hz命中反馈、突刺命中及击杀反馈、击杀与多段去重、材质飞溅、镜头复位和音效时机 |
| impact_burst / impact_burst_144 | 打击感原型（剑气破屏）：F10 开关、重招剑气越飞越快越大并冲出屏幕边、顿帧期间照飞、重击/暴击/击杀切屏和合上、定格照片不带剑气、轻微震屏不超过 3/1 像素并复位、关掉后恢复原回弹 |
| jump_chase / jump_chase_144 | 空格顿帧预输入、双向/远距实体与正式敌人追跃、空中连击、近邻存活目标、失效窗口和墙顶碰撞 |
| thrust_path | 双向30/60/120Hz刀刃完整扫掠、64目标去重、墙体阻挡、单次轻顿帧和镜头/声音 |
| smooth_charge_links / smooth_charge_links_144 | 0.18/0.22秒普通点击、轻击真实前摇、原画收势精确续接、实战两刀间隔、轻重卡肉与迟按分流 |
| primary_charge_chain / primary_charge_chain_144 | 短按逐帧无蓄力姿势、行走及改键、0.55秒蓄满、蓄力作为首段、轻重二三段、收招衔接窗口与顿帧输入 |
| direct_charge / direct_charge_144 | 贴脸直接蓄力无前置轻击、短按轻击、实体/正式敌人击飞及落地、输入清理 |
| charged_draw / charged_draw_144 | 蓄力6倍伤害、双向大范围、墙体阻挡、多目标去重、蓄势衔接与黑红刀气 |
| heavy_cleave | 右键独立重击、蓄势与受击打断、3倍伤害、挥空恢复和输入缓存 |
| roll_thrust_motion | 翻滚姿势、30/60/120Hz连续突刺、位移上限、顿帧续行、取消和掉出路径的目标 |
| shift_controls | 点按/长按/组合点击优先级、旧配置迁移、暂停输入、闪避取消与后续连段、左右蹲行和低矮通道 |
| locomotion_blade | 侧视走/跑全部 64 帧持刀方向、实际刀尖像素、地面间隙与足点镜像 |
| moveset | 招式表、动画帧速、判定帧与刀尖路径完整性 |
| combat_state | 战斗状态机、输入意图、顿帧期间的战斗时钟与输入缓冲 |
| rhythm_combat | 轻重连段、闪避派生和空中旋转斩 |
| enemy_attack | 敌人预警与攻击、玩家受击、闪避和完美闪避判定 |
| perfect_counter | 完美闪避慢动作、反击落点与伤害、顿帧和时钟恢复 |
| night_street_proto | 人物材质覆盖所有场景、光束暴露与标记、无人机连击和顿帧、原型专用按键、F8 场景入口 |
| coburn_reward_flow | 真实F处决与E撤离、一次性50元报酬、余额与扣费、完整结算阅读、购物和睡觉接22:00侧视主线 |
| coburn_execution | 科伯恩原生像素素材、真实F处决输入、暗处与背后条件、E分工、弹窗/楼梯/侧视拦截和剧情撤离 |
| light_sense | 每盏灯的房间/走廊范围、贴图与判定亮度一致；自由模式断电变暗和光斑遮罩；章节暴露涨落、锁定及 R 回本层检查点 |
| hospital_opening | 正式入口601开场与接单、出门进入医院的指定出生点和一次性独白/提示、配电箱禁用、白天医生、二楼巡光曝光及弹窗暂停；显式跳入医院与夜战 |
| hospital_revision | 楼梯上端提示与真实E上楼、柜后碰撞、电脑与抽屉线索、办公室唯一密码锁、大巡光去芯、医生走动转向、真实视野遮挡与目击返检查点 |
| chapter_flow | 真实按键走完默认601开场和接单、医院锁定、不可关闸、密码、背后暗杀、回家购物、睡觉暴走、第一夜（五课、两层、三句台词和处决）、屏息、第 2 天；章节 HUD 和调试键 |
| night_fight | 从 `boot.tscn` 以 `-Step d1_night` 的方式进第一夜，逐项查：人员和生命条、五课按键图标和学会条件、安保一棍、过量生命、死亡后本层重来、楼梯在一楼清空前不开、枪手瞄准线和子弹（命中、跳过、蹲过、完美闪避和反击）、买家逃跑、医生求饶、最后一个医生的保护、三句台词和处决、自由模式医院不受影响 |

## 第一章

策划原文、拍板记录、里程碑和 M1、M2 实现情况见 [docs/design/第一章_实现计划.md](docs/design/第一章_实现计划.md)，台词和流程数据在 `game/assets/story/chapter1.json`。

- 默认流程：7月27日12:00，601安全屋的标题卡、电视新闻、独白和敲门 → 电脑读取乔伦的委托 → 从门口前往医院，12:30在1F药品库门旁走廊566,78入场 → 俯视潜行暗杀科伯恩 → 14:50 撤离回家，委托到账50元 → 电脑读取结算引导并购物 → 睡觉，22:00 暴走 → 地下医院（侧视）第一夜的器官交易战斗 → 最后一个医生的三句台词和处决 → 屏息 → 7 月 28 日 11:00 醒来，接莫温的单。`-Step d1_hospital` 仅用于直接调试医院，`-Step d1_night` 直接调试第一夜。金域大厦是 M4/M5。
- 医院入场：从601接单并出门进入医院后，淡入时主角立绘独白“光粒子监控，真是麻烦...”，关闭后提示“请尽快躲避光线，shift奔跑。”；本轮章节只播放一次。这两句来自用户新增要求，并非SK原稿台词。白天俯视一楼3名、二楼2名医生会巡逻和转向，显示受墙体、家具遮挡的视野扇形，不攻击玩家；夜战使用原有敌人。
- 潜行：灯光或医生视野内持续约1.25秒会锁定并返回本层检查点，医生发现时暴露条显示“目击”，暗处仍需避开医生视线。二楼3束巡光扩大光斑并去掉亮灯芯，实际参与曝光；阅读、密码、设置、顿帧和楼梯过渡期间，巡光、医生巡逻与曝光累计暂停。第一章白天配电箱禁止关闭，持有钥匙也不能拉闸；自由模式原有功能保留。科伯恩仍需在暗处且不被医生目击时，从背后靠近后按F处决，仅俯视角有效；E负责普通交互。
- 医院通路与线索：一楼楼梯顶部靠近即显示E上楼，原底部入口仍可用。第一章白天俯视只锁办公室门，其他门默认开放；密码1010移到二楼治疗室水槽旁抽屉，E查看有短开合反馈，接待电脑只显示值班表。医院家具重新沿墙脚落地，碰撞按地面占地设置，楼梯、门洞与通道保留。
- 第一夜（M2）：近战安保（举棍闪红）、持枪保镖（开枪前红色激光瞄准线，子弹能冲刺穿过、跳过、蹲过，也能完美闪避后反击）、逃跑的买家、求饶的医生，都是代码画的占位剪影。全程无字幕，教学只用按键图标（移动、轻击连段、重击、闪避、完美闪避反击）。主角 100 点生命，掉到 0 从本层开头重来；一楼清空才能上楼；最后一个医生说完三句，一刀处决（顿帧、闪白、黑场）后进屏息。
- 界面：“冷光终端”方案（左上状态牌、底部交互键帽、右上暴露条或夜里的生命条、底部按键图标教学、洋红的暗网终端），对比图见 [docs/design/第一章_UI冷光终端_对比.png](docs/design/第一章_UI冷光终端_对比.png)。

## 赛博朋克视觉原型（夜街）

- 人物：`assets/fx/character_cyber.tres` 挂在 `player.tscn` 的 Sprite 上，所以安全屋、医院、夜街都生效。它按 18 色查找表（`assets/fx/cyber_palette.png`）换色，按光源方向给朝光的边缘上色、背光一侧压暗，刀刃三种钢色和脸部两种肤色做成自发光（刀光、目镜）。原帧一张没改；`look = 0` 就是原配色。
- 夜街：`scenes/night_street_proto.tscn`，只有侧视。CanvasModulate 压暗，PointLight2D 街灯和霓虹，三层视差（A 区巨塔和总控塔、佩特拉卡兹尼神殿式岩壁立面、C 区楼房和金域大厦）加街面层，巡逻无人机的监控光束（光束里飘着微光粒子），湿地反光、雨、低雾、WorldEnvironment 辉光。底图由本机 Codex 的 image_gen 生成、降到原生像素后拼装，过程记录在 `game/art_metadata/night_street_v15/`；脚本占位版留在 `game/assets/night_street_placeholder/`。
- 义体：兜帽下的洋红目镜；斜挎带、腰带和肩带是反光条，被灯照到就亮成那盏灯的颜色；握刀手的前臂上有一块被刮掉的条码疤（设定里主角没有身份序列号），偶尔闪红。站进光束时头顶弹出扫描面板，显示“ID 无法识别”。
- 光 = 被监控：站进光束，右上角暴露条上升、画面出现轻微色差；暴露满了被标记，光束变红并追人，离开光束一段时间后解除。
- 夜街操作：AD 走、空格跳、左键连斩、按住左键蓄力重斩、点按 Shift 翻滚，长按 Shift 奔跑，Shift+A/D+新左键突刺，S+A/D 蹲行；F9 切换赛博配色和原配色对比；R 重置；Tab 在这里不切视角。
- F8 在室内与夜街间往返，返回时恢复医院楼层、视角及可落脚位置；直接启动夜街时 F8 返回安全屋。对话、密码、设置和楼梯过渡期间不切场景；若 F8 已被改键占用，优先执行玩家绑定。
- 安全屋与医院共用夜街的冷色环境光、分档像素点光源、自发光辉光和随位置变化的人物轮廓光，并加入低密度室内薄雾。电视、电脑保留动画及短而向下的光锥；医院灯具与屏幕跟随原有供电分区，应急光独立。原墙体结构与清晰字幕保留。
- 安全屋参考《武士零》公寓的旧居气质，改为磨旧暖棕木地板与剥落暗紫墙面，增加旧书柜、维修桌、木凳、收纳箱、折叠椅，以及磨损地毯、杯瓶报纸、旧海报和沙发毯。维修灯、床头灯的局部琥珀色与原青色屏幕对照；暖灯独立于屏幕供电。书柜、维修桌、箱子可按 E 调查，桌面反光与箱盖有小幅像素反馈。新家具有实体碰撞，原墙体结构与旧物品位置不变，厨房下沿和卧室通道可走。
- 家具和材质原画由内置 image_gen 分两次生成，分别导入原生网格，无抖色、硬透明边。两张原画、完整两次提示词、原生家具/材质/装饰、保护遮罩与放置记录在 `game/art_metadata/home_furniture_warm_v16/`；运行 `python tools/art/import_home_furniture.py` 可重建新底图。旧底图及蓝地板试版参考仍保留，新版由 `layout.background` 选择。更换地板时保护旧屏幕、空相框和冰箱动画区域，保持既有交互对齐。
- 改动清单：[docs/prototypes/夜街赛博原型_改动清单.md](docs/prototypes/夜街赛博原型_改动清单.md)。

## 开发约束（摘要）

完整内容见 [docs/给下一位开发者或AI的接手说明.txt](docs/给下一位开发者或AI的接手说明.txt)。

- 320×180 逻辑世界，最近邻整数放大，玩家 `scale = 1`；不要靠缩放人物做动作。
- `project.godot` 里的项目名仍带 v07：`user://` 改键配置目录跟着项目名走，改名会丢掉玩家已有的改键。
- 输入动作 `reset_arena` 现在的意思是“重置位置”，为了兼容已有改键配置保留原名。
- 原画、提示词和校验记录在 `art_metadata/`，不要只留导出帧。
- 安全屋和医院不放训练木桩；章节医院有科伯恩、白天5名非攻击医生及第一夜的安保、保镖、买家和医生，白天路人只在俯视下出现。夜街保留已有悬浮无人机。`tests/fixtures` 只供回归。

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
