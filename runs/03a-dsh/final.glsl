// Creek remake: a stylized top-down creek and waterfall bay, rebuilt as a procedural SDF scene.
// Two shots: A (dock and creek, camera follows the boat upstream), B (fishing bay, slow then fast push-in).

// Library code below is bundled from shader-skills (MIT): https://github.com/gokayfem/shader-skills
// ---- shader-skills library: common ----
const float TAU = 6.28318530717959;
// Squared length.
float dot2(vec2 v) { return dot(v, v); }
float dot2(vec3 v) { return dot(v, v); }
// 2D rotation matrix. `rot2(a) * v` rotates v counter-clockwise by a radians. (cos, sin) is renormalized because GLSL ES leaves trig precision undefined: on SwiftShader and some mobile GPUs a raw cos/sin pair is far enough from unit length that rotations stop preserving distances.
mat2 rot2(float a) {
    vec2 cs = normalize(vec2(cos(a), sin(a)));
    return mat2(cs.x, cs.y, -cs.y, cs.x);
}

// ---- shader-skills library: hash ----
// PCG-style 1D integer hash.
uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
// 3D integer hash, three decorrelated outputs.
uvec3 pcg3d(uvec3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    return v;
}
// Map a uint to [0,1) using the top 24 bits, so the result can never round up to 1.0.
float uintToUnit(uint h) { return float(h >> 8u) * (1.0 / 16777216.0); }
vec2 uintToUnit(uvec2 h) { return vec2(h >> 8u) * (1.0 / 16777216.0); }
vec3 uintToUnit(uvec3 h) { return vec3(h >> 8u) * (1.0 / 16777216.0); }
vec4 uintToUnit(uvec4 h) { return vec4(h >> 8u) * (1.0 / 16777216.0); }
// Random float in [0,1) for an integer-valued input.
float hash11(float p) { return uintToUnit(pcgHash(uint(int(floor(p))))); }
// Random float in [0,1) for an integer-valued 2D input.
float hash12(vec2 p) {
    uvec2 q = uvec2(ivec2(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y)));
}
// Random float in [0,1) for an integer-valued 3D input.
float hash13(vec3 p) {
    uvec3 q = uvec3(ivec3(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y + pcgHash(q.z))));
}
// Random vec2 in [0,1)^2 for an integer-valued 2D input.
vec2 hash22(vec2 p) {
    ivec2 q = ivec2(floor(p));
    return uintToUnit(pcg3d(uvec3(q.x, q.y, 0x2545u))).xy;
}
// Random vec3 in [0,1)^3 for an integer-valued 3D input.
vec3 hash33(vec3 p) { return uintToUnit(pcg3d(uvec3(ivec3(floor(p))))); }

// ---- shader-skills library: noise ----
// Quintic fade 6t^5 - 15t^4 + 10t^3: C2-continuous interpolation weights for lattice noise.
vec2 quinticFade(vec2 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }
vec3 quinticFade(vec3 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }
// Derivative of quinticFade: 30 t^2 (t - 1)^2.
vec2 quinticFadeDeriv(vec2 f) { return 30.0 * f * f * (f * (f - 2.0) + 1.0); }
vec3 quinticFadeDeriv(vec3 f) { return 30.0 * f * f * (f * (f - 2.0) + 1.0); }
// 2D value noise with analytic derivatives. Returns vec3(value, d/dx, d/dy).
vec3 valueNoiseD(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = quinticFade(f), du = quinticFadeDeriv(f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    float k1 = b - a, k2 = c - a, k3 = a - b - c + d;
    return vec3(a + k1 * u.x + k2 * u.y + k3 * u.x * u.y,
                du * vec2(k1 + k3 * u.y, k2 + k3 * u.x));
}
// 2D value noise.
float valueNoise(vec2 p) { return valueNoiseD(p).x; }
// 3D value noise.
float valueNoise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    vec3 u = quinticFade(f);
    return mix(mix(mix(hash13(i + vec3(0, 0, 0)), hash13(i + vec3(1, 0, 0)), u.x),
                   mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y),
               mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x),
                   mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
// Unit gradient for a 2D lattice point.
vec2 latticeGradient(vec2 cell) {
    float a = TAU * hash12(cell);
    return vec2(cos(a), sin(a));
}
// 2D gradient (Perlin-style) noise with analytic derivatives. Returns vec3(value, d/dx, d/dy). Gradient noise has less grid-aligned blockiness than value noise. Prefer it for fBm.
vec3 gradientNoiseD(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = quinticFade(f), du = quinticFadeDeriv(f);
    vec2 ga = latticeGradient(i);
    vec2 gb = latticeGradient(i + vec2(1.0, 0.0));
    vec2 gc = latticeGradient(i + vec2(0.0, 1.0));
    vec2 gd = latticeGradient(i + vec2(1.0, 1.0));
    float va = dot(ga, f);
    float vb = dot(gb, f - vec2(1.0, 0.0));
    float vc = dot(gc, f - vec2(0.0, 1.0));
    float vd = dot(gd, f - vec2(1.0, 1.0));
    float k = va - vb - vc + vd;
    float value = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * k;
    vec2 deriv = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
               + du * (vec2(vb - va, vc - va) + u.yx * k);
    return vec3(value, deriv);
}
// 2D gradient noise.
float gradientNoise(vec2 p) { return gradientNoiseD(p).x; }
// Dot product of a hashed 3D gradient with the offset to its lattice corner.
float latticeGradDot(vec3 cell, vec3 corner, vec3 f) {
    vec3 g = hash33(cell + corner) * 2.0 - 1.0;
    return dot(g, f - corner);
}
// 3D gradient noise.
float gradientNoise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    vec3 u = quinticFade(f);
    return mix(mix(mix(latticeGradDot(i, vec3(0, 0, 0), f), latticeGradDot(i, vec3(1, 0, 0), f), u.x),
                   mix(latticeGradDot(i, vec3(0, 1, 0), f), latticeGradDot(i, vec3(1, 1, 0), f), u.x), u.y),
               mix(mix(latticeGradDot(i, vec3(0, 0, 1), f), latticeGradDot(i, vec3(1, 0, 1), f), u.x),
                   mix(latticeGradDot(i, vec3(0, 1, 1), f), latticeGradDot(i, vec3(1, 1, 1), f), u.x), u.y), u.z);
}
// 3D gradient noise with analytic derivatives. Returns vec4(value, d/dx, d/dy, d/dz); value equals gradientNoise(p). The trilinear blend is expanded as a polynomial in the fade weights, so the gradient is the same blend of the corner gradients plus the chain-rule term of the fade.
vec4 gradientNoiseD(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    vec3 u = quinticFade(f), du = quinticFadeDeriv(f);
    vec3 g000 = hash33(i) * 2.0 - 1.0;
    vec3 g100 = hash33(i + vec3(1, 0, 0)) * 2.0 - 1.0;
    vec3 g010 = hash33(i + vec3(0, 1, 0)) * 2.0 - 1.0;
    vec3 g110 = hash33(i + vec3(1, 1, 0)) * 2.0 - 1.0;
    vec3 g001 = hash33(i + vec3(0, 0, 1)) * 2.0 - 1.0;
    vec3 g101 = hash33(i + vec3(1, 0, 1)) * 2.0 - 1.0;
    vec3 g011 = hash33(i + vec3(0, 1, 1)) * 2.0 - 1.0;
    vec3 g111 = hash33(i + vec3(1, 1, 1)) * 2.0 - 1.0;
    float v000 = dot(g000, f);
    float v100 = dot(g100, f - vec3(1, 0, 0));
    float v010 = dot(g010, f - vec3(0, 1, 0));
    float v110 = dot(g110, f - vec3(1, 1, 0));
    float v001 = dot(g001, f - vec3(0, 0, 1));
    float v101 = dot(g101, f - vec3(1, 0, 1));
    float v011 = dot(g011, f - vec3(0, 1, 1));
    float v111 = dot(g111, f - vec3(1, 1, 1));
    // value = v000 + kx u.x + ky u.y + kz u.z + kxy u.x u.y + kyz u.y u.z + kzx u.z u.x + kxyz u.x u.y u.z
    float kx = v100 - v000, ky = v010 - v000, kz = v001 - v000;
    float kxy = v000 - v100 - v010 + v110;
    float kyz = v000 - v010 - v001 + v011;
    float kzx = v000 - v100 - v001 + v101;
    float kxyz = -v000 + v100 + v010 - v110 + v001 - v101 - v011 + v111;
    float value = v000 + kx * u.x + ky * u.y + kz * u.z
                + kxy * u.x * u.y + kyz * u.y * u.z + kzx * u.z * u.x + kxyz * u.x * u.y * u.z;
    vec3 grad = g000 + (g100 - g000) * u.x + (g010 - g000) * u.y + (g001 - g000) * u.z
              + (g000 - g100 - g010 + g110) * u.x * u.y
              + (g000 - g010 - g001 + g011) * u.y * u.z
              + (g000 - g100 - g001 + g101) * u.z * u.x
              + (-g000 + g100 + g010 - g110 + g001 - g101 - g011 + g111) * u.x * u.y * u.z
              + du * vec3(kx + kxy * u.y + kzx * u.z + kxyz * u.y * u.z,
                          ky + kxy * u.x + kyz * u.z + kxyz * u.x * u.z,
                          kz + kyz * u.y + kzx * u.x + kxyz * u.x * u.y);
    return vec4(value, grad);
}
const int FBM_MAX_OCTAVES = 12;
// Fractional Brownian motion over 2D gradient noise. Each octave is rotated to hide lattice alignment. persistence 0.5 is the classic look (H = 1). Lower is smoother, higher is rougher.
float fbm(vec2 p, int octaves, float lacunarity, float persistence) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        sum += amp * gradientNoise(p);
        norm += amp;
        amp *= persistence;
        p = lacunarity * (octaveRotation * p) + vec2(17.13, -3.71);
    }
    return 1.4 * sum / norm;
}
// 2D fBm with the usual defaults (lacunarity 2.01 so octave peaks never re-align, persistence 0.5).
float fbm(vec2 p, int octaves) { return fbm(p, octaves, 2.01, 0.5); }
// fBm over 3D gradient noise.
float fbm(vec3 p, int octaves, float lacunarity, float persistence) {
    const mat3 octaveRotation = mat3(0.00, 0.80, 0.60,
                                     -0.80, 0.36, -0.48,
                                     -0.60, -0.48, 0.64);
    float sum = 0.0, amp = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        sum += amp * gradientNoise(p);
        norm += amp;
        amp *= persistence;
        p = lacunarity * (octaveRotation * p) + vec3(17.13, -3.71, 5.29);
    }
    return sum / norm;
}
// Ridged multifractal: inverted |noise| creates sharp crests; each octave is weighted by the previous one, so detail gathers along ridges.
float ridgedFbm(vec2 p, int octaves) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 0.5, weight = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float n = 1.0 - abs(gradientNoise(p) * 1.4);
        n *= n;
        sum += amp * n * weight;
        norm += amp;
        weight = clamp(n * 2.0, 0.0, 1.0);
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + vec2(17.13, -3.71);
    }
    return sum / norm;
}
// Cellular (Worley/Voronoi) noise. Returns vec4(F1, F2, nearestCell.xy). F1 = distance to nearest feature point, F2 = second nearest. nearestCell is integer-valued, so hash it for per-cell randomness. jitter in [0,1] (0 = regular grid). Searches 3x3 cells. F2 can be slightly off at jitter 1.
vec4 voronoi(vec2 p, float jitter) {
    vec2 ip = floor(p), fp = fract(p);
    float f1 = 8.0, f2 = 8.0;
    vec2 nearest = vec2(0.0);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 g = vec2(float(i), float(j));
        vec2 r = g + jitter * hash22(ip + g) - fp;
        float d = dot(r, r);
        if (d < f1) { f2 = f1; f1 = d; nearest = ip + g; }
        else if (d < f2) { f2 = d; }
    }
    return vec4(sqrt(f1), sqrt(f2), nearest);
}

// ---- shader-skills library: sdf3d ----
// Sphere of radius r.
float sdSphere(vec3 p, float r) { return length(p) - r; }
// Axis-aligned box with half-extents b.
float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
// Box with rounded edges. The outer size stays b; r is the edge radius (r <= min(b)).
float sdRoundBox(vec3 p, vec3 b, float r) {
    vec3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}
