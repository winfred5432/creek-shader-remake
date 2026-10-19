// Creek cove: two-shot recreation of a cozy fishing-game frame in one Shadertoy pass.
// Shot A (0 - 3.2 s): dock and house on a creek. Shot B (3.2 s on): waterfall cove, camera pushes in.
// 2D distance fields layered back to front, shaded directly in sRGB to keep the flat illustration palette.

#define DEBUG_MODE 0
#define CUT_TIME 3.25

// ---- palette (sRGB) ----
const vec3 C_WATER_DEEP = vec3(0.06, 0.93, 0.70);
const vec3 C_WATER_MID  = vec3(0.20, 0.89, 0.69);
const vec3 C_WATER_SOFT = vec3(0.40, 0.84, 0.66);
const vec3 C_ROCK       = vec3(0.535, 0.575, 0.565);
const vec3 C_ROCK_LIT   = vec3(0.705, 0.725, 0.695);
const vec3 C_ROCK_DARK  = vec3(0.34, 0.38, 0.38);
const vec3 C_FOAM       = vec3(0.91, 0.95, 0.92);
const vec3 C_SAND       = vec3(0.67, 0.74, 0.48);
const vec3 C_WOOD       = vec3(0.43, 0.29, 0.24);
const vec3 C_WOOD_LIT   = vec3(0.53, 0.38, 0.31);
const vec3 C_WOOD_PALE  = vec3(0.68, 0.52, 0.37);
const vec3 C_CANOPY     = vec3(0.80, 0.73, 0.47);
const vec3 C_FIGURE     = vec3(0.40, 0.18, 0.12);
const vec3 C_HAT        = vec3(0.74, 0.63, 0.36);
const vec3 C_GRASS      = vec3(0.52, 0.61, 0.38);
const vec3 C_GRASS_DARK = vec3(0.30, 0.43, 0.24);
const vec3 C_LEAF       = vec3(0.47, 0.63, 0.35);

float pxSize() { return 2.0 / iResolution.y; }
float fill(float d) { return fillAA(d, pxSize()); }

// Half-plane helpers: negative inside the named region.
float below(float y, float edge) { return edge - y; }
float rightOf(float x, float a)  { return a - x; }
float leftOf(float x, float a)   { return x - a; }

// Stretched grain for planks: high frequency across the board, low along it.
float grain(vec2 p, float across, float along) {
    return fbm(vec2(p.x * across, p.y * along), 2) * 0.5 + 0.5;
}

float blob(vec2 p, vec2 c, vec2 r, float soft) {
    return smoothstep(1.0 + soft, 1.0 - soft, length((p - c) / r));
}

vec3 waterBase(vec2 p, float depth, float t) {
    const vec3 C_SHALLOW = vec3(0.40, 0.62, 0.50);
    vec3 col = mix(C_SHALLOW, C_WATER_SOFT, smoothstep(0.0, 0.10, depth));
    col = mix(col, C_WATER_MID, smoothstep(0.22, 0.55, depth));
    col = mix(col, C_WATER_DEEP, smoothstep(0.55, 1.0, depth));
    col *= 1.05 + 0.06 * fbm(p * 0.8 + vec2(t * 0.02, -t * 0.012), 3);
    return col;
}

// Fine animated caustic web.
float caustics(vec2 p, float t) {
    vec2 q = p * 13.0;
    q += 0.30 * vec2(fbm(q * 0.22 + vec2(0.0, t * 0.06), 3), fbm(q * 0.22 + vec2(5.2, -t * 0.05), 3));
    float b = voronoiBorder(q, 0.9).x;
    float line = 1.0 - smoothstep(0.0, 0.055, b);
    return line * (0.45 + 0.55 * smoothstep(0.30, 0.85, fbm(p * 2.6 + vec2(t * 0.03, 0.0), 3) * 0.5 + 0.5));
}

