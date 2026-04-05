#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Interstellar - Ported from Shadertoy
// https://www.shadertoy.com/view/Xdl3D2
// Original Author: Hazel Quantock
// License: CC0 (Public Domain)

#define GAMMA (2.2)

static float3 interstellar_ToGamma(float3 col) {
    return pow(col, float3(1.0 / GAMMA));
}

static float4 interstellar_Noise(int2 x, texture2d<float> tex, sampler samp) {
    return tex.sample(samp, (float2(x) + 0.5) / 256.0);
}

fragment float4 interstellar_fragment(VertexOut in [[stage_in]],
                                      constant Uniforms& uniforms [[buffer(0)]],
                                      texture2d<float> iChannel0 [[texture(0)]],
                                      sampler samp [[sampler(0)]]) {
    float2 fragCoord = in.uv * uniforms.iResolution;

    float3 ray;
    ray.xy = 2.0 * (fragCoord.xy - uniforms.iResolution.xy * 0.5) / uniforms.iResolution.x;
    ray.z = 1.0;

    float offset = uniforms.iTime * 0.5;
    float speed2 = (cos(offset) + 1.0) * 2.0;
    float speed = speed2 + 0.1;
    offset += sin(offset) * 0.96;
    offset *= 2.0;

    float3 col = float3(0.0);

    float3 stp = ray / max(abs(ray.x), abs(ray.y));

    float3 pos = 2.0 * stp + 0.5;
    for (int i = 0; i < 20; i++) {
        float z = interstellar_Noise(int2(pos.xy), iChannel0, samp).x;
        z = fract(z - offset);
        float d = 50.0 * z - pos.z;
        float w = pow(max(0.0, 1.0 - 8.0 * length(fract(pos.xy) - 0.5)), 2.0);
        float3 c = max(float3(0.0), float3(1.0 - abs(d + speed2 * 0.5) / speed,
                                            1.0 - abs(d) / speed,
                                            1.0 - abs(d - speed2 * 0.5) / speed));
        col += 1.5 * (1.0 - z) * c * w;
        pos += stp;
    }

    return float4(interstellar_ToGamma(col), 1.0);
}
