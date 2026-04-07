#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Creative Coding Palette - Ported from Shadertoy
// https://www.shadertoy.com/view/mtyGWy
// License: CC BY-NC-SA 3.0

static float3 palette_fn(float t) {
    float3 a = float3(0.5, 0.5, 0.5);
    float3 b = float3(0.5, 0.5, 0.5);
    float3 c = float3(1.0, 1.0, 1.0);
    float3 d = float3(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

fragment float4 palette_fragment(VertexOut in [[stage_in]],
                                 constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 uv = (fragCoord * 2.0 - uniforms.iResolution) / uniforms.iResolution.y;
    float2 uv0 = uv;
    float3 finalColor = float3(0.0);

    for (float i = 0.0; i < 4.0; i++) {
        uv = fract(uv * 1.5) - 0.5;
        float d = length(uv) * exp(-length(uv0));
        float3 col = palette_fn(length(uv0) + i * 0.4 + iTime * 0.4);
        d = sin(d * 8.0 + iTime) / 8.0;
        d = abs(d);
        d = pow(0.01 / d, 1.2);
        finalColor += col * d;
    }

    return float4(finalColor, 1.0);
}
