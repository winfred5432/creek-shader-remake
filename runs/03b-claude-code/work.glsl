// Creek fishing remake: shot A (dock, camera follows the boat upstream), hard cut at 3.625 s,
// shot B (waterfall cove: slow descent, fast push at 6.8-7.4 s, then static close-up with the angler).
// Rendering: SDF raymarch of a heightfield plus props; water is a separate plane shaded by depth
// (Beer-Lambert over the bed), with soft sun shadows on it. Fishing rod and line are 2D overlays.
// Paste-ready version: python3 .claude/skills/shader-art-coding/scripts/glsl_tools.py bundle work.glsl -o final.glsl

#define DEBUG_MODE 0   // 0 final | 2 normals | 3 material ids | 5 shadow/AO
#define AA 2           // samples per pixel

// ---- timeline (seconds, video pts) ----
const float CUT_T = 3.6042;        // between frame 86 (3.583 s) and frame 87 (3.625 s)
const float PUSH_T0 = 6.8;         // fast push starts
const float PUSH_T1 = 7.4;         // close-up reached

// ---- light ----
const vec3 SUN_DIR = vec3(-0.3670, 0.8190, 0.4420);   // from the north-west: shadows fall to the lower right
const vec3 SUN_COL = vec3(0.98, 0.93, 0.83);
const vec3 SKY_COL = vec3(0.60, 0.65, 0.70);
const vec3 GND_COL = vec3(0.20, 0.20, 0.18);
const float SHADOW_K = 5.0;        // smaller = larger, softer penumbrae
const float EXPOSURE = 1.0;

// ---- water ----
const vec3 WATER_EXT = vec3(1.10, 0.28, 0.42);   // RGB extinction per unit depth: red goes first
const float WATER_Y = 0.0;

// ---- materials ----
const float M_GROUND = 1.0;
const float M_ROCK = 2.0;
const float M_WALL = 3.0;
const float M_ROOF = 4.0;
const float M_DECK = 5.0;
const float M_LEAF = 6.0;
const float M_TRUNK = 7.0;
const float M_HAT = 8.0;
const float M_BODY = 9.0;
const float M_HULL = 10.0;
const float M_HULL_IN = 11.0;
const float M_BOULDER = 12.0;
const float M_FALL = 13.0;
const float M_PIER = 14.0;
const float M_ROOF2 = 15.0;
const float M_PINE = 16.0;
const float M_BUSH = 17.0;
const float M_SKIN = 18.0;
const float M_BASKET = 19.0;

int gScene;        // 0 = dock, 1 = cove
float gT;          // iTime
vec3 gBoatPos;     // boat waterline center (world)
float gBoatScale = 1.0;   // uniform boat size; shot A uses a smaller boat to match the reference
float gBoatYaw;
float gFishing;    // 0 rowing (oar), 1 fishing (rod)
float gViewDist;   // camera distance to its target
// Fishing timeline (reference: bite and reel 10.25-13.08 s, fish lifted out right after).
const float HOOK_T = 10.3;
const float LIFT_T0 = 12.9;
const float LIFT_T1 = 13.5;
float gHook;       // 0 waiting .. 1 fish on the line
float gLift;       // 0 in the water .. 1 fish lifted into the boat
vec3 gLineEnd;     // bobber or hooked fish, world space
float gFloor = -1e3;  // terrain is clamped to this height; set to the water level for water-surface shadows,
                      // which also skip the cove pines (their long shadows would cover the whole pond)

vec3 rgb(float r, float g, float b) { return srgbToLinear(vec3(r, g, b)); }

// ------------------------------------------------------------------ shared props

// Boat in local space: +z is the bow, origin at the waterline center.
vec2 opU(vec2 a, vec2 b) { return a.x < b.x ? a : b; }

const float OAR_PERIOD = 1.5;   // seconds per rowing stroke

// Oar in boat-local space: pivot at the right oarlock, sweeping fore-aft and dipping on the pull.
// Returns the blade center; dir is the shaft direction.
vec3 oarBlade(out vec3 pivot, out vec3 dir) {
    float ph = TAU * gT / OAR_PERIOD;
    float sweep = 0.55 * sin(ph);
    float dip = mix(0.12, 0.42, 0.5 + 0.5 * cos(ph));
    pivot = vec3(0.6, 0.4, 0.3);
    dir = vec3(cos(sweep) * cos(dip), -sin(dip), -sin(sweep) * cos(dip));
    return pivot + dir * 1.45;
}

vec2 boatMap(vec3 p) {
    vec3 q = (p - gBoatPos) / gBoatScale;
    q.xz = rot2(gBoatYaw) * q.xz;
    float bound = sdBox(q - vec3(0.4, 0.6, 0.0), vec3(2.3, 1.3, 2.0));
    if (bound > 1.5) return vec2(bound * gBoatScale, M_HULL);

    float outer = sdEllipsoid(q - vec3(0.0, 0.12, 0.0), vec3(0.66, 0.46, 1.6));
    float inner = sdEllipsoid(q - vec3(0.0, 0.18, 0.0), vec3(0.56, 0.42, 1.48));
    bool solid = gFloor > -1.0;   // water-surface shadow queries see a solid boat: clean silhouette
    float hull = max(solid ? outer : opSubtract(outer, inner), q.y - 0.36);
    hull = max(hull, -q.z - 1.42);
    // The inner wall (where the subtracted ellipsoid is the nearest surface) takes the light interior wood.
    vec2 res = vec2(hull, (!solid && -inner > outer && q.y < 0.33) ? M_HULL_IN + 0.5 : M_HULL);
    if (!solid) {
        // Gunwale rail and ribs (fractional id = darker trim).
        float rail = length(vec2(sdEllipse(q.xz, vec2(0.61, 1.53)), q.y - 0.36)) - 0.045;
        rail = max(rail, -q.z - 1.42);
        float band = abs(inner + 0.025) - 0.025;
        float ribs = max(max(band, abs(q.z - 0.32 * floor(q.z / 0.32 + 0.5)) - 0.025), q.y - 0.34);
        res = opU(res, vec2(min(rail, ribs), M_HULL + 0.5));

        float seats = sdBox(q - vec3(0.0, 0.16, -0.75), vec3(0.5, 0.04, 0.16));
        seats = min(seats, sdBox(q - vec3(0.0, 0.16, 0.15), vec3(0.54, 0.04, 0.14)));
        seats = min(seats, max(inner + 0.02, q.y - 0.06));
        seats = min(seats, max(sdBox(q - vec3(0.0, 0.0, -1.38), vec3(0.42, 0.3, 0.05)), outer));
        res = opU(res, vec2(seats, M_HULL_IN));
    }

    // Rower / angler near the bow: trousers, red shirt and sleeves, wicker backpack, head, straw hat.
    vec3 b = q - vec3(0.0, 0.0, 0.62);
    vec3 bx = vec3(abs(b.x), b.yz);
    float legs = sdCapsule(bx, vec3(0.12, 0.2, 0.0), vec3(0.12, 0.24, 0.42), 0.11);
    res = opU(res, vec2(legs, M_BODY + 0.5));
    float torso = sdRoundCone(b - vec3(0.0, 0.2, -0.05), 0.24, 0.17, 0.45);
    float arms = sdCapsule(b, vec3(0.2, 0.6, 0.0), vec3(0.22, 0.45, 0.36), 0.07);
    arms = min(arms, sdCapsule(b, vec3(-0.2, 0.6, 0.0), vec3(0.06, 0.45, 0.4), 0.07));
    res = opU(res, vec2(smin(torso, arms, 0.06), M_BODY));
    res = opU(res, vec2(sdRoundBox(b - vec3(0.0, 0.48, -0.28), vec3(0.2, 0.24, 0.12), 0.05), M_BASKET));
    res = opU(res, vec2(sdSphere(b - vec3(0.0, 0.82, 0.03), 0.15), M_SKIN));
    float hat = sdCappedCone(b - vec3(0.0, 1.0, 0.0), 0.07, 0.48, 0.2);
    hat = smin(hat, sdCappedCone(b - vec3(0.0, 1.12, 0.0), 0.08, 0.22, 0.08), 0.05);
    res = opU(res, vec2(hat, M_HAT));

    if (gFishing < 0.5) {
        vec3 pivot, dir;
        vec3 blade = oarBlade(pivot, dir);
        float oar = sdCapsule(q, pivot - dir * 0.35, blade, 0.04);
        // Blade: flattened ellipsoid in the shaft frame.
        vec3 side = normalize(cross(dir, vec3(0.0, 1.0, 0.0)));
        vec3 up = cross(side, dir);
        vec3 l = q - blade;
        oar = min(oar, sdEllipsoid(vec3(dot(l, side), dot(l, up), dot(l, dir)), vec3(0.14, 0.035, 0.32)));
        res = opU(res, vec2(oar, M_HULL + 0.5));
    }
    return vec2(res.x * gBoatScale, res.y);
}

