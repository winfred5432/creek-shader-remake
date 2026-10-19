#!/usr/bin/env python3
"""Render final.glsl with headless Chromium (WebGL2).

Usage:
  python3 tools/render.py stills --times 2 6 12 --out verify --width 1280 --height 720
  python3 tools/render.py video --out verify/render.mp4 --width 1280 --height 720 --fps 24 --duration 14.2
  python3 tools/render.py preview --times 2 6 12 --out /tmp/preview

work.glsl is bundled into final.glsl before rendering, so every delivered image comes
from the delivered shader.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import subprocess
import sys
import time
from pathlib import Path

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / ".claude/skills/shader-art-coding"

HTML = """<!doctype html><html><body style="margin:0;background:#000;overflow:hidden">
<canvas id="c"></canvas>
<script>
const canvas = document.getElementById('c');
const SHADER_SRC = __SHADER_JSON__;
const gl = canvas.getContext('webgl2', {antialias: false, preserveDrawingBuffer: true, alpha: false});
window.error = null;
window.ready = false;
if (!gl) { window.error = 'no webgl2'; }
else {
  const vsrc = `#version 300 es
  in vec2 p;
  void main() { gl_Position = vec4(p, 0.0, 1.0); }`;
  const fsrc = `#version 300 es
precision highp float;
precision highp int;
uniform vec3 iResolution;
uniform float iTime;
uniform int iFrame;
out vec4 fragColor;` + SHADER_SRC + `
void main() { mainImage(fragColor, gl_FragCoord.xy); }`;
  function compile(type, src) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }
  try {
    const prog = gl.createProgram();
    gl.attachShader(prog, compile(gl.VERTEX_SHADER, vsrc));
    gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, fsrc));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
    gl.useProgram(prog);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, 'p');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    window.uRes = gl.getUniformLocation(prog, 'iResolution');
    window.uTime = gl.getUniformLocation(prog, 'iTime');
    window.uFrame = gl.getUniformLocation(prog, 'iFrame');
    window.ready = true;
  } catch (e) { window.error = String(e); }
}
window.resize = (w, h) => { canvas.width = w; canvas.height = h; };
window.drawFrame = (t, frame) => {
  gl.viewport(0, 0, canvas.width, canvas.height);
  gl.uniform3f(window.uRes, canvas.width, canvas.height, 1.0);
  gl.uniform1f(window.uTime, t);
  gl.uniform1i(window.uFrame, frame);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  gl.finish();
  return canvas.toDataURL('image/png');
};
</script></body></html>"""


def bundle() -> None:
    subprocess.run([sys.executable, str(SKILL / "scripts/glsl_tools.py"), "bundle",
                    "work.glsl", "-o", "final.glsl"], cwd=ROOT, check=True)


async def render_jobs(shader: str, jobs: list[tuple[Path, float, int]], width: int, height: int) -> None:
    pw = await async_playwright().start()
    browser = await pw.chromium.launch(args=[
        "--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist",
        "--disable-gpu-vsync", "--disable-frame-rate-limit",
    ])
    page = await browser.new_page(viewport={"width": 320, "height": 180})
    page.set_default_timeout(180_000)
    await page.set_content(HTML.replace("__SHADER_JSON__", json.dumps(shader)))
    err = await page.evaluate("window.error")
    if err:
        raise RuntimeError(err)
    await page.evaluate(f"window.resize({width},{height})")
    for p in jobs:
        p[0].parent.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    for i, (path, t, frame) in enumerate(jobs):
        data = await page.evaluate(f"window.drawFrame({t:.9f}, {frame})")
        path.write_bytes(base64.b64decode(data.split(",", 1)[1]))
        if len(jobs) > 20 and i % 24 == 0:
            print(f"  {i}/{len(jobs)} frames  {time.time() - t0:.1f}s", flush=True)
    await browser.close()
    await pw.stop()
    print(f"rendered {len(jobs)} image(s) in {time.time() - t0:.1f}s")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["stills", "video", "preview", "probe"])
    ap.add_argument("--times", type=float, nargs="*", default=[2.0, 6.0, 12.0])
    ap.add_argument("--out", default="verify")
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--height", type=int, default=720)
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--duration", type=float, default=14.1667)
    ap.add_argument("--start", type=float, default=0.0)
    ap.add_argument("--no-bundle", action="store_true")
    ap.add_argument("--png-dir", default="/tmp/_frames")
    args = ap.parse_args()

    if not args.no_bundle:
        bundle()
    final = (ROOT / "final.glsl").read_text(encoding="utf-8")

    if args.mode in ("stills", "preview", "probe"):
        out = Path(args.out)
        jobs = []
        for t in args.times:
            if args.mode == "probe":
                path = Path("/tmp") / f"probe_t{t:g}.png"
            else:
                path = out / f"t{t:g}.png"
            jobs.append((path, t, int(round(t * args.fps))))
        asyncio.run(render_jobs(final, jobs, args.width, args.height))
        for path, _, _ in jobs:
            print(f"  -> {path}")
        return 0

    png_dir = Path(args.png_dir)
    if png_dir.exists():
        for p in png_dir.glob("f*.png"):
            p.unlink()
    count = int(round(args.duration * args.fps)) + 1
    jobs = [(png_dir / f"f{i:04d}.png", args.start + i / args.fps, i) for i in range(count)]
    print(f"rendering {count} frames at {args.width}x{args.height} to {png_dir}")
    asyncio.run(render_jobs(final, jobs, args.width, args.height))
    out_video = Path(args.out)
    out_video.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(args.fps),
                    "-i", str(png_dir / "f%04d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p",
                    "-crf", "16", "-preset", "medium", "-r", str(args.fps), str(out_video)], check=True)
    info = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                           "stream=width,height,r_frame_rate,nb_frames:format=duration",
                           "-of", "default=nw=1", str(out_video)], capture_output=True, text=True)
    print(info.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
