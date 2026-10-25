#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Yet another 4D Apollonian - Ported from Shadertoy
// https://www.shadertoy.com/view/N3VXz1
// Original Author: mrange
// License: CC0 1.0 Universal (Public Domain Dedication)

fragment float4 apollonian_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(0)]]) {
    float2 r = uniforms.iResolution;
    float iTime = uniforms.iTime;
    float2 C = in.uv * r;

    float d = 0., e = 0., i = 0., j, s, z = 0.;
    float4 p, o, O = float4(0);
    float4 c = cos(iTime / 27. + float4(0, 11, 33, 0));
    float2x2 R = float2x2(c.xy, c.zw);

    // Unrolled form of the original golfed for(;;) header
    for (;;) {
        p = float4(z * normalize(float3(C - .5 * r, r.y)), .6);
        p.z -= 1.;
        p.xw = p.xw * R;
        p.wy = p.wy * R;
        p.zw = p.zw * R;
        o = p;
        if (!(++i < 77.)) break;

        // 4D Apollonian fold: tile + sphere inversion
        for (s = j = 1.; ++j < 7.; s *= e) {
            p -= 2. * round(p * .5);
            e = 2. / dot(p, p);
            p *= e;
        }

        p = abs(p / s);
        d = min(length(p.xy) + 3e-4, min(p.z, p.w) + 3e-3);
        p = e * e + 3. + 3. * cos(30. * dot(o.xy, o.zw) + float4(2, 7, 0, 4));
        O += p.w / d / (1. + 8. * e * e * e) * exp(-z * z * .5) * p;
        z += .6 * d + 1e-3;
    }

    // clamp guards tanh against overflow on mobile GPUs
    o = tanh(clamp(O / 2e4 - length(C / r - .5) / 5. * float4(2, 3, 1, 0), -10., 10.)) / .9;
    return float4(o.rgb, 1.0);
}
