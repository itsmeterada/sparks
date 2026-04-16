#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Fluid Image pass (final visualization)
// Ported from Shadertoy "mipmap-based multiscale fluid dynamics" by Cornus Ammonis

static float softmax_f(float a, float b, float k) {
    return log(exp(k * a) + exp(k * b)) / k;
}

static float softmin_f(float a, float b, float k) {
    return -log(exp(-k * a) + exp(-k * b)) / k;
}

static float4 softmax_v4(float4 a, float4 b, float k) {
    return log(exp(k * a) + exp(k * b)) / k;
}

static float4 softmin_v4(float4 a, float4 b, float k) {
    return -log(exp(-k * a) + exp(-k * b)) / k;
}

static float softclamp_f(float a, float b, float x, float k) {
    return (softmin_f(b, softmax_f(a, x, k), k) + softmax_f(a, softmin_f(b, x, k), k)) / 2.0;
}

static float4 softclamp_v4(float a, float b, float4 x, float k) {
    return (softmin_v4(float4(b), softmax_v4(float4(a), x, k), k) +
            softmax_v4(float4(a), softmin_v4(float4(b), x, k), k)) / 2.0;
}

static float G1V(float dnv, float k) {
    return 1.0 / (dnv * (1.0 - k) + k);
}

static float ggx(float3 n, float3 v, float3 l, float rough, float f0) {
    float alpha = rough * rough;
    float3 h = normalize(v + l);
    float dnl = clamp(dot(n, l), 0.0, 1.0);
    float dnv = clamp(dot(n, v), 0.0, 1.0);
    float dnh = clamp(dot(n, h), 0.0, 1.0);
    float dlh = clamp(dot(l, h), 0.0, 1.0);
    float asqr = alpha * alpha;
    const float pi = 3.14159;
    float den = dnh * dnh * (asqr - 1.0) + 1.0;
    float d = asqr / (pi * den * den);
    float f = f0 + (1.0 - f0) * pow(1.0 - dlh, 5.0);
    float vis = G1V(dnl, alpha) * G1V(dnv, alpha);
    return dnl * d * f * vis;
}

static float3 light_calc(float2 uv, float bump, float srcDist, float2 dxy, float time, thread float3 &avd) {
    float3 sp = float3(uv - 0.5, 0.0);
    float3 lightPos = float3(cos(time / 2.0) * 0.5, sin(time / 2.0) * 0.5, -srcDist);
    float3 ld = lightPos - sp;
    float lDist = max(length(ld), 0.001);
    ld /= lDist;
    avd = reflect(normalize(float3(bump * dxy, -1.0)), float3(0.0, 1.0, 0.0));
    return ld;
}

constant float BUMP = 3200.0;

static float2 diff_pressure(texture2d<float> iChannel1, sampler s, float2 uv, float mip, float2 iResolution) {
    float2 texel = 1.0 / iResolution;
    float4 t = float(1 << int(mip)) * float4(texel, -texel.y, 0.0);

    float d = -iChannel1.sample(s, fract(uv + t.ww), level(mip)).w;
    float d_n = -iChannel1.sample(s, fract(uv + t.wy), level(mip)).w;
    float d_e = -iChannel1.sample(s, fract(uv + t.xw), level(mip)).w;
    float d_s = -iChannel1.sample(s, fract(uv + t.wz), level(mip)).w;
    float d_w = -iChannel1.sample(s, fract(uv - t.xw), level(mip)).w;
    float d_nw = -iChannel1.sample(s, fract(uv - t.xz), level(mip)).w;
    float d_sw = -iChannel1.sample(s, fract(uv - t.xy), level(mip)).w;
    float d_ne = -iChannel1.sample(s, fract(uv + t.xy), level(mip)).w;
    float d_se = -iChannel1.sample(s, fract(uv + t.xz), level(mip)).w;

    return float2(
        0.5 * (d_e - d_w) + 0.25 * (d_ne - d_nw + d_se - d_sw),
        0.5 * (d_n - d_s) + 0.25 * (d_ne + d_nw - d_se - d_sw)
    );
}

static float4 contrast(float4 col, float x) {
    return x * (col - 0.5) + 0.5;
}

fragment float4 fluid_image_fragment(VertexOut in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(0)]],
                                      texture2d<float> iChannel0 [[texture(0)]], // velocity
                                      texture2d<float> iChannel1 [[texture(1)]], // pressure
                                      texture2d<float> iChannel2 [[texture(2)]], // turbulence (unused)
                                      texture2d<float> iChannel3 [[texture(3)]], // confinement (unused)
                                      sampler s [[sampler(0)]])
{
    float2 fragCoord = in.position.xy;
    float2 iResolution = uniforms.iResolution;
    float iTime = uniforms.iTime;
    float2 uv = fragCoord / iResolution;

    float2 dxy = float2(0.0);
    float occ = 0.0;
    float d = -iChannel1.sample(s, fract(uv), level(0.0)).w;

    const float steps = 10.0;
    const float oDist = 2.0;
    for (float mip = 1.0; mip <= steps; mip += 1.0) {
        dxy += (1.0 / pow(2.0, mip)) * diff_pressure(iChannel1, s, uv, mip - 1.0, iResolution);
        occ += softclamp_f(
            -oDist, oDist,
            d - (-iChannel1.sample(s, fract(uv), level(mip)).w),
            1.0
        ) / pow(1.5, mip);
    }
    dxy /= steps;

    occ = pow(max(0.0, softclamp_f(0.2, 0.8, 100.0 * occ + 0.5, 1.0)), 0.5);

    float3 avd;
    float3 ld = light_calc(uv, BUMP, 0.5, dxy, iTime, avd);
    float spec = ggx(avd, float3(0.0, 1.0, 0.0), ld, 0.1, 0.1);

    const float logSpec = 1000.0;
    spec = (log(logSpec + 1.0) / logSpec) * log(1.0 + logSpec * spec);

    float4 diffuse = softclamp_v4(0.0, 1.0, 6.0 * float4(iChannel0.sample(s, uv).xy, 0.0, 0.0) + 0.5, 2.0);
    float4 fragColor = diffuse + 4.0 * mix(float4(spec), 1.5 * diffuse * spec, 0.3);
    fragColor = mix(float4(1.0), float4(occ), float4(0.7)) * softclamp_v4(0.0, 1.0, contrast(fragColor, 4.5), 3.0);
    return fragColor;
}
