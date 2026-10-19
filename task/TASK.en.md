# Task brief: recreate the reference video with the shader-art-coding skill

> English translation of [`TASK.md`](TASK.md). The Chinese original is the version both agents received;
> where the two differ, the Chinese text governs.

## Goal

Recreate the picture of `assets/reference.mp4` as **one Shadertoy GLSL file**. This is not a pixel-exact
reproduction of a 3D game; it is the same scene, the same palette and the same camera move, made with a
procedural shader.

## Inputs

| File | Description |
|---|---|
| `assets/reference.mp4` | 1920×1080, 24 fps, 338 frames; first frame pts 0.083 s, last frame pts 14.125 s. Two shots, timeline below |
| `assets/ref-t2.0.png` | Shot A reference frame (pts 2.0), 960×540 |
| `assets/ref-t6.0.png` | Shot B wide reference frame (pts 6.0), 960×540 |
| `assets/ref-t12.0.png` | Shot B close-up reference frame (pts 12.0), 960×540 |
| `assets/contact-sheet.png` | One frame per second, overview |
| `.claude/skills/shader-art-coding/` | The skill: 186 verified GLSL functions, bundler, checker, templates and reference docs |

## Reference timeline (measured; all times are video pts)

| Interval | Shot | Camera |
|---|---|---|
| 0 – 3.583 s | A: the dock | Oblique top-down; the camera follows the boat upstream, so the whole picture scrolls down; water share falls from 0.34 to 0.11 |
| 3.625 s | Hard cut | The first B frame appears at pts 3.625 s, i.e. frame 85 (counting from 0); frame difference 0.204, every other moment ≤ 0.10 |
| 3.625 – 6.8 s | B: waterfall cove, wide | Slowly descends and pushes in |
| 6.8 – 7.4 s | B | Fast push in to the close-up |
| 7.5 – 14.125 s | B: close-up | Essentially static; only the fish, the fishing line and the water move |

## Deliverables

| File | Requirement |
|---|---|
| `work.glsl` | Source; calls library functions by name |
| `final.glsl` | Output of `glsl_tools.py bundle work.glsl -o final.glsl`; paste-ready, contains only `mainImage`, no `#version`, no textures, no custom uniforms |
| `verify/t2.png` `verify/t6.png` `verify/t12.png` | Screenshots rendered from `final.glsl` at iTime = 2.0 / 6.0 / 12.0, 16:9 |
| `verify/render.mp4` | The whole clip rendered from `final.glsl`: 24 fps, pts starts at 0, the frame with pts t is rendered with iTime = t, covering at least up to 14.125 s |
| `NOTES.md` | Which library functions were used; what was reproduced and what was not; the full output of `score.py`; how over-line indicators were handled; the conclusions of both visual reviews |

## Constraints

- A single file, bundled at the end with the skill's own tool: `glsl_tools.py bundle`
- You must call functions from the skill library; do not copy them in again
- Recreate the timeline as measured above: shot A pans, hard cut at 3.625 s, shot B slow push → fast push → static
- Do not draw the game HUD (time at top left, Creel counter at top, buttons at bottom left, popup at top right, progress bar at bottom)
- 16:9; all coordinates take the frame height as 2 units

## Acceptance criteria

Three layers. Programmatic checks can only prove "no hard mistakes" and "statistically close". Whether it is
the same scene and the same camera move is decided, in the end, by the visual review.

### Layer 1: hard requirements (judged by `score.py`; any failure means not accepted)

| Item | Content |
|---|---|
| H1 | `final.glsl` equals `bundle(work.glsl)`; at least one library function is called; `work.glsl` redefines no library function; no `#version` / `iChannel` / `uniform`; `glsl_tools.py check final.glsl` passes |
| H2 | The three screenshots and `render.mp4` all exist; `render.mp4` is 24 fps and covers 0 – 14.125 s |
| H3 | Hard cut: the position of the largest frame difference in `render.mp4` is the hard cut, and the pts of the first frame after it differs from the reference by no more than 1 frame (3.583 – 3.667 s). A flash frame such as a black first frame also fails this item |

### Layer 2: reference indicators (reported by `score.py`; they do not decide acceptance on their own)

All indicators are computed at 320×180, with the HUD regions masked out on both the reference and the
recreation.

| Item | Indicator | Reference line |
|---|---|---|
| Q1 | ΔE76 (CIE Lab) of the mean colour of 9 patches; patches in the table below | ≤ 10 |
| Q2 | Difference in area share of six classes (water / rock / wood / foliage / sand / dark) | ≤ 0.08 |
| Q3 | Mean luminance difference | ≤ 0.08 |
| Q4 | Luminance standard deviation difference | ≤ 0.06 |
| Q5 | Detail density ratio (mean gradient, recreation ÷ reference) | 0.6 – 1.8 |
| T1 | Timeline: one sample every 0.25 s (57 in total), difference in water share | ≤ 0.08 at every point |
| T2 | Timeline: as above, difference in mean luminance | ≤ 0.08 at every point |
| L | Layout agreement: split the frame into 32×18 cells, classify each cell's mean colour into the six classes, share of cells in the same class as the reference | Value reported only; judged by the visual review |

Anchors for layout agreement (measured on the reference video itself): completely different scenes about
0.25; the same shot with camera positions 1 s apart about 0.65; a fake frame that only paints colour at the
patch positions 0.14 – 0.49.

