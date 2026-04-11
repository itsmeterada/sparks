#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"
#include "FluidCommon.h"

// Multiscale Turbulence - Buffer D (multiscale Poisson solver)
// iChannel0 = Buffer B (turb.xy, 0, curl.w)
// iChannel1 = Buffer D (previous frame, scalar pressure broadcast)

static inline void fluid_D_tex(float2 uv,
                               texture2d<float> bufB, texture2d<float> bufD,
                               sampler smp, float2 iRes,
                               thread float3x3& mx, thread float3x3& my,
                               thread float3x3& mp, int degree) {
    float2 texel = 1.0 / iRes;
    float stride = float(1 << degree);
    float mip = float(degree);
    float2 tp = stride * texel;

    float2 d    = bufB.sample(smp, fract(uv),                         level(mip)).xy;
    float2 d_n  = bufB.sample(smp, fract(uv + float2(0.0,   tp.y)),   level(mip)).xy;
    float2 d_e  = bufB.sample(smp, fract(uv + float2(tp.x,  0.0)),    level(mip)).xy;
    float2 d_s  = bufB.sample(smp, fract(uv + float2(0.0,  -tp.y)),   level(mip)).xy;
    float2 d_w  = bufB.sample(smp, fract(uv + float2(-tp.x, 0.0)),    level(mip)).xy;
    float2 d_nw = bufB.sample(smp, fract(uv + float2(-tp.x, tp.y)),   level(mip)).xy;
    float2 d_sw = bufB.sample(smp, fract(uv + float2(-tp.x,-tp.y)),   level(mip)).xy;
    float2 d_ne = bufB.sample(smp, fract(uv + float2(tp.x,  tp.y)),   level(mip)).xy;
    float2 d_se = bufB.sample(smp, fract(uv + float2(tp.x, -tp.y)),   level(mip)).xy;

    float p    = bufD.sample(smp, fract(uv),                         level(mip)).x;
    float p_n  = bufD.sample(smp, fract(uv + float2(0.0,   tp.y)),   level(mip)).x;
    float p_e  = bufD.sample(smp, fract(uv + float2(tp.x,  0.0)),    level(mip)).x;
    float p_s  = bufD.sample(smp, fract(uv + float2(0.0,  -tp.y)),   level(mip)).x;
    float p_w  = bufD.sample(smp, fract(uv + float2(-tp.x, 0.0)),    level(mip)).x;
    float p_nw = bufD.sample(smp, fract(uv + float2(-tp.x, tp.y)),   level(mip)).x;
    float p_sw = bufD.sample(smp, fract(uv + float2(-tp.x,-tp.y)),   level(mip)).x;
    float p_ne = bufD.sample(smp, fract(uv + float2(tp.x,  tp.y)),   level(mip)).x;
    float p_se = bufD.sample(smp, fract(uv + float2(tp.x, -tp.y)),   level(mip)).x;

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
    mp = float3x3(
        float3(p_nw, p_n, p_ne),
        float3(p_w,  p,   p_e),
        float3(p_sw, p_s, p_se)
    );
}

fragment float4 fluid_bufferD_fragment(VertexOut in [[stage_in]],
                                       constant Uniforms& uniforms [[buffer(0)]],
                                       texture2d<float> bufB      [[texture(0)]],
                                       texture2d<float> bufD      [[texture(1)]],
                                       sampler smp                [[sampler(0)]]) {
    float2 iRes = uniforms.iResolution;
    float2 fragCoord = in.uv * iRes;
    float2 uv = fragCoord / iRes;

    float k0 = FLUID_POIS_ISOTROPY;
    float k1 = 1.0 - 2.0 * FLUID_POIS_ISOTROPY;

    float3x3 pois_x = float3x3(
        float3( k0,  0.0, -k0),
        float3( k1,  0.0, -k1),
        float3( k0,  0.0, -k0)
    );
    float3x3 pois_y = float3x3(
        float3(-k0, -k1, -k0),
        float3( 0.0, 0.0, 0.0),
        float3( k0,  k1,  k0)
    );
    float3x3 gauss = float3x3(
        float3(0.0625, 0.125, 0.0625),
        float3(0.125,  0.25,  0.125),
        float3(0.0625, 0.125, 0.0625)
    );

    float3x3 mx, my, mp;
    float2 v = float2(0);
    float wc = 0.0;

    for (int i = 0; i < FLUID_POISSON_SCALES; i++) {
        fluid_D_tex(uv, bufB, bufD, smp, iRes, mx, my, mp, i);
        float w = FLUID_POIS_W(i);
        wc += w;
        v += w * float2(
            fluid_reduce(pois_x, mx) + fluid_reduce(pois_y, my),
            fluid_reduce(gauss, mp)
        );
    }

    float2 p = v / wc;
    float result = p.x + p.y;
    float4 outC = float4(result);

    if (uniforms.iFrame == 0) {
        outC = 1e-6 * fluid_rand4(fragCoord, iRes, uniforms.iFrame);
    }
    return outC;
}
