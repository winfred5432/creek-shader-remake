#!/usr/bin/env python3
"""Measure the shader recreation against reference frames from the source video.

Usage:
  python3 shader/score.py [--render] [--json]

--render renders the checkpoints through render.py before measuring (needs the render daemon).
Exit code 0 means every quantitative row in RUBRIC.md passed.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
# Repository edit: the run read a local copy of the clip; it now reads the rebuilt reference.
VIDEO = HERE.parents[1] / "assets" / "reference.mp4"
SRC = HERE / "creek.bundle.glsl"
OUT = HERE / "out"

W, H = 320, 180

# checkpoint: (time, patch name -> (x, y, w, h) in fractions, top-left origin)
CHECKPOINTS = {
    "A": (2.0, {
        "water": (0.42, 0.40, 0.20, 0.20),
        "wood":  (0.05, 0.25, 0.15, 0.20),
        "sand":  (0.72, 0.20, 0.14, 0.15),
        "grass": (0.86, 0.05, 0.11, 0.13),
    }),
    "B-wide": (6.0, {
        "water":   (0.45, 0.60, 0.20, 0.15),
        "rock":    (0.34, 0.08, 0.16, 0.12),
        "foliage": (0.05, 0.18, 0.12, 0.16),
    }),
    "B-close": (12.0, {
        "water": (0.55, 0.55, 0.20, 0.15),
        "rock":  (0.80, 0.25, 0.14, 0.15),
        "wood":  (0.10, 0.55, 0.12, 0.15),
    }),
}

# class anchors in sRGB; nearest-anchor classification is a coarse but stable read of composition
ANCHORS = {
    "water":   (0.22, 0.72, 0.56),
    "rock":    (0.55, 0.57, 0.55),
    "wood":    (0.45, 0.29, 0.21),
    "foliage": (0.30, 0.48, 0.24),
    "sand":    (0.64, 0.66, 0.56),
    "dark":    (0.15, 0.15, 0.15),
}

# thresholds mirror RUBRIC.md Q1-Q5
THRESH = {
    "dE": (10.0, 16.0),
    "area": (0.08, 0.12),
    "luma_mean": (0.08, 0.12),
    "luma_std": (0.06, 0.09),
    "detail": (0.6, 1.8, 0.4, 2.4),
}


def load(path: Path) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-vf", f"scale={W}:{H}:flags=area",
         "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.uint8).reshape(H, W, 3).astype(np.float32) / 255.0


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


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def detail(rgb: np.ndarray) -> float:
    g = np.gradient(luma(rgb))
    return float(np.mean(np.sqrt(g[0] ** 2 + g[1] ** 2)))


def classify(rgb: np.ndarray) -> np.ndarray:
    lab = to_lab(rgb).reshape(-1, 3)
    names = list(ANCHORS)
    anchors = np.array([ANCHORS[n] for n in names], dtype=np.float32).reshape(1, -1, 3)
    a_lab = to_lab(anchors).reshape(-1, 3)
    d = ((lab[:, None, :] - a_lab[None, :, :]) ** 2).sum(-1)
    return np.bincount(d.argmin(1), minlength=len(names)) / lab.shape[0]


def reference_frame(t: float, path: Path) -> None:
    if path.exists():
        return
    subprocess.run(["ffmpeg", "-v", "error", "-ss", str(t), "-i", str(VIDEO), "-frames:v", "1",
                    "-vf", f"scale={W}:{H}", "-y", str(path)], check=True)


def measure(name: str, t: float, patches: dict, do_render: bool) -> dict:
    ref_path = OUT / f"ref-{name}.png"
    own_path = OUT / f"own-{name}.png"
    reference_frame(t, ref_path)
    if do_render:
        subprocess.run([sys.executable, str(HERE / "render.py"), "shot", str(SRC), str(t),
                        str(own_path), "960", "540"], check=True)
    ref = load(ref_path)
    own = load(own_path)

    ref_lab, own_lab = to_lab(ref), to_lab(own)
    patches_out = {}
    for pname, (x, y, w, h) in patches.items():
        x0, y0 = int(x * W), int(y * H)
        x1, y1 = int((x + w) * W), int((y + h) * H)
        d = float(np.linalg.norm(ref_lab[y0:y1, x0:x1].mean((0, 1)) - own_lab[y0:y1, x0:x1].mean((0, 1))))
        patches_out[pname] = round(d, 2)

    ref_cls, own_cls = classify(ref), classify(own)
    areas = {n: round(float(o - r), 3) for n, r, o in zip(ANCHORS, ref_cls, own_cls)}

    lr, lo = float(luma(ref).mean()), float(luma(own).mean())
    sr, so = float(luma(ref).std()), float(luma(own).std())
    dr, do = detail(ref), detail(own)

    return {
        "checkpoint": name, "time": t,
        "patches_dE": patches_out,
        "area_delta": areas,
        "luma": {"ref": round(lr, 3), "own": round(lo, 3), "d_mean": round(abs(lo - lr), 3),
                 "d_std": round(abs(so - sr), 3)},
        "detail": {"ref": round(dr, 4), "own": round(do, 4), "ratio": round(do / max(dr, 1e-6), 3)},
    }


def motion_checks() -> dict:
    """Q6/Q7: the cut exists and the cove pushes in."""
    out = {}
    a, b = OUT / "own-A.png", OUT / "own-B-wide.png"
    if a.exists() and b.exists():
        out["cut_diff"] = round(float(np.abs(load(a) - load(b)).mean()), 3)
    for t, name in ((4.0, "zoom-start"), (8.0, "zoom-end")):
        path = OUT / f"own-{name}.png"
        subprocess.run([sys.executable, str(HERE / "render.py"), "shot", str(SRC), str(t),
                        str(path), "960", "540"], check=True)
        cls = classify(load(path))
        out[name] = round(float(cls[list(ANCHORS).index("water")]), 3)
    out["zoom_delta"] = round(out["zoom-end"] - out["zoom-start"], 3)
    out["Q7"] = out["zoom_delta"] >= 0.08
    out["Q6"] = out.get("cut_diff", 0) > 0.10
    return out


def verdict(r: dict) -> dict:
    ok = all(v <= THRESH["dE"][0] for v in r["patches_dE"].values())
    ok &= all(abs(v) <= THRESH["area"][0] for v in r["area_delta"].values())
    ok &= r["luma"]["d_mean"] <= THRESH["luma_mean"][0]
    ok &= r["luma"]["d_std"] <= THRESH["luma_std"][0]
    lo, hi, _, _ = THRESH["detail"]
    ok &= lo <= r["detail"]["ratio"] <= hi
    return {"pass": bool(ok)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--motion", action="store_true")
    args = ap.parse_args()

    results = []
    for name, (t, patches) in CHECKPOINTS.items():
        if not (OUT / f"own-{name}.png").exists() and not args.render:
            print(f"missing {OUT / f'own-{name}.png'}; run with --render", file=sys.stderr)
            return 2
        r = measure(name, t, patches, args.render)
        r["verdict"] = verdict(r)
        results.append(r)

    payload = {"checkpoints": results}
    if args.motion:
        payload["motion"] = motion_checks()
    print(json.dumps(payload, indent=2) if args.json else _table(results))
    return 0 if all(r["verdict"]["pass"] for r in results) else 1


def _table(results: list[dict]) -> str:
    lines = []
    for r in results:
        lines.append(f"[{r['checkpoint']}] t={r['time']}")
        lines.append("  dE    " + "  ".join(f"{k}={v}" for k, v in r["patches_dE"].items()))
        lines.append("  areas " + "  ".join(f"{k}={v:+.2f}" for k, v in r["area_delta"].items()))
        lines.append(f"  luma  mean {r['luma']['ref']}->{r['luma']['own']} (d={r['luma']['d_mean']}), "
                     f"std d={r['luma']['d_std']}")
        lines.append(f"  detail ratio {r['detail']['ratio']}")
        lines.append(f"  verdict {'PASS' if r['verdict']['pass'] else 'FAIL'}")
    return "\n".join(lines)


if __name__ == "__main__":
    sys.exit(main())
