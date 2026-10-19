# 超长战场跑步试玩

双击根目录 `Run-Battlefield.cmd`。这是独立侧视试玩，原有主入口、安全屋、医院、夜街和按键设置保持原样。

- A / D：左右移动；长按 Shift：沿用主角现有的奔跑；空格：跳跃。
- R：返回起点；Esc：关闭试玩。移动、奔跑、跳跃、重置会读取现有改键。
- 背景和主角均为原生 scale 1；320×180 视口使用 nearest 与整数窗口缩放。镜头只显示局部地图，沿人物前进。
- 远处高楼、工厂与轻微青紫霓虹单独使用 `game/assets/battlefield_far_background/battlefield_far_native.png`，6144×256；近景仍使用原来的同尺寸地形长图。
- 远景位于近景后，以镜头水平移动距离的 0.28 倍缓慢滚动。现有镜头更新时只做一次整数位置更新，不循环堆叠贴图；长图足够覆盖整段地图，避免短距离重复。两层均保持 scale 1，远景 256px 高的天空覆盖坡道和跳跃时的完整视口。
- 地面直接读取 `game/assets/battlefield_layer_01/ground_profile.json` 的地表折线，并用一个连续多边形生成最小碰撞。

自动完整跑步检查（先正常执行一次素材导入）：

```powershell
& '<Godot可执行文件>' --headless --path game --editor --import --quit
& '<Godot可执行文件>' --headless --path game res://scenes/battlefield_run_test.tscn -- --battlefield-smoke
```

去掉第二条命令的 `--headless` 可生成原生 320×180 PNG 截图。自动检查使用真实按键事件、原主角速度和地面碰撞从头跑到末端，记录起点、坡道、高地、各分段和末端，正常停止后退出。报告位于 `game/evidence/battlefield_run_test/smoke_report.json`，截图在同目录。自动检查读取专用测试按键配置，不写入玩家改键文件。

报告还记录各截图的远景采样窗口、整数位置、实际滚动比例和全视口覆盖断言。GPU 检查将近景透明处的屏幕像素与远景原图对照，确认截图真正画出了远景中的多种颜色；同时人工查看截图确认高楼、工厂与霓虹可见。头尾镜头移动约 5824px，远景只移动约 1631px，足以体现远近速度差。

独立快速回归：

```powershell
& '<Godot可执行文件>' --headless --path game --script res://tests/test_battlefield_run_test.gd
```

2026-10-20 验证：Godot 4.7.2 素材导入成功，快速回归 28/28、GPU 全程跑步 68/68 通过，11 张截图均验证远景可见；实际远景/近景滚动距离为 1631/5824px（0.280048）。导入、回归与 GPU 测试均正常退出 0，stderr 为空。跳跃、坡道、地图末端的远景覆盖检查通过。
