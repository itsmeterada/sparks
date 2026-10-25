#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// another synthwave sunset thing - Ported from Shadertoy
// https://www.shadertoy.com/view/tsScRK
// Pseudo-tessellation (triangle) noise terrain under a synthwave sunset.
// Sound-texture sampling is disabled in the original by default, so the
// audio-visualizer path (textureMirror) is folded out here.

#define SW_speed 10.

// GLSL-style mod (fmod truncates toward zero)
static float sw_mod(float x, float y) { return x - y * floor(x / y); }

static float sw_amp(float2 p) {
    return smoothstep(1., 8., abs(p.x));
}

static float sw_pow512(float a) {
    a *= a; // ^2
    a *= a; // ^4
    a *= a; // ^8
    a *= a; // ^16
    a *= a; // ^32
    a *= a; // ^64
    a *= a; // ^128
    a *= a; // ^256
    return a * a;
}
static float sw_pow1d5(float a) {
    return a * sqrt(a);
}
static float sw_hash21(float2 co) {
    return fract(sin(dot(co.xy, float2(1.9898, 7.233))) * 45758.5433);
}
static float sw_hash(float2 uv, float jTime) {
    float a = sw_amp(uv);
    // wave_thing
    float w = a > 0. ? (1. - .4 * sw_pow512(.51 + .49 * sin((.02 * (uv.y + .5 * uv.x) - jTime) * 2.))) : 0.;
    return a > 0. ? a * sw_pow1d5(sw_hash21(uv)) * w : 0.;
}

// With sound sampling disabled the a1/a2/a3 edge attenuations are always 1.
static float sw_edgeMin(float dx, float2 da, float2 db) {
    return min(min((1. - dx) * db.y, da.x), da.y);
}

static float2 sw_trinoise(float2 uv, float jTime) {
    const float sq = sqrt(3. / 2.);
    uv.x *= sq;
    uv.y -= .5 * uv.x;
    float2 d = fract(uv);
    uv -= d;

    bool c = dot(d, float2(1)) > 1.;

    float2 dd = 1. - d;
    float2 da = c ? dd : d, db = c ? d : dd;

    float nn = sw_hash(uv + float(c), jTime);
    float n2 = sw_hash(uv + float2(1, 0), jTime);
    float n3 = sw_hash(uv + float2(0, 1), jTime);

    float nmid = mix(n2, n3, d.y);
    float ns = mix(nn, c ? n2 : n3, da.y);
    float dx = da.x / db.y;
    return float2(mix(ns, nmid, dx), sw_edgeMin(dx, da, db));
}

static float2 sw_map(float3 p, float jTime) {
    float2 n = sw_trinoise(p.xz, jTime);
    return float2(p.y - 2. * n.x, n.y);
}

static float3 sw_grad(float3 p, float jTime) {
    const float2 e = float2(.005, 0);
    float a = sw_map(p, jTime).x;
    return float3(sw_map(p + e.xyy, jTime).x - a,
                  sw_map(p + e.yxy, jTime).x - a,
                  sw_map(p + e.yyx, jTime).x - a) / e.x;
}

static float2 sw_intersect(float3 ro, float3 rd, float jTime) {
    float d = 0., h = 0.;
    for (int i = 0; i < 500; i++) { // look nice with 50 iterations
        float3 p = ro + d * rd;
        float2 s = sw_map(p, jTime);
        h = s.x;
        d += h * .5;
        if (abs(h) < .003 * d)
            return float2(d, s.y);
        if (d > 150. || p.y > 2.) break;
    }
    return float2(-1);
}

static void sw_addsun(float3 rd, float3 ld, thread float3& col) {
    float sun = smoothstep(.21, .2, distance(rd, ld));

    if (sun > 0.) {
        float yd = (rd.y - ld.y);
        float a = sin(3.1 * exp(-(yd) * 14.));
        sun *= smoothstep(-.8, 0., a);
        col = mix(col, float3(1., .8, .4) * .75, sun);
    }
}

static float sw_starnoise(float3 rd) {
    float c = 0.;
    float3 p = normalize(rd) * 300.;
    const float3x3 m = float3x3(float3(3. / 5., 0, 4. / 5.), float3(0, 1, 0), float3(-4. / 5., 0, 3. / 5.));
    for (float i = 0.; i < 4.; i++) {
        float3 q = fract(p) - .5;
        float3 id = floor(p);
        float c2 = smoothstep(.5, 0., length(q));
        c2 *= step(sw_hash21(id.xz / id.y), .06 - i * i * 0.005);
        c += c2;
        p = p * .6 + .5 * p * m;
    }
    c *= c;
    float g = dot(sin(rd * 10.512), cos(rd.yzx * 10.512));
    c *= smoothstep(-3.14, -.9, g) * .5 + .5 * smoothstep(-.3, 1., g);
    return c * c;
}

static float3 sw_gsky(float3 rd, float3 ld, bool mask) {
    float haze = exp2(-5. * (abs(rd.y) - .2 * dot(rd, ld)));
    float st = mask ? (sw_starnoise(rd)) * (1. - min(haze, 1.)) : 0.;
    float3 back = float3(.4, .1, .7);
    float3 col = clamp(mix(back, float3(.7, .1, .4), haze) + st, 0., 1.);
    if (mask) sw_addsun(rd, ld, col);
    return col;
}

fragment float4 synthwave_fragment(VertexOut in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    float2 iResolution = uniforms.iResolution;
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * iResolution;

    const float AA = 1.;
    const float iTimeDelta = 1. / 60.;
    float2 uv = (2. * fragCoord - iResolution.xy) / iResolution.y;

    const float shutter_speed = .25; // for motion blur
    float dt = fract(sw_hash21(AA * fragCoord) + iTime) * shutter_speed;
    float jTime = sw_mod(iTime - dt * iTimeDelta, 4000.);
    float3 ro = float3(0., 1, (-20000. + jTime * SW_speed));

    float3 rd = normalize(float3(uv, 4. / 3.));

    float2 i = sw_intersect(ro, rd, jTime);
    float d = i.x;

    float3 ld = normalize(float3(0, .125 + .05 * sin(.1 * jTime), 1));

    float3 fog = d > 0. ? exp2(-d * float3(.14, .1, .28)) : float3(0.);
    float3 sky = sw_gsky(rd, ld, d < 0.);

    float3 p = ro + d * rd;
    float3 n = normalize(sw_grad(p, jTime));

    float diff = dot(n, ld) + .1 * n.y;
    float3 col = float3(.1, .11, .18) * diff;

    float3 rfd = reflect(rd, n);
    float3 rfcol = sw_gsky(rfd, ld, true);

    col = mix(col, rfcol, .05 + .95 * pow(max(1. + dot(rd, n), 0.), 5.));
    col = mix(col, float3(.8, .1, .92), smoothstep(.05, .0, i.y));
    col = mix(sky, col, fog);
    // no gamma for that old cg look
    return float4(clamp(col, 0., 1.), 1.0);
}
