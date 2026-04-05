#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Clouds - Ported from Shadertoy
// https://www.shadertoy.com/view/XslGRr
// Original Author: Inigo Quilez
// License: Educational use only (see original for full terms)

static float3x3 clouds_setCamera(float3 ro, float3 ta, float cr) {
    float3 cw = normalize(ta - ro);
    float3 cp = float3(sin(cr), cos(cr), 0.0);
    float3 cu = normalize(cross(cw, cp));
    float3 cv = normalize(cross(cu, cw));
    return float3x3(cu, cv, cw);
}

static float clouds_noise(float3 x, texture3d<float> noiseTex, sampler samp) {
    float3 p = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float3 uvw = p + f;
    return noiseTex.sample(samp, (uvw + 0.5) / 32.0, level(0.0)).x * 2.0 - 1.0;
}

static float map5(float3 p, float iTime, texture3d<float> noiseTex, sampler samp) {
    float3 q = p - float3(0.0, 0.1, 1.0) * iTime;
    float a = 0.5; float f = 0.0;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.02; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.03; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.01; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.02; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp);
    return clamp(1.5 - p.y - 2.0 + 1.75 * f, 0.0, 1.0);
}

static float map4(float3 p, float iTime, texture3d<float> noiseTex, sampler samp) {
    float3 q = p - float3(0.0, 0.1, 1.0) * iTime;
    float a = 0.5; float f = 0.0;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.02; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.03; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.01; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp);
    return clamp(1.5 - p.y - 2.0 + 1.75 * f, 0.0, 1.0);
}

static float map3(float3 p, float iTime, texture3d<float> noiseTex, sampler samp) {
    float3 q = p - float3(0.0, 0.1, 1.0) * iTime;
    float a = 0.5; float f = 0.0;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.02; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.03; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp);
    return clamp(1.5 - p.y - 2.0 + 1.75 * f, 0.0, 1.0);
}

static float map2(float3 p, float iTime, texture3d<float> noiseTex, sampler samp) {
    float3 q = p - float3(0.0, 0.1, 1.0) * iTime;
    float a = 0.5; float f = 0.0;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.02; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp);
    return clamp(1.5 - p.y - 2.0 + 1.75 * f, 0.0, 1.0);
}

constant float3 sundir = float3(-0.7071, 0.0, -0.7071);

#define CLOUDS_MARCH(STEPS, MAPLOD) \
    for (int i = 0; i < STEPS; i++) { \
        float3 pos = ro + t * rd; \
        if (pos.y < -3.0 || pos.y > 2.0 || sum.a > 0.99) break; \
        float den = MAPLOD(pos, iTime, noiseTex, samp); \
        if (den > 0.01) { \
            float dif = clamp((den - MAPLOD(pos + 0.3 * sundir, iTime, noiseTex, samp)) / 0.6, 0.0, 1.0); \
            float3 lin = float3(1.0, 0.6, 0.3) * dif + float3(0.91, 0.98, 1.05); \
            float4 col = float4(mix(float3(1.0, 0.95, 0.8), float3(0.25, 0.3, 0.35), den), den); \
            col.xyz *= lin; \
            col.xyz = mix(col.xyz, bgcol, 1.0 - exp(-0.003 * t * t)); \
            col.w *= 0.4; \
            col.rgb *= col.a; \
            sum += col * (1.0 - sum.a); \
        } \
        t += max(0.06, 0.05 * t); \
    }

static float4 clouds_raymarch(float3 ro, float3 rd, float3 bgcol, int2 px,
                               float iTime, texture3d<float> noiseTex,
                               texture2d<float> noiseTex2d, sampler samp) {
    float4 sum = float4(0.0);
    float t = 0.05 * noiseTex2d.read(uint2(px & 255), 0).x;
    CLOUDS_MARCH(40, map5);
    CLOUDS_MARCH(40, map4);
    CLOUDS_MARCH(30, map3);
    CLOUDS_MARCH(30, map2);
    return clamp(sum, 0.0, 1.0);
}

static float4 clouds_render(float3 ro, float3 rd, int2 px,
                              float iTime, texture3d<float> noiseTex,
                              texture2d<float> noiseTex2d, sampler samp) {
    float sun = clamp(dot(sundir, rd), 0.0, 1.0);
    float3 col = float3(0.6, 0.71, 0.75) - rd.y * 0.2 * float3(1.0, 0.5, 1.0) + 0.15 * 0.5;
    col += 0.2 * float3(1.0, 0.6, 0.1) * pow(sun, 8.0);
    float4 res = clouds_raymarch(ro, rd, col, px, iTime, noiseTex, noiseTex2d, samp);
    col = col * (1.0 - res.w) + res.xyz;
    col += float3(0.2, 0.08, 0.04) * pow(sun, 3.0);
    return float4(col, 1.0);
}

fragment float4 clouds_fragment(VertexOut in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]],
                                texture2d<float> iChannel0 [[texture(0)]],
                                texture2d<float> iChannel1 [[texture(1)]],
                                texture3d<float> iChannel2 [[texture(2)]],
                                sampler samp [[sampler(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 p = (2.0 * fragCoord - uniforms.iResolution) / uniforms.iResolution.y;

    float2 m;
    if (uniforms.iMouse.z > 0.0) {
        m = uniforms.iMouse.xy / uniforms.iResolution;
    } else {
        m = float2(0.5 + 0.15 * sin(iTime * 0.1), 0.4);
    }

    float3 ro = 4.0 * normalize(float3(sin(3.0 * m.x), 0.8 * m.y, cos(3.0 * m.x))) - float3(0.0, 0.1, 0.0);
    float3 ta = float3(0.0, -1.0, 0.0);
    float3x3 ca = clouds_setCamera(ro, ta, 0.07 * cos(0.25 * iTime));
    float3 rd = ca * normalize(float3(p, 1.5));

    return clouds_render(ro, rd, int2(fragCoord - 0.5), iTime, iChannel2, iChannel1, samp);
}