// Torus in the XZ plane. t.x = major radius, t.y = tube radius.
float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
// Capsule: segment a-b swept by radius r.
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}
// Vertical capped cylinder from y = -h to y = +h, radius r.
float sdCylinder(vec3 p, float h, float r) {
    vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
// Unsigned distance to a 3D quadratic Bezier curve A-B-C; subtract a radius for a tube. Solves the closest-point cubic analytically. Falls back to a segment when the curve is straight.
float sdQuadraticBezier(vec3 pos, vec3 A, vec3 B, vec3 C) {
    vec3 a = B - A;
    vec3 b = A - 2.0 * B + C;
    vec3 c = a * 2.0;
    vec3 d = A - pos;
    float bb = dot(b, b);
    if (bb < 1e-10) {
        vec3 pa = pos - A, ca = C - A;
        return length(pa - ca * clamp(dot(pa, ca) / dot(ca, ca), 0.0, 1.0));
    }
    float kk = 1.0 / bb;
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float pp = ky - kx * kx;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * pp * pp * pp;
    float res;
    if (h >= 0.0) {
        h = sqrt(h);
        vec2 x = (vec2(h, -h) - q) / 2.0;
        vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
    } else {
        float z = sqrt(-pp);
        float v = acos(clamp(q / (pp * z * 2.0), -1.0, 1.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.7320508;
        vec2 t = clamp(vec2(m + m, -n - m) * z - kx, 0.0, 1.0);
        res = min(dot2(d + (c + b * t.x) * t.x), dot2(d + (c + b * t.y) * t.y));
    }
    return sqrt(res);
}

// ---- shader-skills library: sdf2d ----
// Axis-aligned rectangle with half-extents b.
float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
// Unsigned distance to segment a-b. Subtract a width to get a stroke.
float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}
// Arbitrary triangle p0, p1, p2 (any winding).
float sdTriangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
    vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
    vec2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                     vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                     vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}
// Vesica (lens): intersection of two circles of radius r whose centers sit at (+-d, 0). Points along Y. Needs d < r.
float sdVesica(vec2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r * r - d * d);
    return ((p.y - b) * d > p.x * b) ? length(p - vec2(0.0, b))
                                     : length(p - vec2(-d, 0.0)) - r;
}
// Unsigned distance to a quadratic Bezier curve A-B-C. Solves the closest-point cubic analytically. Falls back to a segment when the curve degenerates to a line. Float error in the cubic solve is about 1e-4.
float sdQuadraticBezier(vec2 pos, vec2 A, vec2 B, vec2 C) {
    vec2 a = B - A;
    vec2 b = A - 2.0 * B + C;
    vec2 c = a * 2.0;
    vec2 d = A - pos;
    float bb = dot(b, b);
    if (bb < 1e-10) return sdSegment(pos, A, C);
    float kk = 1.0 / bb;
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float pp = ky - kx * kx;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * pp * pp * pp;
    float res;
    if (h >= 0.0) {
        h = sqrt(h);
        vec2 x = (vec2(h, -h) - q) / 2.0;
        vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
    } else {
        float z = sqrt(-pp);
        float v = acos(clamp(q / (pp * z * 2.0), -1.0, 1.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.7320508;
        vec2 t = clamp(vec2(m + m, -n - m) * z - kx, 0.0, 1.0);
        res = min(dot2(d + (c + b * t.x) * t.x), dot2(d + (c + b * t.y) * t.y));
    }
    return sqrt(res);
}

// ---- shader-skills library: operators ----
// Smooth union (polynomial, C1). Blends where |a - b| < k, with a max bulge of k/4.
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ---- shader-skills library: raymarch ----
#define ZERO (min(iFrame, 0))
vec2 map(vec3 p);
const int RAYMARCH_MAX_STEPS = 256;
// Sphere-trace from ro along unit rd between tmin and tmax. Returns vec3(t, materialId, stepCount). t is -1 on a miss. The hit threshold grows with t (about one pixel's footprint), so distant surfaces don't burn steps. stepScale is 1 for exact or bound fields. Use < 1 (e.g. 0.6) when map() has Lipschitz > 1 (displacement, warps, twist).
vec3 raymarch(vec3 ro, vec3 rd, float tmin, float tmax, float stepScale) {
    float t = tmin;
    for (int i = ZERO; i < RAYMARCH_MAX_STEPS; i++) {
        vec2 h = map(ro + rd * t);
        if (abs(h.x) < max(0.0002 * t, 1e-5)) return vec3(t, h.y, float(i));
        t += h.x * stepScale;
        if (t > tmax) break;
    }
    return vec3(-1.0, -1.0, float(RAYMARCH_MAX_STEPS));
}
// Surface normal from 4 tetrahedral samples (cheaper than 6 central differences, and still centered). eps should scale with distance, e.g. 0.0005 * t: that filters distant detail and avoids sparkling.
vec3 calcNormal(vec3 p, float eps) {
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * map(p + e * eps).x;
    }
    return normalize(n);
}

// ---- shader-skills library: intersect ----
// Ray vs plane dot(p, n) + h = 0 (unit n). Returns t, which is negative when the plane is behind the ray or parallel to it.
float iPlane(vec3 ro, vec3 rd, vec3 n, float h) {
    float denom = dot(rd, n);
    if (abs(denom) < 1e-8) return -1.0;
    return -(dot(ro, n) + h) / denom;
}

// ---- shader-skills library: camera ----
// Camera-to-world matrix looking from ro toward ta, with roll in radians. Columns are (right, up, forward).
mat3 cameraMatrix(vec3 ro, vec3 ta, float roll) {
    vec3 w = normalize(ta - ro);
    vec3 up = vec3(sin(roll), cos(roll), 0.0);
    vec3 u = normalize(cross(w, up));
    vec3 v = cross(u, w);
    return mat3(u, v, w);
}
// Primary ray direction for screen point uv. focal is about 1.5-2.5 for natural framing (see fovToFocal).
vec3 cameraRay(mat3 cam, vec2 uv, float focal) {
    return normalize(cam * vec3(uv, focal));
}

// ---- shader-skills library: shading ----
// Energy-conserving wrap diffuse: light wraps past the terminator by w (0 = Lambert, 0.5 = soft).
float wrapDiffuse(vec3 n, vec3 l, float w) {
    return max((dot(n, l) + w) / ((1.0 + w) * (1.0 + w)), 0.0);
}
// Hemisphere light: sky color from above blended to ground color from below.
vec3 hemisphereLight(vec3 n, vec3 skyColor, vec3 groundColor) {
    return mix(groundColor, skyColor, 0.5 + 0.5 * n.y);
}
// Rim light from the viewing angle: strongest at silhouettes.
float rimLight(vec3 n, vec3 v, float power) {
    return pow(clamp(1.0 - dot(n, v), 0.0, 1.0), power);
}

// ---- shader-skills library: water ----
// Angular frequency sqrt(g*k*tanh(k*depth)) for finite-depth gravity waves. Nonpositive inputs are clamped.
float waterDispersion(float k, float depth, float gravity) {
    k = max(k,0.0);
    float e = exp(-2.0*k*max(depth,0.0));
    return sqrt(max(gravity,0.0)*k*(1.0-e)/(1.0+e));
}
// One sinusoidal wave: vec4(height, dh/dx, dh/dz, Laplacian). Direction is normalized internally; zero uses +X. wavelength > 0, amplitude in meters. footprint filters waves below 2-6 pixels; derivatives hold it constant.
vec4 waterWaveD(vec2 xz, float time, vec2 direction, float wavelength, float amplitude, float depth, float footprint) {
    float dl = length(direction);
    vec2 dir = dl>0.000001 ? direction/dl : vec2(1.0,0.0);
    float lengthM = max(wavelength,0.0001);
    float k = TAU/lengthM;
    float keep = smoothstep(2.0,6.0,lengthM/max(footprint,0.000001));
    float phase = k*dot(dir,xz)-waterDispersion(k,depth,9.81)*time;
    float h = amplitude*keep*sin(phase);
    return vec4(h, amplitude*keep*k*cos(phase)*dir, -k*k*h);
}
// Exact unpolarized dielectric Fresnel for a positive incident cosine and positive refractive indices. Returns 1 for total internal reflection. Caller chooses etaIncident/etaTransmitted for the ray's side.
float fresnelDielectric(float cosIncident, float etaIncident, float etaTransmitted) {
    float ci = clamp(abs(cosIncident),0.0,1.0);
    float ei = max(etaIncident,0.000001), et = max(etaTransmitted,0.000001);
    if (abs(ei-et)<0.0000001) return 0.0;
    float sinT2 = (ei*ei)/(et*et)*max(0.0,1.0-ci*ci);
    if (sinT2>=1.0) return 1.0;
    float ct = sqrt(max(0.0,1.0-sinT2));
    float rs = (ei*ci-et*ct)/max(ei*ci+et*ct,0.000001);
    float rp = (et*ci-ei*ct)/max(et*ci+ei*ct,0.000001);
    return clamp(0.5*(rs*rs+rp*rp),0.0,1.0);
}

// ---- shader-skills library: color ----
// Exact sRGB decode (EOTF): encoded [0,1] -> linear.
vec3 srgbToLinear(vec3 c) {
    c = max(c, 0.0);
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
// Exact sRGB encode (OETF): linear -> display [0,1]. Apply exactly once, after tonemapping. pow(c, 1/2.2) is visibly wrong near black (0.001 encodes to 0.013 here vs 0.043 with 2.2).
vec3 linearToSrgb(vec3 c) {
    c = max(c, 0.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

// ---- shader-skills library: tonemap ----
// Khronos PBR Neutral: leaves [0, ~0.76] almost untouched and compresses only highlights, preserving hue.
vec3 tonemapNeutral(vec3 c) {
    const float startCompression = 0.76;
    const float desaturation = 0.15;
    c = max(c, 0.0);
    float x = min(c.r, min(c.g, c.b));
    float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
    c -= offset;
    float peak = max(c.r, max(c.g, c.b));
    if (peak < startCompression) return c;
    const float d = 1.0 - startCompression;
    float newPeak = 1.0 - d * d / (peak + d - startCompression);
    c *= newPeak / peak;
    float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
    return mix(c, vec3(newPeak), g);
}

// ---- shader ----
const float CUT_TIME = 3.625;
const float WATER_Y = 0.0;
const vec3 SUN_DIR = normalize(vec3(-0.34, 0.80, -0.49));
const vec3 FILL_DIR = normalize(vec3(0.62, 0.50, 0.60));

// Art controls: change these to re-light or re-grade the scene.
const float SUN_INTENSITY = 1.20;
const float AMBIENT = 0.72;
const float EXPOSURE = 1.0;

// Material ids.
const float ID_TERRAIN = 1.0;
const float ID_WOOD = 2.0;
const float ID_ROOF = 3.0;
const float ID_ROCK = 4.0;
const float ID_FOLIAGE = 5.0;
const float ID_DECK = 6.0;
const float ID_BOAT = 7.0;
const float ID_BOAT_IN = 8.0;
const float ID_FIGURE = 9.0;
const float ID_HAT = 10.0;
const float ID_FALL = 11.0;
const float ID_LINE = 12.0;
const float ID_METAL = 13.0;
const float ID_PAINT = 14.0;
const float ID_ROD = 15.0;
const float ID_WOOD_HI_DUMMY = 16.0;
const float ID_ROCK_DK = 17.0;
const float ID_ROPE = 18.0;
const float ID_FLOWER = 19.0;
const float ID_ROCK_PALE = 20.0;

// Globals set once per frame.
int gShot;
float gTime;
vec3 gBoatPos;
float gBoatYaw;
vec3 gBobber;

// ------------------------------------------------------------------ palette

const vec3 C_SAND      = vec3(0.875, 0.888, 0.558);
const vec3 C_SAND_WET  = vec3(0.640, 0.690, 0.500);
const vec3 C_GRASS     = vec3(0.455, 0.575, 0.400);
const vec3 C_GRASS_HI  = vec3(0.555, 0.675, 0.470);
const vec3 C_FOLIAGE   = vec3(0.420, 0.535, 0.310);
const vec3 C_FOLIAGE_HI= vec3(0.486, 0.612, 0.322);
const vec3 C_ROCK      = vec3(0.427, 0.467, 0.459);
const vec3 C_ROCK_HI   = vec3(0.557, 0.592, 0.576);
const vec3 C_WATER_SH  = vec3(0.200, 0.776, 0.612);
const vec3 C_WATER_DP  = vec3(0.106, 0.478, 0.412);
const vec3 C_WOOD      = vec3(0.625, 0.468, 0.405);
const vec3 C_WOOD_HI   = vec3(0.690, 0.530, 0.450);
const vec3 C_WOOD_DK   = vec3(0.357, 0.259, 0.224);
const vec3 C_ROOF      = vec3(0.620, 0.440, 0.390);
const vec3 C_ROOF_HI   = vec3(0.705, 0.520, 0.450);
const vec3 C_HAT       = vec3(0.780, 0.665, 0.380);
const vec3 C_SKIN      = vec3(0.816, 0.667, 0.502);
const vec3 C_CLOTH     = vec3(0.631, 0.353, 0.267);
const vec3 C_DARK      = vec3(0.169, 0.196, 0.180);

// ------------------------------------------------------------------ helpers

float hashCell(vec2 p) { return hash12(floor(p + 0.5)); }

// Soft 2D shadow blob in world XZ. h is the caster height, blur the penumbra width.
float blobShadow(vec2 p, vec2 c, float radius, float h, float blur) {
    vec2 q = p - (c - SUN_DIR.xz * (h / SUN_DIR.y));
    float d = length(q) - radius;
    return smoothstep(blur, -blur, d);
}

// Rotate a world point into a local frame.
vec3 toLocal(vec3 p, vec3 c, float yaw) {
    vec3 q = p - c;
    float cs = cos(yaw), sn = sin(yaw);
    return vec3(cs * q.x - sn * q.z, q.y, sn * q.x + cs * q.z);
}

// ------------------------------------------------------------------ shot A world

float riverCenterA(float z) { return -0.65 + 0.55 * sin(z * 0.24) + 0.22 * sin(z * 0.53 + 1.7); }
float riverHalfA(float z) { return 2.70 + 2.50 * smoothstep(-1.5, 4.0, z) + 0.20 * sin(z * 0.85) + 0.10 * sin(z * 2.1 + 1.3); }

// Ground without the forest canopy.
float baseA(vec2 p) {
    float xc = riverCenterA(p.y);
    float hw = riverHalfA(p.y);
    float d = p.x - xc;
    float ad = abs(d);
    float bedNoise = 0.10 * fbm(p * 0.55 + vec2(1.7, 4.2), 3);
    float bankNoise = 0.10 * fbm(p * 0.30 + vec2(5.3, 2.1), 3) + 0.035 * fbm(p * 1.1, 2);
    float bed = -0.16 - 1.15 * smoothstep(hw, 0.0, ad) + bedNoise;
    float land = 0.12 + 0.22 * smoothstep(hw - 0.6, hw + 2.6, ad) + bankNoise;
    // The west bank is higher: it carries the deck and the cabin.
    land += 0.58 * smoothstep(hw + 0.2, hw + 3.4, -d);
    // The east bank climbs to the grass shelf and the woods.
    land += 0.34 * smoothstep(hw + 5.0, hw + 9.0, d);
    // West plateau flattens under the buildings.
    land = mix(land, 0.74 + 0.05 * fbm(p * 0.5, 2), smoothstep(-4.0, -7.0, d) * smoothstep(2.0, -2.0, p.y));
    float carve = smoothstep(hw + 1.0, hw - 0.5, ad);
    float lagoon = smoothstep(1.0, 0.05, length((p - vec2(4.2, 1.6)) / vec2(5.0, 3.3)));
    float lagoonBed = -0.24 - 0.55 * smoothstep(1.0, 0.1, length((p - vec2(4.2, 1.6)) / vec2(5.0, 3.3)));
    float h = mix(land, bed, carve);
    return mix(h, lagoonBed, lagoon * 0.9);
}

float forestMaskA(vec2 p) {
    float d = p.x - riverCenterA(p.y);
    float east = smoothstep(12.0, 15.0, d);
    float west = smoothstep(-10.5, -13.5, d);
    float north = smoothstep(-13.0, -17.0, p.y) * (0.3 + 0.7 * smoothstep(5.0, 10.0, abs(d)));
    float f = max(max(east, west), north);
    f *= 0.55 + 0.45 * smoothstep(0.15, 0.55, valueNoise(p * 0.28 + vec2(8.0, 3.0)));
    // Keep a clearing around the cabin and dock.
    f *= smoothstep(3.0, 7.0, length(p - vec2(-7.0, -5.0)));
    return clamp(f, 0.0, 1.0);
}

float canopyH(vec2 p) {
    vec4 v = voronoi(p * 0.52 + vec2(3.3, 9.1), 0.85);
    float crown = clamp(1.0 - v.x * 1.55, 0.0, 1.0);
    float n = 0.5 + 0.5 * valueNoise(p * 1.6 + v.zw * 3.0);
    return 1.1 + 1.35 * crown + 0.45 * n;
}

float terrainA(vec2 p) { return baseA(p) + forestMaskA(p) * canopyH(p); }

// ------------------------------------------------------------------ shot B world

const vec2 BAY_C = vec2(0.15, -0.55);

float bayRadius(float a) {
    return 5.55 + 0.85 * sin(a * 3.0 + 0.6) + 0.42 * sin(a * 5.0 - 1.1) + 0.22 * sin(a * 8.0 + 2.3);
}

float forestMaskB(vec2 p) {
    vec2 q = p - BAY_C;
    float r = length(q);
    float a = atan(q.y, q.x + 1e-5);
    float R = bayRadius(a);
    float f = smoothstep(R + 3.4, R + 5.8, r);
    f *= 0.55 + 0.45 * smoothstep(0.12, 0.6, valueNoise(p * 0.26 + vec2(2.0, 7.0)));
    // Dense woods on the west and east flanks, thinner behind the falls.
    f *= 0.60 + 0.40 * smoothstep(-0.6, 0.6, cos(a));
    return clamp(f, 0.0, 1.0);
}

float canopyHB(vec2 p) {
    vec4 v = voronoi(p * 0.60 + vec2(7.7, 1.3), 0.85);
    float crown = clamp(1.0 - v.x * 1.6, 0.0, 1.0);
    float n = 0.5 + 0.5 * valueNoise(p * 1.7 + v.zw * 4.0);
    return 1.0 + 1.55 * crown + 0.55 * n;
}

// Ground without the forest canopy.
float baseB(vec2 p) {
    vec2 q = p - BAY_C;
    float r = length(q);
    float a = atan(q.y, q.x + 1e-5);
    float R = bayRadius(a);
    float ripple = 0.16 * fbm(p * 0.75 + vec2(4.4, 8.8), 3);
    float bed = -0.16 - 1.55 * smoothstep(R, 0.0, r) - 0.55 * smoothstep(0.0, 4.0, q.y) + ripple * 0.4;
    float lip = smoothstep(R - 0.35, R + 0.25, r);
    float wallH = 2.55 + 0.55 * fbm(p * 0.42 + vec2(9.1, 3.2), 3)
                       + 0.30 * ridgedFbm(p * 0.55 + vec2(1.0, 6.0), 3);
    float wall = lip * wallH;
    float shelf = smoothstep(R + 1.3, R + 2.8, r) * (2.85 + 0.35 * fbm(p * 0.5 + vec2(3.3, 7.7), 3));
    float h = mix(bed, wall, smoothstep(R - 0.5, R + 0.9, r));
    h = mix(h, shelf, smoothstep(R + 0.6, R + 2.6, r));
    // The waterfall notch: a straight rock lip on the north rim.
    float notch = smoothstep(2.5, 1.2, abs(p.x + 0.55)) * smoothstep(-4.5, -5.4, p.y);
    h = mix(h, -0.12 - 0.30 * smoothstep(2.2, 0.0, abs(p.x + 0.55)), notch * 0.94);
    return h;
}

float terrainB(vec2 p) { return baseB(p) + forestMaskB(p) * canopyHB(p); }

// ------------------------------------------------------------------ scene A objects

float gableRoof(vec3 p, vec3 b, float h) {
    vec2 q = vec2(abs(p.x), p.y);
    float d2 = sdTriangle(q, vec2(-b.x, 0.0), vec2(b.x, 0.0), vec2(0.0, h));
    return max(d2, abs(p.z) - b.z);
}

vec2 mapTree(vec3 p, vec3 c, float s, float seed) {
    vec3 q = (p - c) / s;
    q.xz = rot2(seed * 2.3) * q.xz;
    float trunk = sdCapsule(q, vec3(0.0, 0.0, 0.0), vec3(0.08, 1.52, 0.04), 0.085);
    vec3 cq = q - vec3(0.0, 0.32, 0.0);
    float canopy = sdSphere(cq - vec3(0.0, 1.70, 0.0), 0.72);
    canopy = smin(canopy, sdSphere(cq - vec3(0.42, 1.38, 0.16), 0.52), 0.20);
    canopy = smin(canopy, sdSphere(cq - vec3(-0.38, 1.52, 0.22), 0.50), 0.20);
    canopy = smin(canopy, sdSphere(cq - vec3(0.10, 2.28, -0.10), 0.48), 0.20);
    canopy = smin(canopy, sdSphere(cq - vec3(0.15, 1.28, -0.42), 0.46), 0.18);
    canopy = smin(canopy, sdSphere(cq - vec3(0.68, 1.92, -0.38), 0.36), 0.14);
    canopy = smin(canopy, sdSphere(cq - vec3(-0.66, 2.02, -0.22), 0.35), 0.14);
    canopy = smin(canopy, sdSphere(cq - vec3(-0.10, 0.98, 0.58), 0.40), 0.14);
    canopy = smin(canopy, sdSphere(cq - vec3(0.62, 1.10, 0.30), 0.30), 0.12);
    canopy = smin(canopy, sdSphere(cq - vec3(-0.58, 1.12, 0.42), 0.29), 0.12);
    canopy = smin(canopy, sdSphere(cq - vec3(0.18, 2.72, -0.05), 0.36), 0.16);
    canopy = smin(canopy, sdSphere(cq - vec3(-0.30, 2.55, 0.28), 0.31), 0.14);
    canopy = smin(canopy, sdSphere(cq - vec3(0.38, 2.40, 0.30), 0.29), 0.14);
    canopy += 0.035 * fbm(q.xz * 5.0 + seed, 2);
    float d = min(trunk, canopy) * s;
    float id = (trunk < canopy) ? ID_WOOD : ID_FOLIAGE;
    return vec2(d, id);
}

float grassTuft(vec3 p, vec2 c) {
    float h = 0.28;
    float d = sdSphere(p - vec3(c.x, h, c.y), 0.20) + 0.03 * fbm(p.xz * 6.0, 2);
    d = min(d, sdSphere(p - vec3(c.x + 0.16, h + 0.07, c.y - 0.10), 0.14));
    d = min(d, sdSphere(p - vec3(c.x - 0.13, h + 0.05, c.y + 0.12), 0.13));
    return d;
}

vec2 mapAHouse(vec3 p) {
    vec3 q = p - vec3(-7.2, 0.0, -6.3);
    float wall = sdBox(q - vec3(0.0, 1.92, 0.0), vec3(2.95, 1.00, 2.15));
    float roof = gableRoof(vec3(q.z, q.y - 2.86, q.x), vec3(2.88, 0.0, 3.55), 2.10);
    float porch = sdBox(q - vec3(3.05, 0.99, 0.2), vec3(0.55, 0.07, 1.1));
    vec2 r = vec2(roof, ID_ROOF);
    if (wall < r.x) r = vec2(wall, ID_WOOD);
    if (porch < r.x) r = vec2(porch, ID_DECK);
    float eaveE = sdBox(q - vec3(3.55, 2.90, 0.0), vec3(0.07, 0.10, 2.88));
    float eaveW = sdBox(q - vec3(-3.55, 2.90, 0.0), vec3(0.07, 0.10, 2.88));
    float ridge = sdBox(q - vec3(0.0, 4.99, 0.0), vec3(3.55, 0.06, 0.10));
    if (ridge < r.x) r = vec2(ridge, ID_WOOD_HI_DUMMY);
    float eaveN = sdBox(q - vec3(0.0, 2.90, 2.88), vec3(3.55, 0.10, 0.07));
    float eaveS = sdBox(q - vec3(0.0, 2.90, -2.88), vec3(3.55, 0.10, 0.07));
    float eave = min(min(eaveE, eaveW), min(eaveN, eaveS));
    if (eave < r.x) r = vec2(eave, ID_WOOD_HI_DUMMY);
    return r;
}

vec2 mapADeck(vec3 p) {
    // Deck planks: a slab along the west bank that overhangs the water.
    float deck = sdBox(p - vec3(-7.5, 0.83, -3.0), vec3(4.3, 0.12, 4.6));
    vec2 r = vec2(deck, ID_DECK);
    // Fascia along the water edge, so the deck reads as a raised platform.
    float fascia = sdBox(p - vec3(-3.22, 0.74, -3.0), vec3(0.06, 0.14, 4.6));
    if (fascia < r.x) r = vec2(fascia, ID_WOOD);
    // Support posts standing in the shallows.
    for (int i = 0; i < 5; i++) {
        float z = -6.8 + float(i) * 2.10;
        float post = sdCylinder(p - vec3(-3.12, 0.35, z), 0.55, 0.12);
        if (post < r.x) r = vec2(post, ID_WOOD);
    }
    // Low rail and net posts along the water edge.
    float rail = sdBox(p - vec3(-3.30, 1.30, -3.0), vec3(0.05, 0.05, 4.6));
    if (rail < r.x) r = vec2(rail, ID_WOOD);
    for (int i = 0; i < 5; i++) {
        float z = -7.2 + float(i) * 2.10;
        float post = sdCylinder(p - vec3(-3.30, 1.05, z), 0.30, 0.055);
        if (post < r.x) r = vec2(post, ID_WOOD);
    }
    // A low back railing.
    float back = sdBox(p - vec3(-11.5, 1.30, -3.0), vec3(0.06, 0.06, 4.6));
    if (back < r.x) r = vec2(back, ID_WOOD);
    // Deck clutter: crates, barrel, fish trap, buoy, hose, bucket.
    float crate = sdBox(p - vec3(-4.55, 1.20, -2.55), vec3(0.38, 0.26, 0.38));
    if (crate < r.x) r = vec2(crate, ID_WOOD);
    float crate2 = sdBox(p - vec3(-5.75, 1.08, -3.15), vec3(0.22, 0.14, 0.22));
    if (crate2 < r.x) r = vec2(crate2, ID_WOOD);
    float barrel = sdCylinder(p - vec3(-9.55, 1.17, -1.95), 0.34, 0.27);
    if (barrel < r.x) r = vec2(barrel, ID_WOOD);
    float trap = sdRoundBox(p - vec3(-4.62, 1.10, -4.75), vec3(0.30, 0.16, 0.22), 0.06);
    if (trap < r.x) r = vec2(trap, ID_WOOD);
    float buoy = sdCylinder(p - vec3(-11.30, 1.04, -0.55), 0.16, 0.10);
    if (buoy < r.x) r = vec2(buoy, ID_PAINT);
    float hose = sdTorus(p - vec3(-10.45, 0.99, 0.55), vec2(0.26, 0.035));
    if (hose < r.x) r = vec2(hose, ID_LINE);
    float bucket = sdCylinder(p - vec3(-11.15, 1.04, -4.05), 0.18, 0.16);
    if (bucket < r.x) r = vec2(bucket, ID_WOOD);
    // Foreground props near the deck edge.
    float crateF = sdBox(p - vec3(-4.45, 1.22, 0.45), vec3(0.40, 0.28, 0.40));
    if (crateF < r.x) r = vec2(crateF, ID_WOOD);
    float barrelF = sdCylinder(p - vec3(-4.75, 1.20, 1.05), 0.34, 0.30);
    if (barrelF < r.x) r = vec2(barrelF, ID_WOOD);
    float trapF = sdRoundBox(p - vec3(-5.55, 1.10, 0.55), vec3(0.30, 0.16, 0.22), 0.06);
    if (trapF < r.x) r = vec2(trapF, ID_WOOD);
    float buoyF = sdCylinder(p - vec3(-3.65, 1.07, 1.20), 0.14, 0.09);
    if (buoyF < r.x) r = vec2(buoyF, ID_PAINT);
    // Net rails between the edge posts.
    for (int i = 0; i < 3; i++) {
        float ry = 1.02 + float(i) * 0.11;
        float net = sdBox(p - vec3(-3.30, ry, -3.0), vec3(0.02, 0.012, 4.6));
        if (net < r.x) r = vec2(net, ID_ROPE);
    }
    // Table with a potted plant against the cabin wall.
    float table = sdBox(p - vec3(-4.75, 1.12, -1.55), vec3(0.22, 0.10, 0.22));
    if (table < r.x) r = vec2(table, ID_WOOD);
    float pot = sdCylinder(p - vec3(-4.75, 1.34, -1.55), 0.10, 0.10);
    if (pot < r.x) r = vec2(pot, ID_WOOD);
    float plant = sdSphere(p - vec3(-4.75, 1.62, -1.55), 0.22) + 0.03 * fbm(p.xz * 5.0, 2);
    if (plant < r.x) r = vec2(plant, ID_FOLIAGE);
    return r;
}

vec2 mapAPiers(vec3 p) {
    vec2 r = vec2(1e9, ID_WOOD);
    // Left jetty, slightly angled toward the creek.
    {
        vec2 c = vec2(-2.55, -10.5);
        vec2 q = rot2(0.10) * (p.xz - c) + c;
        float b = sdBox(vec3(q.x, p.y, q.y) - vec3(c.x, 0.66, c.y), vec3(1.60, 0.11, 0.60));
        float beam = sdBox(vec3(q.x, p.y, q.y) - vec3(c.x, 0.50, c.y), vec3(1.55, 0.10, 0.50));
        if (b < r.x) r = vec2(b, ID_DECK);
        if (beam < r.x) r = vec2(beam, ID_WOOD);
        for (int i = 0; i < 2; i++) {
            for (int j = 0; j < 2; j++) {
                float bx = c.x + (float(i) * 2.0 - 1.0) * 1.45;
                float bz = c.y + (float(j) * 2.0 - 1.0) * 0.48;
                vec2 bp = rot2(-0.10) * (vec2(bx, bz) - c) + c;
                float post = sdCylinder(p - vec3(bp.x, 0.72, bp.y), 0.62, 0.13);
                if (post < r.x) r = vec2(post, ID_WOOD);
                float cap = sdSphere(p - vec3(bp.x, 1.36, bp.y), 0.13);
                if (cap < r.x) r = vec2(cap, ID_WOOD);
            }
        }
    }
    // Right jetty.
    {
        vec2 c = vec2(2.35, -10.5);
        vec2 q = rot2(-0.10) * (p.xz - c) + c;
        float b = sdBox(vec3(q.x, p.y, q.y) - vec3(c.x, 0.66, c.y), vec3(1.70, 0.11, 0.60));
        float beam = sdBox(vec3(q.x, p.y, q.y) - vec3(c.x, 0.50, c.y), vec3(1.65, 0.10, 0.50));
        if (b < r.x) r = vec2(b, ID_DECK);
        if (beam < r.x) r = vec2(beam, ID_WOOD);
        for (int i = 0; i < 2; i++) {
            for (int j = 0; j < 2; j++) {
                float bx = c.x + (float(i) * 2.0 - 1.0) * 1.52;
                float bz = c.y + (float(j) * 2.0 - 1.0) * 0.48;
                vec2 bp = rot2(0.10) * (vec2(bx, bz) - c) + c;
                float post = sdCylinder(p - vec3(bp.x, 0.72, bp.y), 0.62, 0.13);
                if (post < r.x) r = vec2(post, ID_WOOD);
                float cap = sdSphere(p - vec3(bp.x, 1.36, bp.y), 0.13);
                if (cap < r.x) r = vec2(cap, ID_WOOD);
            }
        }
    }
    // Pale ropes sagging across the gap, one above the other.
    float rope1 = sdQuadraticBezier(p, vec3(-0.95, 1.15, -10.35), vec3(-0.15, 0.72, -10.35), vec3(0.62, 1.15, -10.35)) - 0.030;
    float rope2 = sdQuadraticBezier(p, vec3(-0.95, 0.86, -10.35), vec3(-0.15, 0.58, -10.35), vec3(0.62, 0.86, -10.35)) - 0.022;
    float rope = min(rope1, rope2);
    if (rope < r.x) r = vec2(rope, ID_ROPE);
    return r;
}

vec2 mapARocks(vec3 p) {
    vec2 r = vec2(1e9, ID_ROCK);
    vec3 c1 = vec3(8.1, 0.80, -6.6); float r1 = 1.45;
    vec3 c2 = vec3(5.5, 0.55, 1.2);  float r2 = 1.00;
    vec3 c3 = vec3(12.9, 0.95, -7.8); float r3 = 1.55;
    vec3 c4 = vec3(3.9, 0.30, -7.6); float r4 = 0.68;
    vec3 c5 = vec3(2.2, 0.25, 3.0);  float r5 = 0.42;
    vec3 c6 = vec3(-5.6, 0.55, -11.0); float r6 = 0.9;
    float d1 = sdSphere(p - c1, r1) + 0.10 * fbm(p.xz * 1.3 + vec2(p.y * 0.7, 1.0), 3);
    float d2 = sdSphere(p - c2, r2) + 0.08 * fbm(p.xz * 1.7 + vec2(p.y * 0.7, 2.0), 3);
    float d3 = sdSphere(p - c3, r3) + 0.12 * fbm(p.xz * 1.1 + vec2(p.y * 0.7, 3.0), 3);
    float d4 = sdSphere(p - c4, r4) + 0.06 * fbm(p.xz * 2.0 + vec2(p.y * 0.7, 4.0), 2);
    float d5 = sdSphere(p - c5, r5) + 0.04 * fbm(p.xz * 2.4 + vec2(p.y * 0.7, 13.0), 2);
    float d6 = sdSphere(p - c6, r6) + 0.08 * fbm(p.xz * 1.5 + vec2(p.y * 0.7, 14.0), 2);
    return vec2(min(min(min(d1, d2), min(d3, d4)), min(d5, d6)), ID_ROCK);
}

// ------------------------------------------------------------------ boat (both shots)

float gBoatScale;
vec2 mapBoat(vec3 p) {
    vec3 q = toLocal(p, gBoatPos, gBoatYaw) / gBoatScale;
    vec2 v2 = vec2(q.x, q.z);
    float outer2 = sdVesica(v2, 2.05, 1.42);
    float hull = max(outer2 - 0.03, abs(q.y - 0.30) - 0.30);
    float cavity = max(sdVesica(v2, 1.83, 1.42), 0.17 - q.y);
    hull = max(hull, -cavity);
    float rim = max(abs(outer2) - 0.070, abs(q.y - 0.57) - 0.045);
    vec2 r = vec2(hull, ID_BOAT);
    if (rim < r.x) r = vec2(rim, ID_WOOD_HI_DUMMY);
    // Longitudinal floorboards and cross ribs.
    float boards = 1e9;
    for (int i = 0; i < 4; i++) {
        float bx = -0.42 + float(i) * 0.28;
        boards = min(boards, sdBox(q - vec3(bx, 0.205, 0.0), vec3(0.055, 0.018, 1.02)));
    }
    float ribs = 1e9;
    for (int i = 0; i < 5; i++) {
        float bz = -0.82 + float(i) * 0.42;
        ribs = min(ribs, sdBox(q - vec3(0.0, 0.225, bz), vec3(0.52, 0.035, 0.035)));
    }
    float floor = min(boards, ribs);
    if (floor < r.x) r = vec2(floor, ID_BOAT_IN);
    // Seats, bow deck and a round stern cushion.
    float seat1 = sdBox(q - vec3(0.0, 0.385, -0.50), vec3(0.62, 0.045, 0.16));
    float seat2 = sdBox(q - vec3(0.0, 0.385, 0.55), vec3(0.58, 0.045, 0.15));
    float bow = sdBox(q - vec3(0.0, 0.50, -1.30), vec3(0.36, 0.035, 0.24));
    float seats = min(min(seat1, seat2), bow);
    if (seats < r.x) r = vec2(seats, ID_WOOD_HI_DUMMY);
    float cushion = sdCylinder(q - vec3(0.0, 0.43, 0.98), 0.045, 0.34);
    if (cushion < r.x) r = vec2(cushion, ID_HAT);
    // Stern motor / creel.
    float motor = sdCylinder(q - vec3(0.0, 0.66, 1.18), 0.20, 0.26);
    float cap = sdCylinder(q - vec3(0.0, 0.92, 1.18), 0.08, 0.30);
    float mot = min(motor, cap);
    if (mot < r.x) r = vec2(mot, ID_HAT);
    // Oar: long shaft with a broad blade.
    float oar = sdCapsule(q, vec3(0.42, 0.50, 0.42), vec3(1.78, 0.16, -0.38), 0.050);
    float blade = sdBox(q - vec3(1.88, 0.14, -0.44), vec3(0.26, 0.018, 0.11));
    float o = min(oar, blade);
    if (o < r.x) r = vec2(o, ID_WOOD);
    // Angler: body, shoulders, head, arm.
    float body = sdCapsule(q, vec3(0.0, 0.40, -0.25), vec3(0.0, 0.92, -0.15), 0.27);
    float shoulders = sdCapsule(q, vec3(-0.25, 0.86, -0.13), vec3(0.25, 0.86, -0.13), 0.16);
    float head = sdSphere(q - vec3(0.02, 1.06, -0.17), 0.20);
    float fig = min(min(body, shoulders), head);
    if (fig < r.x) r = vec2(fig, ID_FIGURE);
    float hatCrown = sdCylinder(q - vec3(0.02, 1.20, -0.12), 0.14, 0.19);
    float hatBrim = sdCylinder(q - vec3(0.02, 1.07, -0.12), 0.028, 0.37);
    float hat = min(hatCrown, hatBrim);
    if (hat < r.x) r = vec2(hat, ID_HAT);
    float arm = sdCapsule(q, vec3(0.20, 0.80, -0.15), vec3(0.62, 0.94, -0.22), 0.075);
    if (arm < r.x) r = vec2(arm, ID_FIGURE);
    float grip = sdCapsule(q, vec3(0.48, 0.92, -0.20), vec3(0.70, 0.96, -0.28), 0.06);
    if (grip < r.x) r = vec2(grip, ID_FIGURE);
    // Fishing rod and line only in the bay shot.
    if (gShot == 1) {
        vec3 tipL = vec3(2.55, 2.45, 0.10);
        float rod = sdQuadraticBezier(q, vec3(0.60, 0.96, -0.20), vec3(1.60, 2.05, 0.00), tipL) - 0.010;
        if (rod < r.x) r = vec2(rod, ID_ROD);
        vec3 tipW = tipL * gBoatScale;
        vec3 a = gBoatPos + vec3(cos(gBoatYaw) * tipW.x + sin(gBoatYaw) * tipW.z, tipW.y,
                                 -sin(gBoatYaw) * tipW.x + cos(gBoatYaw) * tipW.z);
        vec3 b = gBobber;
        vec3 mid = 0.5 * (a + b) + vec3(0.0, -0.85, 0.0);
        float line = sdQuadraticBezier(p, a, mid, b) - 0.006;
        if (line < r.x) r = vec2(line, ID_LINE);
        float bob = sdSphere(p - gBobber, 0.075);
        if (bob < r.x) r = vec2(bob, ID_PAINT);
    }
    r.x *= gBoatScale;
    return r;
}


// ------------------------------------------------------------------ scene B objects

vec2 mapBRocks(vec3 p) {
    vec2 r = vec2(1e9, ID_ROCK);
    vec3 c1 = vec3(-4.35, 0.58, -1.05); float r1 = 0.90;
    vec3 c2 = vec3(4.35, 1.15, -3.55); float r2 = 1.05;
    vec3 c3 = vec3(2.05, 0.35, 2.55);  float r3 = 0.55;
    vec3 c4 = vec3(-0.45, 0.25, 2.10); float r4 = 0.38;
    vec3 c5 = vec3(6.9, 1.4, 0.3);      float r5 = 2.0;
    vec3 c8 = vec3(2.8, 0.55, 4.6);     float r8 = 1.8;
    vec3 c9 = vec3(5.0, 0.55, 4.8);     float r9 = 1.5;
    vec3 c6 = vec3(3.6, 0.7, -4.4);     float r6 = 1.15;
    vec3 q1 = p - c1; q1.xz = rot2(0.6) * q1.xz;
    float d1 = sdRoundBox(q1, vec3(0.95, 0.55, 0.75), 0.28) + 0.08 * fbm(p.xz * 1.2 + vec2(p.y * 0.7, 5.0), 3);
    float d2 = sdSphere(p - c2, r2) + 0.10 * fbm(p.xz * 1.4 + vec2(p.y * 0.7, 6.0), 3);
    float d3 = sdSphere(p - c3, r3) + 0.05 * fbm(p.xz * 1.8 + vec2(p.y * 0.7, 7.0), 2);
    float d4 = sdSphere(p - c4, r4) + 0.05 * fbm(p.xz * 2.2 + vec2(p.y * 0.7, 8.0), 2);
    float d5 = sdRoundBox(p - vec3(6.9, 1.55, 0.3), vec3(1.55, 2.15, 2.10), 0.55) + 0.14 * fbm(p.xz * 0.8 + vec2(p.y * 0.5, 9.0), 3);
    float d6 = sdSphere(p - c6, r6) + 0.10 * fbm(p.xz * 1.2 + vec2(p.y * 0.7, 10.0), 3);
    float d7 = sdSphere(p - vec3(5.4, 0.5, 4.2), 1.45) + 0.10 * fbm(p.xz * 1.1 + vec2(p.y * 0.6, 12.0), 2);
    float d8 = sdSphere(p - vec3(1.4, 0.45, 5.1), 1.65) + 0.10 * fbm(p.xz * 1.0 + vec2(p.y * 0.6, 15.0), 2);
    float d9 = sdSphere(p - vec3(-1.9, 0.35, 5.6), 1.30) + 0.08 * fbm(p.xz * 1.2 + vec2(p.y * 0.6, 16.0), 2);
    float da = sdSphere(p - c8, r8) + 0.12 * fbm(p.xz * 1.0 + vec2(p.y * 0.6, 17.0), 2);
    float db = sdSphere(p - c9, r9) + 0.10 * fbm(p.xz * 1.1 + vec2(p.y * 0.6, 18.0), 2);
    float m = min(min(min(min(min(d1, d2), min(d3, d4)), min(d5, min(d6, d7))), min(d8, d9)), min(da, db));
    return vec2(m, (d1 <= m + 1e-4) ? ID_ROCK_PALE : ID_ROCK);
}

vec2 mapBWaterfall(vec3 p) {
    vec3 q = p - vec3(-0.55, 1.55, -5.95);
    float width = 1.95 + 0.40 * smoothstep(1.2, 0.0, q.y);
    float sheet = max(abs(q.x) - width, abs(q.z) - 0.10);
    sheet = max(sheet, abs(q.y) - 1.35);
    sheet += 0.10 * fbm(vec2(q.x * 1.4 + gTime * 0.8, q.y * 1.8), 2);
    float sheet2 = sdBox(p - vec3(-0.55, 0.32, -5.75), vec3(2.55, 0.22, 0.28));
    float lip = sdRoundBox(p - vec3(-0.55, 3.12, -6.22), vec3(2.15, 0.28, 0.44), 0.10);
    vec2 r = vec2(min(sheet, sheet2), ID_FALL);
    if (lip < r.x) r = vec2(lip, ID_ROCK_DK);
    // Blocky rock shoulders framing the curtain.
    float rockL = sdRoundBox(p - vec3(-3.85, 1.85, -5.72), vec3(1.55, 1.95, 1.15), 0.28);
    float rockR = sdRoundBox(p - vec3(2.25, 1.55, -5.55), vec3(1.20, 1.70, 1.05), 0.26);
    float rocks = min(rockL, rockR) + 0.08 * fbm(p.xz * 1.3 + vec2(p.y * 0.5, 11.0), 2);
    if (rocks < r.x) r = vec2(rocks, ID_ROCK_DK);
    return r;
}

// ------------------------------------------------------------------ scene dispatch

vec2 mapA(vec3 p) {
    vec2 r = vec2((p.y - terrainA(p.xz)) * 0.55, ID_TERRAIN);
    vec2 h = mapAHouse(p);
    if (h.x < r.x) r = h;
    vec2 d = mapADeck(p);
    if (d.x < r.x) r = d;
    vec2 pi = mapAPiers(p);
    if (pi.x < r.x) r = pi;
    vec2 ro = mapARocks(p);
    if (ro.x < r.x) r = ro;
    vec2 tr = mapTree(p, vec3(10.9, 0.0, -5.2), 3.5, 0.3);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(12.9, 0.0, -12.2), 3.0, 0.7);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(8.7, 0.0, -16.0), 2.8, 0.1);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-12.2, 0.0, -11.2), 3.3, 0.9);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-11.6, 0.0, 1.2), 2.9, 0.45);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(13.8, 0.0, -9.2), 3.7, 0.5);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(14.6, 0.0, -13.0), 3.6, 0.6);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(18.0, 0.0, -18.0), 4.2, 0.2);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(14.0, 0.0, -8.0), 2.6, 0.35);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(15.5, 0.0, -13.0), 2.8, 0.55);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(11.5, 0.0, -11.5), 2.0, 0.75);
    if (tr.x < r.x) r = tr;
    float tuft = grassTuft(p, vec2(4.8, -2.6));
    tuft = min(tuft, grassTuft(p, vec2(6.3, -4.9)));
    tuft = min(tuft, grassTuft(p, vec2(8.0, -7.6)));
    tuft = min(tuft, grassTuft(p, vec2(5.5, 0.5)));
    tuft = min(tuft, grassTuft(p, vec2(9.2, -10.6)));
    tuft = min(tuft, grassTuft(p, vec2(3.4, 1.7)));
    if (tuft < r.x) r = vec2(tuft, ID_FOLIAGE);
    float crab = sdSphere(p - vec3(7.2, 0.16, -9.0), 0.09);
    crab = min(crab, sdCapsule(p, vec3(7.05, 0.14, -9.05), vec3(6.9, 0.12, -9.2), 0.02));
    crab = min(crab, sdCapsule(p, vec3(7.35, 0.14, -8.95), vec3(7.5, 0.12, -8.8), 0.02));
    if (crab < r.x) r = vec2(crab, ID_PAINT);
    vec2 b = mapBoat(p);
    if (b.x < r.x) r = b;
    return r;
}

