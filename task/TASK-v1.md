# 任务书：用 shader-art-coding 技能复刻参考视频

## 目标

把 `assets/reference.mp4` 的画面复刻成**一个 Shadertoy GLSL 文件**。不是逐像素还原 3D 游戏，而是用程序化
着色器做出同一个场景、同一套配色和同一段运镜。

## 输入

| 文件 | 说明 |
|---|---|
| `assets/reference.mp4` | 1920×1080、24 fps、14.17 秒。两个镜头：0–3.2 s 码头，3.3 s 硬切到瀑布湾并推近 |
| `assets/ref-t2.0.png` | 镜头 A 的验收参考帧（t=2.0） |
| `assets/ref-t6.0.png` | 镜头 B 广角的验收参考帧（t=6.0） |
| `assets/ref-t12.0.png` | 镜头 B 近景的验收参考帧（t=12.0） |
| `assets/contact-sheet.png` | 每秒一帧的总览 |
| `.claude/skills/shader-art-coding/` | 技能本体：186 个已验证 GLSL 函数、bundler、checker、模板与参考文档 |

## 交付

| 文件 | 要求 |
|---|---|
| `final.glsl` | 粘贴即用的 Shadertoy 代码，只含 `mainImage`，无 `#version`、无贴图、无自定义 uniform |
| `verify/t2.png` `verify/t6.png` `verify/t12.png` | 用同一份 `final.glsl` 在三个时刻渲染的截图，16:9 |
| `NOTES.md` | 用了哪些库函数、哪些还原了、哪些没还原、怎么验证的 |

## 约束

- 单文件，最终用技能自带工具打包：`glsl_tools.py bundle`
- 必须调用技能库里的函数，不要另抄一份
- 时间轴与参考一致：约 3.25 s 硬切，之后镜头推近
- 16:9；所有坐标以画面高度为 2 个单位

## 验收标准

按画面比例取 9 个色块（x, y, w, h 均为 0–1，原点在左上），和参考帧逐块比较：

| 检查点 | 时间 | 色块 |
|---|---|---|
| A | t=2.0 | water (0.42, 0.40, 0.20, 0.20)；wood (0.05, 0.25, 0.15, 0.20)；sand (0.72, 0.20, 0.14, 0.15)；grass (0.86, 0.05, 0.11, 0.13) |
| B-wide | t=6.0 | water (0.45, 0.60, 0.20, 0.15)；rock (0.34, 0.08, 0.16, 0.12)；foliage (0.05, 0.18, 0.12, 0.16) |
| B-close | t=12.0 | water (0.55, 0.55, 0.20, 0.15)；rock (0.80, 0.25, 0.14, 0.15)；wood (0.10, 0.55, 0.12, 0.15) |

| 项 | 指标 | 通过线 |
|---|---|---|
| Q1 | 色块平均色的 ΔE76（CIE Lab） | ≤ 10 |
| Q2 | 水/岩/木/植被/沙五类面积占比，与本作之差 | ≤ 0.08 |
| Q3 | 画面平均亮度差 | ≤ 0.08 |
| Q4 | 画面亮度标准差差 | ≤ 0.06 |
| Q5 | 细节密度比（平均梯度，本作 ÷ 参考） | 0.6–1.8 |
| Q6 | 硬切前后两镜不同 | 平均差 > 0.10 |
| Q7 | 4→8 秒镜头推近 | 水面占比增加 ≥ 0.08 |

五类分类用最近邻，锚点（sRGB）：

```
water   (0.22, 0.72, 0.56)
rock    (0.55, 0.57, 0.55)
wood    (0.45, 0.29, 0.21)
foliage (0.30, 0.48, 0.24)
sand    (0.64, 0.66, 0.56)
dark    (0.15, 0.15, 0.15)
```

参考帧的色块实测值（sRGB，#RRGGBB），可以直接当调色目标：

| 检查点 | 色块实测 |
|---|---|
| A | water `#679D7F`；wood `#815D52`；sand `#ACBF77`；grass `#688950` |
| B-wide | water `#439E83`；rock `#66716F`；foliage `#607C44` |
| B-close | water `#33C69C`；rock `#717779`；wood `#605143` |

## 自检

```bash
# 编译检查（本机已装 glslangValidator 16.6.0）
python3 .claude/skills/shader-art-coding/scripts/glsl_tools.py check final.glsl

# 打包
python3 .claude/skills/shader-art-coding/scripts/glsl_tools.py bundle work.glsl -o final.glsl
```

渲染截图没有强制工具：Shadertoy 网页、无头 Chrome、本机任意 WebGL 环境都行。只要三张图和 `final.glsl`
对得上，并且是同一份代码。

验收脚本（把三张图放到 `verify/t2.png`、`verify/t6.png`、`verify/t12.png`）：

```bash
python3 tools/score.py --own-dir verify
```

它按上面的 Q1–Q5 逐项打印数值和 ok/FAIL，最后给出 PASS/FAIL。测量在 320×180 下做，和参考帧同一尺度。

## 参考事实（客观信息，不是解法）

- 参考是斜俯视的 3D 游戏画面，带手绘材质；阴影大而软，水按深度变色
- 镜头 A：木屋、码头、河道、右侧沙岸、栈桥、树
- 镜头 B：岩壁围出的水湾、顶部瀑布、船与钓客、浮标、鱼群
- 广角（t=6）比近景（t=12）的水色更暗更灰：`#439E83` vs `#33C69C`
- 两镜的明亮度接近（平均亮度约 0.47 和 0.50）

## 提交

把 `final.glsl`、`verify/` 三张图、`NOTES.md` 留在项目根目录即可。
