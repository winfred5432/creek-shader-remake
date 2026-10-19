#!/usr/bin/env python3
"""Offscreen renderer for Shadertoy-style GLSL through headless Chrome.

Two modes:
  render.py daemon                 watch .queue/ and render requests (needs full disk access)
  render.py shot SRC T OUT [W H]   enqueue one frame and wait for it

The daemon exists because Chrome writes outside the workspace; starting it once keeps every
later render free of approval prompts.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
QUEUE = HERE / ".queue"
CACHE = HERE / ".cache"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

POLL_S = 0.2          # queue poll interval; renders take ~2 s, so this is under 10% overhead
WAIT_S = 120.0        # per-shot client wait; well above the slowest observed render
BUDGET_MS = 2000      # virtual time granted before the screenshot fires

PAGE = """<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;background:#000;overflow:hidden}canvas{display:block}</style>
<canvas id="c"></canvas><script>
const SRC = __SRC__;
const W = __W__, H = __H__, T = __T__, FRAME = __FRAME__;
const cv = document.getElementById('c'); cv.width = W; cv.height = H;
const gl = cv.getContext('webgl2', { preserveDrawingBuffer: true, antialias: false });
const VS = `#version 300 es
in vec2 pos; void main() { gl_Position = vec4(pos, 0.0, 1.0); }`;
function sh(type, src) {
  const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
  return { s, ok: gl.getShaderParameter(s, gl.COMPILE_STATUS), log: gl.getShaderInfoLog(s) || '' };
}
const vs = sh(gl.VERTEX_SHADER, VS);
if (!vs.ok) { document.title = 'ERR:vs ' + vs.log; }
const fs = sh(gl.FRAGMENT_SHADER, SRC);
if (!fs.ok) { document.title = 'ERR:fs ' + fs.log.replace(/\\n/g, ' | '); }
const p = gl.createProgram(); gl.attachShader(p, vs.s); gl.attachShader(p, fs.s);
gl.bindAttribLocation(p, 0, 'pos'); gl.linkProgram(p);
if (!gl.getProgramParameter(p, gl.LINK_STATUS)) document.title = 'ERR:link ' + gl.getProgramInfoLog(p);
const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf);
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
gl.useProgram(p); gl.viewport(0, 0, W, H);
for (const [k, v] of Object.entries({ iResolution: [W, H, 1], iTime: T, iFrame: FRAME })) {
  const loc = gl.getUniformLocation(p, k); if (!loc) continue;
  if (Array.isArray(v)) gl.uniform3f(loc, ...v); else if (k === 'iFrame') gl.uniform1i(loc, v); else gl.uniform1f(loc, v);
}
gl.drawArrays(gl.TRIANGLES, 0, 3);
if (!document.title.startsWith('ERR')) document.title = 'ok';
</script>"""

PRELUDE = "#version 300 es\nprecision highp float;\nprecision highp int;\nuniform vec3 iResolution;\nuniform float iTime;\nuniform int iFrame;\nout vec4 outColor;\n"


def shot(src_path: Path, t: float, out: Path, w: int = 1280, h: int = 720) -> int:
    """Enqueue one frame, block until the daemon writes it."""
    QUEUE.mkdir(exist_ok=True)
    job = uuid.uuid4().hex[:12]
    out = out.resolve()
    tmp = out.with_name(f"{out.stem}-{job}.png")   # per-job name: a stale file can never be mistaken for this render
    err = tmp.with_suffix(".err")
    req = QUEUE / f"{job}.json"
    req.write_text(json.dumps({"glsl": str(src_path.resolve()), "t": t, "w": w, "h": h,
                               "out": str(tmp), "job": job}))
    deadline = time.time() + WAIT_S
    while time.time() < deadline:
        if tmp.exists():
            tmp.replace(out)
            return 0
        if err.exists():
            sys.stderr.write(err.read_text())
            return 1
        time.sleep(POLL_S)
    sys.stderr.write(f"timeout waiting for {out}\n")
    return 1


def render_one(req: dict) -> None:
    glsl = Path(req["glsl"]).read_text()
    body = PRELUDE + glsl + "\nvoid main() { vec4 c = vec4(0.0, 0.0, 0.0, 1.0); mainImage(c, gl_FragCoord.xy); outColor = c; }\n"
    page = (PAGE.replace("__SRC__", json.dumps(body))
                .replace("__W__", str(req["w"])).replace("__H__", str(req["h"]))
                .replace("__T__", repr(float(req["t"]))).replace("__FRAME__", str(int(round(req["t"] * 24.0)))))
    out = Path(req["out"])
    err = out.with_suffix(".err")
    html = CACHE / f"{req['job']}.html"
    html.write_text(page)
    cmd = [CHROME, "--headless=new", "--no-first-run", "--no-default-browser-check",
           "--disable-crash-reporter", "--hide-scrollbars", "--force-device-scale-factor=1",
           "--use-mock-keychain",
           f"--user-data-dir={CACHE / 'chrome-profile'}", f"--window-size={req['w']},{req['h']}",
           f"--virtual-time-budget={BUDGET_MS}", f"--screenshot={out}", f"file://{html}"]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
    if not out.exists() or out.stat().st_size == 0:
        err.write_text((res.stdout + res.stderr)[-4000:])
    else:
        err.unlink(missing_ok=True)


def daemon() -> None:
    QUEUE.mkdir(exist_ok=True)
    print("renderd ready", flush=True)
    while True:
        for req_path in sorted(QUEUE.glob("*.json")):
            if re.search(r"[^a-f0-9]", req_path.stem):
                continue
            try:
                req = json.loads(req_path.read_text())
            except json.JSONDecodeError:
                continue
            req_path.unlink(missing_ok=True)
            try:
                render_one(req)
            except Exception as exc:  # keep the daemon alive across single-shot failures
                Path(req["out"]).with_suffix(".err").write_text(f"{type(exc).__name__}: {exc}\n")
            print(f"rendered {req['job']} t={req['t']}", flush=True)
        time.sleep(POLL_S)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "daemon":
        daemon()
    elif len(sys.argv) > 4:
        sys.exit(shot(Path(sys.argv[2]), float(sys.argv[3]), Path(sys.argv[4]),
                      int(sys.argv[5]) if len(sys.argv) > 5 else 1280,
                      int(sys.argv[6]) if len(sys.argv) > 6 else 720))
    else:
        sys.exit("usage: render.py daemon | render.py shot SRC T OUT [W H]")