vec2 mapB(vec3 p) {
    vec2 r = vec2((p.y - terrainB(p.xz)) * 0.5, ID_TERRAIN);
    vec2 h = mapBWaterfall(p);
    if (h.x < r.x) r = h;
    vec2 ro = mapBRocks(p);
    if (ro.x < r.x) r = ro;
    vec2 tr = mapTree(p, vec3(-7.6, 0.0, 2.6), 2.4, 0.2);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-8.8, 0.0, -3.2), 2.2, 0.6);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(11.2, 0.0, -1.6), 2.4, 0.8);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(10.6, 0.0, -7.0), 2.1, 0.35);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-8.8, 0.0, -9.2), 2.0, 0.15);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-7.8, 0.0, 0.4), 2.0, 0.72);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-6.7, 0.0, -1.8), 2.1, 0.32);

    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-9.4, 0.0, 3.2), 2.3, 0.55);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-9.9, 0.0, -3.4), 2.2, 0.25);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-8.9, 0.0, -7.6), 2.1, 0.75);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(9.6, 0.0, 2.6), 2.3, 0.65);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(10.1, 0.0, -3.8), 2.2, 0.05);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(9.0, 0.0, -8.2), 2.1, 0.85);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-8.4, 0.0, 5.6), 2.3, 0.18);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-10.8, 0.0, 0.6), 2.2, 0.68);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(8.9, 0.0, 5.0), 2.2, 0.38);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(11.8, 0.0, 4.2), 2.1, 0.9);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-9.2, 0.0, 5.2), 2.1, 0.28);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-11.4, 0.0, 4.0), 2.2, 0.58);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(10.6, 0.0, 5.2), 2.2, 0.48);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(12.2, 0.0, 0.5), 2.2, 0.78);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-12.0, 0.0, -3.0), 2.6, 0.22);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(12.0, 0.0, -3.0), 2.6, 0.52);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(-12.0, 0.0, 3.0), 2.5, 0.82);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(12.0, 0.0, 3.5), 2.5, 0.12);
    if (tr.x < r.x) r = tr;
    vec2 fl = vec2(-7.5, 5.0); float flower = sdSphere(p - vec3(fl.x, 2.85, fl.y), 0.055);
    flower = min(flower, sdSphere(p - vec3(-8.5, 2.75, 4.2), 0.05));
    flower = min(flower, sdSphere(p - vec3(-6.4, 2.95, 4.0), 0.05));
    flower = min(flower, sdSphere(p - vec3(8.1, 2.9, 4.4), 0.05));
    flower = min(flower, sdSphere(p - vec3(9.0, 2.8, 3.4), 0.05));
    flower = min(flower, sdSphere(p - vec3(-7.3, 2.7, -0.6), 0.05));
    flower = min(flower, sdSphere(p - vec3(8.4, 2.8, -2.0), 0.05));
    flower = min(flower, sdSphere(p - vec3(9.4, 2.75, -5.0), 0.05));
    if (flower < r.x) r = vec2(flower, ID_FLOWER);
    if (tr.x < r.x) r = tr;
    tr = mapTree(p, vec3(6.8, 0.0, -8.6), 2.7, 0.95);
    if (tr.x < r.x) r = tr;
    vec2 b = mapBoat(p);
    if (b.x < r.x) r = b;
    return r;
}

