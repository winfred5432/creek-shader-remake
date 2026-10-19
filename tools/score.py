#!/usr/bin/env python3
"""Acceptance check for the creek recreation.

Three layers, see TASK.md "验收标准":
  HARD        must pass: shader rules, deliverables present, hard cut within +-1 frame of the reference.
  INDICATORS  reported only: Q1-Q5 on the three stills, timeline curves, layout agreement.
  REVIEW      side-by-side material for the visual review, which gives the final verdict.

Usage:
  python3 tools/score.py --own-dir verify

Expected files:
  work.glsl, final.glsl          project root; final.glsl == bundle(work.glsl)
  verify/t2.png t6.png t12.png   stills rendered at iTime 2.0 / 6.0 / 12.0, 16:9
  verify/render.mp4              24 fps; the frame at pts t is rendered with iTime = t; covers 0..14.125 s
Writes verify/review/sheet.png and verify/review/side_by_side.mp4.
Requires numpy and ffmpeg/ffprobe on PATH.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SKILL_SCRIPTS = ROOT / ".claude/skills/shader-art-coding/scripts"
REF_VIDEO = ROOT / "assets/reference.mp4"
W, H = 320, 180
FPS = 24
FRAME = 1.0 / FPS

# checkpoint -> (reference frame, own file, iTime, patches (x, y, w, h) in fractions)
CHECKPOINTS = {
    "A": ("assets/ref-t2.0.png", "t2.png", 2.0, {
        "water": (0.42, 0.40, 0.20, 0.20),
        "wood":  (0.05, 0.25, 0.15, 0.20),
        "sand":  (0.72, 0.20, 0.14, 0.15),
        "grass": (0.86, 0.05, 0.11, 0.13),
    }),
    "B-wide": ("assets/ref-t6.0.png", "t6.png", 6.0, {
        "water":   (0.45, 0.60, 0.20, 0.15),
        "rock":    (0.34, 0.08, 0.16, 0.12),
        "foliage": (0.05, 0.18, 0.12, 0.16),
    }),
    "B-close": ("assets/ref-t12.0.png", "t12.png", 12.0, {
        "water": (0.55, 0.55, 0.20, 0.15),
        "rock":  (0.80, 0.25, 0.14, 0.15),
        "wood":  (0.10, 0.55, 0.12, 0.15),
    }),
}

ANCHORS = {
    "water":   (0.22, 0.72, 0.56),
    "rock":    (0.55, 0.57, 0.55),
    "wood":    (0.45, 0.29, 0.21),
    "foliage": (0.30, 0.48, 0.24),
    "sand":    (0.64, 0.66, 0.56),
    "dark":    (0.15, 0.15, 0.15),
}

DE_MAX, AREA_MAX, LUMA_MAX, LUMA_STD_MAX = 10.0, 0.08, 0.08, 0.06
DETAIL_RANGE = (0.6, 1.8)
TIMELINE_STEP = 0.25
LAYOUT_GRID = (32, 18)
REVIEW_TIMES = (1.0, 2.0, 3.5, 3.75, 5.0, 6.0, 7.0, 7.5, 10.0, 12.0)

# Game HUD in the reference, excluded from every comparison (x0, y0, x1, y1 fractions).
# Measured on the reference frames: panels are detected as cream-coloured regions.
HUD_ALWAYS = [
    (0.00, 0.01, 0.15, 0.11),   # time-of-day badge
    (0.42, 0.01, 0.57, 0.10),   # creel counter
    (0.00, 0.78, 0.26, 0.96),   # action buttons
]
# (rect, visible pts span). Spans are padded by 2 frames to cover the fade in/out.
HUD_TIMED = [
    ((0.77, 0.02, 1.00, 0.16), (3.875, 6.083)),    # "New fishing spot" popup
    ((0.77, 0.02, 1.00, 0.16), (13.541, 1e9)),     # catch popup
    ((0.30, 0.85, 0.70, 0.94), (10.250, 13.083)),  # reel progress bar
]
HUD_PAD = 2 * FRAME


# ---------------------------------------------------------------- io

def load(path: Path, w: int = W, h: int = H) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-vf", f"scale={w}:{h}:flags=area",
         "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.uint8).reshape(h, w, 3).astype(np.float32) / 255.0


def load_video(path: Path, w: int = W, h: int = H) -> tuple[np.ndarray, np.ndarray]:
    """All frames (uint8) and their pts in seconds, without frame padding or dropping."""
    pts = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time",
         "-of", "csv=p=0", str(path)], capture_output=True, check=True, text=True).stdout
    pts = np.array([float(l.strip().rstrip(",")) for l in pts.splitlines() if l.strip()])
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-fps_mode", "passthrough",
         "-vf", f"scale={w}:{h}:flags=area", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True).stdout
    frames = np.frombuffer(raw, dtype=np.uint8).reshape(-1, h, w, 3)
    n = min(len(frames), len(pts))
    return frames[:n], pts[:n]


def at(frames: np.ndarray, pts: np.ndarray, t: float) -> np.ndarray:
    return frames[int(np.abs(pts - t).argmin())].astype(np.float32) / 255.0


# ---------------------------------------------------------------- measures

def hud_keep(t: float, w: int = W, h: int = H) -> np.ndarray:
    keep = np.ones((h, w), dtype=bool)
    rects = list(HUD_ALWAYS) + [r for r, (a, b) in HUD_TIMED if a - HUD_PAD <= t <= b + HUD_PAD]
    for x0, y0, x1, y1 in rects:
        keep[int(y0 * h):int(np.ceil(y1 * h)), int(x0 * w):int(np.ceil(x1 * w))] = False
    return keep


def to_lab(rgb: np.ndarray) -> np.ndarray:
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805],
                  [0.2126, 0.7152, 0.0722],
                  [0.0193, 0.1192, 0.9505]], dtype=np.float32)
    xyz = lin @ m.T / np.array([0.95047, 1.0, 1.08883], dtype=np.float32)
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116.0 * f[..., 1] - 16.0,
                     500.0 * (f[..., 0] - f[..., 1]),
                     200.0 * (f[..., 1] - f[..., 2])], axis=-1)


ANCHOR_LAB = to_lab(np.array(list(ANCHORS.values()), dtype=np.float32))


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def detail(rgb: np.ndarray, keep: np.ndarray) -> float:
    g = np.gradient(luma(rgb))
    mag = np.sqrt(g[0] ** 2 + g[1] ** 2)
    # Gradients next to a masked rect would see the HUD edge, so erode the mask by one pixel.
    inner = keep.copy()
    inner[1:] &= keep[:-1]
    inner[:-1] &= keep[1:]
    inner[:, 1:] &= keep[:, :-1]
    inner[:, :-1] &= keep[:, 1:]
    return float(mag[inner].mean())


def class_map(rgb: np.ndarray) -> np.ndarray:
    lab = to_lab(rgb)
    return ((lab[..., None, :] - ANCHOR_LAB) ** 2).sum(-1).argmin(-1)


def classify(rgb: np.ndarray, keep: np.ndarray) -> np.ndarray:
    return np.bincount(class_map(rgb)[keep], minlength=len(ANCHORS)) / keep.sum()


def layout_agreement(ref: np.ndarray, own: np.ndarray, keep: np.ndarray) -> float:
    """Share of grid cells whose mean colour falls in the same class (HUD pixels excluded)."""
    gw, gh = LAYOUT_GRID
    cw, ch = W // gw, H // gh
    k = keep.reshape(gh, ch, gw, cw).astype(np.float32)[..., None]
    cnt = k.sum((1, 3))
    valid = cnt[..., 0] > 0

    def cells(img: np.ndarray) -> np.ndarray:
        s = (img.reshape(gh, ch, gw, cw, 3) * k).sum((1, 3))
        return class_map(s / np.maximum(cnt, 1))

    return float((cells(ref) == cells(own))[valid].mean())


def frame_diffs(frames: np.ndarray, pts: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Mean abs change into each frame, keyed by that frame's pts."""
    f = frames.astype(np.float32) / 255.0
    return pts[1:], np.abs(f[1:] - f[:-1]).mean((1, 2, 3))


