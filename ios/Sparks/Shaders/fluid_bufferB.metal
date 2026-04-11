#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"
#include "FluidCommon.h"

// Multiscale Turbulence - Buffer B (multiscale turbulence + curl)
// https://www.shadertoy.com/view/tsKXR3
// Original Author: Cornus Ammonis  (CC BY-NC-SA 3.0)
// iChannel0 = Buffer A (velocity.xy + advection_offset.zw)

// Sample BufA at mip level with 9-tap neighborhood, filling column-major mat3 for x and y.
static inline void fluid_B_tex(float2 uv, texture2d<float> src, sampler smp, float2 iRes,
                               thread float3x3& mx, thread float3x3& my, int degree) {
    float2 texel = 1.0 / iRes;
    float stride = float(1 << degree);
    float mip = float(degree);
    float2 tp = stride * texel;

    float2 d    = src.sample(smp, fract(uv),                         level(mip)).xy;
    float2 d_n  = src.sample(smp, fract(uv + float2(0.0,   tp.y)),   level(mip)).xy;
    float2 d_e  = src.sample(smp, fract(uv + float2(tp.x,  0.0)),    level(mip)).xy;
    float2 d_s  = src.sample(smp, fract(uv + float2(0.0,  -tp.y)),   level(mip)).xy;
    float2 d_w  = src.sample(smp, fract(uv + float2(-tp.x, 0.0)),    level(mip)).xy;
    float2 d_nw = src.sample(smp, fract(uv + float2(-tp.x, tp.y)),   level(mip)).xy;
    float2 d_sw = src.sample(smp, fract(uv + float2(-tp.x,-tp.y)),   level(mip)).xy;
    float2 d_ne = src.sample(smp, fract(uv + float2(tp.x,  tp.y)),   level(mip)).xy;
    float2 d_se = src.sample(smp, fract(uv + float2(tp.x, -tp.y)),   level(mip)).xy;

    mx = float3x3(
        float3(d_nw.x, d_n.x, d_ne.x),
        float3(d_w.x,  d.x,   d_e.x),
        float3(d_sw.x, d_s.x, d_se.x)
    );
    my = float3x3(
        float3(d_nw.y, d_n.y, d_ne.y),
        float3(d_w.y,  d.y,   d_e.y),
        float3(d_sw.y, d_s.y, d_se.y)
    );
}

fragment float4 fluid_bufferB_fragment(VertexOut in [[stage_in]],
                                       constant Uniforms& uniforms [[buffer(0)]],
                                       texture2d<float> bufA      [[texture(0)]],
                                       sampler smp                [[sampler(0)]]) {
    float2 iRes = uniforms.iResolution;
    float2 fragCoord = in.uv * iRes;
    float2 uv = fragCoord / iRes;

    float kTurb = 2.0 - FLUID_TURB_ISOTROPY;
    float3x3 turb_xx = float3x3(
        float3( 0.125 * kTurb,  0.25  * kTurb,  0.125 * kTurb),
        float3(-0.25  * kTurb, -0.5   * kTurb, -0.25  * kTurb),
        float3( 0.125 * kTurb,  0.25  * kTurb,  0.125 * kTurb)
    );
    float3x3 turb_yy = float3x3(
        float3( 0.125 * kTurb, -0.25  * kTurb,  0.125 * kTurb),
        float3( 0.25  * kTurb, -0.5   * kTurb,  0.25  * kTurb),
        float3( 0.125 * kTurb, -0.25  * kTurb,  0.125 * kTurb)
    );
    float kTxy = FLUID_TURB_ISOTROPY;
    float3x3 turb_xy = float3x3(
        float3( 0.25 * kTxy,  0.0,            -0.25 * kTxy),
        float3( 0.0,          0.0,             0.0),
        float3(-0.25 * kTxy,  0.0,             0.25 * kTxy)
    );

    // curl kernels (finite-difference in x from dy, and in y from dx)
    const float norm = 8.8 / (4.0 + 8.0 * FLUID_CURL_ISOTROPY);
    float c0 = FLUID_CURL_ISOTROPY;
    float3x3 curl_x = float3x3(
        float3( c0,   1.0,  c0),
        float3( 0.0,  0.0,  0.0),
        float3(-c0,  -1.0, -c0)
    );
    float3x3 curl_y = float3x3(
        float3( c0, 0.0, -c0),
        float3( 1.0, 0.0, -1.0),
        float3( c0, 0.0, -c0)
    );

    float3x3 mx, my;
    float2 v = float2(0);
    float curl = 0.0;
    float turb_wc = 0.0;
    float curl_wc = 0.0;

    for (int i = 0; i < FLUID_TURBULENCE_SCALES; i++) {
        fluid_B_tex(uv, bufA, smp, iRes, mx, my, i);
        float turb_w = FLUID_TURB_W(i);
        float curl_w = FLUID_CURL_W(i);
        v += turb_w * float2(
            fluid_reduce(turb_xx, mx) + fluid_reduce(turb_xy, my),
            fluid_reduce(turb_yy, my) + fluid_reduce(turb_xy, mx)
        );
        curl += curl_w * (fluid_reduce(curl_x, mx) + fluid_reduce(curl_y, my));
        turb_wc += turb_w;
        curl_wc += curl_w;
    }

    float2 turb = float(FLUID_TURBULENCE_SCALES) * v / turb_wc;
    curl = norm * curl / curl_wc;

    float4 outC = float4(turb, 0.0, curl);
    if (uniforms.iFrame == 0) {
        outC = 1e-6 * fluid_rand4(fragCoord, iRes, uniforms.iFrame);
    }
    return outC;
}
