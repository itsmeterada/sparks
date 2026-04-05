#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Cosmic - Ported from Shadertoy
// https://www.shadertoy.com/view/XXyGzh
// Original Author: Nguyen2007
// License: CC BY-NC-SA 3.0

fragment float4 cosmic_fragment(VertexOut in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;

    float2 v = uniforms.iResolution;
    float2 u = 0.2 * (fragCoord + fragCoord - v) / v.y;

    float4 z = float4(1.0, 2.0, 3.0, 0.0);
    float4 o = z;

    float a = 0.5;
    float t = iTime;
    for (float i = 1.0; i < 19.0; i += 1.0) {
        t += 1.0;
        a += 0.03;
        v = cos(t - 7.0 * u * pow(a, i)) - 5.0 * u;

        float4 cv = cos(i + 0.02 * t - z.wxzw * 11.0);
        float2x2 m = float2x2(float2(cv.x, cv.y), float2(cv.z, cv.w));
        u = u * m;

        float d = dot(u, u);
        u += tanh(40.0 * d * cos(1e2 * u.yx + t)) / 2e2
           + 0.2 * a * u
           + cos(4.0 / exp(dot(o, o) / 1e2) + t) / 3e2;

        o += (1.0 + cos(z + t))
           / length((1.0 + i * dot(v, v))
                  * sin(1.5 * u / (0.5 - dot(u, u)) - 9.0 * u.yx + t));
    }

    o = 25.6 / (min(o, 13.0) + 164.0 / o)
      - dot(u, u) / 250.0;

    return float4(o.rgb, 1.0);
}