vec2 map(vec3 p) {
    if (gShot == 0) return mapA(p);
    return mapB(p);
}

// ------------------------------------------------------------------ camera

struct Cam { vec3 ro; vec3 ta; float focal; };

Cam cameraA(float t) {
    Cam c;
    float cz = 10.26 - 2.20 * t;
    c.ro = vec3(-0.76, 11.46, cz);
    c.ta = vec3(-0.33, 0.82, cz - 10.18);
    c.focal = 2.31;
    return c;
}

Cam cameraB(float t) {
    float u = 0.0;
    if (t < 6.8) u = 0.10 * smoothstep(3.625, 6.8, t);
    else u = mix(0.10, 1.0, smoothstep(6.8, 7.4, t));
    Cam c;
    vec3 roW = vec3(0.0, 14.2, 10.8), taW = vec3(-0.2, 0.0, -1.9);
    vec3 roC = vec3(2.0, 10.0, 8.0), taC = vec3(1.4, 0.0, -2.2);
    c.ro = mix(roW, roC, u);
    c.ta = mix(taW, taC, u);
    if (gShot == 0) c.focal = 2.31;
    else c.focal = mix(2.45, 3.36, u);
    return c;
}

// ------------------------------------------------------------------ terrain shading

float terrainShadow(vec2 p, float y) {
    float res = 1.0;
    vec2 sdir = normalize(SUN_DIR.xz);
    float rise = SUN_DIR.y / length(SUN_DIR.xz);
    float t = 0.45;
    for (int i = 0; i < 7; i++) {
        vec2 q = p + sdir * t;
        float h = (gShot == 0) ? terrainA(q) : terrainB(q);
        float ray = y + rise * t;
        res = min(res, smoothstep(-0.30 - 0.05 * t, 0.34 + 0.05 * t, ray - h));
        t *= 1.75;
    }
    return 0.55 + 0.45 * res;
}

