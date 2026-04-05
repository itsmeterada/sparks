#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Seascape - Ported from Shadertoy
// https://www.shadertoy.com/view/Ms2SD1
// Original Author: Alexander Alekseev aka TDM - 2014
// License: CC BY-NC-SA 3.0

constant int NUM_STEPS = 32;
constant float PI = 3.141592;
constant float EPSILON = 1e-3;

constant int ITER_GEOMETRY = 3;
constant int ITER_FRAGMENT = 5;
constant float SEA_HEIGHT = 0.6;
constant float SEA_CHOPPY = 4.0;
constant float SEA_SPEED = 0.8;
constant float SEA_FREQ = 0.16;
constant float3 SEA_BASE = float3(0.0, 0.09, 0.18);
constant float3 SEA_WATER_COLOR = float3(0.8, 0.9, 0.6) * 0.6;
constant float2x2 octave_m = float2x2(float2(1.6, -1.2), float2(1.2, 1.6));

static float3x3 fromEuler(float3 ang) {
    float2 a1 = float2(sin(ang.x), cos(ang.x));
    float2 a2 = float2(sin(ang.y), cos(ang.y));
    float2 a3 = float2(sin(ang.z), cos(ang.z));
    float3x3 m;
    m[0] = float3(a1.y*a3.y+a1.x*a2.x*a3.x, a1.y*a2.x*a3.x+a3.y*a1.x, -a2.y*a3.x);
    m[1] = float3(-a2.y*a1.x, a1.y*a2.y, a2.x);
    m[2] = float3(a3.y*a1.x*a2.x+a1.y*a3.x, a1.x*a3.x-a1.y*a3.y*a2.x, a2.y*a3.y);
    return m;
}

static float sea_hash(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

static float sea_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return -1.0 + 2.0 * mix(
        mix(sea_hash(i + float2(0.0, 0.0)), sea_hash(i + float2(1.0, 0.0)), u.x),
        mix(sea_hash(i + float2(0.0, 1.0)), sea_hash(i + float2(1.0, 1.0)), u.x), u.y);
}

static float sea_diffuse(float3 n, float3 l, float p) {
    return pow(dot(n, l) * 0.4 + 0.6, p);
}

static float sea_specular(float3 n, float3 l, float3 e, float s) {
    float nrm = (s + 8.0) / (PI * 8.0);
    return pow(max(dot(reflect(e, n), l), 0.0), s) * nrm;
}

static float3 getSkyColor(float3 e) {
    float ey = (max(e.y, 0.0) * 0.8 + 0.2) * 0.8;
    return float3(pow(1.0 - ey, 2.0), 1.0 - ey, 0.6 + (1.0 - ey) * 0.4) * 1.1;
}

