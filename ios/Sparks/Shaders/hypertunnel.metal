#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Hyper Tunnel - Ported from Shadertoy
// https://www.shadertoy.com/view/4t2cR1
// From "Sailing Beyond" demoscene (CC BY-NC-SA 3.0)

#define HT_FAR 1e3
#define HT_INFINITY 1e32
#define HT_FOV 70.0
#define HT_PI 3.14159265

static float ht_hash12(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h)*43758.5453123);
}

static float ht_noise_3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 fm = f - 1.0;
    float3 u = 1.0 + fm*fm*fm*fm*fm;

    float2 ii = i.xy + i.z * float2(5.0);
    float a = ht_hash12(ii + float2(0.0, 0.0));
    float b = ht_hash12(ii + float2(1.0, 0.0));
    float c = ht_hash12(ii + float2(0.0, 1.0));
    float d = ht_hash12(ii + float2(1.0, 1.0));
    float v1 = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);

    ii += float2(5.0);
    a = ht_hash12(ii + float2(0.0, 0.0));
    b = ht_hash12(ii + float2(1.0, 0.0));
    c = ht_hash12(ii + float2(0.0, 1.0));
    d = ht_hash12(ii + float2(1.0, 1.0));
    float v2 = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);

    return max(mix(v1, v2, u.z), 0.0);
}

static float ht_fbm(float3 x) {
    float r = 0.0;
    float w = 1.0, s = 1.0;
    for (int i = 0; i < 4; i++) {
        w *= 0.25;
        s *= 3.0;
        r += w * ht_noise_3(s * x);
    }
    return r;
}

static float ht_yC(float x) {
    return cos(x * -0.134) * 1.0 * sin(x * 0.13) * 15.0 + ht_fbm(float3(x * 0.1, 0.0, 0.0) * 55.4);
}

struct ht_geometry {
    float dist;
    float3 hit;
    int iterations;
};

static float ht_fCylinderInf(float3 p, float r) {
    return length(p.xz) - r;
}

static ht_geometry ht_map(float3 p, float iTime) {
    p.x -= ht_yC(p.y * 0.1) * 3.0;
    p.z += ht_yC(p.y * 0.01) * 4.0;

    float n = pow(abs(ht_fbm(p * 0.06)) * 12.0, 1.3);
    float s = ht_fbm(p * 0.01 + float3(0.0, iTime * 0.14, 0.0)) * 128.0;

    ht_geometry obj;
    obj.hit = float3(0.0);
    obj.iterations = 0;
    obj.dist = max(0.0, -ht_fCylinderInf(p, s + 18.0 - n));

    p.x -= sin(p.y * 0.02) * 34.0 + cos(p.z * 0.01) * 62.0;
    obj.dist = max(obj.dist, -ht_fCylinderInf(p, s + 28.0 + n * 2.0));

    return obj;
}

static ht_geometry ht_trace(float3 o, float3 d, float iTime) {
    const int MAX_ITERATIONS = 100;
    float t_min = 10.0;
    float t_max = HT_FAR;
    float omega = 1.3;
    float t = t_min;
    float candidate_error = HT_INFINITY;
    float candidate_t = t_min;
    float previousRadius = 0.0;
    float stepLength = 0.0;
    float pixelRadius = 1.0 / 1000.0;

    ht_geometry mp = ht_map(o, iTime);
    float functionSign = mp.dist < 0.0 ? -1.0 : 1.0;

    for (int i = 0; i < MAX_ITERATIONS; ++i) {
        mp = ht_map(d * t + o, iTime);
        mp.iterations = i;

        float signedRadius = functionSign * mp.dist;
        float radius = abs(signedRadius);
        bool sorFail = omega > 1.0 && (radius + previousRadius) < stepLength;

        if (sorFail) {
            stepLength -= omega * stepLength;
            omega = 1.0;
        } else {
            stepLength = signedRadius * omega;
        }
        previousRadius = radius;
        float error = radius / t;

        if (!sorFail && error < candidate_error) {
            candidate_t = t;
            candidate_error = error;
        }

        if ((!sorFail && error < pixelRadius) || t > t_max) break;

        t += stepLength * 0.5;
    }

    mp.dist = candidate_t;
    if (t > t_max || candidate_error > pixelRadius) mp.dist = HT_INFINITY;
    return mp;
}

fragment float4 hypertunnel_fragment(VertexOut in [[stage_in]],
                                     constant Uniforms& uniforms [[buffer(0)]]) {
    float2 iRes = uniforms.iResolution;
    float iTime = uniforms.iTime;
    float2 fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * iRes;
    float2 ouv = fragCoord / iRes;
    float2 uv = ouv - 0.5;
    uv *= tan(HT_FOV * HT_PI / 180.0 / 2.0) * 4.0;

    float T = iTime;
    float3 vuv = normalize(float3(cos(T), sin(T * 0.11), sin(T * 0.41)));
    float3 ro = float3(0.0, 30.0 + iTime * 100.0, -0.1);
    ro.x += ht_yC(ro.y * 0.1) * 3.0;
    ro.z -= ht_yC(ro.y * 0.01) * 4.0;

    float3 vrp = float3(0.0, 50.0 + iTime * 100.0, 2.0);
    vrp.x += ht_yC(vrp.y * 0.1) * 3.0;
    vrp.z -= ht_yC(vrp.y * 0.01) * 4.0;

    float3 vpn = normalize(vrp - ro);
    float3 u = normalize(cross(vuv, vpn));
    float3 v = cross(vpn, u);
    float3 vcv = ro + vpn;
    float3 scrCoord = vcv + uv.x * u * iRes.x / iRes.y + uv.y * v;
    float3 rd = normalize(scrCoord - ro);
    float3 oro = ro;

    float3 sceneColor = float3(0.0);
    ht_geometry tr = ht_trace(ro, rd, iTime);
    tr.hit = ro + rd * tr.dist;

    float3 col = float3(1.0, 0.5, 0.4) * ht_fbm(tr.hit.xzy * 0.01) * 20.0;
    col.b *= ht_fbm(tr.hit * 0.01) * 10.0;

    sceneColor += min(0.8, float(tr.iterations) / 90.0) * col + col * 0.03;
    sceneColor *= 1.0 + 0.9 * (abs(ht_fbm(tr.hit * 0.002 + 3.0) * 10.0) * ht_fbm(float3(0.0, 0.0, iTime * 0.05) * 2.0));
    sceneColor *= 0.6;

    float3 steamColor1 = float3(0.0, 0.4, 0.5);
    float3 rro = oro;
    ro = tr.hit;

    float distC = tr.dist, f = 0.0;
    for (float i = 0.0; i < 24.0; i++) {
        rro = ro - rd * distC;
        f += ht_fbm(rro * float3(0.1, 0.1, 0.1) * 0.3) * 0.1;
        distC -= 3.0;
        if (distC < 3.0) break;
    }

    sceneColor += steamColor1 * pow(abs(f * 1.5), 3.0) * 4.0;

    float4 fragColor = float4(clamp(sceneColor * (1.0 - length(uv) / 2.0), 0.0, 1.0), 1.0);
    fragColor = pow(abs(fragColor / tr.dist * 130.0), float4(0.8));
    return fragColor;
}
