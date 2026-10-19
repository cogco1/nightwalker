# 超长战场跑步试玩

双击根目录 `Run-Battlefield.cmd`。这是独立侧视试玩，原有主入口、安全屋、医院、夜街和按键设置保持原样。

- A / D：左右移动；长按 Shift：沿用主角现有的奔跑；空格：跳跃，在空中再次按下可二段跳。
- R：返回起点；Esc：关闭试玩。移动、奔跑、跳跃、重置会读取现有改键。
- E：末段工业电梯。靠近底层或楼顶停靠口可呼叫空笼；走入已停靠的笼体，再按 E 前往另一层。行进中重复按 E 不会反向，角色仍可正常移动和跳跃。
- 背景和主角均为原生 scale 1；320×180 视口使用 nearest 与整数窗口缩放。镜头只显示局部地图，沿人物前进。
- 近、中、远三层建筑均使用 6144×512 原生长图，向画布上方增加 256px 绘制约两倍高的楼体，保持像素格和原有工业配色。三张 Sprite 的原点均为世界 y=-256，scale 1。
- 远景使用 `game/assets/battlefield_far_background/battlefield_far_native.png`，含不透明天空；中景使用 `game/assets/battlefield_mid_background/battlefield_mid_native.png`，RGBA 0/255 透明背景。灰褐钢铁、旧混凝土与低饱和灰蓝仍按景深区分轮廓大小和清晰度。
- 绘制顺序为远景（z=-20）、中景（z=-15）、近景（z=-10）；水平采样速度分别为镜头移动距离的 0.28、0.58、1.0。现有镜头更新时，每个视差层只做一次整数位置更新，不循环堆叠贴图。
- 世界地面仍为 6144×256，直接读取原 `game/assets/battlefield_layer_01/ground_profile.json` 地表折线；人物尺寸、跳跃物理和原地面碰撞不变。新增可踩楼层、屋顶和损坏车辆，使用 `game/assets/battlefield_traversal/foreground_native.png`（6144×512，origin=(0,-256)，z=0）及同目录 `layout.json`。场景启动时按 layout 的 rect/polygon 一次性创建静态碰撞，楼层与屋顶使用单向顶面，可从下方跃上；车辆使用贴合车身的实体轮廓。
- 当前密集布局共 15 栋楼、5 种楼体和 7 辆破车，配有 88 处静态碰撞；8 段混凝土、铁栅与检修盖板改变部分地面外观，仍贴合原有地面高度。末段巨楼通过工业电梯接到左侧宽屋顶，楼梯、露台与高台继续作为实际可踩路线。
- 镜头可向上跟随到世界 y=-256，中心最低为 -166；x 边界和底边 y=256 保持原值。所有图片采样均减去相应 Sprite 原点，覆盖检查使用纹理自身的 6144×512 尺寸。原世界地面 y=168/224 仍对应 source y=424/480。
- 原有 S 键仍为蹲伏/空中下劈，没有新增平台下穿动作；离开平台边缘即可落下。较高楼层需要先从支撑面起跳，再在第一跳高点附近按第二次空格。
- 此试玩将角色 `floor_max_angle` 局部设为 65°，让画面中约 53～61°的外楼梯坡面可以步行；`player.gd`、奔跑速度、重力与一/二段跳数值均不变。原地面坡道仍使用原碰撞。
- 末段巨楼的工业电梯按 `layout.json` 的 `elevator` 字段构建：`id`、`x`、`width`、`bottom_y`、`top_y`、`speed`、`deck_height`、`sprite`、`sprite_offset`，可选 `call_range`（默认 28px）和 `landing_surface_id`（测试屋顶落脚点）。独立 `battlefield_elevator.gd` 使用 `AnimatableBody2D`、`sync_to_physics` 与单向底板，在主角物理步之前移动。角色由原有 `move_and_slide` 的移动平台承托，未绑定位置或新增乘坐状态；笼体图片绘制在整数像素，停靠口提示沿用现有 10px 中文像素字体。

自动完整跑步检查（先正常执行一次素材导入）：

```powershell
& '<Godot可执行文件>' --headless --path game --editor --import --quit
& '<Godot可执行文件>' --headless --path game res://scenes/battlefield_run_test.tscn -- --battlefield-smoke
```

去掉第二条命令的 `--headless` 可生成原生 320×180 PNG 截图。自动检查使用真实按键先跑完整段地面，并在每辆破车前真正起跳；分别记录原地面误差、车辆接触误差与预期跳跃，避免把车顶当作原地面错位。随后仅在 `route_start` 初始化一次，按 layout 的 14 个 waypoint 连续走过车顶、二楼、屋顶、外楼梯并回到地面，中途不移动角色坐标；楼梯的 `walk` 段禁止测试脚本按跳跃键，同时记录真实楼梯碰撞接触与离地帧。汽车、厢式车、卡车均有实际跳跃落脚接触验证。

