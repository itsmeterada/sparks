#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Starship - Ported from Shadertoy
// https://www.shadertoy.com/view/l3cfW4
// Original Author: @XorDev
// License: CC BY-NC-SA 3.0

fragment float4 starship_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]],
                                  texture2d<float> iChannel0 [[texture(0)]],
                                  sampler samp [[sampler(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;

    float2 r = uniforms.iResolution;
    float2x2 rm = float2x2(float2(3.0, 4.0), float2(4.0, -3.0));
    float2 p = (fragCoord + fragCoord - r) / r.y * rm / 1e2;

    float4 S = float4(0.0);
    float4 C = float4(1.0, 2.0, 3.0, 0.0);
    float4 W;

    float t = iTime;
    float T = 0.1 * t + p.y;
    for (float i = 1.0; i <= 50.0; i += 1.0) {
        W = sin(i) * C;

        p += 0.02 * cos(i * (C.xzxz + 8.0 + i) + T + T).xy;

        float texVal = iChannel0.sample(samp, p / exp(W.x) + float2(i, t) / 8.0).x;
        float2 p2 = p / float2(2.0, texVal * 40.0);
        float2 mp = max(p, p2);
        float l = length(mp);

        S += (cos(W) + 1.0) * exp(sin(i + i * T)) / l / 1e4;
    }

    C -= 1.0;
    float4 col = tanh(p.x * C + S * S);
    col.a = 1.0;
    return col;
}