// ------------------------------------------------------------------ shot A: dock

// Signed distance to the river/lagoon outline in the ground plane (negative = water).
float waterA(vec2 q) {
    float c = -0.2 - 0.07 * q.y;
    float hw = 2.65 - 0.17 * q.y;
    float channel = abs(q.x - c) - hw;
    float lakeEdge = mix(-0.5, -3.0, smoothstep(-5.0, -2.5, q.x));
    float lake = q.y - lakeEdge;
    float d = smin(channel, lake, 2.6);
    return d + 0.5 * (valueNoise(q * 0.45) - 0.5);
}

float grassA(vec2 q) {
    float g = sdCircle(q - vec2(4.2, 5.4), 2.4);
    g = min(g, sdEllipse(q - vec2(6.1, 0.4), vec2(2.4, 1.6)));
    g = min(g, sdCircle(q - vec2(-6.0, 7.6), 2.6));
    g = min(g, sdCircle(q - vec2(9.5, 3.0), 2.5));
    g = min(g, sdCircle(q - vec2(4.0, 10.5), 3.0));
    return g + 0.6 * (valueNoise(q * 0.8) - 0.5);
}

float heightA(vec2 q) {
    float s = waterA(q);
    float h = s > 0.0 ? 0.3 * (1.0 - exp(-2.0 * s)) : -1.5 * (1.0 - exp(0.9 * s));
    h += 0.06 * smoothstep(0.2, -0.2, grassA(q));
    return h;
}

// Low-poly boulder: an ellipsoid trimmed by a few hashed planes, which leaves flat facets.
float facetedRock(vec3 q, vec3 r, float seed) {
    float d = sdEllipsoid(q, r);
    for (int i = ZERO; i < 6; i++) {
        vec3 n = normalize(hash33(vec3(seed, float(i), 7.0)) * 2.0 - vec3(1.0, 0.2, 1.0));
        d = max(d, dot(q / r, n) * min(r.x, min(r.y, r.z)) - 0.82 * min(r.x, min(r.y, r.z)));
    }
    return d;
}

vec2 treeA(vec3 p, vec3 c, float r) {
    vec3 q = p - c;
    float bound = length(q) - r * 1.35;
    if (bound > 1.5) return vec2(bound, M_LEAF);
    float d = sdSphere(q, r);
    d = smin(d, sdSphere(q - vec3(0.7, -0.2, 0.5) * r, r * 0.7), 0.5);
    d = smin(d, sdSphere(q - vec3(-0.6, -0.1, -0.5) * r, r * 0.72), 0.5);
    d += r * 0.22 * (valueNoise(q * 1.6 / r * 2.0) - 0.5);
    vec2 res = vec2(d * 0.7, M_LEAF);
    float trunk = sdCapsule(q, vec3(0.0, -c.y, 0.0), vec3(0.0, -0.3 * r, 0.0), 0.28);
    return opU(res, vec2(trunk, M_TRUNK));
}

