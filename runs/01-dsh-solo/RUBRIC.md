# Rubric: creek recreation

Acceptance criteria for `creek.glsl`. The reference is `assets/reference.mp4` (1920×1080, 24 fps,
14.17 s). Checkpoints: **A** t=2.0 (dock), **B-wide** t=6.0, **B-close** t=12.0.

`score.py` measures the quantitative rows; the qualitative rows are judged from rendered stills and
recorded in the round log at the bottom (round log removed in this repository; the outcome is kept). A row is PASS only when every checkpoint passes it.

## Quantitative

| # | Criterion | PASS | WARN | Ground |
|---|---|---|---|---|
| Q1 | Mean colour difference per named patch (ΔE76, CIE Lab) | ≤ 10 | ≤ 16 | ΔE 2.3 is a just-noticeable difference; 10 is an obvious but same-family difference |
| Q2 | Area share per class (water / rock / wood / foliage / sand), absolute difference | ≤ 0.08 | ≤ 0.12 | A class covering 8 points more or less of the frame reads as a different composition |
| Q3 | Luminance mean, absolute difference | ≤ 0.08 | ≤ 0.12 | About one stop of exposure |
| Q4 | Luminance standard deviation, absolute difference | ≤ 0.06 | ≤ 0.09 | Contrast mismatch reads as flat or harsh |
| Q5 | Detail density, own ÷ reference (mean gradient) | 0.6–1.8 | 0.4–2.4 | Below 0.6 the image is visibly flatter; above 1.8 it is noisier |
| Q6 | Motion: shot A and shot B differ at the cut | required | — | Mean abs difference > 0.10 |
| Q7 | Motion: cove pushes in between t=4.0 and t=8.0 | required | — | Water share grows by ≥ 0.08 (push-in fills the frame) |
| Q8 | Compiles: `glsl_tools.py check` | 0 errors | — | glslangValidator 16.6.0 |
| Q9 | Single Shadertoy file, no textures, no `#version`, no custom uniforms | required | — | Skill hard rules |

## Qualitative (pass/fail from rendered stills)

| # | Criterion |
|---|---|
| V1 | No flat fill larger than ~5 % of frame: every large mass carries a gradient or texture |
| V2 | Foliage reads as layered canopies, not a row of discs |
| V3 | The angler reads as a seated figure with a hat, arm and rod |
| V4 | Shot A house, dock, bridge and bank read as separate structures |
| V5 | The waterfall has a lip, a falling sheet and an impact ring at the pool |

## Outcome after 10 rounds

**Not met.** Two rows remain open: Q5 (A 0.515 and B-wide 0.589 against a 0.6 floor) and, in the
establishing shot only, Q1 water (11.0) and Q2 rock/foliage (+0.15 / −0.10). Everything else passes,
including both motion checks and compilation.

The remaining gap is structural rather than a tuning miss: the reference gets its gradient energy from
painted 3D assets (wood grain, moss, leaf clusters, stone facets) that cover the whole frame. Adding
that energy procedurally with lines and grain moved detail from 0.37 to 0.52-0.84, but each increment
large enough to cross 0.6 in the flat top-down shots also shifted the patch colours that Q1 measures.

