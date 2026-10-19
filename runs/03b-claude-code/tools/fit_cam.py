#!/usr/bin/env python3
"""Grid-search one camera keyframe of work.glsl against a reference still (probe tool, not shipped).

  python3 tools/fit_cam.py --time 12 --key 2

Rewrites ta<key>/d<key>/p<key>/y<key>/f<key> in a temp copy, renders at 320x180, and ranks by
layout agreement minus 0.01 * mean patch dE (score.py measures).
"""
from __future__ import annotations

import argparse
import base64
import itertools
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import render as R  # noqa: E402
import score as S  # noqa: E402

GT = ROOT / ".claude/skills/shader-art-coding/scripts/glsl_tools.py"


def variant(src: str, k: int, tx, tz, p, d, y, f) -> str:
    src = re.sub(rf"ta{k} = vec3\([^)]*\)", f"ta{k} = vec3({tx:.3f}, 0.0, {tz:.3f})", src)
    src = re.sub(rf"d{k} = [0-9.]+", f"d{k} = {d:.3f}", src)
    src = re.sub(rf"p{k} = radians\([^)]*\)", f"p{k} = radians({p:.3f})", src)
    src = re.sub(rf"y{k} = radians\([^)]*\)", f"y{k} = radians({y:.3f})", src)
    src = re.sub(rf"f{k} = [0-9.]+", f"f{k} = {f:.3f}", src)
    return src


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--time", type=float, default=12.0)
    ap.add_argument("--key", type=int, default=2)
    ap.add_argument("--grid", default="tx=1.0,1.6,2.2;tz=1.0,1.6;p=40,48,56;y=10,20,30;d=4.5,5.5,6.5;f=1.2,1.5")
    args = ap.parse_args()

    grid = {kv.split("=")[0]: [float(x) for x in kv.split("=")[1].split(",")] for kv in args.grid.split(";")}
    cp = next(c for c in S.CHECKPOINTS.values() if c[2] == args.time)
    ref = S.load(ROOT / cp[0])
    keep = S.hud_keep(args.time)
    ref_lab = S.to_lab(ref)
    src0 = (ROOT / "work.glsl").read_text()
    tmp = Path("/tmp/cr/fit.glsl")
    results = []
    with sync_playwright() as pw:
        page = pw.chromium.launch(headless=True, args=["--use-angle=metal", "--enable-gpu"]).new_page()
        page.set_content(R.PAGE)
        combos = list(itertools.product(grid["tx"], grid["tz"], grid["p"], grid["d"], grid["y"], grid["f"]))
        for i, (tx, tz, p, d, y, f) in enumerate(combos):
            tmp.write_text(variant(src0, args.key, tx, tz, p, d, y, f))
            code = subprocess.run([sys.executable, str(GT), "bundle", str(tmp)], capture_output=True, text=True).stdout
            st = page.evaluate("([s, w, h]) => setup(s, w, h)", [code, S.W, S.H])
            if not st.startswith("ok"):
                print(st)
                return 1
            raw = base64.b64decode(page.evaluate("([t, f, r]) => frame(t, f, r)", [args.time, 0, 24]))
            img = np.frombuffer(raw, np.uint8).reshape(S.H, S.W, 4)[::-1, :, :3].astype(np.float32) / 255.0
            lab = S.to_lab(img)
            des = []
            for (x, yy, w, h) in cp[3].values():
                x0, y0, x1, y1 = int(x * S.W), int(yy * S.H), int((x + w) * S.W), int((yy + h) * S.H)
                k = keep[y0:y1, x0:x1]
                des.append(float(np.linalg.norm(ref_lab[y0:y1, x0:x1][k].mean(0) - lab[y0:y1, x0:x1][k].mean(0))))
            lay = S.layout_agreement(ref, img, keep)
            results.append((lay - 0.01 * np.mean(des), lay, np.mean(des), (tx, tz, p, d, y, f)))
            if i % 20 == 0:
                print(f"{i}/{len(combos)}", file=sys.stderr)
    results.sort(reverse=True)
    for r in results[:8]:
        print(f"score {r[0]:.3f} layout {r[1]:.2f} dE {r[2]:.1f}  tx,tz,pitch,dist,yaw,focal = {r[3]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
