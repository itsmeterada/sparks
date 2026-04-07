#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Octgrams - Ported from Shadertoy
// https://www.shadertoy.com/view/tlVGDt
// License: CC BY-NC-SA 3.0

static float3 glsl_mod(float3 x, float y) {
    return x - y * floor(x / y);
}

static float2x2 oct_rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

static float oct_sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

static float oct_box(float3 pos, float scale) {
    pos *= scale;
    float base = oct_sdBox(pos, float3(0.4, 0.4, 0.1)) / 1.5;
    pos.xy *= 5.0;
    pos.y -= 3.5;
    pos.xy = pos.xy * oct_rot(0.75);
    return -base;
}

static float box_set(float3 pos, float gTime) {
    float3 pos_origin = pos;
    pos = pos_origin;
    pos.y += sin(gTime * 0.4) * 2.5;
    pos.xy = pos.xy * oct_rot(0.8);
    float box1 = oct_box(pos, 2.0 - abs(sin(gTime * 0.4)) * 1.5);
    pos = pos_origin;
    pos.y -= sin(gTime * 0.4) * 2.5;
    pos.xy = pos.xy * oct_rot(0.8);
    float box2 = oct_box(pos, 2.0 - abs(sin(gTime * 0.4)) * 1.5);
    pos = pos_origin;
    pos.x += sin(gTime * 0.4) * 2.5;
    pos.xy = pos.xy * oct_rot(0.8);
    float box3 = oct_box(pos, 2.0 - abs(sin(gTime * 0.4)) * 1.5);
    pos = pos_origin;
    pos.x -= sin(gTime * 0.4) * 2.5;
    pos.xy = pos.xy * oct_rot(0.8);
    float box4 = oct_box(pos, 2.0 - abs(sin(gTime * 0.4)) * 1.5);
    pos = pos_origin;
    pos.xy = pos.xy * oct_rot(0.8);
    float box5 = oct_box(pos, 0.5) * 6.0;
    pos = pos_origin;
    float box6 = oct_box(pos, 0.5) * 6.0;
    return max(max(max(max(max(box1, box2), box3), box4), box5), box6);
}

fragment float4 octgrams_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 p = (fragCoord * 2.0 - uniforms.iResolution) / min(uniforms.iResolution.x, uniforms.iResolution.y);
    float3 ro = float3(0.0, -0.2, iTime * 4.0);
    float3 ray = normalize(float3(p, 1.5));
    ray.xy = ray.xy * oct_rot(sin(iTime * 0.03) * 5.0);
    ray.yz = ray.yz * oct_rot(sin(iTime * 0.05) * 0.2);
    float t = 0.1;
    float3 col = float3(0.0);
    float ac = 0.0;

    for (int i = 0; i < 99; i++) {
        float3 pos = ro + ray * t;
        pos = glsl_mod(pos - 2.0, 4.0) - 2.0;
        float gTime = iTime - float(i) * 0.01;

        float d = box_set(pos, gTime);
        d = max(abs(d), 0.01);
        ac += exp(-d * 23.0);
        t += d * 0.55;
    }

    col = float3(ac * 0.02);
    col += float3(0.0, 0.2 * abs(sin(iTime)), 0.5 + sin(iTime) * 0.2);

    return float4(col, 1.0 - t * (0.02 + 0.02 * sin(iTime)));
}
