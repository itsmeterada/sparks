#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Fluid Buffer A (velocity field)
// Ported from Shadertoy "mipmap-based multiscale fluid dynamics" by Cornus Ammonis

constant int ADVECTION_STEPS = 3;
constant float ADVECTION_SCALE = 40.0;
constant float ADVECTION_TURBULENCE = 1.0;
constant float VELOCITY_TURBULENCE = 0.0;
constant float VELOCITY_CONFINEMENT = 0.01;
constant float VELOCITY_LAPLACIAN = 0.02;
constant float ADVECTION_CONFINEMENT = 0.6;
constant float ADVECTION_DIVERGENCE = 0.0;
constant float ADVECTION_VELOCITY = -0.05;
constant float DIVERGENCE_MINIMIZATION = 0.1;
constant float DIVERGENCE_LOOKAHEAD = 1.0;
constant float LAPLACIAN_LOOKAHEAD = 1.0;
constant float DAMPING = 0.0001;
constant float VELOCITY_SCALE = 1.0;
constant float UPDATE_SMOOTHING = 0.0;
constant float MOUSE_AMP = 0.05;
constant float MOUSE_RADIUS = 0.001;
constant float PUMP_SCALE = 0.001;
constant float PUMP_CYCLE = 0.2;

static float2 normz(float2 x) {
    return all(x == float2(0.0)) ? float2(0.0) : normalize(x);
}

static float hash1(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffffU);
}

static float3 hash3(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    uint3 k = n * uint3(n, n * 16807U, n * 48271U);
    return float3(k & uint3(0x7fffffffU)) / float(0x7fffffffU);
}

static float4 rand4(float2 fragCoord, float2 resolution, int frame) {
    uint2 p = uint2(fragCoord);
    uint2 r = uint2(resolution);
    uint c = p.x + r.x * p.y + r.x * r.y * uint(frame);
    return float4(hash3(c), hash1(c + 75132895U));
}

