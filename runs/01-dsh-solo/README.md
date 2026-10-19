# Shader recreation rig

> **Repository note:** this is the run's own README, kept as written. `shader/` in the commands below is this
> directory (`runs/01-dsh-solo/`), and `.dsh/skills/shader-art-coding` is the skill installed by
> `tools/install_skill.sh`. Reference frames that the run cached in `out/` are not published; `score.py`
> re-extracts them from `assets/reference.mp4`. `out/compare.png` is not included for the same reason.

Working directory for the creek-video recreation. Not part of the skill; the skill lives in
`.dsh/skills/shader-art-coding`.

## Files

| Path | What |
|---|---|
| `creek.glsl` | Source: two-shot scene, art controls at the top, `DEBUG_MODE` switches |
| `creek.bundle.glsl` | Bundled Shadertoy-ready output (`glsl_tools.py bundle`) |
| `render.py` | Offscreen renderer through headless Chrome |
| `out/` | Rendered stills and the reference-vs-shader comparison sheet |
| `.queue/`, `.cache/` | Renderer plumbing, safe to delete |

## Render a frame

The renderer runs as a daemon because Chrome writes outside the workspace. Start it once:

```bash
python3 shader/render.py daemon
```

Then, without further permissions:

```bash
python3 shader/render.py shot shader/creek.bundle.glsl 9.5 shader/out/b-095.png 1280 720
```

The daemon renders through Chrome headless + ANGLE Metal. `--use-mock-keychain` is set and `HOME`
is not overridden, so Chrome does not prompt for Keychain access.

## Build and check

```bash
python3 .dsh/skills/shader-art-coding/scripts/glsl_tools.py bundle shader/creek.glsl -o shader/creek.bundle.glsl
python3 .dsh/skills/shader-art-coding/scripts/glsl_tools.py check shader/creek.bundle.glsl
```

`check` compiles with glslangValidator 16.6.0 (installed).

## Status

Both shots exist and animate: hard cut at 3.25 s, establishing push-in to the cove, enclosed rock
basin with treeline, water with caustics and foam rim, waterfall spilling from the rock into the
pool, boulders with contact shadows, boat with angler, rod, bobber and fish, shot A dock/house/bank.

Scored against `RUBRIC.md` by `score.py`. Current state: shot A passes palette, area, luma and contrast;
shot B-close passes every row; shot B-wide still misses water palette and rock/foliage area. Detail
density is the last open row overall (0.52 / 0.59 / 0.84 against a 0.6 floor).

Honest limit: a flat procedural shader cannot reach the reference's painted 3D texture without a
detail budget that would break the measured palette.

Latest comparison: `out/compare.png` (reference left, shader right).

## Conventions

- Shading is computed directly in sRGB and written out without the linear/tonemap round trip; the
  reference is flat art and palette fidelity matters more than HDR headroom.
- Screens are 16:9; all coordinates are normalized so the frame height spans 2 units.