def cut_time(frames: np.ndarray, pts: np.ndarray) -> tuple[float, float]:
    """The hard cut is the largest frame-to-frame change: pts of the first new frame, and that change."""
    t, d = frame_diffs(frames, pts)
    i = int(d.argmax())
    return float(t[i]), float(d[i])


# ---------------------------------------------------------------- hard checks

def check_shader(root: Path) -> bool:
    work, final = root / "work.glsl", root / "final.glsl"
    print("[H1 shader]")
    if not work.exists() or not final.exists():
        print(f"  missing {'work.glsl' if not work.exists() else ''} {'final.glsl' if not final.exists() else ''}  FAIL")
        return False
    sys.path.insert(0, str(SKILL_SCRIPTS))
    import glsl_tools as gt  # noqa: E402
    lib = gt.Library()
    src = work.read_text(encoding="utf-8")
    ok = True

    same = gt.normalize(gt.bundle_source(lib, src)) == gt.normalize(final.read_text(encoding="utf-8"))
    ok &= same
    print(f"  final.glsl == bundle(work.glsl)   {'ok' if same else 'FAIL'}")

    defined = {it.name for it in gt.parse(src) if it.kind in ("fn", "struct", "const", "define")}
    copied = sorted(n for n in defined if any(it.kind != "proto" for it in lib.by_name.get(n, [])))
    used = sorted(lib.idents(src) - defined)
    ok &= not copied and bool(used)
    print(f"  library functions called: {len(used)}   {'ok' if used else 'FAIL'}")
    print(f"  library functions redefined: {copied or 'none'}   {'FAIL' if copied else 'ok'}")

    code = gt.strip_comments(final.read_text(encoding="utf-8"))
    banned = [p for p in (r"#\s*version", r"\biChannel\d", r"^\s*uniform\b") if re.search(p, code, re.M)]
    ok &= not banned
    print(f"  no #version / iChannel / uniform   {'ok' if not banned else 'FAIL ' + str(banned)}")

    r = subprocess.run([sys.executable, str(SKILL_SCRIPTS / "glsl_tools.py"), "check", str(final)],
                       capture_output=True, text=True)
    ok &= r.returncode == 0
    print(f"  glsl_tools check final.glsl   {'ok' if r.returncode == 0 else 'FAIL'}")
    if r.returncode != 0:
        print("    " + (r.stdout + r.stderr).strip().replace("\n", "\n    "))
    return ok