static float sea_octave(float2 uv, float choppy) {
    uv += sea_noise(uv);
    float2 wv = 1.0 - abs(sin(uv));
    float2 swv = abs(cos(uv));
    wv = mix(wv, swv, wv);
    return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

static float sea_map(float3 p, float SEA_TIME) {
    float freq = SEA_FREQ;
    float amp = SEA_HEIGHT;
    float choppy = SEA_CHOPPY;
    float2 uv = p.xz; uv.x *= 0.75;
    float d, h = 0.0;
    for (int i = 0; i < ITER_GEOMETRY; i++) {
        d = sea_octave((uv + SEA_TIME) * freq, choppy);
        d += sea_octave((uv - SEA_TIME) * freq, choppy);
        h += d * amp;
        uv = octave_m * uv; freq *= 1.9; amp *= 0.22;
        choppy = mix(choppy, 1.0, 0.2);
    }
    return p.y - h;
}

static float sea_map_detailed(float3 p, float SEA_TIME) {
    float freq = SEA_FREQ;
    float amp = SEA_HEIGHT;
    float choppy = SEA_CHOPPY;
    float2 uv = p.xz; uv.x *= 0.75;
    float d, h = 0.0;
    for (int i = 0; i < ITER_FRAGMENT; i++) {
        d = sea_octave((uv + SEA_TIME) * freq, choppy);
        d += sea_octave((uv - SEA_TIME) * freq, choppy);
        h += d * amp;
        uv = octave_m * uv; freq *= 1.9; amp *= 0.22;
        choppy = mix(choppy, 1.0, 0.2);
    }
    return p.y - h;
}

static float3 getSeaColor(float3 p, float3 n, float3 l, float3 eye, float3 dist) {
    float fresnel = clamp(1.0 - dot(n, -eye), 0.0, 1.0);
    fresnel = min(fresnel * fresnel * fresnel, 0.5);
    float3 reflected = getSkyColor(reflect(eye, n));
    float3 refracted = SEA_BASE + sea_diffuse(n, l, 80.0) * SEA_WATER_COLOR * 0.12;
    float3 color = mix(refracted, reflected, fresnel);
    float atten = max(1.0 - dot(dist, dist) * 0.001, 0.0);
    color += SEA_WATER_COLOR * (p.y - SEA_HEIGHT) * 0.18 * atten;
    color += sea_specular(n, l, eye, 600.0 * rsqrt(dot(dist, dist)));
    return color;
}

static float3 getNormal(float3 p, float eps, float SEA_TIME) {
    float3 n;
    n.y = sea_map_detailed(p, SEA_TIME);
    n.x = sea_map_detailed(float3(p.x + eps, p.y, p.z), SEA_TIME) - n.y;
    n.z = sea_map_detailed(float3(p.x, p.y, p.z + eps), SEA_TIME) - n.y;
    n.y = eps;
    return normalize(n);
}

static float heightMapTracing(float3 ori, float3 dir, thread float3& p, float SEA_TIME) {
    float tm = 0.0;
    float tx = 1000.0;
    float hx = sea_map(ori + dir * tx, SEA_TIME);
    if (hx > 0.0) { p = ori + dir * tx; return tx; }
    float hm = sea_map(ori, SEA_TIME);
    for (int i = 0; i < NUM_STEPS; i++) {
        float tmid = mix(tm, tx, hm / (hm - hx));
        p = ori + dir * tmid;
        float hmid = sea_map(p, SEA_TIME);
        if (hmid < 0.0) { tx = tmid; hx = hmid; }
        else { tm = tmid; hm = hmid; }
        if (abs(hmid) < EPSILON) break;
    }
    return mix(tm, tx, hm / (hm - hx));
}

static float3 getPixel(float2 coord, float time, float2 iResolution, float SEA_TIME, float EPSILON_NRM) {
    float2 uv = coord / iResolution;
    uv = uv * 2.0 - 1.0;
    uv.x *= iResolution.x / iResolution.y;
    float3 ang = float3(sin(time * 3.0) * 0.1, sin(time) * 0.2 + 0.3, time);
    float3 ori = float3(0.0, 3.5, time * 5.0);
    float3 dir = normalize(float3(uv.xy, -2.0));
    dir.z += length(uv) * 0.14;
    dir = normalize(dir) * fromEuler(ang);
    float3 p;
    heightMapTracing(ori, dir, p, SEA_TIME);
    float3 dist = p - ori;
    float3 n = getNormal(p, dot(dist, dist) * EPSILON_NRM, SEA_TIME);
    float3 light = normalize(float3(0.0, 1.0, 0.8));
    return mix(
        getSkyColor(dir),
        getSeaColor(p, n, light, dir, dist),
        pow(smoothstep(0.0, -0.02, dir.y), 0.2));
}

fragment float4 seascape_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float SEA_TIME = 1.0 + iTime * SEA_SPEED;
    float EPSILON_NRM = 0.1 / uniforms.iResolution.x;
    float time = iTime * 0.3 + uniforms.iMouse.x * 0.01;
    float3 color = getPixel(fragCoord, time, uniforms.iResolution, SEA_TIME, EPSILON_NRM);
    return float4(pow(color, float3(0.65)), 1.0);
}