fragment float4 fluid_a_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(0)]],
                                  texture2d<float> iChannel0 [[texture(0)]], // velocity.src
                                  texture2d<float> iChannel1 [[texture(1)]], // pressure.src
                                  texture2d<float> iChannel2 [[texture(2)]], // confinement
                                  texture2d<float> iChannel3 [[texture(3)]], // turbulence
                                  sampler s [[sampler(0)]])
{
    float2 fragCoord = in.position.xy;
    float2 iResolution = uniforms.iResolution;
    float4 iMouse = uniforms.iMouse;
    float iTime = uniforms.iTime;
    int iFrame = uniforms.iFrame;

    float2 uvArg = fragCoord / iResolution;
    float2 tx = 1.0 / iResolution;
    float4 t4 = float4(tx, -tx.y, 0.0);

    float2 turb = float2(0.0);
    float2 confine = float2(0.0);
    float2 div = float2(0.0);
    float2 delta_v = float2(0.0);
    float2 offset = float2(0.0);
    float2 lapl = float2(0.0);
    float4 vel;
    float4 adv = float4(0.0);
    float4 init = iChannel0.sample(s, fract(uvArg));

    for (int i = 0; i < ADVECTION_STEPS; i++) {
        turb = iChannel3.sample(s, fract(uvArg + tx * offset)).xy;
        confine = iChannel2.sample(s, fract(uvArg + tx * offset)).xy;
        vel = iChannel0.sample(s, fract(uvArg + tx * offset));
        offset = (float(i + 1) / float(ADVECTION_STEPS)) * -ADVECTION_SCALE *
            (ADVECTION_VELOCITY * vel.xy +
                ADVECTION_TURBULENCE * turb -
                ADVECTION_CONFINEMENT * confine +
                ADVECTION_DIVERGENCE * div);

        // diff
        float2 uvD = uvArg + tx * DIVERGENCE_LOOKAHEAD * offset;
        float dC = iChannel1.sample(s, fract(uvD + t4.ww)).x;
        float dN = iChannel1.sample(s, fract(uvD + t4.wy)).x;
        float dE = iChannel1.sample(s, fract(uvD + t4.xw)).x;
        float dS = iChannel1.sample(s, fract(uvD + t4.wz)).x;
        float dW = iChannel1.sample(s, fract(uvD - t4.xw)).x;
        float dNW = iChannel1.sample(s, fract(uvD - t4.xz)).x;
        float dSW = iChannel1.sample(s, fract(uvD - t4.xy)).x;
        float dNE = iChannel1.sample(s, fract(uvD + t4.xy)).x;
        float dSE = iChannel1.sample(s, fract(uvD + t4.xz)).x;
        div = float2(
            0.5 * (dE - dW) + 0.25 * (dNE - dNW + dSE - dSW),
            0.5 * (dN - dS) + 0.25 * (dNE + dNW - dSE - dSW)
        );

        // vector_laplacian
        float2 uvL = uvArg + tx * LAPLACIAN_LOOKAHEAD * offset;
        float k0 = -20.0 / 6.0;
        float k1 = 4.0 / 6.0;
        float k2 = 1.0 / 6.0;
        float4 nC = iChannel0.sample(s, fract(uvL + t4.ww));
        float4 nN = iChannel0.sample(s, fract(uvL + t4.wy));
        float4 nE = iChannel0.sample(s, fract(uvL + t4.xw));
        float4 nS = iChannel0.sample(s, fract(uvL + t4.wz));
        float4 nW = iChannel0.sample(s, fract(uvL - t4.xw));
        float4 nNW = iChannel0.sample(s, fract(uvL - t4.xz));
        float4 nSW = iChannel0.sample(s, fract(uvL - t4.xy));
        float4 nNE = iChannel0.sample(s, fract(uvL + t4.xy));
        float4 nSE = iChannel0.sample(s, fract(uvL + t4.xz));
        lapl = (k0 * nC + k1 * (nE + nW + nN + nS) + k2 * (nNE + nNW + nSE + nSW)).xy;

        adv += iChannel0.sample(s, fract(uvArg + tx * offset));
        delta_v += VELOCITY_LAPLACIAN * lapl +
            VELOCITY_TURBULENCE * turb +
            VELOCITY_CONFINEMENT * confine -
            DAMPING * vel.xy -
            DIVERGENCE_MINIMIZATION * div;
    }
    adv /= float(ADVECTION_STEPS);
    delta_v /= float(ADVECTION_STEPS);

    float2 pq = 2.0 * (uvArg * 2.0 - 1.0) * float2(1.0, tx.x / tx.y);
    float2 pump = float2(0.0);

    const float amp = 15.0;
    const float scl = -50.0;
    float uvy0 = exp(scl * pow(pq.y, 2.0));
    float uvx0 = exp(scl * pow(uvArg.x, 2.0));
    pump += -amp * float2(max(0.0, cos(PUMP_CYCLE * iTime)) * PUMP_SCALE * uvx0 * uvy0, 0.0);

    float uvy1 = exp(scl * pow(pq.y, 2.0));
    float uvx1 = exp(scl * pow(1.0 - uvArg.x, 2.0));
    pump += amp * float2(max(0.0, cos(PUMP_CYCLE * iTime + 3.1416)) * PUMP_SCALE * uvx1 * uvy1, 0.0);

    float uvy2 = exp(scl * pow(pq.x, 2.0));
    float uvx2 = exp(scl * pow(uvArg.y, 2.0));
    pump += -amp * float2(0.0, max(0.0, sin(PUMP_CYCLE * iTime)) * PUMP_SCALE * uvx2 * uvy2);

    float uvy3 = exp(scl * pow(pq.x, 2.0));
    float uvx3 = exp(scl * pow(1.0 - uvArg.y, 2.0));
    pump += amp * float2(0.0, max(0.0, sin(PUMP_CYCLE * iTime + 3.1416)) * PUMP_SCALE * uvx3 * uvy3);

    float4 fragColor = mix(adv + float4(VELOCITY_SCALE * (delta_v + pump), offset), init, UPDATE_SMOOTHING);

    if (iMouse.z > 0.0) {
        float4 mouseUV = iMouse / float4(iResolution, iResolution);
        float2 delta = normz(mouseUV.zw - mouseUV.xy);
        float2 md = (mouseUV.xy - uvArg) * float2(1.0, tx.x / tx.y);
        float ampMouse = exp(max(-12.0, -dot(md, md) / MOUSE_RADIUS));
        fragColor.xy += VELOCITY_SCALE * MOUSE_AMP * clamp(ampMouse * delta, -1.0, 1.0);
    }

    if (iFrame == 0) {
        fragColor = 1e-6 * rand4(fragCoord, iResolution, iFrame);
    }
    return fragColor;
}
