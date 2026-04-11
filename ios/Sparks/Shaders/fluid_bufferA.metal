#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"
#include "FluidCommon.h"

// Multiscale Turbulence - Buffer A (velocity + advection update)
// iChannel0 = Buffer A (self, previous)   : velocity.xy + advection_offset.zw
// iChannel1 = Buffer D                    : poisson pressure (broadcast to .xyzw)
// iChannel2 = Buffer C                    : vorticity confinement force.xy
// iChannel3 = Buffer B                    : turbulence.xy + curl.w

// Simple samplers (current frame offset by `off`)
#define SAMPLE_TURB(off) (bufB.sample(smp, fract(uv + (off))).xy)
#define SAMPLE_CONF(off) (bufC.sample(smp, fract(uv + (off))).xy)
#define SAMPLE_VEL(off)  (bufA.sample(smp, fract(uv + (off))))
#define SAMPLE_POIS(off) (bufD.sample(smp, fract(uv + (off))).x)

// 9-tap central-difference gradient on BufD pressure field.
#define POIS_DIFF(base) {                                                     \
    float2 tt = tx;                                                           \
    float p   = SAMPLE_POIS((base) + float2(0.0,  0.0));                      \
    float p_n = SAMPLE_POIS((base) + float2(0.0,  tt.y));                     \
    float p_e = SAMPLE_POIS((base) + float2(tt.x, 0.0));                      \
    float p_s = SAMPLE_POIS((base) + float2(0.0, -tt.y));                     \
    float p_w = SAMPLE_POIS((base) + float2(-tt.x, 0.0));                     \
    float p_nw= SAMPLE_POIS((base) + float2(-tt.x, tt.y));                    \
    float p_sw= SAMPLE_POIS((base) + float2(-tt.x,-tt.y));                    \
    float p_ne= SAMPLE_POIS((base) + float2(tt.x,  tt.y));                    \
    float p_se= SAMPLE_POIS((base) + float2(tt.x, -tt.y));                    \
    divg = float2(                                                            \
        0.5 * (p_e - p_w) + 0.25 * (p_ne - p_nw + p_se - p_sw),               \
        0.5 * (p_n - p_s) + 0.25 * (p_ne + p_nw - p_se - p_sw));              \
}

// 9-tap vector laplacian on BufA velocity field.
#define VEL_LAPL(base) {                                                      \
    float _K0 = -20.0/6.0, _K1 = 4.0/6.0, _K2 = 1.0/6.0;                      \
    float2 tt = tx;                                                           \
    float4 d   = SAMPLE_VEL((base) + float2(0.0,  0.0));                      \
    float4 d_n = SAMPLE_VEL((base) + float2(0.0,  tt.y));                     \
    float4 d_e = SAMPLE_VEL((base) + float2(tt.x, 0.0));                      \
    float4 d_s = SAMPLE_VEL((base) + float2(0.0, -tt.y));                     \
    float4 d_w = SAMPLE_VEL((base) + float2(-tt.x, 0.0));                     \
    float4 d_nw= SAMPLE_VEL((base) + float2(-tt.x, tt.y));                    \
    float4 d_sw= SAMPLE_VEL((base) + float2(-tt.x,-tt.y));                    \
    float4 d_ne= SAMPLE_VEL((base) + float2(tt.x,  tt.y));                    \
    float4 d_se= SAMPLE_VEL((base) + float2(tt.x, -tt.y));                    \
    lapl = (_K0 * d + _K1 * (d_e + d_w + d_n + d_s) + _K2 * (d_ne + d_nw + d_se + d_sw)).xy; \
}