float objectShadowA(vec3 p) {
    float s = 0.0;
    s = max(s, blobShadow(p.xz, vec2(-7.2, -6.3), 3.1, 2.8, 1.4));
    s = max(s, blobShadow(p.xz, gBoatPos.xz, 1.5 * gBoatScale, 1.6, 1.0));
    s = max(s, blobShadow(p.xz, vec2(8.1, -6.6), 1.35, 1.5, 1.0));
    s = max(s, blobShadow(p.xz, vec2(12.9, -7.8), 1.45, 1.7, 1.2));
    s = max(s, blobShadow(p.xz, vec2(-3.4, -1.0), 2.0, 1.0, 1.1));
    s = max(s, blobShadow(p.xz, vec2(10.9, -5.2), 3.4, 4.2, 2.4));
    s = max(s, blobShadow(p.xz, vec2(12.9, -12.2), 3.0, 4.0, 2.4));
    s = max(s, blobShadow(p.xz, vec2(-12.2, -11.2), 3.0, 4.0, 2.6));
    s = max(s, blobShadow(p.xz, vec2(13.8, -9.2), 3.6, 4.4, 2.6));
    s = max(s, blobShadow(p.xz, vec2(9.8, -3.5), 3.2, 4.0, 2.4));
    return clamp(s, 0.0, 1.0);
}