vec2 mapA(vec3 p) {
    vec2 res = vec2((p.y - max(heightA(p.xz), gFloor)) * 0.55, M_GROUND);

    // Deck on stilts, house, roofs.
    vec2 b = vec2(sdBox(p - vec3(-7.6, 0.55, -0.275), vec3(4.6, 0.12, 3.425)), M_DECK);
    vec3 pp = p;
    pp.x = mod(p.x + 12.0, 2.15) - 1.075;
    float posts = sdCylinder(pp - vec3(0.0, -0.3, -3.6), 0.95, 0.13);
    posts = max(posts, p.x + 2.8);
    posts = max(posts, -p.x - 12.0);
    b = opU(b, vec2(posts, M_PIER));
    // Crates (slatted), barrel, coiled rope, rope rail along the deck front.
    b = opU(b, vec2(sdBox(p - vec3(-5.2, 0.95, -1.45), vec3(0.32, 0.3, 0.32)), M_WALL + 0.5));
    b = opU(b, vec2(sdBox(p - vec3(-4.6, 0.85, -2.15), vec3(0.26, 0.22, 0.26)), M_WALL + 0.5));
    b = opU(b, vec2(sdCylinder(p - vec3(-4.5, 1.1, -0.2), 0.45, 0.3), M_WALL + 0.5));
    b = opU(b, vec2(sdTorus(p - vec3(-6.6, 0.72, -2.15), vec2(0.28, 0.06)), M_HULL_IN));
    vec3 rp = p - vec3(-7.0, 1.05, -3.6);
    float rail = sdCapsule(rp, vec3(-3.0, 0.0, 0.0), vec3(3.0, 0.0, 0.0), 0.04);
    rail = min(rail, sdCapsule(rp, vec3(-3.0, -0.25, 0.0), vec3(3.0, -0.25, 0.0), 0.03));
    b = opU(b, vec2(rail, M_HULL_IN));
    // House walls; roof ridge along z near the back wall, one long plank slope down toward the river (+x).
    b = opU(b, vec2(sdBox(p - vec3(-8.0, 1.75, 1.3), vec3(3.6, 1.1, 2.3)), M_WALL));
    vec3 rq = vec3(p.x, p.y, p.z - 1.3);
    float gable = opExtrude(rq, sdTriangle(rq.xy, vec2(-11.9, 2.85), vec2(-4.2, 2.75), vec2(-10.6, 5.8)), 2.6);
    b = opU(b, vec2(gable - 0.03, M_ROOF));
    // Bent stovepipe on the roof.
    float pipe = sdCapsule(p, vec3(-9.6, 5.0, 0.6), vec3(-9.6, 6.0, 0.6), 0.1);
    pipe = min(pipe, sdCapsule(p, vec3(-9.6, 6.0, 0.6), vec3(-9.2, 6.25, 0.3), 0.1));
    b = opU(b, vec2(pipe, M_PIER));
    // Striped awning: tucked under the main eave, nearly flat, reaching back to the roof's rear; one corner post.
    vec3 lt = p - vec3(-3.45, 2.3, 1.35);
    lt.xy = rot2(-0.08) * lt.xy;
    lt.zy = rot2(0.06) * lt.zy;
    b = opU(b, vec2(sdBox(lt, vec3(0.95, 0.07, 2.45)), M_ROOF2));
    b = opU(b, vec2(sdCylinder(p - vec3(-2.75, 1.45, -0.95), 0.8, 0.08), M_PIER));

    // Broken pier halves with posts.
    vec2 pier = vec2(sdBox(p - vec3(-1.75, 0.85, 3.45), vec3(0.95, 0.07, 0.85)), M_PIER);
    pier = opU(pier, vec2(sdBox(p - vec3(1.95, 0.85, 3.5), vec3(0.95, 0.07, 0.8)), M_PIER));
    vec3 pq = p;
    pq.z = abs(pq.z - 3.47) - 0.8;
    float pierPosts = min(sdCylinder(pq - vec3(-2.65, 0.4, 0.0), 1.1, 0.12),
                          sdCylinder(pq - vec3(-0.85, 0.4, 0.0), 1.1, 0.12));
    pierPosts = min(pierPosts, min(sdCylinder(pq - vec3(1.05, 0.4, 0.0), 1.1, 0.12),
                                   sdCylinder(pq - vec3(2.85, 0.4, 0.0), 1.1, 0.12)));
    pier = opU(pier, vec2(pierPosts, M_TRUNK));
    // Rope rails along each half, and a broken plank hanging into the gap.
    vec3 rz = p;
    rz.z = abs(rz.z - 3.47) - 0.8;
    float ropes = min(sdCapsule(rz, vec3(-2.65, 1.45, 0.0), vec3(-0.85, 1.4, 0.0), 0.035),
                      sdCapsule(rz, vec3(1.05, 1.4, 0.0), vec3(2.85, 1.45, 0.0), 0.035));
    pier = opU(pier, vec2(ropes, M_HULL_IN));
    vec3 bp = p - vec3(-0.45, 0.6, 3.2);
    bp.xy = rot2(-0.45) * bp.xy;
    pier = opU(pier, vec2(sdBox(bp, vec3(0.55, 0.05, 0.16)), M_PIER));
    b = opU(b, pier);

    // Faceted boulders.
    float rk = facetedRock(p - vec3(5.4, 0.25, 5.4), vec3(1.25, 0.75, 0.95), 1.0);
    rk = min(rk, facetedRock(p - vec3(5.9, 0.2, 0.5), vec3(1.15, 0.7, 0.85), 2.0));
    rk = min(rk, facetedRock(p - vec3(-7.4, 0.3, 7.6), vec3(1.2, 0.85, 1.0), 3.0));
    rk = min(rk, facetedRock(p - vec3(-5.4, 0.25, 8.4), vec3(0.6, 0.45, 0.5), 4.0));
    rk = min(rk, facetedRock(p - vec3(7.0, 0.25, 9.6), vec3(0.8, 0.55, 0.7), 5.0));
    b = opU(b, vec2(rk, M_BOULDER));
    // Red crab on the sand.
    vec3 cq = p - vec3(3.6, 0.36, 2.6);
    float crab = sdEllipsoid(cq, vec3(0.16, 0.07, 0.12));
    crab = min(crab, sdCapsule(vec3(abs(cq.x), cq.yz), vec3(0.1, 0.0, 0.0), vec3(0.24, -0.04, 0.1), 0.025));
    b = opU(b, vec2(crab, M_BODY));

    // Trees.
    b = opU(b, treeA(p, vec3(9.0, 3.4, 4.6), 2.2));
    b = opU(b, treeA(p, vec3(9.2, 3.1, 1.0), 1.9));
    b = opU(b, treeA(p, vec3(8.8, 3.6, 8.4), 2.3));
    b = opU(b, treeA(p, vec3(7.4, 3.5, 6.4), 1.9));
    b = opU(b, treeA(p, vec3(-3.4, 3.4, 8.6), 2.1));
    b = opU(b, treeA(p, vec3(0.5, 3.6, 12.5), 2.4));
    b = opU(b, treeA(p, vec3(-9.5, 3.4, 10.5), 2.2));
    res = opU(res, b);
    return opU(res, boatMap(p));
}

// ------------------------------------------------------------------ shot B: waterfall cove

const float RIM_H = 2.8;     // cliff height above the water
const float GROUND_H = 2.6;  // meadow level

float pondB(vec2 q) {
    float d = sdEllipse(q - vec2(0.2, 0.0), vec2(4.4, 3.4));
    d = smin(d, sdTriangle(q, vec2(-4.4, -0.2), vec2(4.8, -0.2), vec2(1.0, -6.6)), 2.6);
    d = smin(d, sdBox(q - vec2(-0.5, 4.0), vec2(0.9, 1.4)), 0.6);              // inflow above the fall
    return d + 0.8 * (valueNoise(q * 0.42 + 3.0) - 0.5) + 0.25 * (valueNoise(q * 1.3) - 0.5);
}

float heightB(vec2 q) {
    float d = pondB(q);
    if (d < 0.0) return -0.7 * (1.0 - exp(4.0 * d)) - 1.3 * (1.0 - exp(0.7 * d));
    float wall = RIM_H * smoothstep(-0.1, 0.9, d);
    float top = RIM_H + 0.35 * valueNoise(q * 0.9) - 0.15;
    float h = mix(wall, top, smoothstep(0.7, 1.0, d));
    h = mix(h, GROUND_H, smoothstep(0.85, 1.2, d));
    // Stream bed above the fall stays at cliff-top level.
    float inflow = sdBox(q - vec2(-0.5, 5.6), vec2(1.0, 2.0));
    h = mix(h, RIM_H - 0.4, smoothstep(0.3, -0.3, inflow) * step(4.2, q.y));
    return h;
}

// Cove conifers: vec4(x, z, height, radius) at meadow level.
const int PINE_COUNT = 6;
vec4 pineParams(int i) {
    if (i == 0) return vec4(-7.6, -0.8, 8.0, 3.0);
    if (i == 1) return vec4(-7.2, 4.6, 7.5, 2.7);
    if (i == 2) return vec4(-5.2, -5.6, 7.8, 2.9);
    if (i == 3) return vec4(6.6, -6.2, 8.0, 3.1);
    if (i == 4) return vec4(-1.0, -9.0, 7.8, 2.9);
    return vec4(-4.0, 8.8, 7.0, 2.5);
}

const float PINE_TIERS = 7.0;
const float PINE_BRANCHES = 13.0;

// Tier layout shared by geometry and shading: x = tier index, y = position inside the tier (0 rim .. 1 top),
// z = tier radius, w = tier half-height.
vec4 pineTier(float y, float h, float r) {
    float y0 = 0.18 * h, stepH = (h - y0) / PINE_TIERS;
    float i = clamp(floor((y - y0) / stepH), 0.0, PINE_TIERS - 1.0);
    float local = clamp((y - y0) / stepH - i, 0.0, 1.0);
    return vec4(i, local, r * (1.0 - 0.8 * i / PINE_TIERS), 0.9 * stepH);
}

