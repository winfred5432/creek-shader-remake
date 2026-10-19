# creek-shader-remake

[English](README.md)

两个编程智能体拿到同一个任务：把一段 14 秒的 3D 钓鱼游戏画面，复刻成**一个 Shadertoy GLSL 片段着色器**。
本仓库收录任务书、评分脚本、每次运行产出的着色器、渲染结果和笔记，以及重建参考素材、重新评分的脚本。

- **参考视频：** [@sorenxet 的帖子](https://x.com/sorenxet/status/2111892085444092101)里的片段，是用 Opus 5.5 +
  Blender + Unity 6 做的休闲钓鱼游戏。仓库**不包含**这段视频，由 `tools/fetch_reference.sh` 下载。
- **技能：** gokayfem 的 [`shader-art-coding`](https://github.com/gokayfem/shader-skills)（MIT），提交 `b19dcf9`。
  仓库不附带技能本体，由 `tools/install_skill.sh` 安装。
- **智能体：** [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh），模型 `deepseek-flash`，
  推理强度 `max`；Claude Code，模型 Claude Opus 5.5。

## 三个阶段

| 阶段 | 执行者 | 验收方式 | 结果 |
|---|---|---|---|
| 1 | dsh 单独完成 | 自己写的评分标准和脚本，目标 10 轮 | 10 轮后**未达标**；只有静帧 |
| 2 | Claude Opus 5.5 与实验者 | 只改写 `TASK.md` 的验收部分，扩展 `score.py`（143 → 395 行） | 三层验收：硬性检查、参考指标、以视觉评审为最终判定 |
| 3 | dsh 与 Claude Code 并行，各 3 轮 | 同一份最终 `TASK.md` | 两边都通过硬性检查和最后一次视觉评审，详见下表 |

整个过程中实验者一直在和智能体对话（选方案、要求做差距分析、指出问题）。完整时间线见
[`docs/process.md`](docs/process.md)（英文）。

## 结果

| | 阶段 1：dsh 单独 | 阶段 3a：dsh | 阶段 3b：Claude Code |
|---|---|---|---|
| 硬性检查 H1–H3 | — | 通过 | 通过 |
| 没达标的参考指标 | — | 2 项 | 0 项 |
| 布局一致率（全片均值 / 最小值） | — | 0.54 / 0.42 | 0.64 / 0.55 |
| 调用的库函数 | — | 30 个 | 50 个 |
| 最后一次独立视觉评审 | — | 通过，水面"部分达到" | 通过但有保留；最后几处修改没有再评审 |
| 交付物 | 3 张静帧（960×540） | 3 张静帧 + 视频（1280×720） | 3 张静帧 + 视频（1280×720） |

布局一致率在参考视频自身上的参照值：完全不同的场景约 0.25；同一镜头相差 1 秒约 0.65。

| t | 阶段 1：dsh 单独 | 阶段 3a：dsh | 阶段 3b：Claude Code |
|---|---|---|---|
| 2 s | ![](runs/01-dsh-solo/out/own-A.png) | ![](runs/03a-dsh/verify/t2.png) | ![](runs/03b-claude-code/verify/t2.png) |
| 6 s | ![](runs/01-dsh-solo/out/own-B-wide.png) | ![](runs/03a-dsh/verify/t6.png) | ![](runs/03b-claude-code/verify/t6.png) |
| 12 s | ![](runs/01-dsh-solo/out/own-B-close.png) | ![](runs/03a-dsh/verify/t12.png) | ![](runs/03b-claude-code/verify/t12.png) |

视频：[`runs/03a-dsh/verify/render.mp4`](runs/03a-dsh/verify/render.mp4)、
[`runs/03b-claude-code/verify/render.mp4`](runs/03b-claude-code/verify/render.mp4)。
每个 `final.glsl` 都可以直接粘贴到 [Shadertoy](https://www.shadertoy.com/new) 运行。

## 目录

```
task/
  TASK.md          最终任务书，中文原文（阶段 3 两边拿到的就是这份）
  TASK.en.md       英文译本
  TASK-v1.md       阶段 2 改写验收之前的任务书
  score-v1.py      与 TASK-v1.md 配套的评分脚本
tools/
  score.py             最终评分脚本（H1–H3、Q1–Q5、T1/T2、L；生成 verify/review/）
  fetch_reference.sh   从公开帖子重建 assets/
  install_skill.sh     把 shader-art-coding @ b19dcf9 装到 .claude/skills 和 .dsh/skills
  make_workspace.sh    创建阶段 3 的项目目录，可选放入某次运行的产物
runs/
  01-dsh-solo/       creek.glsl、creek.bundle.glsl、render.py、score.py、RUBRIC.md、README.md、out/ 静帧
  03a-dsh/           work.glsl、final.glsl、NOTES.md、tools/render.py、verify/ 静帧和 render.mp4
  03b-claude-code/   work.glsl、final.glsl、NOTES.md、tools/（render.py、cmp.sh、full.sh、fit_cam.py）、
                     verify/ 静帧、render.mp4 和 score.txt
docs/process.md      三个阶段的时间线
```

阶段 1 的静帧：`own-A.png` 对应 t = 2 s，`own-B-wide.png` 对应 6 s，`own-B-close.png` 对应 12 s。
`runs/` 下的文件保持智能体写出时的样子，只做了这些改动：缩短绝对路径、删除逐轮记录，并在每份改过的文档开头注明改了什么。

## 复现

依赖：Python 3 和 numpy、ffmpeg/ffprobe（≥ 5）、yt-dlp、git。可选：glslangValidator（`glsl_tools.py check`
用它编译）、Playwright 和 Chromium（阶段 3 的渲染器）、Google Chrome（阶段 1 的渲染器）。

```bash
tools/fetch_reference.sh     # assets/：reference.mp4、ref-t2.0/6.0/12.0.png、contact-sheet.png
tools/install_skill.sh       # .claude/skills/shader-art-coding（以及 .dsh/skills 链接）
```

`fetch_reference.sh` 会把结果和运行时用的片段对比（首帧视频 pts 0.083 s、338 帧、逐帧哈希的汇总哈希），不一致就以非零码退出。

**重新评分阶段 3 的某次运行：**

```bash
tools/make_workspace.sh /tmp/ws-claude 03b-claude-code
cd /tmp/ws-claude && python3 tools/score.py --own-dir verify
```

输出与该运行 `NOTES.md` 里记录的报告相同，并生成视觉评审用的 `verify/review/sheet.png` 和 `side_by_side.mp4`（左参考、右复刻）。

**重新渲染阶段 3 的某次运行**（在工作目录里，需要 Playwright + Chromium）：

- dsh：照 `runs/03a-dsh/NOTES.md` 第 "4. Reproduce" 节的命令。
- Claude Code：`mkdir -p /tmp/cr && W=1280 tools/full.sh`（脚本把评分摘要写到 `/tmp/cr/`）。

**阶段 1** 在仓库根目录运行：`python3 runs/01-dsh-solo/score.py` 用仓库里的静帧评分，参考帧从
`assets/reference.mp4` 现取；`--render` 和 `--motion` 需要先启动它的 Chrome 守护进程（`python3 runs/01-dsh-solo/render.py daemon`）。

**重新做一次实验：** 用 `tools/make_workspace.sh <目录>`（不带运行名）建一个干净的工作目录，在 Claude Code 或 DeepSeek Harness
里打开，发送 `@TASK.md 按这个目标执行`。

### 已验证

环境为 ffmpeg 9.0.2、yt-dlp 2026.08.19、Python 3.14、numpy 2.5：重建的 `reference.mp4` 与原文件的音视频包时间戳和解码帧完全一致；
三张参考帧和总览图逐像素一致。两次阶段 3 运行在原素材和重建素材上跑 `tools/score.py`，输出完全相同，也与各自 `NOTES.md`
里记录的报告一致。阶段 1 的 `score.py` 复现出第 10 轮的数值。

## 致谢与许可

- 参考游戏和视频：[@sorenxet](https://x.com/sorenxet)。仓库不包含该视频，权利归原作者。
- gokayfem 的 [shader-skills](https://github.com/gokayfem/shader-skills)，MIT。它自己的致谢列出了库中实现的公开技术来源。
- DeepSeek AI 的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)；Anthropic 的 [Claude Code](https://claude.com/claude-code)。

本仓库全部内容以 MIT 许可发布，© 2026 Duoduo · openduo.ai，见 [LICENSE](LICENSE)。