float objectShadowB(vec3 p) {
    float s = 0.0;
    s = max(s, blobShadow(p.xz, gBoatPos.xz, 1.6 * gBoatScale, 1.8, 1.2));
    s = max(s, blobShadow(p.xz, vec2(-4.35, -1.05), 1.2, 1.1, 0.9));
    s = max(s, blobShadow(p.xz, vec2(4.35, -3.55), 1.0, 1.6, 1.0));
    s = max(s, blobShadow(p.xz, vec2(6.6, 0.3), 2.8, 2.6, 1.8));
    s = max(s, blobShadow(p.xz, vec2(-7.4, -2.0), 3.8, 4.6, 2.6));
    s = max(s, blobShadow(p.xz, vec2(-5.8, 2.0), 2.4, 3.2, 2.0));
    s = max(s, blobShadow(p.xz, vec2(8.6, 0.5), 2.6, 3.6, 2.2));
    s = max(s, blobShadow(p.xz, vec2(-7.8, 0.4), 2.6, 3.6, 2.2));
    s = max(s, blobShadow(p.xz, vec2(-6.7, -1.8), 3.8, 4.6, 2.8));
    s = max(s, blobShadow(p.xz, vec2(-6.8, -2.4), 3.4, 4.2, 2.6));
    s = max(s, blobShadow(p.xz, vec2(6.2, -1.6), 2.8, 3.2, 2.4));
    s = max(s, blobShadow(p.xz, vec2(-5.0, 1.0), 3.6, 4.8, 2.8));
    return clamp(s, 0.0, 1.0);
}

float surfaceShadow(vec3 p, out float ao) {
    float sh = terrainShadow(p.xz, p.y);
    float os = (gShot == 0) ? objectShadowA(p) : objectShadowB(p);
    sh *= 1.0 - 0.55 * os;
    float hd = terrainA(p.xz);
    ao = clamp(1.0 - 0.35 * smoothstep(0.0, 0.6, p.y - hd), 0.55, 1.0);
    return sh;
}

vec3 terrainAlbedoA(vec3 p, vec3 n) {
    float h = p.y;
    float slope = 1.0 - clamp(n.y, 0.0, 1.0);
    float d = p.x - riverCenterA(p.z);
    float hw = riverHalfA(p.z);
    float fm = forestMaskA(p.xz);
    float grain = 0.5 + 0.5 * fbm(p.xz * 1.4 + vec2(2.0, 9.0), 3);
    float macro = 0.5 + 0.5 * fbm(p.xz * 0.22 + vec2(7.0, 1.0), 2);
    vec3 grass = mix(C_GRASS, C_GRASS_HI, macro * 0.8) * (0.90 + 0.20 * grain);
    vec3 sand = mix(C_SAND, C_SAND_WET, smoothstep(0.45, 0.0, h) * 0.7) * (0.96 + 0.07 * grain);
    vec3 foliage = mix(C_FOLIAGE, C_FOLIAGE_HI, grain) * (0.86 + 0.26 * grain);
    vec3 rock = mix(C_ROCK, C_ROCK_HI, grain) * (0.88 + 0.22 * (0.5 + 0.5 * fbm(p.xz * 2.6, 2)));
    vec3 c = grass;
    // Broad east sand bank, plus the wet strip all around the waterline.
    float eastBank = smoothstep(9.6, 7.8, d) * smoothstep(1.75, 0.35, h);
    // A grassy rise at the far top-right corner, as in the reference bank.
    float grassyRise = smoothstep(3.0, 1.0, length((p.xz - vec2(13.0, -14.0)) * vec2(1.0, 1.4)));
    eastBank *= 1.0 - grassyRise;
    float lowBand = smoothstep(0.60, 0.05, h);
    c = mix(c, sand, eastBank * 0.96);
    // Mossy green patches breaking up the broad sand bank.
    float moss = smoothstep(0.48, 0.76, 0.5 + 0.5 * fbm(p.xz * 0.85 + vec2(4.0, 2.0), 2));
    c = mix(c, C_GRASS * 0.92, eastBank * moss * 0.32);
    c = mix(c, sand, lowBand * 0.85);
    // Pale, dry sand on the wide shelf.
    c = mix(c, C_SAND * 1.06, smoothstep(5.0, 7.6, d) * smoothstep(0.75, 0.15, h) * 0.35);
    // Forest floor / canopy tops.
    c = mix(c, foliage, smoothstep(0.40, 0.78, fm) * smoothstep(0.05, 0.5, h - baseA(p.xz)));
    // Exposed rock on steep banks.
    c = mix(c, rock, smoothstep(0.34, 0.60, slope));
    // Dry grass tufts and little flowers on the sand shelf.
    float tuft = smoothstep(0.55, 0.75, valueNoise(p.xz * 2.7 + 3.0)) * smoothstep(0.55, 0.25, h);
    c = mix(c, C_GRASS_HI * 0.85, tuft * 0.16);
    return c;
}

vec3 terrainAlbedoB(vec3 p, vec3 n) {
    float h = p.y;
    float slope = 1.0 - clamp(n.y, 0.0, 1.0);
    float fm = forestMaskB(p.xz);
    float grain = 0.5 + 0.5 * fbm(p.xz * 1.3 + vec2(5.0, 2.0), 3);
    float macro = 0.5 + 0.5 * fbm(p.xz * 0.25 + vec2(1.0, 8.0), 2);
    vec3 grass = mix(C_GRASS, C_GRASS_HI, macro * 0.7) * (0.88 + 0.22 * grain);
    vec3 foliage = mix(C_FOLIAGE, C_FOLIAGE_HI, grain) * (0.80 + 0.30 * grain);
    vec3 rock = mix(C_ROCK, C_ROCK_HI, grain * 0.8);
    rock *= 0.82 + 0.28 * (0.5 + 0.5 * fbm(p.xz * 3.0, 2));
    // Layered rock wall.
    float strata = 0.5 + 0.5 * sin(p.y * 7.0 + 2.0 * fbm(p.xz * 0.8, 2));
    rock *= 0.90 + 0.16 * strata;
    vec3 c = mix(grass, rock, smoothstep(0.34, 0.62, slope));
    c = mix(c, rock, smoothstep(0.35, 0.8, h - 1.0) * 0.6);
    // The bay wall band is bare rock even where the heightfield slope is gentle.
    vec2 bq = p.xz - BAY_C;
    float br = length(bq);
    float ba = atan(bq.y, bq.x + 1e-5);
    float bR = bayRadius(ba);
    float wallBand = smoothstep(bR + 2.2, bR + 0.1, br) * smoothstep(bR - 0.9, bR - 0.1, br);
    c = mix(c, rock, wallBand * smoothstep(0.35, 1.2, h));
    // Grass and moss capping the rock ledge.
    c = mix(c, grass * 0.85, smoothstep(0.55, 0.90, n.y) * smoothstep(1.0, 2.4, h) * 0.42);
    c = mix(c, foliage, smoothstep(0.45, 0.8, fm) * smoothstep(0.05, 0.5, h - baseB(p.xz)));
    // Sand pockets at the waterline.
    c = mix(c, C_SAND, smoothstep(0.28, 0.05, h) * smoothstep(0.08, 0.25, slope));
    // A broken white wet line just above the water.
    float wetEdge = smoothstep(0.10, 0.0, h) * (0.35 + 0.65 * valueNoise(p.xz * 14.0));
    c = mix(c, vec3(0.86, 0.88, 0.83), wetEdge * 0.55);
    return c;
}

// ------------------------------------------------------------------ material shading

vec3 woodColor(vec3 p, vec3 n, float id) {
    float grain = 0.5 + 0.5 * fbm(vec2(p.x + p.z, p.y * 2.0) * 3.0, 3);
    vec3 c = mix(C_WOOD, C_WOOD_HI, grain * 0.65) * (0.88 + 0.2 * grain);
    if (id == ID_DECK) {
        // Long boards running across the dock; their seams and per-board tone.
        float board = floor(p.z * 1.35);
        float seam = abs(fract(p.z * 1.35) - 0.5);
        float tint = hash11(board);
        c = mix(C_WOOD * 1.12, C_WOOD_HI * 1.12, 0.30 + 0.55 * tint) * (0.90 + 0.18 * grain);
        c *= 1.0 - 0.32 * smoothstep(0.45, 0.50, seam);
        c *= 1.0 - 0.22 * smoothstep(0.42, 0.50, abs(fract(p.x * 0.35 + 0.3) - 0.5));
    } else {
        c *= 1.0 - 0.22 * smoothstep(0.32, 0.5, abs(fract(p.y * 3.0 + p.x * 0.2) - 0.5));
    }
    return c;
}