vec2 pine(vec3 p, vec4 prm) {
    vec3 q = p - vec3(prm.x, GROUND_H, prm.y);
    float h = prm.z, r = prm.w;
    float rad = length(q.xz);
    float bound = max(rad - r - 0.6, abs(q.y - 0.5 * h) - 0.5 * h - 0.4);
    if (bound > 1.5) return vec2(bound, M_PINE);
    float a = atan(q.z, q.x + 1e-4);
    float y0 = 0.18 * h, stepH = (h - y0) / PINE_TIERS;
    float d = 1e9;
    // Each point is inside at most two overlapping tiers: its own and the one below.
    float ti = clamp(floor((q.y - y0) / stepH), 0.0, PINE_TIERS - 1.0);
    for (int k = ZERO; k < 2; k++) {
        float i = clamp(ti - float(k), 0.0, PINE_TIERS - 1.0);
        float rr = r * (1.0 - 0.8 * i / PINE_TIERS);
        float hh = 0.9 * stepH;
        float c = sdCappedCone(q - vec3(0.0, y0 + i * stepH + hh, 0.0), hh, rr, rr * 0.08);
        // Branch fingers with gaps between them, and serrated needle tips.
        float f = abs(fract(a * PINE_BRANCHES / TAU + 0.37 * i) - 0.5) * 2.0;
        c += rr * 0.22 * smoothstep(0.35, 1.0, f) * smoothstep(0.25 * rr, rr, rad);
        c += 0.1 * valueNoise(vec2(a * rad * 5.0, rad * 6.0 + q.y * 3.0)) + 0.1 * valueNoise(vec2(a * rad * 14.0, rad * 12.0));
        d = min(d, c);
    }
    vec2 res = vec2(d * 0.45, M_PINE);
    float trunk = sdCapsule(q, vec3(0.0), vec3(0.0, h * 0.5, 0.0), 0.25);
    return opU(res, vec2(trunk, M_TRUNK));
}

// Painted pine albedo: dark gaps between branches and under each tier, light needle tips, radial needle strokes.
vec3 pineAlbedo(vec3 p) {
    vec4 prm = pineParams(0);
    float best = 1e9;
    for (int i = ZERO; i < PINE_COUNT; i++) {
        vec4 c = pineParams(i);
        float dd = length(p.xz - c.xy) / c.w;
        if (dd < best) { best = dd; prm = c; }
    }
    vec3 q = p - vec3(prm.x, GROUND_H, prm.y);
    float rad = length(q.xz);
    float a = atan(q.z, q.x + 1e-4);
    vec4 tier = pineTier(q.y, prm.z, prm.w);
    float f = abs(fract(a * PINE_BRANCHES / TAU + 0.37 * tier.x) - 0.5) * 2.0;
    float tip = smoothstep(0.45, 1.0, rad / tier.z);
    float under = smoothstep(0.35, 0.95, tier.y);
    // Needle clumps: spiky star tufts scattered in top-down xz (the view is mostly from above), turned outward.
    // Inner tufts sit higher on the cone, so they overlap outer ones like shingles; tone runs dark root -> light tip.
    vec2 uv = q.xz * 4.0;
    vec2 cell = floor(uv);
    float cover = 0.0, toTip = 0.0, nearest = 1e9, streak = 0.0;
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 cid = cell + vec2(float(i), float(j));
        vec2 h = hash22(cid + vec2(17.0 * tier.x, 0.0));
        vec2 ctr = cid + 0.15 + 0.7 * h;
        vec2 d = uv - ctr;
        d = rot2(-a + 0.9 * (h.x - 0.5)) * d + vec2(0.35, 0.0);   // local +x points away from the trunk
        if (length(ctr) > nearest) continue;
        // A fan of five tapered needles from the tuft root.
        for (int k = 0; k < 5; k++) {
            float ang = 0.32 * (float(k) - 2.0) + 0.15 * (hash12(cid + float(k) * 7.1) - 0.5);
            vec2 tipP = vec2(cos(ang), sin(ang)) * (0.85 + 0.25 * h.y);
            float along = clamp(dot(d, tipP) / dot(tipP, tipP), 0.0, 1.0);
            if (sdSegment(d, vec2(0.0), tipP) < 0.17 * (1.0 - along) + 0.02) {
                nearest = length(ctr);
                cover = 1.0;
                toTip = along;
                streak = float(k & 1);
            }
        }
    }
    float shade = (0.7 + 0.3 * tip) * (1.0 - 0.2 * f) * (1.0 - 0.35 * under);
    float light = mix(0.2, (0.4 + 0.75 * toTip) * (0.8 + 0.3 * streak), cover) * shade;
    vec3 dark = rgb(0.30, 0.46, 0.30), mid = rgb(0.62, 0.76, 0.46), tipc = rgb(0.84, 0.92, 0.60);
    vec3 c = mix(dark, mid, smoothstep(0.0, 0.45, light));
    return mix(c, tipc, smoothstep(0.45, 0.9, light));
}

vec2 mapB(vec3 p) {
    vec2 res = vec2((p.y - max(heightB(p.xz), gFloor)) * 0.36, M_GROUND);

    // Waterfall: sheet between two stacks of blocks, plus stubs in the plunge pool.
    vec2 b = vec2(sdBox(p - vec3(-0.5, 1.3, 3.75), vec3(1.0, 1.45, 0.12)), M_FALL);
    // Stacked slabs either side of the fall (each slab slightly offset), and rounded pillars in the pool.
    float blocks = 1e9;
    for (int i = ZERO; i < 4; i++) {
        float fi = float(i);
        vec2 jit = hash22(vec2(fi, 11.0)) - 0.5;
        blocks = min(blocks, sdRoundBox(p - vec3(1.4 + 0.25 * jit.x, 0.45 + 0.85 * fi, 3.9 + 0.2 * jit.y),
                                        vec3(0.8 - 0.06 * fi, 0.4, 0.75), 0.12));
        blocks = min(blocks, sdRoundBox(p - vec3(-2.35 + 0.25 * jit.y, 0.45 + 0.85 * fi, 3.95 + 0.2 * jit.x),
                                        vec3(0.8 - 0.05 * fi, 0.4, 0.75), 0.12));
    }
    blocks = min(blocks, sdRoundBox(p - vec3(1.95, 0.7, 3.2), vec3(0.55, 0.45, 0.45), 0.12));
    blocks = min(blocks, sdRoundBox(p - vec3(-0.2, 0.2, 2.75), vec3(0.3, 0.55, 0.26), 0.16));
    blocks = min(blocks, sdRoundBox(p - vec3(1.05, 0.15, 2.55), vec3(0.32, 0.5, 0.28), 0.16));
    b = opU(b, vec2(blocks, M_ROCK + 0.5));
    // Churning foam pile at the foot of the fall.
    vec3 fq = p - vec3(-0.5, 0.05, 3.3);
    float foamPile = sdEllipsoid(fq, vec3(1.25, 0.35, 0.45));
    foamPile += 0.18 * (valueNoise(p * 3.0 + vec3(0.0, gT * 2.0, 0.0)) - 0.5);
    b = opU(b, vec2(foamPile * 0.7, M_FALL + 0.5));

    // Pale boulder beside the boat, and a submerged slab.
    vec3 bq = p - vec3(-2.75, 0.25, -0.1);
    bq.xz = rot2(0.3) * bq.xz;
    float boulder = sdHexPrism(bq.xzy, vec2(0.78, 0.6)) - 0.18;
    b = opU(b, vec2(boulder, M_BOULDER));
    float slab = sdEllipsoid(p - vec3(2.6, -1.35, -2.8), vec3(1.1, 0.55, 1.3));
    b = opU(b, vec2(slab, M_BOULDER + 0.5));

    // Pines around the cove.
    if (gFloor < -1.0) {
        for (int i = ZERO; i < PINE_COUNT; i++) b = opU(b, pine(p, pineParams(i)));
    }

    // Dark pointed rock in the meadow north-west of the fall.
    b = opU(b, vec2(facetedRock(p - vec3(-3.4, GROUND_H + 0.3, 6.0), vec3(0.7, 0.9, 0.5), 9.0), M_ROCK));

    // Round bushes.
    float bush = sdSphere(p - vec3(-4.6, GROUND_H + 0.6, -4.6), 1.1);
    bush = min(bush, sdSphere(p - vec3(3.6, GROUND_H + 0.5, -7.4), 1.0));
    bush = min(bush, sdSphere(p - vec3(7.8, GROUND_H + 0.5, 6.0), 1.1));
    bush += 0.25 * (valueNoise(p * 2.5) - 0.5);
    b = opU(b, vec2(bush * 0.8, M_BUSH));

    res = opU(res, b);
    return opU(res, boatMap(p));
}

