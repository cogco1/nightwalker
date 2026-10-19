夜行者 · 三层工业战场背景 v04 · 2026-10-20

本版调整
远景重新配色及明暗：移除原先大面积海军蓝，改为低饱和钢灰、尘灰，压低局部反差，保留少量暗青与灰紫灯光。
新增中景：旧楼、厂房、锅炉房、烟囱、储罐和管廊，以灰褐旧混凝土和钢铁衔接原来的近景。
近景保持原钢墙、工厂、黄沙及地表形状。三层使用相同原生像素尺寸。

图片
battlefield_near_native.png：6144×256，透明近景，运行速度1.0。
battlefield_mid_native.png：6144×256，透明中景，运行速度0.58，alpha仅0/255。
battlefield_far_native.png：6144×256，不透明远景及天空，运行速度0.28。
对应 *_12288x512.png 是准确2倍最近邻放大的导出图，可直接作为超长图片使用。
每张实际是完整单行长图。接触表仅用于检查分段，不替代长图。

试玩
完整工程：https://github.com/cogco1/nightwalker
在完整工程根目录双击 Run-Battlefield.cmd。
A/D移动，长按Shift奔跑，空格跳跃，R回到起点，Esc退出。
使用原有主角，320×180原生视口，scale=1，nearest整数放大。
本包source_code仅保存本次场景/测试/构建源码，依赖完整工程中的人物与控制脚本。
安全屋、医院、夜街与原主入口没有改动。

实际验证
Godot 4.7.2.stable.official.ed1daf0bf。
headless素材导入退出0。
快速回归：34项，通过。
GPU完整地图跑步：103项，失败0项。
实际跑动6076.91原生像素，保存11张实际游戏截图。
实测中景比例0.580014，远景比例0.280048。
详细报告与GPU截图见run_test_evidence，4倍预览仍为最近邻放大。

素材来源与复现
本版使用内置imagegen生成/修改；far_sources保存8张重配色远景，mid_sources保存8张透明中景。
完整提示词和来源路径保存在generation_prompts.json。
按已授权的方式，以本地Pillow/NumPy进行像素网格归一、上移对齐、接缝处理、统一调色板和长图拼接。
构建脚本在source_code/tools/build_battlefield_depth_layers.py，放回完整工程后可运行。
layer_info.json记录像素尺寸、绘制顺序、颜色数和SHA256，file_manifest.json记录本包文件校验值。
修改前备份另存于Nightwalker_Backups/夜行者_三层景深与配色修改前_2026-10-20_41111b6.zip。