vec3 roofColor(vec3 p) {
    // Long boards parallel to the ridge, alternating light and dark, with faint butt joints.
    float u = (p.z + 6.0) * 1.70;
    float row = floor(u);
    float f = fract(u);
    float tone = hash11(row + 11.0);
    vec3 c = mix(C_ROOF * 0.94, C_ROOF_HI, 0.20 + 0.68 * tone);
    c *= 1.0 - 0.30 * smoothstep(0.40, 0.50, abs(f - 0.5));
    float seam = abs(fract((p.x + 7.2) * 0.60 + tone * 0.7) - 0.5);
    c *= 1.0 - 0.07 * smoothstep(0.47, 0.50, seam);
    c *= 0.88 + 0.18 * (0.5 + 0.5 * fbm(p.xz * 2.5, 2));
    c = mix(c, C_ROOF_HI * 1.08, smoothstep(0.28, 0.08, abs(p.z + 6.3)) * smoothstep(4.9, 4.4, p.y));
    // A soft branch shadow falling across the upper roof.
    float branch = smoothstep(0.50, 0.0, abs((p.x + 7.2) * 0.55 + (p.z + 4.2) * 0.85 - 0.4));
    branch *= smoothstep(3.3, 4.4, p.y) * (0.55 + 0.45 * smoothstep(-7.0, -4.0, p.z));
    c *= 1.0 - 0.18 * branch;
    return c;
}

vec3 boatColor(vec3 p, vec3 n, float id, vec3 q) {
    if (id == ID_BOAT) {
        float plank = abs(fract(q.y * 7.0) - 0.5);
        vec3 c = mix(vec3(0.57, 0.53, 0.51), vec3(0.71, 0.67, 0.65), 0.4 + 0.6 * q.y);
        c *= 1.0 - 0.12 * smoothstep(0.38, 0.5, plank);
        return c;
    }
    if (id == ID_BOAT_IN) {
        if (q.y < 0.23) return vec3(0.66, 0.62, 0.59);
        return vec3(0.81, 0.78, 0.76);
    }
    if (id == ID_WOOD_HI_DUMMY) return vec3(0.78, 0.70, 0.60);
    if (id == ID_HAT) {
        if (q.z > 0.85) {
            if (q.y < 0.55) return vec3(0.74, 0.60, 0.40);
            return vec3(0.60, 0.54, 0.46);
        }
        float rr = length(q.xz - vec2(0.02, -0.12));
        if (rr < 0.215 && q.y > 1.14 && q.y < 1.22) return vec3(0.40, 0.49, 0.27);
        return C_HAT;
    }
    if (id == ID_FIGURE) {
        if (p.y > 0.95) return C_SKIN;
        return C_CLOTH;
    }
    if (id == ID_ROD) return vec3(0.27, 0.19, 0.13);
    if (id == ID_LINE) return vec3(0.16, 0.14, 0.12);
    if (id == ID_ROPE) return vec3(0.72, 0.70, 0.62);
    if (id == ID_FLOWER) return vec3(0.94, 0.94, 0.86);
    if (id == ID_PAINT) return vec3(0.85, 0.22, 0.18);
    return vec3(0.5);
}

// ------------------------------------------------------------------ water shading

float fishMask(vec2 p, float t) {
    float m = 0.0;
    if (gShot == 0) {
        vec2 f1 = vec2(1.1 + 0.25 * sin(t * 0.3), 1.4 + 0.15 * sin(t * 0.21 + 1.0));
        vec2 q = vec2(p.x - f1.x, (p.y - f1.y) * 1.8);
        float body = smoothstep(0.02, 0.0, abs(q.y) - 0.035) * smoothstep(0.16, 0.12, abs(q.x));
        m = max(m, body * 0.35);
    } else {
        for (int i = 0; i < 6; i++) {
            float fi = float(i);
            vec2 c = vec2(-1.2 + fi * 1.05 + 0.3 * sin(t * 0.25 + fi * 2.1),
                          1.9 - fi * 0.62 + 0.18 * sin(t * 0.18 + fi * 1.3));
            float ang = 0.5 + 0.35 * sin(t * 0.2 + fi * 1.7);
            vec2 q = rot2(ang) * (p - c);
            float body = smoothstep(0.110, 0.06, abs(q.y)) * smoothstep(0.42, 0.30, abs(q.x));
            float tail = smoothstep(0.15, 0.05, length((q - vec2(-0.39, 0.0)) * vec2(1.0, 2.2)));
            m = max(m, max(body, tail * 0.8) * (0.75 + 0.15 * sin(fi * 3.0)));
        }
    }
    return m;
}

vec3 shadeWater(vec3 p, vec3 rd, float depth) {
    float foot = 0.004;
    vec4 w1 = waterWaveD(p.xz, gTime, vec2(0.8, 0.5), 1.8, 0.018, depth, foot * 2.0);
    vec4 w2 = waterWaveD(p.xz, gTime, vec2(-0.35, 0.9), 0.9, 0.010, depth, foot * 2.0);
    vec2 grad = w1.yz + w2.yz;
    float chop = 0.5 + 0.5 * valueNoise(p.xz * 2.4 + gTime * 0.15);
    vec3 n = normalize(vec3(-grad.x * 7.0, 1.0, -grad.y * 7.0));

    float sh = terrainShadow(p.xz, 0.0);
    float os = (gShot == 0) ? objectShadowA(p) : objectShadowB(p);
    sh *= 1.0 - 0.75 * os;
    sh = 0.38 + 0.62 * sh;

    // Depth colour: a sandy bottom near the shore, saturated teal in the channel.
    float dep = clamp(depth, 0.0, 3.2);
    vec3 bed = (gShot == 0)
        ? srgbToLinear(mix(vec3(0.52, 0.58, 0.39), vec3(0.38, 0.48, 0.34), 0.5 + 0.5 * valueNoise(p.xz * 3.0)))
        : srgbToLinear(mix(vec3(0.30, 0.43, 0.33), vec3(0.23, 0.35, 0.29), 0.5 + 0.5 * valueNoise(p.xz * 3.0)));
    vec3 shallow = srgbToLinear(vec3(0.42, 0.82, 0.68));
    vec3 mid = srgbToLinear(C_WATER_SH);
    vec3 deep = srgbToLinear(vec3(0.25, 0.64, 0.52));
    vec3 body = mix(bed, shallow, smoothstep(0.02, 0.45, dep));
    body = mix(body, mid, smoothstep(0.35, 0.90, dep));
    body = mix(body, deep, smoothstep(0.90, 2.4, dep));
    if (gShot == 0) {
        body = mix(body, srgbToLinear(vec3(0.55, 0.72, 0.58)), smoothstep(0.32, 0.0, dep) * 0.45);
    } else {
        body = mix(body, srgbToLinear(vec3(0.45, 0.78, 0.68)), smoothstep(0.26, 0.0, dep) * 0.25);
    }
    // Low-frequency caustic bands across the shallow water.
    float caustic = 0.5 + 0.5 * sin(p.x * 6.5 + sin(p.z * 5.0 + gTime * 0.25) * 1.6);
    body *= 1.0 + 0.05 * (caustic - 0.5) * smoothstep(0.15, 1.2, dep);
    body *= 0.94 + 0.08 * valueNoise(p.xz * 1.7 + gTime * 0.1);
    // Fish shapes under the surface.
    float fish = fishMask(p.xz, gTime);
    body = mix(body, srgbToLinear(vec3(0.13, 0.26, 0.27)), fish * smoothstep(0.15, 0.5, dep) * 0.9);
    // A hint of the weedy bottom in the shallows.
    body = mix(body, vec3(0.27, 0.40, 0.26), 0.12 * smoothstep(0.45, 0.95, valueNoise(p.xz * 0.9 + 4.0)) * smoothstep(0.9, 0.2, dep));

    // Fresnel sky tint and a soft sun glint.
    float fres = fresnelDielectric(clamp(dot(n, -rd), 0.0, 1.0), 1.0, 1.333);
    vec3 sky = srgbToLinear(mix(vec3(0.50, 0.70, 0.68), vec3(0.72, 0.82, 0.79), 0.5 + 0.5 * n.x));
    // The creek shot is shaded by the dock and woods; the wide bay sees deeper, duller water.
    if (gShot == 0) body = mix(body, srgbToLinear(vec3(0.33, 0.52, 0.47)), 0.30);
    float closeMix = smoothstep(6.8, 7.4, gTime);
    body = mix(mix(body, srgbToLinear(vec3(0.263, 0.620, 0.514)), 0.32) * 1.24, body, closeMix);
    vec3 col = body * (0.88 + 0.22 * sh) + sky * fres * 0.10;
    // Soft contact shade along the bank, as if the cliffs and trees darken the shallows.
    col *= (0.52 + 0.48 * sh) * (1.0 - 0.52 * os) * (0.80 + 0.20 * smoothstep(0.0, 0.9, dep));
    float spec = pow(max(dot(reflect(-SUN_DIR, n), -rd), 0.0), 70.0);
    col += vec3(1.0, 0.98, 0.90) * spec * 0.06 * sh;

    // Foam: a broken band along the shore, plus a wake around the boat.
    float wob = 0.5 + 0.5 * valueNoise(p.xz * 5.0 + gTime * 0.2);
    float wob2 = 0.5 + 0.5 * valueNoise(p.xz * 11.0 + vec2(3.0, 7.0));
    float shore = smoothstep(0.14, 0.005, dep) * smoothstep(0.30, 0.72, wob * 0.6 + wob2 * 0.4);
    shore *= 0.35 + 0.65 * smoothstep(0.0, 0.22, dep);
    // A crisp, broken wet-line just inside the shore.
    float wet = smoothstep(0.035, 0.006, abs(dep - 0.095) - 0.022 * wob2);
    wet *= smoothstep(0.15, 0.60, wob);
    vec2 bd = p.xz - gBoatPos.xz;
    float wake = smoothstep(0.30, 0.0, abs(length(bd * vec2(0.8, 1.0)) - 1.55 * gBoatScale / 1.35 - 0.10 * sin(gTime * 1.2)));
    wake *= smoothstep(3.4, 1.2, length(bd)) * 0.82 * (0.35 + 0.65 * valueNoise(p.xz * 13.0 + gTime * 0.7));
    wake *= (gShot == 0) ? 1.0 : mix(0.55, 1.0, smoothstep(6.6, 7.4, gTime));
    float ring = 0.0;
    if (gShot == 1) {
        float rd = length(p.xz - gBobber.xz);
        ring = smoothstep(0.035, 0.0, abs(rd - 0.32 - 0.02 * sin(gTime * 2.0))) * 0.9;
        ring += 0.5 * smoothstep(0.03, 0.0, abs(rd - 0.55 - 0.02 * sin(gTime * 2.0 + 1.0)));
    }
    // Readable soft shadows: the cabin/dock over the creek, the west trees over
    // the bay, and the boat offset by the sun direction.
    if (gShot == 0) {
        float cabD = length((p.xz - vec2(-3.4, -1.8)) * vec2(0.8, 0.95));
        col *= 1.0 - 0.22 * smoothstep(4.6, 0.6, cabD);
        vec2 shC = gBoatPos.xz + vec2(0.62, 0.78) * 2.2 * gBoatScale / 1.35;
        col *= 1.0 - 0.16 * smoothstep(2.0 * gBoatScale + 0.6, 0.4, length((p.xz - shC) * vec2(0.85, 1.0)));
    } else {
        float treeD = length((p.xz - vec2(-5.0, 2.4)) * vec2(0.8, 0.9));
        col *= 1.0 - 0.22 * smoothstep(4.6, 0.6, treeD);
        vec2 shC = gBoatPos.xz + vec2(0.62, 0.78) * 2.6 * gBoatScale / 1.35;
        float shD = length((p.xz - shC) * vec2(0.85, 1.0));
        col *= 1.0 - 0.38 * smoothstep(1.9 * gBoatScale + 0.7, 0.4, shD);
    }
    float foam = clamp(shore + wake + ring, 0.0, 1.0);
    foam *= 0.55 + 0.45 * valueNoise(p.xz * 8.0 + gTime * 0.35);
    col = mix(col, srgbToLinear(vec3(0.94, 0.98, 0.94)), clamp(foam + wet * 0.9, 0.0, 1.0) * 0.74);
    if (gShot == 1) {
        vec2 fq = p.xz - vec2(-0.55, -5.05);
        float fd = length(fq * vec2(0.7, 1.0));
        float splash = smoothstep(1.9, 0.2, fd) * (0.45 + 0.55 * valueNoise(p.xz * 4.5 + gTime * 0.6));
        float bubbles = smoothstep(0.35, 0.8, valueNoise(p.xz * 9.0 + gTime * 0.9));
        col = mix(col, srgbToLinear(vec3(0.96, 0.99, 0.97)), clamp(splash + 0.30 * bubbles * smoothstep(1.9, 0.2, fd), 0.0, 1.0) * 0.70);
    }
    return col;
}

