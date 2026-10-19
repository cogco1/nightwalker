夜行者 · 废车随机烟火 v10 · 2026-10-20

本次增加
地图原有7辆毁坏车辆均冒烟，破损处带少量橙黄小火苗；不改车辆原画、可踩表面或碰撞。
3套独立烟火原画（hood、cabin、engine），每套6帧烟和6帧火，共36帧、6张192×128透明PNG，均为64×64原生单帧。
每次启动以一次shuffle分配外观，随机烟火相位、周期和小幅整数位置偏移；运行中保持固定喷口，不每帧重新抽签。
烟周期1.7–2.7秒，火周期0.5–0.85秒；烟和火各自播放，避免所有车辆同步燃烧。
本次实际GPU取证随机种子为1035528850，分配记录见smoke_report.json的ambient.vehicle_assignments。
把vehicle_effects.random_seed设为该正整数可复现取证分配；默认0使用每次启动的新随机种子。

保留上一版动态
v09的大而浓的原生蒸汽、12处厂灯、10处烟囱/排气口、稀疏12个星点和16粒风沙完整保留。
全部效果合计64个固定对象，环境每秒16.0次更新，中途新增节点0。
保持320×180、人物scale1、整数像素与最近邻显示；烟火增加可见动画，不新增碰撞或伤害。
灯、烟、星沿用各背景层视差；车辆烟火跟随固定世界坐标，在玩家与场景中正常遮挡。
v07的15栋/5类建筑、7辆废车、8段地面、14站高处路线和末段工业电梯均保留。
8项背景/前景/地形/人物核心/电梯物理/工程入口文件与v09逐字核对未变，见baseline_assets.json。

试玩
完整工程：https://github.com/cogco1/nightwalker
拉取最新main，双击Run-Battlefield.cmd。
A/D移动、长按Shift跑步、空格跳跃/二段跳、E操作末段工业电梯、R回起点、Esc退出。
沿地面向右跑到第一辆废车即可看烟火；可以继续踩上车顶、登楼或乘工业电梯。

实际动态预览
wreck_smoke_fire_preview.gif：第一辆车附近的12张实际GPU原生截图，展示烟和小火独立变化。
factory_steam_wind_preview.gif：保留的大雾、厂灯和风沙。
distant_steam_stars_preview.gif：高处相机的中远景蒸汽与稀疏星点。
3个GIF均按8Hz采样，最近邻4倍预览；未拼贴烟火到游戏画面，未添加模拟效果。
取证时仅暂停人物/电梯物理并固定相机，按有序环境时间采样；原始RGB截图完整保存在run_test_evidence。
GIF采用统一256色调色板；PNG保留原始颜色。

原画、源码与再构建
内置imagegen生成3套烟火原画；source_art保留原图，generation_prompts.json保存完整提示词、工具模式和来源。
asset_images保存6张分离后的原生烟/火图层及最近邻放大预览，asset_info.json记录帧尺寸、对齐和调色板处理。
asset_images/vehicle_effects_contact.png为3套烟火×3类车的离线贴车组合对照，仅用于素材审阅，不是游戏GPU截图。
原图最近邻归一为48px艺术，置入64×64画布，以(32,58)整数喷口对齐；烟使用v05的64色色板，火使用7色暖橙/琥珀色板。
离线只做透明分层、最近邻归一、整数对齐和色板匹配；运行时scale1。
ambient.json含7个车辆锚点、3套贴图、随机范围以及保留的环境配置。
source_code按仓库相对路径存放本次更新源码和环境素材；完整旧场景/人物/地形依赖从GitHub仓库获取。
离线构建需Pillow/NumPy，运行tools/build_battlefield_vehicle_effects.py；使用仓库中保留的v09与v05构建依赖。

实际验证
Godot 4.7.2.stable.official.ed1daf0bf；version/import/quick/headless/GPU全部退出0，stderr空。
快速回归67项、无窗口391项、GPU 635项全部通过。
原全长地面、7辆车真实起跳、14个连续高处落点、外楼梯和工业电梯往返均通过。
车辆烟火全部有固定像素喷口、原生scale1，随机分配和独立节奏均有实际状态检查。
六类动态按局部小矩形做两时刻GPU差分：lights: 736像素变化；steam: 2549像素变化；stars: 2像素变化；dust: 62像素变化；vehicle_smoke: 325像素变化；vehicle_fire: 83像素变化。
详细检查、原生截图、实际进程退出码和日志见run_test_evidence。

修改前完整备份
E:\CodexWorkspace\Nightwalker_Backups\夜行者_废车烟火修改前_2026-10-20_v09.zip
CRC已验证，SHA256见backup_info.json。
file_manifest.json列出本交付包文件的SHA256；最终ZIP已逐文件校验与CRC校验。