def check_files(own_dir: Path, ref_end: float) -> tuple[bool, tuple | None]:
    print("[H2 deliverables]")
    ok = True
    for _, own_name, _, _ in CHECKPOINTS.values():
        exists = (own_dir / own_name).exists()
        ok &= exists
        print(f"  {own_name:12} {'ok' if exists else 'missing  FAIL'}")
    video = own_dir / "render.mp4"
    if not video.exists():
        print("  render.mp4   missing  FAIL")
        return False, None
    info = json.loads(subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate",
         "-of", "json", str(video)], capture_output=True, check=True, text=True).stdout)
    num, den = (int(x) for x in info["streams"][0]["r_frame_rate"].split("/"))
    frames, pts = load_video(video)
    rate_ok = num == FPS * den
    span_ok = pts[0] <= FRAME / 2 and pts[-1] >= ref_end - FRAME / 2
    ok &= rate_ok and span_ok
    print(f"  render.mp4   {num / den:g} fps {'ok' if rate_ok else 'FAIL'}; "
          f"pts {pts[0]:.3f}..{pts[-1]:.3f} s (need 0..{ref_end:.3f}) {'ok' if span_ok else 'FAIL'}")
    return ok, (frames, pts)


def check_cut(ref: tuple, own: tuple) -> bool:
    rt, rd = cut_time(*ref)
    ot, od = cut_time(*own)
    good = abs(ot - rt) <= FRAME + 1e-3
    print("[H3 hard cut]")
    print(f"  reference first frame after cut {rt:.3f} s (frame diff {rd:.3f})")
    print(f"  own       first frame after cut {ot:.3f} s (frame diff {od:.3f})   {'ok' if good else 'FAIL'}")
    if not good:
        t, d = frame_diffs(*own)
        top = ", ".join(f"{t[i]:.3f} s ({d[i]:.3f})" for i in np.argsort(d)[::-1][:3])
        print(f"  own largest frame diffs: {top}")
    return good


