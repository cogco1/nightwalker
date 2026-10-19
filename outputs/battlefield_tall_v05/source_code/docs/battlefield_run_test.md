# 超长战场跑步试玩

双击根目录 `Run-Battlefield.cmd`。这是独立侧视试玩，原有主入口、安全屋、医院、夜街和按键设置保持原样。

- A / D：左右移动；长按 Shift：沿用主角现有的奔跑；空格：跳跃。
- R：返回起点；Esc：关闭试玩。移动、奔跑、跳跃、重置会读取现有改键。
- 背景和主角均为原生 scale 1；320×180 视口使用 nearest 与整数窗口缩放。镜头只显示局部地图，沿人物前进。
- 近、中、远三层建筑均使用 6144×512 原生长图，向画布上方增加 256px 绘制约两倍高的楼体，保持像素格和原有工业配色。三张 Sprite 的原点均为世界 y=-256，scale 1。
- 远景使用 `game/assets/battlefield_far_background/battlefield_far_native.png`，含不透明天空；中景使用 `game/assets/battlefield_mid_background/battlefield_mid_native.png`，RGBA 0/255 透明背景。灰褐钢铁、旧混凝土与低饱和灰蓝仍按景深区分轮廓大小和清晰度。
- 绘制顺序为远景（z=-20）、中景（z=-15）、近景（z=-10）；水平采样速度分别为镜头移动距离的 0.28、0.58、1.0。现有镜头更新时，每个视差层只做一次整数位置更新，不循环堆叠贴图。
- 世界地形仍为 6144×256。地面直接读取原 `game/assets/battlefield_layer_01/ground_profile.json` 地表折线，碰撞、人物尺寸、相机边界与跳跃视口保持原值。原世界地面 y=168/224 对应新图 source y=424/480；所有图片采样均减去相应 Sprite 原点，覆盖检查使用纹理自身的 6144×512 尺寸。

自动完整跑步检查（先正常执行一次素材导入）：

```powershell
& '<Godot可执行文件>' --headless --path game --editor --import --quit
& '<Godot可执行文件>' --headless --path game res://scenes/battlefield_run_test.tscn -- --battlefield-smoke
```

去掉第二条命令的 `--headless` 可生成原生 320×180 PNG 截图。自动检查使用真实按键事件、原主角速度和地面碰撞从头跑到末端，记录起点、坡道、高地、各分段和末端，正常停止后退出。报告位于 `game/evidence/battlefield_run_test/smoke_report.json`，截图在同目录。自动检查读取专用测试按键配置，不写入玩家改键文件。

报告记录独立的 `world_size`、`art_size`、`art_origin`，以及各截图三层采样窗口、整数位置、实际滚动比例和完整覆盖断言。GPU 每 4px 采样，按近→中→远选择真正暴露的最上层源像素，并排除当前人物帧不透明像素包围盒及 4px 光晕范围；每张图每个暴露层需有至少 99.5% 样本与原图匹配（RGB 容差 1.5/255）。高建筑可完全遮住后层，该帧记录 0 暴露而不误报；整条路线累计每层仍需至少 256 个匹配样本、64 个相邻不透明像素色差超过 6/255 的细节样本，且至少一帧有 8 种匹配颜色，防止纯色或未显示的图层通过。人工查看截图确认建筑尺度、景深和配色。

头尾镜头移动约 5824px，中景移动约 3378px，远景只移动约 1631px。新增画布高度不会增加世界范围或改变镜头速度。

独立快速回归：

```powershell
& '<Godot可执行文件>' --headless --path game --script res://tests/test_battlefield_run_test.gd
```

2026-10-20 建筑加高版本验证：Godot `4.7.2.stable.official.ed1daf0bf`，快速回归 41/41、GPU 全程跑步 130/130 通过，生成 11 张 320×180 截图。报告确认 art=6144×512、world=6144×256、origin=(0,-256)；近/中/远层累计匹配 27546/8264/2848 个样本，其中细节样本 21349/5780/762 个，所有暴露层逐图匹配率均超过 99.5%。人物跑过 6076.9px，离地 0 帧，最大脚底误差 4.08px；中远景速度仍为 0.580014/0.280048。版本核对、导入、快速回归、GPU 测试均正常退出 0，`tall_*_stderr.log` 全部为空。