vec2 map(vec3 p) {
    if (gScene == 0) return mapA(p);
    return mapB(p);
}

// ------------------------------------------------------------------ materials

float shoreSDF(vec2 q) { return gScene == 0 ? waterA(q) : pondB(q); }

vec3 groundAlbedo(vec3 p, vec3 n) {
    vec2 q = p.xz;
    float nz = valueNoise(q * 1.3);
    if (gScene == 0) {
        vec3 sand = mix(rgb(0.80, 0.78, 0.60), rgb(0.86, 0.83, 0.66), nz);
        vec3 bed = mix(rgb(0.60, 0.74, 0.62), rgb(0.54, 0.70, 0.58), nz);
        vec3 grass = mix(rgb(0.52, 0.72, 0.30), rgb(0.62, 0.80, 0.38), valueNoise(q * 2.7));
        vec3 c = p.y < 0.02 ? bed : sand;
        if (p.y < 0.02) {
            // Fern-like water plants on the bed in front of the deck.
            for (int i = ZERO; i < 5; i++) {
                vec2 h = hash22(vec2(float(i), 3.0));
                vec2 l = q - vec2(-9.0 + 5.0 * h.x, -5.4 - 1.6 * h.y);
                float fern = sdStar(rot2(6.0 * h.x) * l, 0.55, 7, 4.0);
                c = mix(c, h.y > 0.7 ? rgb(0.42, 0.28, 0.45) : rgb(0.30, 0.52, 0.26), smoothstep(0.03, -0.03, fern));
            }
        }
        return mix(c, grass, smoothstep(0.08, -0.08, grassA(q)) * step(0.02, p.y));
    }
    float d = pondB(q);
    vec3 bed = mix(rgb(0.55, 0.86, 0.70), rgb(0.50, 0.70, 0.36), 0.7 * smoothstep(0.7, 0.9, valueNoise(q * 0.6)));
    // Near the shore the bed is the rock wall continuing under water.
    if (p.y < 0.02) return mix(bed, rgb(0.50, 0.54, 0.54), smoothstep(-0.6, -0.1, d));
    float streak = valueNoise(vec2(q.x + q.y, p.y * 2.0) * 1.4) * 0.6 + 0.4 * valueNoise(q * 3.1 + p.y);
    vec3 rock = mix(rgb(0.52, 0.55, 0.56), rgb(0.64, 0.66, 0.66), streak);
    rock *= 0.85 + 0.3 * valueNoise(q * 0.7);
    float fr = length(fract(q * 5.0) - 0.5);
    float isFlower = step(0.92, hash12(floor(q * 5.0)));
    vec3 grass = mix(rgb(0.50, 0.68, 0.32), rgb(0.62, 0.78, 0.40), valueNoise(q * 1.9));
    grass = mix(grass, rgb(0.40, 0.56, 0.26), 0.6 * smoothstep(0.6, 0.8, valueNoise(q * 7.0)));   // tufts
    grass = mix(grass, rgb(0.95, 0.94, 0.88), isFlower * step(fr, 0.2));
    grass = mix(grass, rgb(0.95, 0.80, 0.30), isFlower * step(fr, 0.07));
    float g = smoothstep(0.85, 1.05, d + 0.3 * (nz - 0.5)) * smoothstep(0.4, 0.8, n.y);
    return mix(rock, grass, g);
}