fragment float4 fluid_bufferA_fragment(VertexOut in [[stage_in]],
                                       constant Uniforms& uniforms [[buffer(0)]],
                                       texture2d<float> bufA      [[texture(0)]],
                                       texture2d<float> bufD      [[texture(1)]],
                                       texture2d<float> bufC      [[texture(2)]],
                                       texture2d<float> bufB      [[texture(3)]],
                                       sampler smp                [[sampler(0)]]) {
    float2 iRes = uniforms.iResolution;
    float2 fragCoord = in.uv * iRes;
    float2 uv = fragCoord / iRes;
    float2 tx = 1.0 / iRes;

    float4 init = bufA.sample(smp, fract(uv));

    float2 turb    = float2(0);
    float2 confine = float2(0);
    float2 divg    = float2(0);
    float2 delta_v = float2(0);
    float2 offset  = float2(0);
    float2 lapl    = float2(0);
    float4 vel     = float4(0);
    float4 adv     = float4(0);

    // Multi-step advection with offset recalculation each substep
    for (int i = 0; i < FLUID_ADVECTION_STEPS; i++) {
        turb = SAMPLE_TURB(tx * offset);
        confine = SAMPLE_CONF(tx * offset);
        vel = SAMPLE_VEL(tx * offset);

        offset = (float(i + 1) / float(FLUID_ADVECTION_STEPS))
                * -FLUID_ADVECTION_SCALE
                * (FLUID_ADVECTION_VELOCITY * vel.xy
                   + FLUID_ADVECTION_TURBULENCE * turb
                   - FLUID_ADVECTION_CONFINEMENT * confine
                   + FLUID_ADVECTION_DIVERGENCE * divg);

        POIS_DIFF(tx * FLUID_DIVERGENCE_LOOKAHEAD * offset);
        VEL_LAPL (tx * FLUID_LAPLACIAN_LOOKAHEAD * offset);

        adv += SAMPLE_VEL(tx * offset);

        delta_v += FLUID_VELOCITY_LAPLACIAN * lapl
                 + FLUID_VELOCITY_TURBULENCE * turb
                 + FLUID_VELOCITY_CONFINEMENT * confine
                 - FLUID_DAMPING * vel.xy
                 - FLUID_DIVERGENCE_MINIMIZATION * divg;
    }
    adv /= float(FLUID_ADVECTION_STEPS);
    delta_v /= float(FLUID_ADVECTION_STEPS);

    // --- Pump (alternating side drivers to stir fluid) ---
    float2 pq = 2.0 * (uv * 2.0 - 1.0) * float2(1.0, tx.x / tx.y);
    float2 pump = float2(0);
    const float AMP = 15.0;
    const float SCL = -50.0;
    float iTime = uniforms.iTime;

    float uvy0 = exp(SCL * pq.y * pq.y);
    float uvx0 = exp(SCL * uv.x * uv.x);
    pump += -AMP * float2(max(0.0, cos(FLUID_PUMP_CYCLE * iTime)) * FLUID_PUMP_SCALE * uvx0 * uvy0, 0.0);

    float uvy1 = exp(SCL * pq.y * pq.y);
    float uvx1 = exp(SCL * (1.0 - uv.x) * (1.0 - uv.x));
    pump += AMP * float2(max(0.0, cos(FLUID_PUMP_CYCLE * iTime + 3.1416)) * FLUID_PUMP_SCALE * uvx1 * uvy1, 0.0);

    float uvy2 = exp(SCL * pq.x * pq.x);
    float uvx2 = exp(SCL * uv.y * uv.y);
    pump += -AMP * float2(0.0, max(0.0, sin(FLUID_PUMP_CYCLE * iTime)) * FLUID_PUMP_SCALE * uvx2 * uvy2);

    float uvy3 = exp(SCL * pq.x * pq.x);
    float uvx3 = exp(SCL * (1.0 - uv.y) * (1.0 - uv.y));
    pump += AMP * float2(0.0, max(0.0, sin(FLUID_PUMP_CYCLE * iTime + 3.1416)) * FLUID_PUMP_SCALE * uvx3 * uvy3);

    float4 outC = mix(adv + float4(FLUID_VELOCITY_SCALE * (delta_v + pump), offset),
                      init, FLUID_UPDATE_SMOOTHING);

    // --- Mouse interaction ---
    if (uniforms.iMouse.z > 0.0) {
        float4 mouseUV = uniforms.iMouse / float4(iRes, iRes);
        float2 delta = fluid_normz(mouseUV.zw - mouseUV.xy);
        float2 md = (mouseUV.xy - uv) * float2(1.0, tx.x / tx.y);
        float amp = exp(max(-12.0, -dot(md, md) / FLUID_MOUSE_RADIUS));
        outC.xy += FLUID_VELOCITY_SCALE * FLUID_MOUSE_AMP * clamp(amp * delta, -1.0, 1.0);
    }

    if (uniforms.iFrame == 0) {
        outC = 1e-6 * fluid_rand4(fragCoord, iRes, uniforms.iFrame);
    }

    return outC;
}
