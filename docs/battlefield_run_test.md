# 超长战场跑步试玩

双击根目录 `Run-Battlefield.cmd`。这是独立侧视试玩，原有主入口、安全屋、医院、夜街和按键设置保持原样。

- A / D：左右移动；长按 Shift：沿用主角现有的奔跑；空格：跳跃。
- R：返回起点；Esc：关闭试玩。移动、奔跑、跳跃、重置会读取现有改键。
- 背景和主角均为原生 scale 1；320×180 视口使用 nearest 与整数窗口缩放。镜头只显示局部地图，沿人物前进。
- 远处高楼、工厂使用 `game/assets/battlefield_far_background/battlefield_far_native.png`，6144×256、不透明天空，配色压低饱和度，使用灰蓝与灰褐色融入原有工业场景。
- 中景楼群与厂房使用 `game/assets/battlefield_mid_background/battlefield_mid_native.png`，6144×256、RGBA 0/255 透明背景；灰褐钢铁与旧混凝土的轮廓大小、清晰度位于近景和远景之间。近景仍使用原来的同尺寸地形长图。
- 绘制顺序为远景（z=-20）、中景（z=-15）、近景（z=-10）；水平采样速度分别为镜头移动距离的 0.28、0.58、1.0。现有镜头更新时，每层只做一次整数位置更新，不循环堆叠贴图；长图足够覆盖整段地图，避免短距离重复。三层均保持 scale 1，中远景 y=0，远景 256px 高的天空覆盖坡道和跳跃时的完整视口。
- 地面直接读取 `game/assets/battlefield_layer_01/ground_profile.json` 的地表折线，并用一个连续多边形生成最小碰撞。

自动完整跑步检查（先正常执行一次素材导入）：

```powershell
& '<Godot可执行文件>' --headless --path game --editor --import --quit
& '<Godot可执行文件>' --headless --path game res://scenes/battlefield_run_test.tscn -- --battlefield-smoke
```

去掉第二条命令的 `--headless` 可生成原生 320×180 PNG 截图。自动检查使用真实按键事件、原主角速度和地面碰撞从头跑到末端，记录起点、坡道、高地、各分段和末端，正常停止后退出。报告位于 `game/evidence/battlefield_run_test/smoke_report.json`，截图在同目录。自动检查读取专用测试按键配置，不写入玩家改键文件。

报告还记录各截图的中远景采样窗口、整数位置、实际滚动比例和全视口覆盖断言。GPU 检查先扣除近景遮挡，再按中景透明度分别对照中景和远景原图，确认两层都实际可见；同时人工查看截图确认高楼、工厂与三层配色。头尾镜头移动约 5824px，中景移动约 3378px，远景只移动约 1631px，体现三个层次的速度差。

独立快速回归：

```powershell
& '<Godot可执行文件>' --headless --path game --script res://tests/test_battlefield_run_test.gd
```

2026-10-20 三层版本验证：Godot 4.7.2 素材导入成功，快速回归 34/34、GPU 全程跑步 103/103 通过，11 张截图均验证中远景可见。镜头/中景/远景实际移动 5824/3378/1631px，中远景比率为 0.580014/0.280048；扣除前层遮挡后，每张图匹配中景 244～1086 个、远景 884～1992 个采样点。导入、回归和 GPU 测试均正常退出 0，`depth_*_stderr.log` 全部为空；坡道、跳跃及地图末端的覆盖检查通过。