void material(float id, vec3 p, vec3 n, out vec3 albedo, out float wrap) {
    float m = floor(id);
    wrap = 0.3;
    if (m == M_GROUND) {
        albedo = groundAlbedo(p, n);
    } else if (m == M_ROCK) {
        albedo = mix(rgb(0.46, 0.49, 0.50), rgb(0.58, 0.60, 0.60), valueNoise(p.xy * 3.0 + p.z));
        albedo = mix(albedo, rgb(0.42, 0.52, 0.30), 0.6 * smoothstep(0.6, 0.9, n.y) * smoothstep(0.4, 0.7, valueNoise(p.xz * 4.0)));   // moss on top
    } else if (m == M_WALL) {
        float plank = smoothstep(0.42, 0.5, abs(fract(p.y * 2.6) - 0.5));
        albedo = mix(rgb(0.50, 0.30, 0.24), rgb(0.40, 0.24, 0.20), plank);
        if (fract(id) > 0.1) {
            float slat = smoothstep(0.4, 0.5, abs(fract((p.y + p.x * 0.01) * 5.0) - 0.5));
            albedo = mix(rgb(0.66, 0.53, 0.40), rgb(0.48, 0.37, 0.27), slat);
        } else if (p.z < -0.95) {
            // Front wall: blue plank door with dark frame, round porthole window.
            if (p.x > -7.2 && p.x < -6.1 && p.y < 2.35) {
                float dp = smoothstep(0.4, 0.5, abs(fract(p.x * 4.0) - 0.5));
                albedo = mix(rgb(0.28, 0.45, 0.58), rgb(0.20, 0.34, 0.45), dp);
                if (p.x < -7.1 || p.x > -6.2 || p.y > 2.25) albedo = rgb(0.30, 0.20, 0.16);
            }
            float w = length(vec2(p.x + 8.3, p.y - 1.9));
            if (w < 0.36) albedo = w < 0.28 ? rgb(0.22, 0.32, 0.40) : rgb(0.30, 0.20, 0.16);
        }
    } else if (m == M_ROOF) {
        // Planks run down the slope along x (alternating tones across z); lighter battens run along the ridge.
        float plank = step(0.5, fract(p.z * 2.2));
        albedo = mix(rgb(0.62, 0.44, 0.40), rgb(0.52, 0.35, 0.31), plank);
        albedo *= 1.0 - 0.35 * smoothstep(0.42, 0.5, abs(fract(p.z * 2.2 + 0.25) - 0.5));
        float batten = smoothstep(0.86, 0.9, 1.0 - 2.0 * abs(fract((p.x + 12.0) / 1.25) - 0.5));
        albedo = mix(albedo, rgb(0.78, 0.64, 0.56), batten);
        wrap = 0.9;
        albedo *= 0.9 + 0.2 * valueNoise(p.xz * vec2(0.6, 4.0).yx);
    } else if (m == M_ROOF2) {
        float band = step(0.5, fract(p.z * 1.5));
        albedo = mix(rgb(0.70, 0.46, 0.39), rgb(0.86, 0.72, 0.60), band);
    } else if (m == M_DECK) {
        float plank = smoothstep(0.44, 0.5, abs(fract(p.z * 2.2) - 0.5));
        albedo = mix(rgb(0.74, 0.62, 0.50), rgb(0.60, 0.48, 0.38), plank);
    } else if (m == M_PIER) {
        float plank = smoothstep(0.4, 0.5, abs(fract(p.x * 2.5) - 0.5));
        albedo = mix(rgb(0.46, 0.42, 0.36), rgb(0.30, 0.27, 0.24), plank);
    } else if (m == M_LEAF) {
        float k = valueNoise(p * 2.2);
        albedo = mix(rgb(0.48, 0.64, 0.38), rgb(0.66, 0.80, 0.48), k);
        wrap = 0.5;
    } else if (m == M_PINE) {
        albedo = pineAlbedo(p);
        wrap = 0.8;
    } else if (m == M_BUSH) {
        albedo = mix(rgb(0.55, 0.58, 0.26), rgb(0.70, 0.70, 0.36), valueNoise(p * 3.0));
        wrap = 0.5;
    } else if (m == M_TRUNK) {
        albedo = rgb(0.36, 0.26, 0.20);
    } else if (m == M_HAT) {
        float hr = length(p.xz - (gBoatPos.xz + rot2(-gBoatYaw) * vec2(0.0, 0.62) * gBoatScale)) / gBoatScale;
        albedo = mix(rgb(0.84, 0.74, 0.48), rgb(0.74, 0.63, 0.40), smoothstep(0.4, 0.5, abs(fract(hr * 9.0) - 0.5)));
        albedo = mix(albedo, rgb(0.28, 0.55, 0.52), smoothstep(0.015, 0.0, abs(hr - 0.22) - 0.025));   // teal band
    } else if (m == M_BODY) {
        albedo = fract(id) > 0.1 ? rgb(0.24, 0.24, 0.30) : rgb(0.62, 0.24, 0.18);
    } else if (m == M_SKIN) {
        albedo = rgb(0.80, 0.60, 0.48);
    } else if (m == M_BASKET) {
        float weave = step(0.5, fract(p.y * 9.0)) * step(0.5, fract((p.x + p.z) * 9.0));
        albedo = mix(rgb(0.62, 0.46, 0.28), rgb(0.48, 0.34, 0.20), weave);
    } else if (m == M_HULL) {
        albedo = fract(id) > 0.1 ? rgb(0.44, 0.32, 0.26) : rgb(0.56, 0.38, 0.30);
    } else if (m == M_HULL_IN) {
        float plank = smoothstep(0.42, 0.5, abs(fract(p.x * 6.0) - 0.5));
        albedo = mix(rgb(0.74, 0.65, 0.56), rgb(0.60, 0.52, 0.44), plank);
        if (fract(id) > 0.1) albedo = mix(rgb(0.66, 0.56, 0.46), rgb(0.56, 0.47, 0.39), smoothstep(0.4, 0.5, abs(fract(p.y * 9.0) - 0.5)));
    } else if (m == M_BOULDER) {
        albedo = mix(rgb(0.70, 0.72, 0.66), rgb(0.78, 0.79, 0.74), valueNoise(p.xz * 2.0));
        if (fract(id) > 0.1) albedo = rgb(0.74, 0.80, 0.74);
    } else {
        albedo = rgb(0.8, 0.82, 0.84);
    }
}

vec3 lightSurface(vec3 p, vec3 n, vec3 albedo, float wrap, out float sha) {
    sha = softShadow(p + n * 0.02, SUN_DIR, 0.05, 25.0, SHADOW_K);
    float ao = calcAO(p, n, 0.5);
    vec3 key = SUN_COL * wrapDiffuse(n, SUN_DIR, wrap) * sha;
    // Foliage (high wrap) keeps a soft fill; hard surfaces get deep contact darkening in crevices.
    float occ = wrap > 0.45 ? mix(0.8, 1.0, ao) : mix(0.35, 1.0, ao * ao);
    vec3 fill = hemisphereLight(n, SKY_COL, GND_COL) * occ;
    return albedo * (key + fill);
}

// Waterfall sheet: streaks sliding down, brighter foam at the base.
// Waterfall: thin bright streaks sliding down over a see-through teal-grey sheet; the foot is a foam pile.
vec3 shadeFall(vec3 p, float id) {
    if (fract(id) > 0.1) {
        float n = valueNoise(p.xz * 6.0 + vec2(0.0, -gT * 2.0));
        return mix(rgb(0.80, 0.84, 0.85), rgb(0.97, 0.98, 0.98), n);
    }
    float s = 0.6 * valueNoise(vec2(p.x * 14.0, p.y * 0.8 + gT * 4.0)) + 0.4 * valueNoise(vec2(p.x * 31.0, p.y * 1.5 + gT * 5.0));
    s = smoothstep(0.45, 0.75, s);
    vec3 c = mix(rgb(0.36, 0.46, 0.48), rgb(0.94, 0.96, 0.97), s);
    return mix(c, rgb(0.92, 0.94, 0.95), smoothstep(0.9, 0.2, p.y));   // spray whitens the lower part
}

// Fish in the cove: dark slender shapes under the surface.
float fishMask(vec2 q) {
    float m = 0.0;
    for (int i = ZERO; i < 6; i++) {
        float fi = float(i);
        vec2 h = hash22(vec2(fi, 7.0));
        vec2 c = vec2(-0.3 + 3.2 * h.x, -2.6 + 3.6 * h.y);
        float rr = 0.5 + 0.6 * hash12(vec2(fi, 3.0));
        float w = (0.25 + 0.2 * h.y) * (h.x > 0.5 ? 1.0 : -1.0);
        float a = gT * w + fi * 2.1;
        vec2 pos = c + rr * vec2(cos(a), sin(a));
        vec2 dir = normalize(vec2(-sin(a), cos(a)) * sign(w));
        vec2 l = q - pos;
        l = vec2(dot(l, vec2(dir.y, -dir.x)), dot(l, dir));
        l /= 1.6;
        float body = sdVesica(l, 0.2, 0.17);
        float tail = sdTriangle(l, vec2(0.0, -0.22), vec2(-0.08, -0.36), vec2(0.08, -0.36));
        m = max(m, smoothstep(0.02, -0.01, min(body, tail)));
    }
    return m;
}

