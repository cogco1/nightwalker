夜行者 · 工业风沙与环境动态 v08 · 2026-10-20

本次增加
12处现有灯窗不同时闪烁，复用原窗格像素，保留暖色亮度与细节。
10个真实排气口/烟囱冒出蒸汽；首段低位排气口在地面即可见，高烟囱登楼后能看到。
烟根始终固定在真实管口，6帧原画在内部向上翻卷、向右舒展；较远的烟更淡、节奏更慢。
天空稀疏12个星点，单个仅1原生像素，随远景移动并被较近楼体遮挡。
10粒低透明度风沙沿地面缓慢漂移；使用世界坐标，跑步时人物会正常掠过尘粒。
所有效果保留320×180、scale1、最近邻和整数像素绘制，环境每秒12次更新，固定44个对象池。
灯、烟、星分别继承所在背景层的视差与遮挡，沙粒在前景地面附近，效果不增加碰撞。

试玩
完整工程 https://github.com/cogco1/nightwalker ，拉取最新main后双击Run-Battlefield.cmd。
A/D移动、长按Shift跑步、空格跳跃/二段跳、E操作末段工业电梯、R回起点、Esc退出。
前段坡顶附近可以看到厂灯与低位蒸汽；登楼后可以看到中远景烟囱和少有的星星。
v07的15栋/5类建筑、7辆废车、8段地面、原14站高处路线及末段工业电梯均保留。
原背景、可踩前景、地形布局、人物核心、电梯物理和主工程入口的8项文件与v07逐字核对未变，见baseline_assets.json。

动态预览与原画
factory_steam_wind_preview.gif：实际GPU渲染的12张原生PNG按8Hz时间采样，最近邻4倍预览。
distant_steam_stars_preview.gif：高处相机的同类12帧，展示中远蒸汽与稀疏星点。
取证时仅暂停人物/电梯物理并固定相机，按有序环境时间采样；预览没有新增画面元素或合成环境效果。
GIF使用统一256色调色板；完整原始RGB截图在run_test_evidence。
蒸汽原画由内置imagegen生成，原图保存在source_art，完整提示词、工具模式及来源见generation_prompts.json。
asset_images/steam.png：96×64，3列2行，每帧32×32，固定emitter(16,29)，透明度只有0/255。
运行时通过透明度淡入淡出；离线仅做最近邻归一、整像素对齐、v05调色板匹配，没有代码绘制替代蒸汽原画。
星点/沙粒为简单原生1px或2px几何，灯窗直接复用现有贴图区域。
ambient.json：全部源图坐标、独立节奏和轻微亮度/透明度参数；anchor_suggestions.json保留原图定位说明。
source_code为本次更新源码与素材，按仓库相对路径保存，完整旧场景/人物依赖从仓库获取。
离线构建需要Pillow/NumPy，依次运行build_battlefield_ambient_assets.py和build_battlefield_ambient_layout.py。

实际验证
Godot 4.7.2.stable.official.ed1daf0bf，所有version/import/quick/headless/GPU退出0且stderr空。
快速回归58项、无窗口355项、GPU 585项全部通过。
原全长地面、7车真实起跳、14个连续车顶/楼层/屋顶落点、外楼梯和工业电梯完整往返均通过。
环境池44对象，回放新增节点0；全部烟口跨phase固定，原生scale1与景深继承均验证。
四类效果按实际小包围区域做两时刻GPU像素差：lights: 736像素变化；steam: 238像素变化；stars: 2像素变化；dust: 25像素变化。
原图比对仅避开当前动态效果的局部小范围，未豁免整层背景；遮挡后仍能看到的变化才计入动态证据。
详细结果、所有原生截图与实际进程退出码见run_test_evidence。

修改前完整备份
E:\CodexWorkspace\Nightwalker_Backups\夜行者_环境动态修改前_2026-10-20_v07.zip
CRC已验证，SHA256见backup_info.json；file_manifest.json为本交付ZIP内文件SHA256清单。
