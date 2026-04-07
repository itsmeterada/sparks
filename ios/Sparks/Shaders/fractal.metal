#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Fractal Pyramid - Ported from Shadertoy
// https://www.shadertoy.com/view/tsXBzS
// License: CC BY-NC-SA 3.0

static float3 fractal_palette(float d) {
    return mix(float3(0.2, 0.7, 0.9), float3(1.0, 0.0, 1.0), d);
}

static float2 fractal_rotate(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return p * float2x2(float2(c, s), float2(-s, c));
}

static float fractal_map(float3 p, float iTime) {
    for (int i = 0; i < 8; ++i) {
        float t = iTime * 0.2;
        p.xz = fractal_rotate(p.xz, t);
        p.xy = fractal_rotate(p.xy, t * 1.89);
        p.xz = abs(p.xz);
        p.xz -= 0.5;
    }
    return dot(sign(p), p) / 5.0;
}

static float4 fractal_rm(float3 ro, float3 rd, float iTime) {
    float t = 0.0;
    float3 col = float3(0.0);
    float d;
    for (float i = 0.0; i < 64.0; i++) {
        float3 p = ro + rd * t;
        d = fractal_map(p, iTime) * 0.5;
        if (d < 0.02) break;
        if (d > 100.0) break;
        col += fractal_palette(length(p) * 0.1) / (400.0 * d);
        t += d;
    }
    return float4(col, 1.0 / (d * 100.0));
}

fragment float4 fractal_fragment(VertexOut in [[stage_in]],
                                 constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 uv = (fragCoord - uniforms.iResolution / 2.0) / uniforms.iResolution.x;
    float3 ro = float3(0.0, 0.0, -50.0);
    ro.xz = fractal_rotate(ro.xz, iTime);
    float3 cf = normalize(-ro);
    float3 cs = normalize(cross(cf, float3(0.0, 1.0, 0.0)));
    float3 cu = normalize(cross(cf, cs));

    float3 uuv = ro + cf * 3.0 + uv.x * cs + uv.y * cu;
    float3 rd = normalize(uuv - ro);

    return fractal_rm(ro, rd, iTime);
}
