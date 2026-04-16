#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Fluid Buffer D (pressure field)
// Ported from Shadertoy "mipmap-based multiscale fluid dynamics" by Cornus Ammonis

constant int POISSON_SCALES = 11;
constant float POIS_ISOTROPY = 0.16;

static float hash1_d(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffffU);
}

static float3 hash3_d(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    uint3 k = n * uint3(n, n * 16807U, n * 48271U);
    return float3(k & uint3(0x7fffffffU)) / float(0x7fffffffU);
}

static float4 rand4_d(float2 fragCoord, float2 resolution, int frame) {
    uint2 p = uint2(fragCoord);
    uint2 r = uint2(resolution);
    uint c = p.x + r.x * p.y + r.x * r.y * uint(frame);
    return float4(hash3_d(c), hash1_d(c + 75132895U));
}

static float reduce_mat(float3x3 a, float3x3 b) {
    float r = 0.0;
    for (int j = 0; j < 3; j++) for (int i = 0; i < 3; i++) r += a[j][i] * b[j][i];
    return r;
}

fragment float4 fluid_d_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(0)]],
                                  texture2d<float> iChannel0 [[texture(0)]], // velocity
                                  texture2d<float> iChannel1 [[texture(1)]], // pressure.src
                                  sampler s [[sampler(0)]])
{
    float2 fragCoord = in.position.xy;
    float2 iResolution = uniforms.iResolution;
    int iFrame = uniforms.iFrame;
    float2 uv = fragCoord / iResolution;

    float k0 = POIS_ISOTROPY;
    float k1 = 1.0 - 2.0 * POIS_ISOTROPY;
    float3x3 pois_x = float3x3(float3(k0, 0.0, -k0), float3(k1, 0.0, -k1), float3(k0, 0.0, -k0));
    float3x3 pois_y = float3x3(float3(-k0, -k1, -k0), float3(0.0, 0.0, 0.0), float3(k0, k1, k0));
    float3x3 gauss = float3x3(float3(0.0625, 0.125, 0.0625), float3(0.125, 0.25, 0.125), float3(0.0625, 0.125, 0.0625));

    float2 v = float2(0.0);
    float wc = 0.0;
    float2 texel = 1.0 / iResolution;
    for (int i = 0; i < POISSON_SCALES; i++) {
        float stride = float(1 << i);
        float mip = float(i);
        float4 t = stride * float4(texel, -texel.y, 0.0);

        float2 d = iChannel0.sample(s, fract(uv + t.ww), level(mip)).xy;
        float2 d_n = iChannel0.sample(s, fract(uv + t.wy), level(mip)).xy;
        float2 d_e = iChannel0.sample(s, fract(uv + t.xw), level(mip)).xy;
        float2 d_s = iChannel0.sample(s, fract(uv + t.wz), level(mip)).xy;
        float2 d_w = iChannel0.sample(s, fract(uv - t.xw), level(mip)).xy;
        float2 d_nw = iChannel0.sample(s, fract(uv - t.xz), level(mip)).xy;
        float2 d_sw = iChannel0.sample(s, fract(uv - t.xy), level(mip)).xy;
        float2 d_ne = iChannel0.sample(s, fract(uv + t.xy), level(mip)).xy;
        float2 d_se = iChannel0.sample(s, fract(uv + t.xz), level(mip)).xy;

        float p = iChannel1.sample(s, fract(uv + t.ww), level(mip)).x;
        float p_n = iChannel1.sample(s, fract(uv + t.wy), level(mip)).x;
        float p_e = iChannel1.sample(s, fract(uv + t.xw), level(mip)).x;
        float p_s = iChannel1.sample(s, fract(uv + t.wz), level(mip)).x;
        float p_w = iChannel1.sample(s, fract(uv - t.xw), level(mip)).x;
        float p_nw = iChannel1.sample(s, fract(uv - t.xz), level(mip)).x;
        float p_sw = iChannel1.sample(s, fract(uv - t.xy), level(mip)).x;
        float p_ne = iChannel1.sample(s, fract(uv + t.xy), level(mip)).x;
        float p_se = iChannel1.sample(s, fract(uv + t.xz), level(mip)).x;

        float3x3 mx = float3x3(
            float3(d_nw.x, d_n.x, d_ne.x),
            float3(d_w.x, d.x, d_e.x),
            float3(d_sw.x, d_s.x, d_se.x));
        float3x3 my = float3x3(
            float3(d_nw.y, d_n.y, d_ne.y),
            float3(d_w.y, d.y, d_e.y),
            float3(d_sw.y, d_s.y, d_se.y));
        float3x3 mp = float3x3(
            float3(p_nw, p_n, p_ne),
            float3(p_w, p, p_e),
            float3(p_sw, p_s, p_se));

        float w = 1.0 / float(i + 1);
        wc += w;
        v += w * float2(reduce_mat(pois_x, mx) + reduce_mat(pois_y, my), reduce_mat(gauss, mp));
    }
    float2 p = v / wc;

    float4 fragColor = float4(p.x + p.y);
    if (iFrame == 0) {
        fragColor = 1e-6 * rand4_d(fragCoord, iResolution, iFrame);
    }
    return fragColor;
}
