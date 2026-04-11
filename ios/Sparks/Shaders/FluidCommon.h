#pragma once
#include <metal_stdlib>
using namespace metal;

// Multiscale Turbulence (Cornus Ammonis) - shared Common tab port
// https://www.shadertoy.com/view/tsKXR3

// --- Simulation parameters (from original Common tab) ---
#define FLUID_TURBULENCE_SCALES         11
#define FLUID_VORTICITY_SCALES          11
#define FLUID_POISSON_SCALES            11

#define FLUID_ADVECTION_STEPS           3
#define FLUID_ADVECTION_SCALE           40.0
#define FLUID_ADVECTION_TURBULENCE      1.0
#define FLUID_VELOCITY_TURBULENCE       0.0
#define FLUID_VELOCITY_CONFINEMENT      0.01
#define FLUID_VELOCITY_LAPLACIAN        0.02
#define FLUID_ADVECTION_CONFINEMENT     0.6
#define FLUID_ADVECTION_DIVERGENCE      0.0
#define FLUID_ADVECTION_VELOCITY        -0.05
#define FLUID_DIVERGENCE_MINIMIZATION   0.1
#define FLUID_DIVERGENCE_LOOKAHEAD      1.0
#define FLUID_LAPLACIAN_LOOKAHEAD       1.0
#define FLUID_DAMPING                   0.0001
#define FLUID_VELOCITY_SCALE            1.0
#define FLUID_UPDATE_SMOOTHING          0.0

#define FLUID_TURB_ISOTROPY             0.9
#define FLUID_CURL_ISOTROPY             0.6
#define FLUID_CONF_ISOTROPY             0.25
#define FLUID_POIS_ISOTROPY             0.16

#define FLUID_PREMULTIPLY_CURL          1

#define FLUID_TURB_W(i)                 (1.0)
#define FLUID_CURL_W(i)                 (1.0 / float((i) + 1))
#define FLUID_CONF_W(i)                 (1.0)
#define FLUID_POIS_W(i)                 (1.0 / float((i) + 1))

#define FLUID_MOUSE_AMP                 0.05
#define FLUID_MOUSE_RADIUS              0.001

#define FLUID_PUMP_SCALE                0.001
#define FLUID_PUMP_CYCLE                0.2

#define FLUID_BUMP                      3200.0

// --- Soft min/max helpers ---
static inline float fluid_softmax(float a, float b, float k) {
    return log(exp(k * a) + exp(k * b)) / k;
}
static inline float fluid_softmin(float a, float b, float k) {
    return -log(exp(-k * a) + exp(-k * b)) / k;
}
static inline float fluid_softclamp(float a, float b, float x, float k) {
    return 0.5 * (fluid_softmin(b, fluid_softmax(a, x, k), k)
                 + fluid_softmax(a, fluid_softmin(b, x, k), k));
}
static inline float4 fluid_softmax4(float4 a, float4 b, float k) {
    return log(exp(k * a) + exp(k * b)) / k;
}
static inline float4 fluid_softmin4(float4 a, float4 b, float k) {
    return -log(exp(-k * a) + exp(-k * b)) / k;
}
static inline float4 fluid_softclamp4(float4 a, float4 b, float4 x, float k) {
    return 0.5 * (fluid_softmin4(b, fluid_softmax4(a, x, k), k)
                 + fluid_softmax4(a, fluid_softmin4(b, x, k), k));
}
static inline float4 fluid_softclamp4s(float a, float b, float4 x, float k) {
    return fluid_softclamp4(float4(a), float4(b), x, k);
}

// --- normz: normalize or zero ---
static inline float2 fluid_normz(float2 v) {
    return all(v == float2(0)) ? float2(0) : normalize(v);
}
static inline float3 fluid_normz(float3 v) {
    return all(v == float3(0)) ? float3(0) : normalize(v);
}

// --- 3x3 component-wise dot ---
static inline float fluid_reduce(float3x3 a, float3x3 b) {
    return dot(a[0], b[0]) + dot(a[1], b[1]) + dot(a[2], b[2]);
}

// --- Integer hash (Hugo Elias) ---
static inline float fluid_hash1(uint n) {
    n = (n << 13u) ^ n;
    n = n * (n * n * 15731u + 789221u) + 1376312589u;
    return float(n & 0x7fffffffu) / float(0x7fffffff);
}
static inline float3 fluid_hash3(uint n) {
    n = (n << 13u) ^ n;
    n = n * (n * n * 15731u + 789221u) + 1376312589u;
    uint3 k = n * uint3(n, n * 16807u, n * 48271u);
    return float3(k & uint3(0x7fffffffu)) / float(0x7fffffff);
}
static inline float4 fluid_rand4(float2 fragCoord, float2 iResolution, int iFrame) {
    uint2 p = uint2(fragCoord);
    uint2 r = uint2(iResolution);
    uint c = p.x + r.x * p.y + r.x * r.y * uint(iFrame);
    return float4(fluid_hash3(c), fluid_hash1(c + 75132895u));
}

// --- GGX specular (Noby's Goo shader, MIT) ---
static inline float fluid_G1V(float dnv, float k) {
    return 1.0 / (dnv * (1.0 - k) + k);
}
static inline float fluid_ggx(float3 n, float3 v, float3 l, float rough, float f0) {
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
    dlh = pow(1.0 - dlh, 5.0);
    float f = f0 + (1.0 - f0) * dlh;
    float k = alpha;
    float vis = fluid_G1V(dnl, k) * fluid_G1V(dnv, k);
    return dnl * d * f * vis;
}

// --- Light direction + reflected view (Shane's bumpmapping) ---
static inline float3 fluid_light_dir(float2 uv, float bumpAmt, float srcDist, float2 dxy,
                                     float iTime, thread float3& avd) {
    float3 sp = float3(uv - 0.5, 0);
    float3 lightPos = float3(cos(iTime * 0.5) * 0.5, sin(iTime * 0.5) * 0.5, -srcDist);
    float3 ld = lightPos - sp;
    float lDist = max(length(ld), 0.001);
    ld /= lDist;
    avd = reflect(normalize(float3(bumpAmt * dxy, -1.0)), float3(0, 1, 0));
    return ld;
}
