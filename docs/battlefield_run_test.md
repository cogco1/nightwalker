# 超长战场跑步试玩

双击根目录 `Run-Battlefield.cmd`。这是独立侧视试玩，原有主入口、安全屋、医院、夜街和按键设置保持原样。

- A / D：左右移动；长按 Shift：沿用主角现有的奔跑；空格：跳跃。
- R：返回起点；Esc：关闭试玩。移动、奔跑、跳跃、重置会读取现有改键。
- 背景和主角均为原生 scale 1；320×180 视口使用 nearest 与整数窗口缩放。镜头只显示局部地图，沿人物前进。
- 地面直接读取 `game/assets/battlefield_layer_01/ground_profile.json` 的地表折线，并用一个连续多边形生成最小碰撞。

自动完整跑步检查（先正常执行一次素材导入）：

```powershell
& '<Godot可执行文件>' --headless --path game --editor --import --quit
& '<Godot可执行文件>' --headless --path game res://scenes/battlefield_run_test.tscn -- --battlefield-smoke
```

去掉第二条命令的 `--headless` 可生成原生 320×180 PNG 截图。自动检查使用真实按键事件、原主角速度和地面碰撞从头跑到末端，记录起点、坡道、高地、各分段和末端，正常停止后退出。报告位于 `game/evidence/battlefield_run_test/smoke_report.json`，截图在同目录。自动检查读取专用测试按键配置，不写入玩家改键文件。

独立快速回归：

```powershell
& '<Godot可执行文件>' --headless --path game --script res://tests/test_battlefield_run_test.gd
```