// ------------------------------------------------------------------ beauty shading

vec3 shadeObject(vec3 p, vec3 n, vec3 rd, float id) {
    float sh = terrainShadow(p.xz, p.y);
    vec3 albedo;
    vec3 q = toLocal(p, gBoatPos, gBoatYaw);
    if (id == ID_WOOD) {
        albedo = woodColor(p, n, ID_WOOD);
        // South wall (facing the camera): a blue door with a pale frame.
        if (n.z > 0.55 && p.z > -4.4) {
            float dx = p.x + 6.4;
            if (abs(dx) < 0.62 && p.y > 0.92 && p.y < 2.08) {
                albedo = (abs(dx) < 0.44 && p.y > 1.00 && p.y < 1.98)
                       ? vec3(0.19, 0.37, 0.52) : vec3(0.88, 0.84, 0.72);
            }
            if (abs(dx + 1.5) < 0.42 && p.y > 1.30 && p.y < 1.95) {
                albedo = vec3(0.32, 0.46, 0.55);
            }
        }
        // East wall face: a small window.
        if (n.x > 0.55 && p.x > -4.5) {
            float dz = p.z + 6.3;
            if (abs(dz - 0.9) < 0.38 && p.y > 1.30 && p.y < 1.95) {
                albedo = vec3(0.36, 0.50, 0.58);
            }
        }
    }
    else if (id == ID_DECK) albedo = woodColor(p, n, ID_DECK);
    else if (id == ID_ROOF) albedo = roofColor(p);
    else if (id == ID_FOLIAGE) {
        float sun = clamp(dot(n, SUN_DIR), 0.0, 1.0);
        float g = 0.5 + 0.5 * fbm(p.xz * 2.4 + p.y * 0.9, 3);
        float leaf = 0.5 + 0.5 * valueNoise(p.xz * 7.0 + p.y * 3.0);
        float clump = smoothstep(0.30, 0.80, leaf * 0.6 + g * 0.4);
        vec3 dark = srgbToLinear(vec3(0.27, 0.36, 0.23));
        vec3 mid = srgbToLinear(vec3(0.39, 0.50, 0.30));
        vec3 light = srgbToLinear(vec3(0.54, 0.65, 0.39));
        albedo = mix(dark, mid, clump);
        albedo = mix(albedo, light, smoothstep(0.20, 0.95, sun) * 0.45 + 0.12 * clump);
        albedo *= 0.78 + 0.28 * valueNoise(p.xz * 12.0 + p.y * 5.0);
        return albedo * (0.88 + 0.14 * sun) * (0.70 + 0.30 * sh);
    } else if (id == ID_ROCK || id == ID_ROCK_DK || id == ID_ROCK_PALE) {
        float g = 0.5 + 0.5 * fbm(p.xz * 2.2 + vec2(p.y * 0.8, 3.0), 3);
        float cracks = smoothstep(0.55, 0.85, 1.0 - abs(fbm(p.xz * 4.0 + p.y * 1.5, 3) * 2.0 - 1.0));
        vec3 rockBase = (id == ID_ROCK_PALE) ? vec3(0.56, 0.59, 0.56) : C_ROCK;
        vec3 rockHi = (id == ID_ROCK_PALE) ? vec3(0.68, 0.71, 0.67) : C_ROCK_HI;
        albedo = mix(rockBase, rockHi, 0.12 + 0.45 * g + 0.12 * smoothstep(0.0, 0.8, n.y));
        albedo *= 1.0 - 0.08 * cracks;
        float facet = 0.5 + 0.5 * sin(p.x * 5.0 + p.z * 3.0 + p.y * 2.0);
        albedo *= 0.92 + 0.14 * facet;
        if (id == ID_ROCK_DK) albedo *= 0.78;
    } else if (id == ID_FALL) {
        float streak = 0.5 + 0.5 * fbm(vec2(p.x * 6.5, p.y * 0.8 + gTime * 2.1), 3);
        float fine = 0.5 + 0.5 * valueNoise(vec2(p.x * 30.0, p.y * 3.5 + gTime * 4.5));
        float strand = 0.5 + 0.5 * sin(p.x * 38.0 + fbm(vec2(p.x * 9.0, p.y * 1.2 + gTime * 1.6), 2) * 7.0);
        float gap = smoothstep(0.18, 0.55, fbm(vec2(p.x * 8.0, p.y * 0.6 + gTime * 1.2), 2) * 0.5 + 0.5);
        float ribbon = smoothstep(0.25, 0.85, strand * 0.55 + gap * 0.30 + streak * 0.15);
        float foam = smoothstep(0.9, 0.1, p.y) * (0.4 + 0.6 * fine);
        albedo = mix(vec3(0.22, 0.44, 0.50), vec3(0.98, 0.99, 0.98), clamp(ribbon * 0.85 + fine * 0.15 + foam * 0.15, 0.0, 1.0));
        albedo *= 0.70 + 0.30 * smoothstep(2.1, 2.8, p.y);
        albedo = srgbToLinear(albedo);
        // Falling water glows: it is lit by the sky, not by the sun.
        return albedo * (1.02 + 0.12 * fine) + vec3(0.02);
    } else {
        albedo = boatColor(p, n, id, q);
        if (id != ID_FALL) albedo = srgbToLinear(albedo);
    }
    // Everything except the boat palette is authored in sRGB.
    if (id == ID_BOAT || id == ID_BOAT_IN || id == ID_WOOD_HI_DUMMY || id == ID_HAT || id == ID_FIGURE
        || id == ID_ROD || id == ID_LINE || id == ID_PAINT) {
        albedo = srgbToLinear(albedo);
    } else {
        albedo = srgbToLinear(albedo);
    }
    float ao = clamp(1.0 - 0.18 * smoothstep(0.0, 0.35, p.y - (gShot == 0 ? baseA(p.xz) : baseB(p.xz))), 0.72, 1.0);
    float ndl = wrapDiffuse(n, SUN_DIR, 0.35);
    vec3 sun = vec3(1.0, 0.96, 0.86) * (SUN_INTENSITY * ndl * sh);
    vec3 amb = hemisphereLight(n, vec3(0.64, 0.74, 0.76), vec3(0.26, 0.32, 0.22)) * AMBIENT;
    vec3 fill = vec3(0.66, 0.72, 0.72) * (0.50 * wrapDiffuse(n, FILL_DIR, 0.50));
    if (id == ID_BOAT || id == ID_BOAT_IN || id == ID_WOOD_HI_DUMMY || id == ID_HAT) { fill *= 2.3; sh = max(sh, 0.86); }
    vec3 col;
    if (id == ID_ROCK || id == ID_ROCK_DK || id == ID_ROCK_PALE) {
        // Stylized rock: mostly diffuse, softly modelled, no harsh terminator.
        float sunN = clamp(dot(n, SUN_DIR), 0.0, 1.0);
        float flatLight = 0.95 + 0.20 * sunN;
        albedo *= mix(vec3(0.93, 0.95, 0.97), vec3(1.0), 0.65 + 0.35 * smoothstep(0.1, 0.9, sunN));
        col = albedo * flatLight * (0.78 + 0.30 * sh) * ao;
    } else {
        col = albedo * (sun + amb + fill) * ao;
    }
    // A soft rim to separate shapes from the dark water.
    col += albedo * rimLight(n, -rd, 3.0) * 0.10;
    return col;
}

vec3 shadeTerrain(vec3 p, vec3 n, vec3 rd) {
    vec3 albedo = (gShot == 0) ? terrainAlbedoA(p, n) : terrainAlbedoB(p, n);
    albedo = srgbToLinear(albedo);
    float sh = terrainShadow(p.xz, p.y);
    float os = (gShot == 0) ? objectShadowA(p) : objectShadowB(p);
    sh *= 1.0 - 0.68 * os;
    float hd = (gShot == 0) ? terrainA(p.xz) : terrainB(p.xz);
    float ao = clamp(1.0 - 0.32 * smoothstep(0.0, 0.5, p.y - hd), 0.60, 1.0);
    float ndl = wrapDiffuse(n, SUN_DIR, 0.35);
    vec3 sun = vec3(1.0, 0.96, 0.86) * (SUN_INTENSITY * ndl * sh);
    vec3 amb = hemisphereLight(n, vec3(0.62, 0.72, 0.74), vec3(0.24, 0.30, 0.20)) * AMBIENT;
    vec3 fill = vec3(0.64, 0.71, 0.72) * (0.32 * wrapDiffuse(n, FILL_DIR, 0.50));
    vec3 col = albedo * (sun + amb + fill) * ao;
    return col;
}

// ------------------------------------------------------------------ main

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    gTime = iTime;
    gShot = (iTime < CUT_TIME) ? 0 : 1;

    Cam cam;
    if (gShot == 0) {
        cam = cameraA(iTime);
        gBoatPos = vec3(0.0, 0.02 * sin(iTime * 1.5), cam.ro.z - 8.76);
        gBoatYaw = 0.04;
        gBoatScale = 1.15;
        gBobber = vec3(1.1, 0.03, gBoatPos.z + 1.0);
    } else {
        cam = cameraB(iTime);
        float drift = smoothstep(6.6, 7.4, iTime);
        gBoatPos = mix(vec3(-0.9, 0.02 * sin(iTime * 1.2), 1.15),
                       vec3(-2.55, 0.02 * sin(iTime * 1.2), -0.5), drift);
        gBoatYaw = mix(-0.12, -0.02, drift) + 0.02 * sin(iTime * 0.4);
        gBoatScale = mix(1.22, 1.65, drift);
        gBobber = vec3(2.55, 0.04, -2.15);
    }

    mat3 cm = cameraMatrix(cam.ro, cam.ta, 0.0);
    vec3 rd = cameraRay(cm, uv, cam.focal);

    float tWater = iPlane(cam.ro, rd, vec3(0.0, 1.0, 0.0), WATER_Y);
    float tmax = 80.0;
    float limit = (tWater > 0.0) ? tWater + 0.05 : tmax;
    vec3 hit = raymarch(cam.ro, rd, 0.05, min(limit, tmax), 0.55);

    vec3 col;
    if (hit.x > 0.0 && hit.x < limit) {
        vec3 p = cam.ro + hit.x * rd;
        vec3 n = calcNormal(p, max(0.0025, 0.0012 * hit.x));
        if (hit.y == ID_TERRAIN) col = shadeTerrain(p, n, rd);
        else col = shadeObject(p, n, rd, hit.y);
    } else if (tWater > 0.0 && tWater < tmax) {
        vec3 p = cam.ro + tWater * rd;
        float H = (gShot == 0) ? baseA(p.xz) : baseB(p.xz);
        float depth = WATER_Y - H;
        if (depth > 0.0) {
            col = shadeWater(p, rd, depth);
        } else {
            vec3 n = normalize(vec3(0.0, 1.0, 0.0));
            col = shadeTerrain(p, n, rd);
        }
    } else {
        // Background: a soft hazy green, seen only beyond the scene.
        col = vec3(0.20, 0.29, 0.20);
    }

    col *= EXPOSURE;
    if (gShot == 1) {
        vec3 mb = vec3(-0.55, 1.15, -5.4);
        vec3 rel = mb - cam.ro;
        float tca = dot(rel, rd);
        float md = sqrt(max(dot(rel, rel) - tca * tca, 0.0));
        float mist = smoothstep(2.8, 0.2, md) * smoothstep(0.0, 2.0, tca);
        mist *= 0.45 + 0.55 * valueNoise(vec2(rd.x * 42.0, rd.y * 42.0 + gTime * 0.4));
        col += srgbToLinear(vec3(0.86, 0.93, 0.93)) * mist * 0.11;
    }
    col = tonemapNeutral(col);
    col = linearToSrgb(col);
    col += (hash12(floor(fragCoord)) - 0.5) * 0.012;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
