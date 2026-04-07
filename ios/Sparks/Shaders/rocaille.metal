#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Rocaille - Ported from Shadertoy
// https://www.shadertoy.com/view/WXyczK
// Original Author: @XorDev
// License: CC BY-NC-SA 3.0

fragment float4 rocaille_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 v = uniforms.iResolution;
    float2 p = (fragCoord + fragCoord - v) / v.y / .3;

    float4 O = float4(0);
    float i, f;
    for (i = 0.; i < 9.; i++) {
        v = p;
        for (f = 0.; f < 9.; f++)
            v += sin(v.yx * (f + 1.) + i + iTime) / (f + 1.);
        O += (cos(i + 1. + float4(0, 1, 2, 3)) + 1.) / 6. / length(v);
    }

    O = tanh(O * O);
    return float4(O.rgb, 1.0);
}