For every item over its reference line, `NOTES.md` must state either that it was fixed, or why it is
acceptable, explained in the visual review.

| Checkpoint | Time | Patches (x, y, w, h, 0–1, origin at top left) |
|---|---|---|
| A | 2.0 | water (0.42, 0.40, 0.20, 0.20); wood (0.05, 0.25, 0.15, 0.20); sand (0.72, 0.20, 0.14, 0.15); grass (0.86, 0.05, 0.11, 0.13) |
| B-wide | 6.0 | water (0.45, 0.60, 0.20, 0.15); rock (0.34, 0.08, 0.16, 0.12); foliage (0.05, 0.18, 0.12, 0.16) |
| B-close | 12.0 | water (0.55, 0.55, 0.20, 0.15); rock (0.80, 0.25, 0.14, 0.15); wood (0.10, 0.55, 0.12, 0.15) |

Classification is nearest neighbour in CIE Lab, with anchors (sRGB):

```
water   (0.22, 0.72, 0.56)
rock    (0.55, 0.57, 0.55)
wood    (0.45, 0.29, 0.21)
foliage (0.30, 0.48, 0.24)
sand    (0.64, 0.66, 0.56)
dark    (0.15, 0.15, 0.15)
```

Measured patch values of the reference frames (sRGB), usable directly as colour targets:

| Checkpoint | Measured patches |
|---|---|
| A | water `#679D7F`; wood `#815D52`; sand `#ACBF77`; grass `#688950` |
| B-wide | water `#439E83`; rock `#66716F`; foliage `#607C44` |
| B-close | water `#33C69C`; rock `#717779`; wood `#605143` |

HUD mask (x0, y0, x1, y1): always mask (0.00, 0.01, 0.15, 0.11), (0.42, 0.01, 0.57, 0.10), (0.00, 0.78, 0.26, 0.96);
from 3.875 – 6.083 s and after 13.541 s also mask the top-right popup (0.77, 0.02, 1.00, 0.16); from
10.250 – 13.083 s also mask the progress bar (0.30, 0.85, 0.70, 0.94). Each interval is padded by 2 frames on
both sides to cover the fade in and out.

### Layer 3: visual review (the final verdict)

**Review material** (generated automatically by `score.py`):

- `verify/review/sheet.png`: reference (left) and recreation (right) side by side at 1, 2, 3.5, 3.75, 5, 6, 7, 7.5, 10, 12 s
- `verify/review/side_by_side.mp4`: the whole clip side by side, for judging the rhythm of the camera move

**Reviewers**: acceptance requires both reviews to pass.

1. The maker's own check, item by item against the checklist below; if it does not pass, keep iterating.
2. An independent review: a clean-context subagent that took no part in making it. It receives only the review material, this checklist and the `score.py` output; it does not see the conversation or the source.

**Checklist**: judge three things for each item — is it there, is it in the right place (in the same region
of the frame as in the reference), is the colour right.

| Shot | Main elements (missing any one fails) | Secondary elements (if missing, explain in NOTES.md) |
|---|---|---|
| A | Cabin (with roof), dock platform, river channel, sandy bank on the right, boat | Footbridge, trees, rocks, grass |
| B wide | Ring of rock walls, cove, waterfall at the top, boat, woods on both sides | Large boulders, school of fish |
| B close-up | Rock walls, cove, waterfall, boat and angler | Fishing line, float, school of fish |
| Whole clip | Water changes colour with depth; shadows are large and soft | — |

**Camera**: the direction and rhythm of the downward scroll in shot A; hard cut at 3.625 s; in shot B first
a slow push, a fast push from 6.8 – 7.4 s, then static.

**Overall judgement**: a one-sentence conclusion — would someone who has not read the notes recognise it as
the same scene and the same camera move.

**Pass condition**: layer 1 passes in full; in both visual reviews the main elements, the camera and the
overall judgement pass; every over-line item in layer 2 is fixed or explained.

## Self-check

```bash
# Compile check (glslangValidator 16.6.0 is installed on this machine)
python3 .claude/skills/shader-art-coding/scripts/glsl_tools.py check final.glsl

# Bundle
python3 .claude/skills/shader-art-coding/scripts/glsl_tools.py bundle work.glsl -o final.glsl

# Acceptance: prints H1–H3, Q1–Q5, T1/T2, L, and generates verify/review/
python3 tools/score.py --own-dir verify
```

No rendering tool is mandated: the Shadertoy website, headless Chrome or any local WebGL environment will
do. The three screenshots, `render.mp4` and `final.glsl` must all come from the same code. `score.py`
reports the difference between each screenshot and the video frame at the same moment, for the reviewers
to check.

The exit code of `score.py` reflects only layer 1 (hard requirements). The final conclusion is the visual
review's.

## Reference facts (objective information, not a solution)

- The reference is oblique top-down 3D game footage with hand-painted materials; shadows are large and soft, water changes colour with depth
- Shot A: cabin, dock, river channel, sandy bank on the right, footbridge, trees
- Shot B: a cove enclosed by rock walls, waterfall at the top, boat and angler, float, school of fish
- The wide shot (t=6) has darker, greyer water than the close-up (t=12): `#439E83` vs `#33C69C`
- Mean luminance with the HUD masked: t=2 about 0.56, t=6 about 0.46, t=12 about 0.49

## Submission

Leave `work.glsl`, `final.glsl`, `verify/` (including `review/`) and `NOTES.md` in the project root.