// Faceted rock: quantised shading, bright lit rim, dark waterline.
vec3 rockShade(vec2 p, vec2 c, vec2 r, float t, out float d) {
    vec2 q = (p - c) / r;
    d = (length(q) - 1.0) * min(r.x, r.y);
    float h = sqrt(max(0.0, 1.0 - dot(q, q)));
    vec3 n = normalize(vec3(q, h + 0.001));
    float lit = clamp(dot(n, normalize(vec3(-0.60, 0.55, 0.58))), 0.0, 1.0);
    vec3 col = mix(C_ROCK * 0.80, C_ROCK * 1.04, lit * 0.85);
    col = mix(col, C_ROCK_LIT, smoothstep(0.80, 1.0, lit) * 0.30);
    col = mix(col, vec3(0.80, 0.81, 0.76), smoothstep(0.90, 1.0, lit) * 0.25);
    col *= 0.96 + 0.06 * fbm(p * 5.0, 3);
    col = mix(col, C_ROCK_DARK, smoothstep(-0.05, -0.50, n.y) * 0.30);
    col = mix(col, C_ROCK_DARK * 0.92, smoothstep(0.85, 0.55, h) * 0.0);
    return col;
}

// ---------------------------------------------------------------- boat -----

// Rowboat in local coordinates: bow at -Y, stern at +Y, length about 2.
vec3 boatColor(vec2 p, float t, float shade, out float cover, out float shadow) {
    // hull: rounded box body with a pointed bow and a flat transom at the stern
    float body = sdRoundedBox(p - vec2(0.0, 0.10), vec2(0.34, 0.62), vec4(0.16));
    float bow = sdTriangle(p, vec2(-0.34, -0.30), vec2(0.34, -0.30), vec2(0.0, -0.86));
    float hull = min(body, bow);
    hull = max(hull, p.y - 0.74);
    float inner = hull + 0.055;

    shadow = blob(p, vec2(0.16, 0.04), vec2(0.60, 1.00), 0.25);

    vec3 hullCol = mix(C_WOOD * 0.92, C_WOOD_LIT, smoothstep(-0.6, 0.8, p.y));
    vec3 floorCol = C_WOOD_PALE * (0.88 + 0.12 * sin(p.y * 16.0) + 0.05 * fbm(p * 22.0, 2));
    vec3 col = mix(hullCol, floorCol, fill(inner));
    // gunwale: lit inner edge, dark outer edge
    col = mix(col, C_WOOD_LIT * 1.18, (1.0 - smoothstep(0.0, 0.014, abs(inner + 0.020))) * 0.45);
    col = mix(col, C_WOOD * 0.72, (1.0 - smoothstep(0.0, 0.010, abs(hull + 0.012))) * 0.55);

    // floor planks and benches
    col *= 0.97 + 0.03 * sin(p.y * 30.0);
    float bench = min(sdBox(p - vec2(0.0, -0.16), vec2(0.27, 0.040)),
                      sdBox(p - vec2(0.0, 0.22), vec2(0.30, 0.040)));
    col = mix(col, C_WOOD_LIT * 1.05, fill(bench) * fill(inner));
    col = mix(col, C_WOOD_LIT, fill(sdBox(p - vec2(0.0, 0.58), vec2(0.31, 0.085))) * fill(inner));

    // canopy over the stern, drawn first so the angler sits in front of it
    vec2 cp = p - vec2(0.0, 0.60);
    float dome = sdEllipse(cp, vec2(0.28, 0.20));
    col = mix(col, C_CANOPY * 1.05, fill(dome));
    col = mix(col, C_CANOPY * 0.86, fill(sdEllipse(cp, vec2(0.21, 0.14))) * 0.75);
    col = mix(col, C_WOOD * 0.62, fill(sdSegment(p, vec2(0.0, 0.58), vec2(0.0, 0.34)) - 0.006));
    cover = max(fill(hull), fill(dome));

    // angler: torso, arm, straw hat
    vec2 ap = p - vec2(0.01, 0.18);
    float torso = sdUnevenCapsule(vec2(ap.x, ap.y + 0.09), 0.045, 0.115, 0.20);
    col = mix(col, C_FIGURE, fill(torso) * fill(inner));
    float arm = sdSegment(ap, vec2(0.05, -0.02), vec2(0.23, -0.15)) - 0.024;
    col = mix(col, C_FIGURE * 1.12, fill(arm) * fill(inner));
    col = mix(col, C_HAT * 0.86, fill(sdCircle(ap - vec2(0.0, -0.13), 0.115)));
    col = mix(col, C_HAT, fill(sdCircle(ap - vec2(0.0, -0.15), 0.068)));

    // oar over the starboard side
    float oar = sdSegment(p, vec2(0.30, 0.14), vec2(0.52, -0.22)) - 0.017;
    col = mix(col, C_WOOD_LIT, fill(oar));
    cover = max(cover, fill(oar));

    // rod butt
    float rod = sdSegment(p, vec2(0.20, -0.06), vec2(0.38, -0.86)) - 0.007;
    col = mix(col, C_WOOD * 0.78, fill(rod));
    cover = max(cover, fill(rod));
    return col * shade;
}

