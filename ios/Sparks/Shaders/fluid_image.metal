#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"
#include "FluidCommon.h"

// Multiscale Turbulence - Image (final lit rendering)
// iChannel0 = Buffer A (velocity.xy)
// iChannel1 = Buffer B (turb.xy + curl.w, used as heightmap)
// iChannel2 = Buffer D (pressure, scalar in all channels)
// iChannel3 = Buffer C (confinement force.xy)

static inline float fluid_image_hsample(texture2d<float> bufB, sampler smp,
                                        float2 uv, float mip) {
    return -bufB.sample(smp, fract(uv), level(mip)).w;
}

static inline float2 fluid_image_diff(texture2d<float> bufB, sampler smp,
                                      float2 uv, float2 iRes, float mip) {
    float2 texel = 1.0 / iRes;
    float s = float(1 << int(mip));
    float2 tp = s * texel;

    float d    = fluid_image_hsample(bufB, smp, uv,                          mip);
    float d_n  = fluid_image_hsample(bufB, smp, uv + float2(0.0,   tp.y),    mip);
    float d_e  = fluid_image_hsample(bufB, smp, uv + float2(tp.x,  0.0),     mip);
    float d_s  = fluid_image_hsample(bufB, smp, uv + float2(0.0,  -tp.y),    mip);
    float d_w  = fluid_image_hsample(bufB, smp, uv + float2(-tp.x, 0.0),     mip);
    float d_nw = fluid_image_hsample(bufB, smp, uv + float2(-tp.x, tp.y),    mip);
    float d_sw = fluid_image_hsample(bufB, smp, uv + float2(-tp.x,-tp.y),    mip);
    float d_ne = fluid_image_hsample(bufB, smp, uv + float2(tp.x,  tp.y),    mip);
    float d_se = fluid_image_hsample(bufB, smp, uv + float2(tp.x, -tp.y),    mip);

    return float2(
        0.5 * (d_e - d_w) + 0.25 * (d_ne - d_nw + d_se - d_sw),
        0.5 * (d_n - d_s) + 0.25 * (d_ne + d_nw - d_se - d_sw)
    );
}

static inline float4 fluid_image_contrast(float4 col, float x) {
    return x * (col - 0.5) + 0.5;
}

fragment float4 fluid_image_fragment(VertexOut in [[stage_in]],
                                     constant Uniforms& uniforms [[buffer(0)]],
                                     texture2d<float> bufA      [[texture(0)]],
                                     texture2d<float> bufB      [[texture(1)]],
                                     texture2d<float> bufD      [[texture(2)]],
                                     texture2d<float> bufC      [[texture(3)]],
                                     sampler smp                [[sampler(0)]]) {
    float2 iRes = uniforms.iResolution;
    float2 fragCoord = in.uv * iRes;
    float2 uv = fragCoord / iRes;

    float2 dxy = float2(0);
    float occ = 0.0;
    float mip = 0.0;
    float d = fluid_image_hsample(bufB, smp, uv, 0.0);

    const float STEPS = 10.0;
    const float ODIST = 2.0;
    for (mip = 1.0; mip <= STEPS; mip += 1.0) {
        dxy += (1.0 / pow(2.0, mip)) * fluid_image_diff(bufB, smp, uv, iRes, mip - 1.0);
        occ += fluid_softclamp(-ODIST, ODIST, d - fluid_image_hsample(bufB, smp, uv, mip), 1.0)
               / pow(1.5, mip);
    }
    dxy /= STEPS;
    occ = pow(max(0.0, fluid_softclamp(0.2, 0.8, 100.0 * occ + 0.5, 1.0)), 0.5);

    float3 avd = float3(0);
    float3 ld = fluid_light_dir(uv, FLUID_BUMP, 0.5, dxy, uniforms.iTime, avd);
    float spec = fluid_ggx(avd, float3(0, 1, 0), ld, 0.1, 0.1);

    const float LOG_SPEC = 1000.0;
    spec = (log(LOG_SPEC + 1.0) / LOG_SPEC) * log(1.0 + LOG_SPEC * spec);

    // VIEW_VELOCITY (default in original)
    float2 vel = bufA.sample(smp, uv).xy;
    float4 diffuse = fluid_softclamp4s(0.0, 1.0, 6.0 * float4(vel, 0.0, 0.0) + 0.5, 2.0);

    float4 color = diffuse + 4.0 * mix(float4(spec), 1.5 * diffuse * spec, 0.3);
    color = mix(float4(1.0), float4(occ), 0.7) *
            fluid_softclamp4s(0.0, 1.0, fluid_image_contrast(color, 4.5), 3.0);
    return float4(color.rgb, 1.0);
}
