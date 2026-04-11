#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"
#include "FluidCommon.h"

// Multiscale Turbulence - Buffer C (multiscale vorticity confinement)
// iChannel0 = Buffer B (turb.xy, 0, curl.w)

static inline void fluid_C_tex(float2 uv, texture2d<float> src, sampler smp, float2 iRes,
                               thread float3x3& mc, thread float& curlC, int degree) {
    float2 texel = 1.0 / iRes;
    float stride = float(1 << degree);
    float mip = float(degree);
    float2 tp = stride * texel;

    float d    = abs(src.sample(smp, fract(uv),                       level(mip)).w);
    float d_n  = abs(src.sample(smp, fract(uv + float2(0.0,   tp.y)), level(mip)).w);
    float d_e  = abs(src.sample(smp, fract(uv + float2(tp.x,  0.0)),  level(mip)).w);
    float d_s  = abs(src.sample(smp, fract(uv + float2(0.0,  -tp.y)), level(mip)).w);
    float d_w  = abs(src.sample(smp, fract(uv + float2(-tp.x, 0.0)),  level(mip)).w);
    float d_nw = abs(src.sample(smp, fract(uv + float2(-tp.x, tp.y)), level(mip)).w);
    float d_sw = abs(src.sample(smp, fract(uv + float2(-tp.x,-tp.y)), level(mip)).w);
    float d_ne = abs(src.sample(smp, fract(uv + float2(tp.x,  tp.y)), level(mip)).w);
    float d_se = abs(src.sample(smp, fract(uv + float2(tp.x, -tp.y)), level(mip)).w);

    mc = float3x3(
        float3(d_nw, d_n, d_ne),
        float3(d_w,  d,   d_e),
        float3(d_sw, d_s, d_se)
    );
    curlC = src.sample(smp, fract(uv), level(mip)).w;
}

fragment float4 fluid_bufferC_fragment(VertexOut in [[stage_in]],
                                       constant Uniforms& uniforms [[buffer(0)]],
                                       texture2d<float> bufB      [[texture(0)]],
                                       sampler smp                [[sampler(0)]]) {
    float2 iRes = uniforms.iResolution;
    float2 fragCoord = in.uv * iRes;
    float2 uv = fragCoord / iRes;

    float k0 = FLUID_CONF_ISOTROPY;
    float k1 = 1.0 - 2.0 * FLUID_CONF_ISOTROPY;

    float3x3 conf_x = float3x3(
        float3(-k0, -k1, -k0),
        float3( 0.0, 0.0,  0.0),
        float3( k0,  k1,   k0)
    );
    float3x3 conf_y = float3x3(
        float3(-k0, 0.0,  k0),
        float3(-k1, 0.0,  k1),
        float3(-k0, 0.0,  k0)
    );

    float3x3 mc;
    float2 v = float2(0);
    float cacc = 0.0;
    float2 nacc = float2(0);
    float wc = 0.0;
    float curl = 0.0;

    for (int i = 0; i < FLUID_VORTICITY_SCALES; i++) {
        fluid_C_tex(uv, bufB, smp, iRes, mc, curl, i);
        float w = FLUID_CONF_W(i);
        float2 n = w * fluid_normz(float2(fluid_reduce(conf_x, mc), fluid_reduce(conf_y, mc)));
        v += curl * n;
        cacc += curl;
        nacc += n;
        wc += w;
    }

#if FLUID_PREMULTIPLY_CURL
    float2 result = v / wc;
#else
    float2 result = nacc * cacc / wc;
#endif

    float4 outC = float4(result, 0.0, 0.0);
    if (uniforms.iFrame == 0) {
        outC = 1e-6 * fluid_rand4(fragCoord, iRes, uniforms.iFrame);
    }
    return outC;
}
