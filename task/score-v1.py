#!/usr/bin/env python3
"""Acceptance check for the creek recreation.

Compares three of your renders against the reference frames in assets/ using the rubric in TASK.md.

Usage:
  python3 tools/score.py --own-dir verify

Expected files: verify/t2.png, verify/t6.png, verify/t12.png (any size, 16:9).
Requires numpy and ffmpeg on PATH.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
W, H = 320, 180

# checkpoint -> (reference frame, own file, patches (x, y, w, h) in fractions)
CHECKPOINTS = {
    "A": ("assets/ref-t2.0.png", "t2.png", {
        "water": (0.42, 0.40, 0.20, 0.20),
        "wood":  (0.05, 0.25, 0.15, 0.20),
        "sand":  (0.72, 0.20, 0.14, 0.15),
        "grass": (0.86, 0.05, 0.11, 0.13),
    }),
    "B-wide": ("assets/ref-t6.0.png", "t6.png", {
        "water":   (0.45, 0.60, 0.20, 0.15),
        "rock":    (0.34, 0.08, 0.16, 0.12),
        "foliage": (0.05, 0.18, 0.12, 0.16),
    }),
    "B-close": ("assets/ref-t12.0.png", "t12.png", {
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
    anchors = to_lab(np.array([ANCHORS[n] for n in names], dtype=np.float32).reshape(1, -1, 3)).reshape(-1, 3)
    d = ((lab[:, None, :] - anchors[None, :, :]) ** 2).sum(-1)
    return np.bincount(d.argmin(1), minlength=len(names)) / lab.shape[0]


def check(name: str, ref_rel: str, own_name: str, patches: dict, own_dir: Path) -> bool:
    ref_path, own_path = ROOT / ref_rel, own_dir / own_name
    if not own_path.exists():
        print(f"[{name}] missing {own_path}")
        return False
    ref, own = load(ref_path), load(own_path)
    ref_lab, own_lab = to_lab(ref), to_lab(own)

    ok = True
    print(f"[{name}]")
    for pname, (x, y, w, h) in patches.items():
        x0, y0 = int(x * W), int(y * H)
        x1, y1 = int((x + w) * W), int((y + h) * H)
        de = float(np.linalg.norm(ref_lab[y0:y1, x0:x1].mean((0, 1)) - own_lab[y0:y1, x0:x1].mean((0, 1))))
        good = de <= DE_MAX
        ok &= good
        print(f"  Q1 {pname:8} dE {de:5.1f}  {'ok' if good else 'FAIL'}")

    doc, ooc = classify(ref), classify(own)
    for cls, r, o in zip(ANCHORS, doc, ooc):
        d = float(o - r)
        good = abs(d) <= AREA_MAX
        ok &= good
        print(f"  Q2 {cls:8} {r:.2f} -> {o:.2f}  ({d:+.2f}) {'ok' if good else 'FAIL'}")

    lm, ls = abs(float(luma(own).mean() - luma(ref).mean())), abs(float(luma(own).std() - luma(ref).std()))
    ok &= lm <= LUMA_MAX and ls <= LUMA_STD_MAX
    print(f"  Q3 luma mean diff {lm:.3f} {'ok' if lm <= LUMA_MAX else 'FAIL'}")
    print(f"  Q4 luma std  diff {ls:.3f} {'ok' if ls <= LUMA_STD_MAX else 'FAIL'}")

    ratio = detail(own) / max(detail(ref), 1e-6)
    good = DETAIL_RANGE[0] <= ratio <= DETAIL_RANGE[1]
    ok &= good
    print(f"  Q5 detail ratio   {ratio:.3f} {'ok' if good else 'FAIL'}")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--own-dir", default="verify")
    args = ap.parse_args()
    own_dir = (ROOT / args.own_dir).resolve()
    results = [check(n, r, o, p, own_dir) for n, (r, o, p) in CHECKPOINTS.items()]
    print("\nRESULT:", "PASS" if all(results) else "FAIL")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
