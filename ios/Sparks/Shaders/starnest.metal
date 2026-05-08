#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Star Nest - Ported from Shadertoy
// https://www.shadertoy.com/view/XlfGRj
// Original Author: Pablo Roman Andrioli
// License: MIT

constant int   STARNEST_ITERATIONS = 17;
constant float STARNEST_FORMUPARAM = 0.53;
constant int   STARNEST_VOLSTEPS   = 20;
constant float STARNEST_STEPSIZE   = 0.1;
constant float STARNEST_ZOOM       = 0.800;
constant float STARNEST_TILE       = 0.850;
constant float STARNEST_SPEED      = 0.010;
constant float STARNEST_BRIGHTNESS = 0.0015;
constant float STARNEST_DARKMATTER = 0.300;
constant float STARNEST_DISTFADING = 0.730;
constant float STARNEST_SATURATION = 0.850;

fragment float4 starnest_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
    float2 iResolution = uniforms.iResolution;
    float iTime = uniforms.iTime;
    float4 iMouse = uniforms.iMouse;
    float2 fragCoord = in.uv * iResolution;

    // get coords and direction
    float2 uv = fragCoord / iResolution - 0.5;
    uv.y *= iResolution.y / iResolution.x;
    float3 dir = float3(uv * STARNEST_ZOOM, 1.0);
    float time = iTime * STARNEST_SPEED + 0.25;

    // mouse rotation
    float a1 = 0.5 + iMouse.x / iResolution.x * 2.0;
    float a2 = 0.8 + iMouse.y / iResolution.y * 2.0;
    float c1 = cos(a1), s1 = sin(a1);
    float c2 = cos(a2), s2 = sin(a2);
    float2x2 rot1 = float2x2(float2(c1, s1), float2(-s1, c1));
    float2x2 rot2 = float2x2(float2(c2, s2), float2(-s2, c2));

    dir.xz = dir.xz * rot1;
    dir.xy = dir.xy * rot2;
    float3 from = float3(1.0, 0.5, 0.5);
    from += float3(time * 2.0, time, -2.0);
    from.xz = from.xz * rot1;
    from.xy = from.xy * rot2;

    // volumetric rendering
    float s = 0.1;
    float fade = 1.0;
    float3 v = float3(0.0);
    for (int r = 0; r < STARNEST_VOLSTEPS; r++) {
        float3 p = from + s * dir * 0.5;
        p = abs(float3(STARNEST_TILE) - fmod(p, float3(STARNEST_TILE * 2.0))); // tiling fold
        float pa = 0.0;
        float a = 0.0;
        for (int i = 0; i < STARNEST_ITERATIONS; i++) {
            p = abs(p) / dot(p, p) - STARNEST_FORMUPARAM; // the magic formula
            float lp = length(p);
            a += abs(lp - pa);
            pa = lp;
        }
        float dm = max(0.0, STARNEST_DARKMATTER - a * a * 0.001); // dark matter
        a *= a * a; // add contrast
        if (r > 6) fade *= 1.0 - dm;
        v += fade;
        v += float3(s, s * s, s * s * s * s) * a * STARNEST_BRIGHTNESS * fade;
        fade *= STARNEST_DISTFADING;
        s += STARNEST_STEPSIZE;
    }
    v = mix(float3(length(v)), v, STARNEST_SATURATION);
    return float4(v * 0.01, 1.0);
}
