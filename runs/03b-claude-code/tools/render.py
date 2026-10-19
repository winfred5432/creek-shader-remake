#!/usr/bin/env python3
"""Render a Shadertoy mainImage shader with headless Chromium (WebGL2).

  python3 tools/render.py final.glsl --times 2 6 12 --out verify/t{t:g}.png
  python3 tools/render.py final.glsl --video verify/render.mp4 --end 14.125

Video frames use pts = i / fps and iTime = pts, starting at pts 0.
"""

from __future__ import annotations

import argparse
import base64
import subprocess
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

PAGE = """<!doctype html><html><body style="margin:0;background:#000">
<canvas id="c"></canvas>
<script>
window.setup = function(src, w, h) {
  const c = document.getElementById('c');
  c.width = w; c.height = h;
  const gl = c.getContext('webgl2', {preserveDrawingBuffer: true, antialias: false});
  if (!gl) return 'no webgl2';
  const vs = `#version 300 es
in vec2 p; void main(){ gl_Position = vec4(p, 0.0, 1.0); }`;
  const fs = `#version 300 es
precision highp float; precision highp int;
uniform vec3 iResolution; uniform float iTime; uniform float iTimeDelta; uniform int iFrame;
uniform float iFrameRate; uniform vec4 iMouse; uniform vec4 iDate;
out vec4 outColor;
` + src + `
void main(){ vec4 c = vec4(0.0); mainImage(c, gl_FragCoord.xy); outColor = vec4(c.rgb, 1.0); }`;
  function sh(t, s) {
    const o = gl.createShader(t); gl.shaderSource(o, s); gl.compileShader(o);
    if (!gl.getShaderParameter(o, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(o));
    return o;
  }
  const pr = gl.createProgram();
  try { gl.attachShader(pr, sh(gl.VERTEX_SHADER, vs)); gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, fs)); }
  catch (e) { return String(e); }
  gl.linkProgram(pr);
  if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) return gl.getProgramInfoLog(pr);
  gl.useProgram(pr);
  const b = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, b);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 3,-1, -1,3]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(pr, 'p');
  gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  const u = n => gl.getUniformLocation(pr, n);
  window.R = {gl, w, h, buf: new Uint8Array(w * h * 4),
    uRes: u('iResolution'), uTime: u('iTime'), uDt: u('iTimeDelta'), uFrame: u('iFrame'),
    uRate: u('iFrameRate'), uMouse: u('iMouse'), uDate: u('iDate')};
  return 'ok:' + gl.getParameter(gl.RENDERER) + ' / ' + (gl.getExtension('WEBGL_debug_renderer_info') ?
    gl.getParameter(gl.getExtension('WEBGL_debug_renderer_info').UNMASKED_RENDERER_WEBGL) : '');
};
window.frame = function(t, f, fps) {
  const {gl, w, h, buf} = R;
  gl.viewport(0, 0, w, h);
  gl.uniform3f(R.uRes, w, h, 1.0); gl.uniform1f(R.uTime, t); gl.uniform1f(R.uDt, 1.0 / fps);
  gl.uniform1i(R.uFrame, f); gl.uniform1f(R.uRate, fps); gl.uniform4f(R.uMouse, 0, 0, 0, 0);
  gl.uniform4f(R.uDate, 2026, 9, 19, t);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, buf);
  let s = ''; const CH = 0x8000;
  for (let i = 0; i < buf.length; i += CH) s += String.fromCharCode.apply(null, buf.subarray(i, i + CH));
  return btoa(s);
};
</script></body></html>"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("shader")
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--height", type=int, default=720)
    ap.add_argument("--times", type=float, nargs="*", default=[])
    ap.add_argument("--out", default="out_t{t:g}.png", help="still path pattern, {t} = iTime")
    ap.add_argument("--video")
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--end", type=float, default=14.125)
    args = ap.parse_args()

    src = Path(args.shader).read_text(encoding="utf-8")
    w, h = args.width, args.height
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True, args=[
            "--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist", "--enable-unsafe-webgpu"])
        page = browser.new_page()
        page.set_content(PAGE)
        status = page.evaluate("([s, w, h]) => setup(s, w, h)", [src, w, h])
        print(status, file=sys.stderr)
        if not status.startswith("ok"):
            return 1

        def grab(t: float, f: int) -> bytes:
            data = base64.b64decode(page.evaluate("([t, f, r]) => frame(t, f, r)", [t, f, args.fps]))
            return data

        enc = lambda dst: ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba",
                           "-s", f"{w}x{h}", "-i", "-", "-vf", "vflip"]
        for t in args.times:
            dst = args.out.format(t=t)
            Path(dst).parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(enc(dst) + ["-frames:v", "1", dst], input=grab(t, int(round(t * args.fps))),
                           check=True)
            print(dst, file=sys.stderr)

        if args.video:
            n = int(round(args.end * args.fps)) + 1
            Path(args.video).parent.mkdir(parents=True, exist_ok=True)
            proc = subprocess.Popen(enc(args.video)[:6] + ["-framerate", str(args.fps)] + enc(args.video)[6:] +
                                    ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16",
                                     "-r", str(args.fps), args.video], stdin=subprocess.PIPE)
            for i in range(n):
                proc.stdin.write(grab(i / args.fps, i))
                if i % 48 == 0:
                    print(f"frame {i}/{n}", file=sys.stderr)
            proc.stdin.close()
            proc.wait()
            print(args.video, file=sys.stderr)
        browser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
