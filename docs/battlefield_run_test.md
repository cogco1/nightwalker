# 超长战场跑步试玩

双击根目录 `Run-Battlefield.cmd`。这是独立侧视试玩，原有主入口、安全屋、医院、夜街和按键设置保持原样。

- A / D：左右移动；长按 Shift：沿用主角现有的奔跑；空格：跳跃，在空中再次按下可二段跳。
- R：返回起点；Esc：关闭试玩。移动、奔跑、跳跃、重置会读取现有改键。
- 背景和主角均为原生 scale 1；320×180 视口使用 nearest 与整数窗口缩放。镜头只显示局部地图，沿人物前进。
- 近、中、远三层建筑均使用 6144×512 原生长图，向画布上方增加 256px 绘制约两倍高的楼体，保持像素格和原有工业配色。三张 Sprite 的原点均为世界 y=-256，scale 1。
- 远景使用 `game/assets/battlefield_far_background/battlefield_far_native.png`，含不透明天空；中景使用 `game/assets/battlefield_mid_background/battlefield_mid_native.png`，RGBA 0/255 透明背景。灰褐钢铁、旧混凝土与低饱和灰蓝仍按景深区分轮廓大小和清晰度。
- 绘制顺序为远景（z=-20）、中景（z=-15）、近景（z=-10）；水平采样速度分别为镜头移动距离的 0.28、0.58、1.0。现有镜头更新时，每个视差层只做一次整数位置更新，不循环堆叠贴图。
- 世界地面仍为 6144×256，直接读取原 `game/assets/battlefield_layer_01/ground_profile.json` 地表折线；人物尺寸、跳跃物理和原地面碰撞不变。新增可踩楼层、屋顶和损坏车辆，使用 `game/assets/battlefield_traversal/foreground_native.png`（6144×512，origin=(0,-256)，z=0）及同目录 `layout.json`。场景启动时按 layout 的 rect/polygon 一次性创建静态碰撞，楼层与屋顶使用单向顶面，可从下方跃上；车辆使用贴合车身的实体轮廓。
- 镜头可向上跟随到世界 y=-256，中心最低为 -166；x 边界和底边 y=256 保持原值。所有图片采样均减去相应 Sprite 原点，覆盖检查使用纹理自身的 6144×512 尺寸。原世界地面 y=168/224 仍对应 source y=424/480。
- 原有 S 键仍为蹲伏/空中下劈，没有新增平台下穿动作；离开平台边缘即可落下。较高楼层需要先从支撑面起跳，再在第一跳高点附近按第二次空格。
- 此试玩将角色 `floor_max_angle` 局部设为 65°，让画面中约 53～61°的外楼梯坡面可以步行；`player.gd`、奔跑速度、重力与一/二段跳数值均不变。原地面坡道仍使用原碰撞。

自动完整跑步检查（先正常执行一次素材导入）：

```powershell
& '<Godot可执行文件>' --headless --path game --editor --import --quit
& '<Godot可执行文件>' --headless --path game res://scenes/battlefield_run_test.tscn -- --battlefield-smoke
```

去掉第二条命令的 `--headless` 可生成原生 320×180 PNG 截图。自动检查使用真实按键先跑完整段地面，并在每辆破车前真正起跳；分别记录原地面误差、车辆接触误差与预期跳跃，避免把车顶当作原地面错位。随后仅在 `route_start` 初始化一次，按 layout 的 14 个 waypoint 连续走过车顶、二楼、屋顶、外楼梯并回到地面，中途不移动角色坐标；楼梯的 `walk` 段禁止测试脚本按跳跃键，同时记录真实楼梯碰撞接触与离地帧。汽车、厢式车、卡车均有实际跳跃落脚接触验证。

报告位于 `game/evidence/battlefield_run_test/smoke_report.json`，`ground_traversal` 记录全地图与车辆，`course` 记录连续路线每站的承托 collider、脚底误差和跳跃次数；截图在同目录。自动检查的输入控制器仅在烟雾模式动态加载 `game/tests/support/battlefield_traversal_driver.gd`，正常试玩不运行路线扫描；测试使用专用按键配置，不写入玩家改键文件。

报告记录独立的 `world_size`、`art_size`、`art_origin`，以及各截图前景/近景/中景/远景采样窗口、整数位置、实际滚动比例和完整覆盖断言。GPU 每 4px 采样，按可踩前景→近→中→远选择真正暴露的最上层源像素，并排除当前人物帧不透明像素包围盒及 4px 光晕范围；每张图每个暴露层需有至少 99.5% 样本与原图匹配（RGB 容差 1.5/255）。建筑可完全遮住后层，该帧记录 0 暴露而不误报；整条路线累计每层仍需至少 256 个匹配样本、64 个相邻不透明像素色差超过 6/255 的细节样本，且至少一帧有 8 种匹配颜色，防止纯色或未显示的图层通过。人工查看截图确认可踩边沿、建筑尺度、景深和配色。

头尾镜头移动约 5824px，中景移动约 3378px，远景只移动约 1631px。新增画布高度不会增加世界范围或改变镜头速度。

独立快速回归：

```powershell
& '<Godot可执行文件>' --headless --path game --script res://tests/test_battlefield_run_test.gd
```

可踩建筑与车辆版本的验证结果以 `test_report.json`、`smoke_report.json` 和同目录截图为准。
