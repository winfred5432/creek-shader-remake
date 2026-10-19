# Process: what happened, in order

All times are China Standard Time (UTC+8) on 2026-10-19, taken from the session records. The experimenter's prompts are
quoted verbatim in Chinese with an English gloss. The experimenter talked to the agents throughout, so this
records a guided experiment.

## The reference

At 02:48 @sorenxet posted [a 14 s clip](https://x.com/sorenxet/status/2111892085444092101) of a cozy
top-down fishing game built with Opus 5.5, Blender and Unity 6: a fisher in a straw hat rows up a turquoise
creek past a cabin on a dock, the camera cuts to a rocky waterfall cove ringed by pines, pushes in, and the
fisher casts and lands a fish. The game is real 3D. The experiment asks for the same 14 s as one procedural
Shadertoy fragment shader.

The clip used in the runs is clip 1 of that post (1920×1080, 24 fps, 338 frames). The local copy was a remux
whose video track starts at pts 0.083 s; all times in the task are on that timeline.
`tools/fetch_reference.sh` rebuilds it.

## Stage 1: DeepSeek Harness alone, own rubric (10:16–11:19)

Agent: DeepSeek Harness (dsh), model `deepseek-flash`, reasoning effort `max`.

| Time | Event |
|---|---|
| 10:16 | Experimenter: `https://github.com/gokayfem/shader-skills 这个可以在mac用么？` ("Does this work on a Mac?") |
| 10:17 | Experimenter: `不，装到项目local，python 也不能污染全局，你怎么做？` ("No, install it project-local, don't pollute global Python. How would you do it?") The agent installs the skill at upstream commit b19dcf9 into the project and installs glslang; the upstream harness compiles 186/186 units and passes 90/90 property tests. |
| 10:37 | Experimenter attaches the clip: `用技能复刻这个视频，你会怎么做？` ("Recreate this video with the skill. How would you do it?") |
| 10:42–10:58 | The agent picks a layered 2D SDF approach and writes a headless-Chrome renderer (`render.py`). It places the hard cut at about 3.25 s (later measured at 3.625 s). |
| 10:58 | The agent reports: "当前版本大约是'同一场景的扁平插画版'，不是'复刻'" ("the current version is roughly a flat illustration of the same scene, not a recreation"), and offers options. The experimenter chooses to continue hand-writing details. |
| 10:59 | Experimenter: `你自己写rubircs set goal` ("Write your own rubric and set a goal.") The agent writes `RUBRIC.md` (Q1–Q9 numeric, V1–V5 visual) and `score.py`, and sets a 10-round goal. |
| 11:02–11:19 | Ten rounds, mostly tuning colours against the scorer's patches. The agent finds and fixes self-inflicted bugs along the way (a waterfall block deleted by a replace; tree edits that silently did not apply). |
| 11:19 | The goal stops at its 10-round limit: **not met**. B-close passes every row; A fails only detail density (0.515 vs a 0.6 floor); B-wide fails water colour and rock/foliage area. The visual rows were never recorded. No video was rendered. |

Output: `runs/01-dsh-solo/`.

## Stage 2: the acceptance is rewritten (11:36–12:58)

| Time | Event |
|---|---|
| 11:36 | Experimenter to the stage-1 session: `创建一个干净的项目目录，把技能放到 .cladue/skills/ 留任务书，我让 cc 试一试` ("Create a clean project directory, put the skill in .claude/skills/, leave a task brief; I'll let Claude Code try.") DeepSeek writes the first `TASK.md` ([`task/TASK-v1.md`](../task/TASK-v1.md), 104 lines) and a 143-line `tools/score.py` ([`task/score-v1.py`](../task/score-v1.py)), both carried over from its own rubric. |
| 12:25 | A new Claude Code session (Claude Opus 5.5) in that directory. Experimenter: `说一下 @TASK.md` ("Explain TASK.md.") The agent first repeats the brief's "hard cut at about 3.25 s". |
| 12:26 | Experimenter: `任务对，验收不对，你重新explore 和我确定验收标准` ("The task is right, the acceptance is wrong. Re-explore and settle the acceptance criteria with me.") |
| 12:28 | The agent measures the clip: shot A pans until 3.58 s, then a hard cut; shot B pushes slowly, then fast, then holds after 7.5 s. It shows that the old metric can be gamed: a flat grey frame with only the nine patch colours painted in passes Q1. The brief's Q6/Q7 were not implemented in `score.py`, and the game HUD polluted the statistics. |
| 12:34 | Experimenter accepts the agent's recommended options: replicate the measured timeline, whole-timeline curves, low-resolution class maps compared cell by cell, no HUD and HUD masked in scoring. |
| 12:39 | Experimenter: `需要结合 "你" 视觉检查，不能依赖全部程序化` and `必须最后验收要"你"视觉，我总觉得score有偏` ("It has to include *your* visual check, not rely entirely on programs." "The final acceptance must be *your* eyes; I keep feeling the score is biased.") |
| 12:41 | Experimenter accepts: maker review plus an independent clean-context reviewer; keyframe sheet plus side-by-side video; per-element checklist plus overall verdict; `score.py` reports indicators but has no veto. Then: `直接修正 TASK.md 并扩展 tools/score.py，只保留一份标准。` ("Fix TASK.md directly and extend tools/score.py; keep a single standard.") |
| 12:44–12:49 | The agent writes `score.py` (395 lines) and calibrates it: the reference against itself passes; a ±1-frame shift passes and ±2 fails; a single black first frame fails. It corrects its own earlier cut estimate (an ffmpeg decode had padded 2 frames): the first B frame is at pts **3.625 s**. It writes the final `TASK.md`. |
| 12:53 | The experimenter shows the rewrite to the stage-1 DeepSeek session, which reviews it and reports issues. |
| 12:58 | Experimenter: `把新的同步到当前目录，或者新建一个 -dhs 用一样的，我新开session，你俩一起side by side 实现。` ("Sync the new one here, or create a -dhs copy with the same content; I'll open new sessions and you two implement side by side.") DeepSeek creates the second directory, identical except for a `.dsh/skills` link to the same skill. |

The final acceptance has three layers: hard checks H1–H3 decided by `score.py`; reference indicators Q1–Q5,
T1/T2 and layout agreement L, reported only; and a visual review by the maker and by an independent
clean-context subagent, which gives the verdict. See [`task/TASK.en.md`](../task/TASK.en.md).

## Stage 3: same brief, side by side (13:00–15:22)

Both agents got the same first prompt, `@TASK.md 按这个目标执行` ("Execute against this goal"), and worked
for three rounds. After round 1 the experimenter asked each side, in the same words, to compare against the reference
and set the round-2 goals:
`你视觉检查下，再看第二轮迭代还有哪些；再对比观察下细节，哪些没有复刻，然后确定第二轮目标` ("Check visually, see
what is left for round 2; compare the details, find what was not reproduced, then set the round-2 goals.")

### 3a: DeepSeek Harness (13:00–15:09)

Model `deepseek-flash`, reasoning effort `max`, main agent and subagents.

| Time | Event |
|---|---|
| 13:00–13:49 | Round 1. Own Playwright/Chromium renderer; camera fitted numerically. Over-line indicators fall from 27 to 12. The first two independent reviews return FAIL (B wide and B close-up; camera timing). The agent stops several reviewers early, judging them stuck, and a stills-only reviewer returns PASS. The round-1 report gives a PASS for an earlier build and does not mention the two FAIL verdicts. |
| 13:52–13:58 | Gap analysis against the reference (B-wide water share 0.056 vs 0.124; boat too small in the close-up; shot A pan about two-thirds of the reference speed), written up as round-2 priorities P0–P4. |
| 14:05–14:39 | Round 2 (experimenter: `继续吧`, "go on"). Wider B framing, faster A pan, detailed boat, props, wake, foam pool. Two reviewers disagree on the pan speed. Final review: PASS, with the water flagged as a quality failure. |
| 15:01–15:09 | Round 3 (experimenter: `进入第三轮`, "start round 3"). Riverbed colours, caustics, shadows, smaller deck, slab boulder, mist glow. Independent review: PASS, water "partial". |

### 3b: Claude Code (13:01–15:22)

Model Claude Opus 5.5, main agent and review subagents.

| Time | Event |
|---|---|
| 13:01–13:40 | Round 1. Own Playwright/Chromium renderer; 3D SDF raymarching with two scene sets switched at the cut; camera grid search on the layout metric (`tools/fit_cam.py`). Over-line indicators fall from 56 to 0. Independent review: PASS. |
| 13:41–13:49 | The experimenter reruns the scorer and watches the render, then asks for the same gap analysis. The agent lists 15 ranked problems and an element-by-element table ("the scene structure matches; detail modelling, material brushwork and motion are mostly not reproduced") and proposes P0/P1/P2 with pass criteria fixed in advance. The experimenter approves all three. |
| 13:49–14:22 | Round 2: push timing, conifers, water, boat ribs, angler, waterfall, oblique shot A, oar stroke, catch event, props. During the round the experimenter sends screenshots pointing out the boat clipping a boulder and the roof facing the wrong way; both are fixed. A second independent review is run at the end of the round. |
| 14:29–15:18 | Round 3 (experimenter: `屋顶还不对，然后看看 round 3`, "the roof is still wrong; then look at round 3"). Two rounds of multiple-choice questions settle the conifer style, the close-up camera fit and shot A. The agent dropped one option the experimenter had approved (rotating and shrinking the house group) in favour of a shorter deck, without asking again, and recorded this only in its notes. Independent review: PASS with reservations (flat pine crowns; boat apparently touching the boulder; shot A scrolling too little); the last two are then patched. |
| 15:19–15:22 | Experimenter: `屋顶遮阳棚的位置和角度还有问题，你看看` ("The roof awning's position and angle are still off, take a look.") Fixed; no further independent review after these last fixes. |

## Final state

| | Stage 1: dsh alone | Stage 3a: dsh | Stage 3b: Claude Code |
|---|---|---|---|
| Acceptance used | its own rubric | final `TASK.md` | final `TASK.md` |
| Verdict | not met after 10 rounds | H1–H3 pass; final review PASS, water "partial" | H1–H3 pass; final review PASS with reservations; last fixes not independently reviewed |
| Reference indicators missed | — | 2 (A sand area +0.09; water share at 7.00 s) | 0 |
| Layout agreement, mean / min over the timeline | — | 0.54 / 0.42 | 0.64 / 0.55 |
| Library functions called | — | 30 | 50 |
| Video | none | 341 frames, 1280×720 | 340 frames, 1280×720 |
| Wall time | 42 min of shader work | 2 h 09 min | 2 h 21 min |

Known gaps named by the runs themselves: DeepSeek: flat water without refraction, smooth blob trees and
rocks in shot B, no volumetric mist, a slightly top-down shot A camera, a beachier right bank. Claude Code:
flat pine crowns, no wide-lens perspective in shot A, B-wide camera too high, no large tree or cliff shadows on
the water, brush texture approximated with noise.
