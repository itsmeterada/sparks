#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Plasma Globe - Ported from Shadertoy
// https://www.shadertoy.com/view/XsjXRm
// Original Author: nimitz (twitter: @stormoid)
// License: CC BY-NC-SA 3.0

#define NUM_RAYS 13.
#define VOLUMETRIC_STEPS 19
#define MAX_ITER 35
#define FAR 6.

static float2x2 plasma_mm2(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

static float plasma_noise_1d(float x, texture2d<float> tex, sampler samp) {
    return tex.sample(samp, float2(x * 0.01, 1.0), level(0.0)).x;
}

static float plasma_hash(float n) {
    return fract(sin(n) * 43758.5453);
}

static float plasma_noise_3d(float3 p, texture2d<float> tex, sampler samp) {
    float3 ip = floor(p);
    float3 fp = fract(p);
    fp = fp * fp * (3.0 - 2.0 * fp);
    float2 tap = (ip.xy + float2(37.0, 17.0) * ip.z) + fp.xy;
    float2 rg = tex.sample(samp, (tap + 0.5) / 256.0, level(0.0)).yx;
    return mix(rg.x, rg.y, fp.z);
}

constant float3x3 plasma_m3 = float3x3(
    float3( 0.00,  0.80,  0.60),
    float3(-0.80,  0.36, -0.48),
    float3(-0.60, -0.48,  0.64)
);

static float plasma_flow(float3 p, float t, float time, texture2d<float> tex, sampler samp) {
    float z = 2.0;
    float rz = 0.0;
    float3 bp = p;
    for (float i = 1.0; i < 5.0; i++) {
        p += time * 0.1;
        rz += (sin(plasma_noise_3d(p + t * 0.8, tex, samp) * 6.0) * 0.5 + 0.5) / z;
        p = mix(bp, p, 0.6);
        z *= 2.0;
        p *= 2.01;
        p = p * plasma_m3;
    }
    return rz;
}

static float plasma_sins(float x, float time) {
    float rz = 0.0;
    float z = 2.0;
    for (float i = 0.0; i < 3.0; i++) {
        rz += abs(fract(x * 1.4) - 0.5) / z;
        x *= 1.3;
        z *= 1.15;
        x -= time * 0.65 * z;
    }
    return rz;
}

static float plasma_segm(float3 p, float3 a, float3 b) {
    float3 pa = p - a;
    float3 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) * 0.5;
}

static float3 plasma_path(float i, float d, float time) {
    float3 en = float3(0.0, 0.0, 1.0);
    float sns2 = plasma_sins(d + i * 0.5, time) * 0.22;
    float sns = plasma_sins(d + i * 0.6, time) * 0.21;
    en.xz = plasma_mm2((plasma_hash(i * 10.569) - 0.5) * 6.2 + sns2) * en.xz;
    en.xy = plasma_mm2((plasma_hash(i * 4.732) - 0.5) * 6.2 + sns) * en.xy;
    return en;
}

static float2 plasma_map(float3 p, float i, float time) {
    float lp = length(p);
    float3 bg = float3(0.0);
    float3 en = plasma_path(i, lp, time);
    float ins = smoothstep(0.11, 0.46, lp);
    float outs = 0.15 + smoothstep(0.0, 0.15, abs(lp - 1.0));
    p *= ins * outs;
    float id = ins * outs;
    float rz = plasma_segm(p, bg, en) - 0.011;
    return float2(rz, id);
}

static float plasma_march(float3 ro, float3 rd, float startf, float maxd, float j, float time) {
    float precis = 0.001;
    float h = 0.5;
    float d = startf;
    for (int i = 0; i < MAX_ITER; i++) {
        if (abs(h) < precis || d > maxd) break;
        d += h * 1.2;
        float res = plasma_map(ro + rd * d, j, time).x;
        h = res;
    }
    return d;
}

static float3 plasma_vmarch(float3 ro, float3 rd, float j, float3 orig, float time, texture2d<float> tex, sampler samp) {
    float3 p = ro;
    float2 r = float2(0.0);
    float3 sum = float3(0.0);
    for (int i = 0; i < VOLUMETRIC_STEPS; i++) {
        r = plasma_map(p, j, time);
        p += rd * 0.03;
        float lp = length(p);
        float3 col = sin(float3(1.05, 2.5, 1.52) * 3.94 + r.y) * 0.85 + 0.4;
        col.rgb *= smoothstep(0.0, 0.015, -r.x);
        col *= smoothstep(0.04, 0.2, abs(lp - 1.1));
        col *= smoothstep(0.1, 0.34, lp);
        float dpo = max(distance(p, orig) - 2.0, 1e-6);
        sum += abs(col) * 5.0 * (1.2 - plasma_noise_1d(lp * 2.0 + j * 13.0 + time * 5.0, tex, samp) * 1.1) / (log(dpo) + 0.75);
    }
    return sum;
}

static float2 iSphere2(float3 ro, float3 rd) {
    float3 oc = ro;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - 1.0;
    float h = b * b - c;
    if (h < 0.0) return float2(-1.0);
    return float2(-b - sqrt(h), -b + sqrt(h));
}

fragment float4 plasma_fragment(VertexOut in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]],
                                texture2d<float> iChannel0 [[texture(0)]],
                                sampler samp [[sampler(0)]]) {
    float time = uniforms.iTime * 1.1;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 p = fragCoord / uniforms.iResolution - 0.5;
    p.x *= uniforms.iResolution.x / uniforms.iResolution.y;
    float2 um = uniforms.iMouse.xy / uniforms.iResolution - 0.5;

    float3 ro = float3(0.0, 0.0, 5.0);
    float3 rd = normalize(float3(p * 0.7, -1.5));
    float2x2 mx = plasma_mm2(time * 0.4 + um.x * 6.0);
    float2x2 my = plasma_mm2(time * 0.3 + um.y * 6.0);
    ro.xz = mx * ro.xz; rd.xz = mx * rd.xz;
    ro.xy = my * ro.xy; rd.xy = my * rd.xy;

    float3 bro = ro;
    float3 brd = rd;

    float3 col = float3(0.0125, 0.0, 0.025);
    for (float j = 1.0; j < NUM_RAYS + 1.0; j++) {
        ro = bro;
        rd = brd;
        float2x2 mm = plasma_mm2((time * 0.1 + ((j + 1.0) * 5.1)) * j * 0.25);
        ro.xy = mm * ro.xy; rd.xy = mm * rd.xy;
        ro.xz = mm * ro.xz; rd.xz = mm * rd.xz;
        float rz = plasma_march(ro, rd, 2.5, FAR, j, time);
        if (rz >= FAR) continue;
        float3 pos = ro + rz * rd;
        col = max(col, plasma_vmarch(pos, rd, j, bro, time, iChannel0, samp));
    }

    ro = bro;
    rd = brd;
    float2 sph = iSphere2(ro, rd);

    if (sph.x > 0.0) {
        float3 pos = ro + rd * sph.x;
        float3 pos2 = ro + rd * sph.y;
        float3 rf = reflect(rd, pos);
        float3 rf2 = reflect(rd, pos2);
        float nz = -log(max(abs(plasma_flow(rf * 1.2, time, time, iChannel0, samp) - 0.01), 1e-6));
        float nz2 = -log(max(abs(plasma_flow(rf2 * 1.2, -time, time, iChannel0, samp) - 0.01), 1e-6));
        col += (0.1 * nz * nz * float3(0.12, 0.12, 0.5) + 0.05 * nz2 * nz2 * float3(0.55, 0.2, 0.55)) * 1.6;
    }

    return float4(col * 1.3, 1.0);
}