# ---------------------------------------------------------------- indicators

def flag(good: bool) -> str:
    return "ok" if good else "OVER"


def stills(own_dir: Path, own_video: tuple | None) -> int:
    over = 0
    for name, (ref_rel, own_name, t, patches) in CHECKPOINTS.items():
        own_path = own_dir / own_name
        if not own_path.exists():
            continue
        ref, own = load(ROOT / ref_rel), load(own_path)
        keep = hud_keep(t)
        ref_lab, own_lab = to_lab(ref), to_lab(own)
        print(f"[{name} t={t:g}]")
        for pname, (x, y, w, h) in patches.items():
            x0, y0, x1, y1 = int(x * W), int(y * H), int((x + w) * W), int((y + h) * H)
            k = keep[y0:y1, x0:x1]
            de = float(np.linalg.norm(ref_lab[y0:y1, x0:x1][k].mean(0) - own_lab[y0:y1, x0:x1][k].mean(0)))
            over += de > DE_MAX
            print(f"  Q1 {pname:8} dE {de:5.1f}  {flag(de <= DE_MAX)}")

        rc, oc = classify(ref, keep), classify(own, keep)
        for cls, r, o in zip(ANCHORS, rc, oc):
            d = float(o - r)
            over += abs(d) > AREA_MAX
            print(f"  Q2 {cls:8} {r:.2f} -> {o:.2f}  ({d:+.2f}) {flag(abs(d) <= AREA_MAX)}")

        lr, lo = luma(ref)[keep], luma(own)[keep]
        lm, ls = abs(float(lo.mean() - lr.mean())), abs(float(lo.std() - lr.std()))
        over += (lm > LUMA_MAX) + (ls > LUMA_STD_MAX)
        print(f"  Q3 luma mean diff {lm:.3f} {flag(lm <= LUMA_MAX)}")
        print(f"  Q4 luma std  diff {ls:.3f} {flag(ls <= LUMA_STD_MAX)}")

        ratio = detail(own, keep) / max(detail(ref, keep), 1e-6)
        good = DETAIL_RANGE[0] <= ratio <= DETAIL_RANGE[1]
        over += not good
        print(f"  Q5 detail ratio   {ratio:.3f} {flag(good)}")

        print(f"  layout agreement {LAYOUT_GRID[0]}x{LAYOUT_GRID[1]}  {layout_agreement(ref, own, keep):.2f}")
        if own_video is not None:
            gap = float(np.abs(at(*own_video, t) - own).mean())
            print(f"  still vs render.mp4 frame at {t:g} s: mean abs diff {gap:.3f}")
    return over


