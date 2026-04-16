#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Fluid Buffer C (vorticity confinement)
// Ported from Shadertoy "mipmap-based multiscale fluid dynamics" by Cornus Ammonis

constant int VORTICITY_SCALES = 11;
constant float CONF_ISOTROPY = 0.25;

static float2 normz_c(float2 x) {
    return all(x == float2(0.0)) ? float2(0.0) : normalize(x);
}

static float hash1_c(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffffU);
}

static float3 hash3_c(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    uint3 k = n * uint3(n, n * 16807U, n * 48271U);
    return float3(k & uint3(0x7fffffffU)) / float(0x7fffffffU);
}

static float4 rand4_c(float2 fragCoord, float2 resolution, int frame) {
    uint2 p = uint2(fragCoord);
    uint2 r = uint2(resolution);
    uint c = p.x + r.x * p.y + r.x * r.y * uint(frame);
    return float4(hash3_c(c), hash1_c(c + 75132895U));
}

static float reduce_mat(float3x3 a, float3x3 b) {
    float r = 0.0;
    for (int j = 0; j < 3; j++) for (int i = 0; i < 3; i++) r += a[j][i] * b[j][i];
    return r;
}

fragment float4 fluid_c_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(0)]],
                                  texture2d<float> iChannel0 [[texture(0)]], // turbulence
                                  sampler s [[sampler(0)]])
{
    float2 fragCoord = in.position.xy;
    float2 iResolution = uniforms.iResolution;
    int iFrame = uniforms.iFrame;
    float2 uv = fragCoord / iResolution;

    float k0 = CONF_ISOTROPY;
    float k1 = 1.0 - 2.0 * CONF_ISOTROPY;
    float3x3 conf_x = float3x3(float3(-k0, -k1, -k0), float3(0.0, 0.0, 0.0), float3(k0, k1, k0));
    float3x3 conf_y = float3x3(float3(-k0, 0.0, k0), float3(-k1, 0.0, k1), float3(-k0, 0.0, k0));

    float2 v = float2(0.0);
    float wc = 0.0;
    float2 texel = 1.0 / iResolution;
    for (int i = 0; i < VORTICITY_SCALES; i++) {
        float stride = float(1 << i);
        float mip = float(i);
        float4 t = stride * float4(texel, -texel.y, 0.0);

        float d = abs(iChannel0.sample(s, fract(uv + t.ww), level(mip)).w);
        float d_n = abs(iChannel0.sample(s, fract(uv + t.wy), level(mip)).w);
        float d_e = abs(iChannel0.sample(s, fract(uv + t.xw), level(mip)).w);
        float d_s = abs(iChannel0.sample(s, fract(uv + t.wz), level(mip)).w);
        float d_w = abs(iChannel0.sample(s, fract(uv - t.xw), level(mip)).w);
        float d_nw = abs(iChannel0.sample(s, fract(uv - t.xz), level(mip)).w);
        float d_sw = abs(iChannel0.sample(s, fract(uv - t.xy), level(mip)).w);
        float d_ne = abs(iChannel0.sample(s, fract(uv + t.xy), level(mip)).w);
        float d_se = abs(iChannel0.sample(s, fract(uv + t.xz), level(mip)).w);

        float3x3 mc = float3x3(
            float3(d_nw, d_n, d_ne),
            float3(d_w, d, d_e),
            float3(d_sw, d_s, d_se));
        float curl = iChannel0.sample(s, fract(uv), level(mip)).w;

        float w = 1.0;
        float2 n = w * normz_c(float2(reduce_mat(conf_x, mc), reduce_mat(conf_y, mc)));
        v += curl * n;
        wc += w;
    }
    float2 conf = v / wc;

    float4 fragColor = float4(conf, 0.0, 0.0);
    if (iFrame == 0) {
        fragColor = 1e-6 * rand4_c(fragCoord, iResolution, iFrame);
    }
    return fragColor;
}