报告位于 `game/evidence/battlefield_run_test/smoke_report.json`，`ground_traversal` 记录全地图与车辆，`course` 记录连续路线每站的承托 collider、脚底误差和跳跃次数；截图在同目录。`elevator` 另在相邻地面初始化一次，然后使用真实 E / A / D 输入走入笼体、上升、走出屋顶、空笼下降并呼叫返回、重新走入并下降回地面，全程不再次移动人物坐标。报告记录真实移动平台接触帧、脚底与底板误差、精确停靠、远处 E 无效、运行中不能反向、出笼后不会被拖走和高处镜头覆盖。自动检查的输入控制器仅在烟雾模式动态加载 `game/tests/support/battlefield_traversal_driver.gd`，正常试玩不运行路线扫描；测试使用专用按键配置，不写入玩家改键文件。

报告记录独立的 `world_size`、`art_size`、`art_origin`，以及各截图前景/近景/中景/远景采样窗口、整数位置、实际滚动比例和完整覆盖断言。GPU 每 4px 采样，按可踩前景→近→中→远选择真正暴露的最上层源像素，并排除当前人物帧不透明像素包围盒及 4px 光晕范围、移动电梯笼体和停靠提示；每张图每个暴露层需有至少 99.5% 样本与原图匹配（RGB 容差 1.5/255）。建筑可完全遮住后层，该帧记录 0 暴露而不误报；整条路线累计每层仍需至少 256 个匹配样本、64 个相邻不透明像素色差超过 6/255 的细节样本，且至少一帧有 8 种匹配颜色，防止纯色或未显示的图层通过。人工查看截图确认可踩边沿、建筑尺度、景深和配色。

头尾镜头移动约 5824px，中景移动约 3378px，远景只移动约 1631px。新增画布高度不会增加世界范围或改变镜头速度。

独立快速回归：

```powershell
& '<Godot可执行文件>' --headless --path game --script res://tests/test_battlefield_run_test.gd
```

可踩建筑与车辆版本的验证结果以 `test_report.json`、`smoke_report.json` 和同目录截图为准。


环境动态 v09：独立战场额外读取 `game/assets/battlefield_ambient/ambient.json` 与透明 `steam_large.png`。

- 窗灯直接裁取所属近/中/远背景的真实灯窗区域，缓慢明暗闪烁，短暂暗跳；不会增加悬空光球。灯与蒸汽节点挂在对应背景 Sprite 下，继承相同的整数位置、视差速度和绘制层级，近处建筑正常遮挡后方效果。
- 蒸汽是新绘的 192×128、3列2行六帧图集，每帧64×64，固定 scale 1、nearest 与二值透明边。`steam_anchor` 默认 `[24,59]` 对齐实际管口；烟根始终固定在管口，六帧原画内部表现蒸汽向上、向右扩展后淡出，使用预创建 Sprite 循环复用。
- 稀疏星点只挂远层，每点为1个原生像素，亮度缓慢变化；星坐标仅选实际天空。固定16粒细沙沿镜头内地表轻微右移，不影响碰撞或人物操作。
- 动态以16Hz量化更新，保留时间余量保证60fps下每秒仍有16次更新，所有绘制位置取整；启动时只建立一个有限节点池，不逐帧创建节点、读取/扫描图片、发射碰撞对象。离屏灯/烟/星只做矩形可见性判断，不更新帧与外观。
- JSON 的 `lights` 包含 `id/layer/rect/period/phase/min_gain/max_gain`；`steam` 包含 `id/layer/position/period/phase/opacity`；`stars` 包含 `id/position/period/phase/opacity`（固定远层）；所有 `rect/position` 使用所属背景源图像素坐标，y=0..511。`dust` 包含 `count/speed/opacity/lengths`，原生长度循环为1、2、3px。`steam_frame_size` 与 `steam_frames` 定义原生帧格，运行时校验图集尺寸；`update_hz=16` 定义更新率，`steam_min_alpha=0.30` 保留每周期最淡时的管口烟雾。

现有原图 GPU 比对只额外排除当前实际效果的小包围框：灯的源区域、当前蒸汽帧的非透明包围框、1px星点与1–3px沙粒；报告记录 `ambient_excluded_samples` 与逐个效果坐标，不排除整片天空或工业区域。原地形、车辆、楼层路线、三层视差、电梯的实际输入回归继续运行。

GPU 烟雾测试额外保存 `ambient_animation_00.png` 至 `ambient_animation_11.png`：固定正常镜头 `[400,104]`，连续1.375秒、8Hz、320×180原生画面；可供真实渲染 GIF 预览。另存 `ambient_sky_animation_00.png` 至 `ambient_sky_animation_11.png`（报告 `sky_animation_frames`），固定高处镜头 `[1008,-106]`，以相同8Hz时序展示中景烟囱与稀疏远空星点。`ambient_probe_{lights,steam,stars,dust}_{a,b}.png` 分别记录相同镜头的两个实际时刻，每类必须在自身效果小矩形内产生可见的 GPU 像素差异。证据捕捉期间暂停人物和电梯物理，结束立即恢复；其余路线测试继续使用真实物理输入。状态与像素证据记入 `smoke_report.json` 的 `ambient`。

蒸汽保持原生像素绘制与固定烟根，通过重绘更宽、更高的64px帧扩大可见烟羽，未放大旧贴图。v09仍为12处灯、10处烟、12颗星和16粒沙的50对象固定池。
