#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Fluid Buffer B (turbulence field)
// Ported from Shadertoy "mipmap-based multiscale fluid dynamics" by Cornus Ammonis

constant int TURBULENCE_SCALES = 11;
constant float TURB_ISOTROPY = 0.9;
constant float CURL_ISOTROPY = 0.6;

static float hash1_b(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffffU);
}

static float3 hash3_b(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    uint3 k = n * uint3(n, n * 16807U, n * 48271U);
    return float3(k & uint3(0x7fffffffU)) / float(0x7fffffffU);
}

static float4 rand4_b(float2 fragCoord, float2 resolution, int frame) {
    uint2 p = uint2(fragCoord);
    uint2 r = uint2(resolution);
    uint c = p.x + r.x * p.y + r.x * r.y * uint(frame);
    return float4(hash3_b(c), hash1_b(c + 75132895U));
}

static float reduce_mat(float3x3 a, float3x3 b) {
    float r = 0.0;
    for (int j = 0; j < 3; j++) for (int i = 0; i < 3; i++) r += a[j][i] * b[j][i];
    return r;
}

fragment float4 fluid_b_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(0)]],
                                  texture2d<float> iChannel0 [[texture(0)]], // velocity
                                  sampler s [[sampler(0)]])
{
    float2 fragCoord = in.position.xy;
    float2 iResolution = uniforms.iResolution;
    int iFrame = uniforms.iFrame;

    float2 uv = fragCoord / iResolution;

    float3x3 turb_xx = (2.0 - TURB_ISOTROPY) * float3x3(
        float3(0.125, 0.25, 0.125), float3(-0.25, -0.5, -0.25), float3(0.125, 0.25, 0.125));
    float3x3 turb_yy = (2.0 - TURB_ISOTROPY) * float3x3(
        float3(0.125, -0.25, 0.125), float3(0.25, -0.5, 0.25), float3(0.125, -0.25, 0.125));
    float3x3 turb_xy = TURB_ISOTROPY * float3x3(
        float3(0.25, 0.0, -0.25), float3(0.0, 0.0, 0.0), float3(-0.25, 0.0, 0.25));

    const float norm = 8.8 / (4.0 + 8.0 * CURL_ISOTROPY);
    float c0 = CURL_ISOTROPY;
    float3x3 curl_x = float3x3(float3(c0, 1.0, c0), float3(0.0, 0.0, 0.0), float3(-c0, -1.0, -c0));
    float3x3 curl_y = float3x3(float3(c0, 0.0, -c0), float3(1.0, 0.0, -1.0), float3(c0, 0.0, -c0));

    float2 v = float2(0.0);
    float turb_wc = 0.0;
    float curl_wc = 0.0;
    float curl = 0.0;

    float2 texel = 1.0 / iResolution;
    for (int i = 0; i < TURBULENCE_SCALES; i++) {
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

        float3x3 mx = float3x3(
            float3(d_nw.x, d_n.x, d_ne.x),
            float3(d_w.x, d.x, d_e.x),
            float3(d_sw.x, d_s.x, d_se.x));
        float3x3 my = float3x3(
            float3(d_nw.y, d_n.y, d_ne.y),
            float3(d_w.y, d.y, d_e.y),
            float3(d_sw.y, d_s.y, d_se.y));

        float turb_w = 1.0;
        float curl_w = 1.0 / float(i + 1);
        v += turb_w * float2(
            reduce_mat(turb_xx, mx) + reduce_mat(turb_xy, my),
            reduce_mat(turb_yy, my) + reduce_mat(turb_xy, mx));
        curl += curl_w * (reduce_mat(curl_x, mx) + reduce_mat(curl_y, my));
        turb_wc += turb_w;
        curl_wc += curl_w;
    }
    float2 turb = float(TURBULENCE_SCALES) * v / turb_wc;
    curl = norm * curl / curl_wc;

    float4 fragColor = float4(turb, 0.0, curl);
    if (iFrame == 0) {
        fragColor = 1e-6 * rand4_b(fragCoord, iResolution, iFrame);
    }
    return fragColor;
}