def timeline(ref: tuple, own: tuple) -> int:
    end = min(ref[1][-1], own[1][-1])
    times = np.arange(0.0, end + 1e-6, TIMELINE_STEP)
    rows = []
    for t in times:
        r, o, keep = at(*ref, t), at(*own, t), hud_keep(t)
        rows.append((t,
                     classify(r, keep)[0], classify(o, keep)[0],
                     float(luma(r)[keep].mean()), float(luma(o)[keep].mean()),
                     layout_agreement(r, o, keep)))
    a = np.array(rows)
    dw, dl = np.abs(a[:, 2] - a[:, 1]), np.abs(a[:, 4] - a[:, 3])
    print(f"[timeline] {len(times)} samples, every {TIMELINE_STEP:g} s")
    print("     t   water ref/own    luma ref/own   layout")
    for (t, wr, wo, lr, lo, la), ew, el in zip(rows, dw, dl):
        marks = ("W" if ew > AREA_MAX else " ") + ("L" if el > LUMA_MAX else " ")
        print(f"  {t:5.2f}   {wr:.2f} / {wo:.2f}     {lr:.3f} / {lo:.3f}    {la:.2f}  {marks}")
    nw, nl = int((dw > AREA_MAX).sum()), int((dl > LUMA_MAX).sum())
    print(f"  water fraction: {nw} samples over {AREA_MAX} (worst {dw.max():.2f} at {times[dw.argmax()]:.2f} s)")
    print(f"  mean luma:      {nl} samples over {LUMA_MAX} (worst {dl.max():.3f} at {times[dl.argmax()]:.2f} s)")
    print(f"  layout agreement mean {a[:, 5].mean():.2f}, min {a[:, 5].min():.2f} at {times[a[:, 5].argmin()]:.2f} s")
    return nw + nl


# ---------------------------------------------------------------- review material

def review(own_dir: Path) -> None:
    out = own_dir / "review"
    out.mkdir(exist_ok=True)
    rw, rh = 480, 270
    ref = load_video(REF_VIDEO, rw, rh)
    own = load_video(own_dir / "render.mp4", rw, rh)
    rows = [np.concatenate([at(*ref, t), np.ones((rh, 8, 3), np.float32), at(*own, t)], axis=1)
            for t in REVIEW_TIMES]
    sep = np.ones((8, rows[0].shape[1], 3), np.float32)
    sheet = np.concatenate([x for r in rows for x in (r, sep)][:-1], axis=0)
    img = (np.clip(sheet, 0, 1) * 255).astype(np.uint8)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                    "-s", f"{img.shape[1]}x{img.shape[0]}", "-i", "-", str(out / "sheet.png")],
                   input=img.tobytes(), check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(REF_VIDEO), "-i", str(own_dir / "render.mp4"),
                    "-filter_complex", "[0:v]scale=640:360[a];[1:v]scale=640:360[b];[a][b]hstack=shortest=1",
                    "-r", str(FPS), "-pix_fmt", "yuv420p", "-an", str(out / "side_by_side.mp4")], check=True)
    times = ", ".join(f"{t:g}" for t in REVIEW_TIMES)
    print(f"[review] {out / 'sheet.png'}  rows = t {times} s; left reference, right own")
    print(f"[review] {out / 'side_by_side.mp4'}  left reference, right own")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--own-dir", default="verify")
    args = ap.parse_args()
    own_dir = (ROOT / args.own_dir).resolve()

    ref = load_video(REF_VIDEO)
    print("== HARD (must pass) ==")
    h1 = check_shader(ROOT)
    h2, own = check_files(own_dir, float(ref[1][-1]))
    h3 = check_cut(ref, own) if own is not None else False
    hard = h1 and h2 and h3

    print("\n== INDICATORS (reported, not a verdict) ==")
    over = stills(own_dir, own)
    if own is not None:
        over += timeline(ref, own)
        print()
        review(own_dir)

    print(f"\nHARD: {'PASS' if hard else 'FAIL'}")
    print(f"INDICATORS: {over} over the line; each needs a fix or a reason in the visual review")
    print("FINAL VERDICT: visual review (see TASK.md)")
    return 0 if hard else 1


if __name__ == "__main__":
    sys.exit(main())