vec3 shadeWater(vec3 pw, float path, vec3 bedCol, float sha, float px) {
    vec2 q = pw.xz;
    float depth = max(path, 0.0);
    vec3 deep = gScene == 0 ? rgb(0.08, 0.67, 0.56) : rgb(0.03, 0.78, 0.60);
    vec3 tr = beerTransmittance(WATER_EXT, depth);
    vec3 col = bedCol * tr + deep * (1.0 - tr);

    // Caustic web on the bed.
    vec2 cq = q * 0.5 + 0.6 * vec2(valueNoise(q * 0.7 + gT * 0.15), valueNoise(q * 0.7 + 5.0 - gT * 0.12));
    vec3 vb = voronoiBorder(cq, 0.9);
    float caustic = smoothstep(0.14, 0.0, vb.x) * smoothstep(0.3, 0.7, valueNoise(q * 0.9 - gT * 0.1));
    col += rgb(0.55, 0.80, 0.68) * 0.22 * caustic * exp(-0.4 * depth) * (0.3 + 0.7 * sha);

    col *= mix(0.45, 1.0, sha);

    if (gScene == 1) col = mix(col, col * vec3(0.30, 0.42, 0.44), 0.85 * fishMask(q));

    // Thin foam line just inside the shore.
    float s = shoreSDF(q);
    // Jagged, mostly continuous foam line just inside the shore.
    float jag = 0.07 * (valueNoise(q * 9.0) - 0.5) + 0.04 * sin(gT * 1.5 + q.x * 2.0);
    float foam = strokeAA(s + 0.12 + jag, 0.028, px);
    foam *= smoothstep(0.1, 0.3, valueNoise(q * 1.7 + vec2(gT * 0.2, 0.0)));

    // Wake and ripples around the boat.
    vec2 bl = (q - gBoatPos.xz) / gBoatScale;
    bl = rot2(gBoatYaw) * bl;
    float e = sdEllipse(bl, vec2(0.75, 1.7));
    float wake = strokeAA(e - 0.15 - 0.1 * sin(gT * 2.0 + bl.y * 3.0), 0.03, px) * step(bl.y, 0.6);
    wake *= smoothstep(0.3, 0.6, valueNoise(bl * 6.0 + gT));
    foam = max(foam, wake * (1.0 - gFishing));

    if (gScene == 1) {
        // Lily pad near the south end of the pond.
        vec2 lp = rot2(0.6) * (q - vec2(0.6, -3.6));
        float pad = max(sdCircle(lp, 0.32), -sdPie(lp, vec2(0.2, 0.98), 0.4));
        col = mix(col, mix(rgb(0.36, 0.62, 0.22), rgb(0.48, 0.72, 0.30), valueNoise(lp * 8.0)), fillAA(pad, px));
        // Plunge-pool foam below the fall.
        vec2 f = q - vec2(-0.5, 3.15);
        float pool = sdEllipse(f, vec2(1.7, 0.7));
        float n = valueNoise(f * 4.0 + vec2(0.0, -gT * 1.5));
        foam = max(foam, smoothstep(0.3, -0.3, pool + 0.6 * (n - 0.5)) * 0.9);
        vec2 cell = floor(q * 14.0);
        float sparkle = step(0.93, hash12(cell + floor(gT * 8.0))) * smoothstep(1.2, -0.3, sdEllipse(f, vec2(2.4, 1.2)));
        foam = max(foam, sparkle * 0.9);
        // Bobber rings.
        if (gFishing > 0.5 && gLift < 0.5) {
            float r = length(q - gLineEnd.xz);
            float grow = fract(gT * (0.5 + gHook));
            float rings = strokeAA(r - 0.3 - 0.5 * grow, 0.03, px) * (1.0 - grow);
            rings = max(rings, strokeAA(r - 0.3 - 0.5 * fract(grow + 0.5), 0.025, px) * (1.0 - fract(grow + 0.5)));
            float splash = gHook * smoothstep(0.25, 0.0, r) * smoothstep(0.4, 0.7, valueNoise(q * 12.0 + gT * 6.0));
            foam = max(foam, max(rings * 0.8, splash));
        }
    }
    col = mix(col, rgb(0.92, 0.95, 0.93), foam);
    // Aerial haze: from far away the water reads darker and greyer (the reference wide shot vs close-up).
    float haze = smoothstep(6.0, 16.0, gViewDist);
    return mix(col, saturation(col, 0.85) * 0.72, haze);
}

// ------------------------------------------------------------------ camera rig

struct Cam { vec3 ta; float dist; float pitch; float yaw; float focal; };

Cam camAt(float t) {
    Cam c;
    if (t < CUT_T) {
        // Shot A: one framing (at t = 0) carried upstream with the boat.
        vec3 ta9 = vec3(-0.24, 0.0, -1.73);
        float d9 = 19.0, p9 = radians(50.0), y9 = radians(0.0), f9 = 4.2;
        c.ta = ta9 + vec3(0.28, 0.0, 1.0) * t;   // pan speed fitted to the reference pier track
        c.dist = d9; c.pitch = p9; c.yaw = y9; c.focal = f9;
        return c;
    }
    // Shot B keyframes: K0 at the cut, K1 at the start of the push, K2 close-up.
    vec3 ta0 = vec3(-0.4, 0.0, -1.6), ta1 = vec3(-0.4, 0.0, -0.4), ta2 = vec3(2.17, 0.0, 0.2);
    float d0 = 17.0, d1 = 13.0, d2 = 3.45;
    float p0 = radians(58.0), p1 = radians(64.0), p2 = radians(51.6);
    float y0 = 0.0, y1 = 0.0, y2 = radians(2.4);
    float f0 = 2.6, f1 = 2.6, f2 = 1.04;
    float a = clamp((t - CUT_T) / (PUSH_T0 - CUT_T), 0.0, 1.0);
    a = 0.6 * a + 0.4 * smoothstep(0.0, 1.0, a);
    float b = smoothstep(PUSH_T0, PUSH_T1, t);   // slow start, fast middle: close-up is reached near 7.3 s
    c.ta = mix(mix(ta0, ta1, a), ta2, b);
    c.dist = mix(mix(d0, d1, a), d2, b);
    c.pitch = mix(mix(p0, p1, a), p2, b);
    c.yaw = mix(mix(y0, y1, a), y2, b);
    c.focal = mix(mix(f0, f1, a), f2, b);
    return c;
}

void setupScene(float t) {
    gT = t;
    if (t < CUT_T) {
        gScene = 0;
        gBoatPos = vec3(-0.51 + 0.28 * t, 0.0, -2.6 + t);   // keeps pace with the camera
        gBoatYaw = 0.3;   // bow toward the upper right, as in the reference
        gBoatScale = 0.77;
        gFishing = 0.0;
        gHook = 0.0;
        gLift = 0.0;
        gLineEnd = vec3(0.0);
    } else {
        gScene = 1;
        gBoatScale = 1.0;
        float b = smoothstep(PUSH_T0 - 0.2, PUSH_T1, t);
        gBoatPos = vec3(-0.7 + 0.04 * sin(t * 0.7), 0.0, -0.45 + 0.05 * sin(t * 0.5));
        gBoatYaw = mix(0.0, -0.1, b);
        gFishing = step(PUSH_T0 + 0.1, t);
        gHook = smoothstep(HOOK_T, HOOK_T + 0.3, t);
        gLift = smoothstep(LIFT_T0, LIFT_T1, t);
        vec2 rest = vec2(2.6, 1.2);
        vec2 drag = mix(rest, vec2(1.3, 0.5), smoothstep(HOOK_T, LIFT_T0, t));
        drag += gHook * (1.0 - gLift) * 0.12 * vec2(sin(t * 7.0), cos(t * 5.3));
        // Lifted fish arcs up out of the water and lands on the middle seat.
        vec3 seat = gBoatPos + vec3((rot2(-gBoatYaw) * vec2(0.0, -0.3)).x, 0.3, (rot2(-gBoatYaw) * vec2(0.0, -0.3)).y);
        gLineEnd = mix(vec3(drag.x, 0.02, drag.y), seat, gLift) + vec3(0.0, 1.8 * sin(PI * gLift), 0.0);
    }
}