// ---------------------------------------------------------------- shot B ---

vec3 shotB(vec2 p, float t) {
    // camera push-in: wide at the cut, settled by CUT + 4 s
    float zoom = mix(0.62, 1.0, smoothstep(CUT_TIME, CUT_TIME + 5.4, t));
    vec2 center = vec2(-0.05, -0.10);
    p = (p - center) / zoom + center;

    vec2 poolP = (p - vec2(-0.14, -0.26)) / vec2(1.44, 0.88);
    float pool = length(poolP) - 1.0;
    pool += 0.22 * fbm(p * 1.15 + vec2(0.0, t * 0.004), 3) * smoothstep(1.4, 0.4, length(poolP));
    pool += 0.06 * fbm(p * 4.5, 2);
    pool = max(pool, p.x - 1.02);

    float depth = smoothstep(0.0, 0.50, -pool);
    vec3 col = waterBase(p, depth, t);
    float wide = smoothstep(0.95, 0.62, zoom);
    col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), 0.30 * wide);
    col = mix(col, vec3(0.52, 0.58, 0.45), 1.00 * wide);
    col *= 1.0 - 0.90 * wide + 0.35 * wide;
    col += vec3(0.80, 1.0, 0.90) * caustics(p, t) * 0.075 * depth;
    float ripple = sin(p.y * 46.0 + 3.0 * fbm(p * 1.6 + vec2(t * 0.10, 0.0), 2)) * 0.5 + 0.5;
    col += vec3(0.55, 0.95, 0.85) * smoothstep(0.80, 1.0, ripple) * 0.035 * depth;
    float sparkle = hash12(floor(p * 46.0));
    col += vec3(0.70, 0.95, 0.88) * smoothstep(0.985, 1.0, sparkle) * 0.10 * depth;
    col += vec3(0.60, 0.95, 0.88) * (fbm(p * 26.0 + vec2(t * 0.4, 0.0), 2) * 0.5 + 0.5) * 0.025 * depth;

    // land: everything outside an organic pool outline
    float edge = 0.30 + 0.08 * fbm(vec2(p.x * 1.3, 1.7), 4);
    float land = -pool;

    vec3 rock = mix(C_ROCK * 0.94, C_ROCK * 1.04, smoothstep(-0.85, -0.15, land));
    rock = mix(rock, C_ROCK_LIT, smoothstep(-0.15, 0.10, land) * 0.45);
    float facets = fbm(p * 2.3 + vec2(3.0, 1.0), 3) * 0.5 + 0.5;
    rock *= 0.80 + 0.32 * facets;
    rock *= 0.93 + 0.09 * fbm(vec2(p.x * 3.5, p.y * 5.0), 3);
    rock *= 0.94 + 0.06 * fbm(vec2(p.x * 6.0, p.y * 1.2), 3);

    rock *= 0.98 + 0.06 * smoothstep(-0.85, -0.02, land);
    rock *= 1.0 + 0.26 * fbm(p * 9.0, 2);
    rock *= 1.0 + 0.16 * fbm(p * 20.0, 2);
    float crack = smoothstep(0.90, 0.99, 1.0 - abs(fbm(p * 6.0 + 2.0, 3)));
    rock *= 1.0 - 0.16 * crack;
    rock *= 0.95 + 0.05 * smoothstep(0.0, 0.40, -land);
    rock *= mix(0.42, 1.06, smoothstep(0.95, 0.55, p.y));
    rock = mix(rock, C_ROCK_LIT, smoothstep(0.05, 0.0, abs(land + 0.03)) * 0.30);
    col = mix(col, rock, fill(land));

    // foam where the water meets the rock
    float foam = (1.0 - smoothstep(0.0, 0.030, abs(land))) * (0.40 + 0.60 * fbm(p * 9.0, 2));
    col = mix(col, C_FOAM, foam * 0.70);

    // treeline: overlapping canopies on the high ground
    // waterfall: sheet, bright lip, streaks, impact foam and mist
    float fx = -0.34 + 0.015 * sin(p.y * 2.2 + t * 0.6);
    float halfW = 0.21 + 0.02 * fbm(vec2(p.y * 3.0, t * 0.25), 2);
    float fall = smoothstep(halfW, halfW * 0.72, abs(p.x - fx))
               * smoothstep(0.02, 0.14, pool) * smoothstep(0.30, 0.46, p.y);
    float streak = fbm(vec2(p.x * 26.0, p.y * 2.0 + t * 2.6), 3);
    vec3 fallCol = mix(vec3(0.62, 0.75, 0.78), vec3(1.0), 0.55 + 0.45 * streak);
    col = mix(col, fallCol, fall * (0.62 + 0.38 * streak));
    float lip = smoothstep(0.030, 0.0, abs(pool)) * smoothstep(0.34, 0.05, abs(p.x - fx));
    col = mix(col, C_FOAM, lip * 0.85);

    vec2 sp = p - vec2(fx, 0.34);
    float splash = exp(-length(sp * vec2(2.0, 3.4)) * 2.6);
    col = mix(col, C_FOAM, splash * (0.40 + 0.60 * fbm(p * 16.0 + t * 0.9, 2)));
    float ring = abs(length(sp * vec2(1.7, 2.6)) - 0.15 - 0.02 * sin(t * 2.0)) - 0.012;
    col = mix(col, C_FOAM, (1.0 - smoothstep(0.0, 0.03, ring)) * 0.55);
    col += vec3(0.70, 0.82, 0.80) * exp(-length(sp * vec2(1.0, 1.6)) * 1.8) * 0.10;

    // rocks breaking the cliff base
    float dC1, dC2, dC3;
    vec3 cC1 = rockShade(p, vec2(-1.25, 0.16), vec2(0.22, 0.22), t, dC1);
    vec3 cC2 = rockShade(p, vec2(0.05, 0.04), vec2(0.30, 0.22), t, dC2);
    vec3 cC3 = rockShade(p, vec2(0.86, -0.02), vec2(0.22, 0.24), t, dC3);
    col = mix(col, C_WATER_DEEP * 0.50, blob(p, vec2(-1.00, 0.00), vec2(0.34, 0.26), 0.6) * 0.30);
    col = mix(col, C_WATER_DEEP * 0.50, blob(p, vec2(0.10, -0.06), vec2(0.38, 0.28), 0.6) * 0.30);
    col = mix(col, C_WATER_DEEP * 0.50, blob(p, vec2(0.90, -0.12), vec2(0.30, 0.30), 0.6) * 0.28);
    col = mix(col, cC1, fill(dC1));
    col = mix(col, cC2, fill(dC2));
    col = mix(col, cC3, fill(dC3));

    // foliage hanging over the shelf at the frame margins

    // dark forest band on the side land, mostly visible in the establishing shot
    for (int i = 0; i < 12; i++) {
        float fi = float(i);
        float side = (mod(fi, 2.0) < 0.5) ? -1.0 : 1.0;
        float row = floor(fi / 2.0);
        vec2 c = vec2(side * (1.96 + 0.22 * mod(row, 3.0)),
                      -0.55 + 0.30 * row + 0.10 * (hash11(fi + 61.0) - 0.5));
        float r = 0.20 + 0.07 * hash11(fi + 67.0);
        float d = sdCircle(p - c, r) + 0.045 * fbm(p * 12.0 + fi, 2);
        col = mix(col, mix(C_GRASS_DARK, C_LEAF, 0.45), fill(d));
        col = mix(col, C_LEAF * 1.1, fill(d + 0.07) * 0.5);
    }

    for (int i = 0; i < 12; i++) {
        float fi = float(i);
        vec2 c = vec2(-2.0 + 0.36 * fi + 0.12 * (hash11(fi + 71.0) - 0.5),
                      1.22 + 0.08 * (hash11(fi + 73.0) - 0.5));
        float r = 0.18 + 0.07 * hash11(fi + 79.0);
        float d = sdCircle(p - c, r) + 0.075 * fbm(p * 11.0 + fi, 2);
        col = mix(col, mix(C_GRASS_DARK, C_LEAF, 0.55), fill(d));
        col = mix(col, C_LEAF * 1.15, fill(d + 0.07) * 0.5);
    }

    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float side = (fi < 4.0) ? -1.0 : 1.0;
        vec2 c = vec2(side * (1.78 - 0.06 * mod(fi, 4.0)), 0.55 + 0.14 * mod(fi, 4.0));
        float d = sdCircle(p - c, 0.27) + 0.05 * fbm(p * 11.0 + fi, 2);
        col = mix(col, mix(C_GRASS_DARK, C_LEAF, 0.55), fill(d));
        col = mix(col, C_LEAF * 1.1, fill(d + 0.07) * 0.5);
    }

    // forest columns outside the close framing; they fill the establishing shot
    for (int i = 0; i < 22; i++) {
        float fi = float(i);
        float sideSel = mod(fi, 2.0);
        float side = (sideSel < 0.5) ? -1.0 : 1.0;
        float row = floor(fi / 2.0);
        vec2 c = vec2(side * (2.10 + 0.28 * mod(row, 2.0)),
                      -0.75 + 0.26 * row + 0.12 * (hash11(fi + 31.0) - 0.5));
        float r = 0.28 + 0.10 * hash11(fi + 37.0);
        float d = sdCircle(p - c, r) + 0.040 * fbm(p * 11.0 + fi, 2);
        col = mix(col, mix(C_GRASS_DARK, C_LEAF, 0.55), fill(d));
        col = mix(col, C_LEAF * 1.15, fill(d + 0.08) * 0.6);
    }

    for (int i = 0; i < 10; i++) {
        float fi = float(i);
        vec2 c = vec2(-2.10 + 0.47 * fi + 0.14 * (hash11(fi + 41.0) - 0.5),
                      1.32 + 0.08 * (hash11(fi + 43.0) - 0.5));
        float r = 0.24 + 0.10 * hash11(fi + 47.0);
        float d = sdCircle(p - c, r) + 0.045 * fbm(p * 10.0 + fi, 2);
        col = mix(col, C_GRASS_DARK * 0.85, fill(d));
        col = mix(col, C_LEAF, fill(d + 0.08) * 0.5);
    }

    // boulders
    float dR, dL, dB, dM;
    vec3 cR = rockShade(p, vec2(0.98, -0.22), vec2(0.34, 0.40), t, dR);
    vec3 cL = rockShade(p, vec2(-1.44, -0.72), vec2(0.34, 0.27), t, dL);
    vec3 cB = rockShade(p, vec2(0.16, -1.00), vec2(0.46, 0.22), t, dB);
    vec3 cM = rockShade(p, vec2(0.76, -0.52), vec2(0.12, 0.09), t, dM);

    col = mix(col, C_WATER_DEEP * 0.55, blob(p, vec2(1.24, -0.24), vec2(0.46, 0.52), 0.55) * 0.28);
    col = mix(col, C_WATER_DEEP * 0.55, blob(p, vec2(-1.38, -0.78), vec2(0.38, 0.31), 0.55) * 0.26);
    col = mix(col, C_FOAM, (1.0 - smoothstep(0.0, 0.05, abs(min(min(dR, dL), min(dB, dM)) + 0.05))) * 0.40);
    col = mix(col, cR, fill(dR));
    col = mix(col, cL, fill(dL));
    col = mix(col, cB, fill(dB));
    col = mix(col, cM, fill(dM));

    // boat: bow toward the lower left
    vec2 bp = rot2(0.64) * (p - vec2(-1.16, -0.14));
    float bcover, bshadow;
    vec3 bcol = boatColor(bp * 1.68, t, 0.82, bcover, bshadow);
        col = mix(col, C_WATER_DEEP * 0.45, bshadow * 0.55 * (1.0 - bcover));
    col = mix(col, bcol, bcover);

    // reeds and grass tufts at the left waterline
    vec2 gc = floor(p * vec2(10.0, 10.0));
    vec2 gf = fract(p * vec2(10.0, 10.0)) - 0.5;
    float reed = min(sdSegment(gf, vec2(-0.04, -0.22), vec2(0.01, 0.24)),
                     sdSegment(gf, vec2(0.08, -0.22), vec2(0.14, 0.10))) - 0.010;
    float reedMask = step(0.84, hash12(gc)) * step(abs(p.x + 1.34), 0.12) * step(p.y, -0.30);
    col = mix(col, C_GRASS_DARK * 0.9, fill(reed) * reedMask);

    // rod line and bobber
    vec2 tip = vec2(-0.66, 0.34);
    vec2 bob = vec2(0.34, -0.34) + vec2(0.0, 0.015 * sin(t * 1.6));
    col = mix(col, vec3(0.12, 0.11, 0.10), fill(sdSegment(p, tip, bob) - 0.0042));
    col = mix(col, vec3(0.70, 0.10, 0.12), fill(sdCircle(p - bob, 0.024)));
    float rring = abs(length(p - bob) - 0.09 - 0.025 * sin(t * 1.3)) - 0.004;
    col = mix(col, C_FOAM, (1.0 - smoothstep(0.0, 0.008, rring)) * 0.35);

    // fish
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        vec2 fp = p - vec2(-0.30 + 0.28 * fi + 0.045 * sin(t * 0.7 + fi * 1.7),
                           -0.56 - 0.09 * fi + 0.03 * cos(t * 0.6 + fi));
        fp = rot2(0.45 + 0.2 * sin(t + fi)) * fp;
        float body = length(fp * vec2(1.0, 3.2)) - 0.030;
        float tail = sdTriangle(vec2(fp.x, fp.y + 0.10), vec2(-0.030, 0.02), vec2(0.030, 0.02), vec2(0.0, 0.10));
        col = mix(col, C_WATER_DEEP * 0.38, fill(min(body, tail)) * 0.75);
    }

#if DEBUG_MODE == 1
    return debugDistance(land);
#elif DEBUG_MODE == 5
    return vec3(fill(land), fill(dR), caustics(p, t));
#endif
    return col;
}

// ---------------------------------------------------------------- shot A ---

vec3 shotA(vec2 p, float t) {
    vec2 q = p + vec2(0.12, 0.0);

    // channel water, shallow near both banks
    float bankX = 0.46 + 0.12 * fbm(vec2(q.y * 1.2, 2.0), 3) + 0.38 * q.y;
    float bank = rightOf(q.x, bankX);
    float depth = smoothstep(0.0, 0.38, -bank) * smoothstep(0.10, -0.90, q.y);
    vec3 col = waterBase(q, depth, t);
    col += vec3(0.80, 1.0, 0.90) * caustics(q, t) * 0.055 * depth;
    col += vec3(0.75, 0.95, 0.85) * caustics(q * 1.7 + 11.0, t * 0.8) * 0.035 * depth;
    float arc = abs(fract(length(q * 2.3 + vec2(0.0, t * 0.05)) * 2.0) - 0.5);
    col += vec3(0.60, 0.90, 0.82) * smoothstep(0.08, 0.0, arc) * 0.06 * depth;

    // far bank at the top of the frame
    float farBank = 0.43 + 0.05 * fbm(vec2(q.x * 2.0, 5.0), 3) - q.y + max(0.0, q.x - 0.85) * 2.2;
    col = mix(col, C_SAND * 0.96, fill(farBank));
    col = mix(col, C_GRASS, fill(farBank - 0.10));
    col = mix(col, C_FOAM, (1.0 - smoothstep(0.0, 0.02, abs(farBank))) * 0.45);

    // right bank: sand, grass, then a darker grass belt
    vec3 sandCol = C_SAND * (1.00 + 0.08 * fbm(q * 5.0, 3));
    sandCol *= 1.05 + 0.10 * (fbm(q * 30.0, 2) * 0.5 + 0.5);
    col = mix(col, sandCol, fill(bank));
    vec3 grassCol = C_GRASS * (0.90 + 0.14 * (fbm(q * 24.0, 3) * 0.5 + 0.5));
    grassCol = mix(grassCol, C_GRASS_DARK, smoothstep(0.55, 0.9, fbm(q * 12.0 + 3.0, 2) * 0.5 + 0.5) * 0.5);
    grassCol *= 1.0 + 0.14 * fbm(q * 40.0, 2);
    col = mix(col, grassCol, fill(rightOf(q.x, bankX + 1.10)));
    col = mix(col, C_GRASS_DARK, fill(rightOf(q.x, bankX + 1.16)) * 0.35);
    col = mix(col, C_FOAM, (1.0 - smoothstep(0.0, 0.020, abs(bank))) * 0.50);
    // shallow-water brightening inside the foam line
    col = mix(col, C_WATER_SOFT, (1.0 - smoothstep(0.0, 0.16, bank)) * step(0.0, bank) * 0.25);

    // reeds along the waterline
    vec2 gc = floor(q * vec2(9.0, 9.0));
    vec2 gf = fract(q * vec2(9.0, 9.0)) - 0.5;
    float reed = min(sdSegment(gf, vec2(-0.03, -0.25), vec2(0.02, 0.22)),
                     sdSegment(gf, vec2(0.06, -0.25), vec2(0.12, 0.12))) - 0.012;
    float reedMask = step(0.80, hash12(gc)) * step(abs(bank + 0.02), 0.055);
    col = mix(col, C_GRASS_DARK * 0.85, fill(reed) * reedMask);

    // dock on the left: planks with gaps, posts and a net
    float deck = max(leftOf(q.x, -1.24), q.y - 0.54);
    float plankId = floor(q.y * 16.0);
    vec3 plank = mix(C_WOOD_LIT, C_WOOD, 0.20 + 0.55 * hash11(plankId));
    plank *= 0.94 + 0.06 * sin(q.y * 120.0) + 0.05 * fbm(q * 26.0, 2);
    plank *= 0.76 + 0.48 * grain(q, 14.0, 2.0);
    plank *= 0.90 + 0.18 * smoothstep(0.90, 1.0, sin(q.y * 18.0));
    plank *= 1.0 - 0.30 * smoothstep(0.93, 1.0, sin(q.y * 26.0));
    col = mix(col, plank, fill(deck));
    col = mix(col, C_WOOD * 0.6, (1.0 - smoothstep(0.0, 0.008, abs(fract(q.y * 16.0) - 0.5))) * fill(deck) * 0.5);
    float post = min(min(sdBox(q - vec2(-1.28, 0.50), vec2(0.05, 0.07)),
                         sdBox(q - vec2(-1.28, -0.42), vec2(0.05, 0.07))),
                     sdBox(q - vec2(-0.68, -0.44), vec2(0.05, 0.07)));
    col = mix(col, C_WOOD * 0.85, fill(post));
    // house: a large roof slab seen from above, ridge and plank courses
    vec2 hp = q - vec2(-1.20, 0.60);
    float roof = sdBox(hp, vec2(0.58, 0.42)) - 0.010;
    float ridge = smoothstep(0.03, 0.0, abs(hp.y - 0.02));
    float course = 0.5 + 0.5 * sin(hp.y * 46.0 + 0.4);
    vec3 roofA = vec3(0.60, 0.42, 0.36) * (0.86 + 0.20 * course);
    vec3 roofB = vec3(0.50, 0.33, 0.28) * (0.86 + 0.20 * course);
    vec3 roofCol = mix(roofB, roofA, smoothstep(-0.02, 0.02, hp.y - 0.02));
    roofCol = mix(roofCol, vec3(0.26, 0.14, 0.12), ridge * 0.6);
    roofCol *= 0.74 + 0.52 * grain(hp, 2.0, 14.0);
    roofCol *= 0.90 + 0.20 * smoothstep(0.92, 1.0, sin(hp.y * 18.0));
    roofCol *= 0.96 + 0.08 * smoothstep(0.94, 1.0, sin(hp.x * 150.0));
    col = mix(col, roofCol, fill(roof));
    col = mix(col, C_WOOD * 0.7, fill(sdBox(hp - vec2(0.0, -0.42), vec2(0.58, 0.02))));

    // wall strip at the water side with a door
    float wall = sdBox(hp - vec2(0.0, -0.44), vec2(0.52, 0.05)) - 0.008;
    col = mix(col, C_WOOD_LIT * 0.92, fill(wall));
    col = mix(col, vec3(0.17, 0.29, 0.35), fill(sdBox(hp - vec2(-0.26, -0.44), vec2(0.055, 0.035))));

    // bridge across the top of the channel
    vec2 bq = q - vec2(-0.14, 0.90);
    float bridge = sdBox(bq, vec2(0.30, 0.055)) - 0.006;
    col = mix(col, C_WOOD_LIT * 0.88, fill(bridge));
    float bpost = min(min(sdBox(bq - vec2(-0.27, -0.09), vec2(0.024, 0.09)),
                          sdBox(bq - vec2(0.27, -0.09), vec2(0.024, 0.09))),
                      min(sdBox(bq - vec2(-0.14, -0.09), vec2(0.024, 0.09)),
                          sdBox(bq - vec2(0.14, -0.09), vec2(0.024, 0.09))));
    col = mix(col, C_WOOD * 0.9, fill(bpost));
    col = mix(col, C_WOOD * 0.72, fill(sdBox(bq - vec2(0.0, -0.13), vec2(0.30, 0.010))));

    // boat drifting in the channel
    vec2 bp = rot2(-0.42) * (q - vec2(0.04, -0.34));
    float bcover, bshadow;
    vec3 bcol = boatColor(bp * 2.0, t, 1.0, bcover, bshadow);
    col = mix(col, C_WATER_DEEP * 0.55, bshadow * 0.40 * (1.0 - bcover));
    col = mix(col, bcol, bcover);

    // tree on the right bank
    vec2 tp = q - vec2(1.50, 0.70);
    col = mix(col, C_WOOD * 0.8, fill(sdSegment(tp, vec2(0.0, 0.02), vec2(0.02, -0.24)) - 0.028));
    float canopy = min(sdEllipse(tp - vec2(-0.04, 0.24), vec2(0.33, 0.27)),
                       sdEllipse(tp - vec2(0.19, 0.40), vec2(0.26, 0.22)));
    canopy += 0.028 * fbm(tp * 10.0, 3);
    col = mix(col, C_LEAF, fill(canopy));
    col = mix(col, C_LEAF * 1.18, fill(canopy + 0.09) * 0.35);
    col = mix(col, C_GRASS_DARK, fill(canopy + 0.035) * 0.28);

    // bank boulders
    float dC, dA, dBb;
    vec3 rC = rockShade(q, vec2(0.72, 0.04), vec2(0.16, 0.11), t, dC);
    col = mix(col, rC, fill(dC));
    vec3 rA = rockShade(q, vec2(0.92, 0.12), vec2(0.15, 0.11), t, dA);
    vec3 rB = rockShade(q, vec2(1.10, -0.24), vec2(0.09, 0.07), t, dBb);
    col = mix(col, rA, fill(dA));
    col = mix(col, rB, fill(dBb));

    return col;
}

// ---------------------------------------------------------------- main -----

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    float t = iTime;

    vec3 col = (t < CUT_TIME) ? shotA(uv, t) : shotB(uv, t);

    // micro-texture: fine luminance break-up that the reference gets from painted materials
    float micro = fbm(uv * 38.0, 2) * 0.5 + 0.5;
    col *= 0.97 + 0.06 * micro;

    // gentle contrast and edge falloff, then 8-bit dither
    col = clamp(col, 0.0, 1.0);
    col = mix(col, col * col * (3.0 - 2.0 * col), 0.18);
    col *= 1.0 - 0.10 * dot(uv * vec2(0.55, 0.7), uv * vec2(0.55, 0.7));
    fragColor = vec4(col + ditherTPDF(fragCoord, iFrame), 1.0);
}