vec3 camPos(Cam c) {
    vec3 back = vec3(sin(c.yaw) * cos(c.pitch), sin(c.pitch), -cos(c.yaw) * cos(c.pitch));
    return c.ta + back * c.dist;
}

// cameraMatrix's first column points to world -x for a north-facing view; flip it so +x is screen right.
mat3 rigMatrix(vec3 ro, vec3 ta) {
    mat3 m = cameraMatrix(ro, ta, 0.0);
    m[0] = -m[0];
    return m;
}

vec2 project(mat3 cam, vec3 ro, float focal, vec3 p) {
    vec3 v = transpose(cam) * (p - ro);
    return v.xy / v.z * focal;
}

// ------------------------------------------------------------------ render

vec3 render(vec2 fragCoord, Cam c) {
    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    vec3 ro = camPos(c);
    mat3 cam = rigMatrix(ro, c.ta);
    vec3 rd = cameraRay(cam, uv, c.focal);

    vec3 hit = raymarch(ro, rd, 0.5, 80.0, 0.9);
    float tw = iPlane(ro, rd, vec3(0.0, 1.0, 0.0), -WATER_Y);
    float t = hit.x;
    float px = 2.0 / iResolution.y;

    vec3 col;
    if (t < 0.0 && tw > 0.0) {
        // Rays that graze the cliff foot can run out of steps; they end at the waterline, so shade them as water.
        vec3 pw = ro + rd * tw;
        col = shadeWater(pw, 0.3, rgb(0.50, 0.54, 0.54), 1.0, tw * px / c.focal);
        t = tw;
    } else if (t < 0.0) {
        col = gScene == 0 ? rgb(0.80, 0.78, 0.60) : rgb(0.45, 0.65, 0.30);
        t = 80.0;
    } else {
        vec3 p = ro + rd * t;
        vec3 n = calcNormal(p, 0.0006 * t);
        vec3 albedo;
        float wrap;
        material(hit.y, p, n, albedo, wrap);
        float sha = 1.0;
        bool under = tw > 0.0 && tw < t;
        if (floor(hit.y) == M_FALL) {
            col = shadeFall(p, hit.y);
        } else if (under) {
            col = albedo * (SUN_COL * wrapDiffuse(n, SUN_DIR, wrap) + hemisphereLight(n, SKY_COL, GND_COL));
        } else {
            col = lightSurface(p, n, albedo, wrap, sha);
        }
#if DEBUG_MODE == 2
        return debugNormal(n);
#elif DEBUG_MODE == 3
        return debugIdColor(floor(hit.y));
#elif DEBUG_MODE == 5
        return vec3(sha, calcAO(p, n, 0.5), 0.0);
#endif
        if (under) {
            vec3 pw = ro + rd * tw;
            gFloor = WATER_Y;
            // Shadow as seen on the bed: move the bed point up the sun ray to the surface, then trace from there.
            vec3 pb = p + SUN_DIR * ((WATER_Y - p.y) / SUN_DIR.y);
            float wsha = softShadow(pb + vec3(0.0, 0.15, 0.0), SUN_DIR, 0.05, 25.0, SHADOW_K);
            gFloor = -1e3;
            float footprint = tw * px / c.focal;
            col = shadeWater(pw, (t - tw) * abs(rd.y), col, wsha, footprint);
            t = tw;
        }
    }
    return col;
}

// Fishing rod and line, drawn in screen space from projected 3D points.
vec3 boatToWorld(vec3 l) {
    vec2 xz = rot2(-gBoatYaw) * l.xz;
    return gBoatPos + vec3(xz.x, l.y, xz.y) * gBoatScale;
}

float fishSilhouette(vec2 l) {
    float body = sdEllipse(l, vec2(0.05, 0.016));
    float tail = sdTriangle(l, vec2(-0.045, 0.0), vec2(-0.075, 0.018), vec2(-0.075, -0.018));
    return min(body, tail);
}

vec3 overlay(vec3 col, vec2 fragCoord, Cam c) {
    if (gFishing < 0.5) return col;
    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    vec3 ro = camPos(c);
    mat3 cam = rigMatrix(ro, c.ta);
    float px = 2.0 / iResolution.y;
    // Rod tip: waiting, bent toward the fish when hooked, raised high to lift it.
    vec3 tipL = mix(vec3(2.3, 2.0, 1.3), vec3(2.4, 1.5, 1.0), gHook);
    tipL = mix(tipL, vec3(0.6, 3.0, 0.6), gLift);
    vec2 a = project(cam, ro, c.focal, boatToWorld(vec3(0.3, 0.6, 0.98)));
    vec2 b = project(cam, ro, c.focal, boatToWorld(tipL));
    vec2 e = project(cam, ro, c.focal, gLineEnd);
    // Rod bends more under load.
    vec2 ab = b - a;
    vec2 rodCtl = mix(a, b, 0.5) + vec2(ab.y, -ab.x) * mix(0.08, 0.2, gHook * (1.0 - 0.5 * gLift));
    float rod = strokeAA(sdQuadraticBezier(uv, a, rodCtl, b), 0.007, px);
    // Line: slack sag while waiting, taut when hooked, hanging while lifted.
    float sag = 0.05 * (1.0 - gHook) + 0.01 * sin(gT * 1.3) * (1.0 - gHook);
    vec2 ctl = mix(b, e, 0.5) - vec2(0.0, sag);
    float line = strokeAA(sdQuadraticBezier(uv, b, ctl, e), 0.0022, px);
    col = mix(col, rgb(0.16, 0.11, 0.09), rod);
    col = mix(col, rgb(0.05, 0.05, 0.05), line * 0.85);
    // Bobber while in the water; a silver fish on the line while lifted, then lying in the boat.
    if (gLift < 0.05) {
        col = mix(col, rgb(0.85, 0.25, 0.25), fillAA(length(uv - e) - 0.011, px));
    } else {
        vec2 l = uv - e - vec2(0.0, -0.05) * (1.0 - step(0.99, gLift));
        l = rot2(1.2 * (1.0 - gLift) + 0.3 * sin(gT * 9.0) * (1.0 - gLift)) * l;
        float fsh = fillAA(fishSilhouette(l * 0.8), px);
        col = mix(col, mix(rgb(0.80, 0.82, 0.84), rgb(0.55, 0.58, 0.62), smoothstep(-0.01, 0.015, l.y)), fsh);
    }
    return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    setupScene(iTime);
    Cam c = camAt(iTime);
    gViewDist = gScene == 1 ? c.dist : 0.0;
    vec3 acc = vec3(0.0);
    for (int i = ZERO; i < AA; i++) {
        vec2 fc = fragCoord + (AA > 1 ? aaOffset(i) : vec2(0.0));
        vec3 col = overlay(render(fc, c), fc, c);
#if DEBUG_MODE == 0
        col = tonemapNeutral(col * EXPOSURE);
#endif
        acc += col;
    }
    vec3 col = acc / float(AA);
#if DEBUG_MODE == 0
    col = linearToSrgb(col) + ditherTPDF(fragCoord, iFrame);
#endif
    fragColor = vec4(col, 1.0);
}
