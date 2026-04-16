#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Fur Ball - Ported from Shadertoy "fur ball"
// Original Author: Simon Green (@simesgreen) v1.1, 2013
// License: CC BY-NC-SA 3.0

constant float uvScale = 1.0;
constant float colorUvScale = 0.1;
constant float furDepth = 0.2;
constant int furLayers = 64;
constant float rayStep = furDepth * 2.0 / float(furLayers);
constant float furThreshold = 0.4;
constant float shininess = 50.0;

static bool intersectSphere(float3 ro, float3 rd, float r, thread float &t) {
    float b = dot(-ro, rd);
    float det = b * b - dot(ro, ro) + r * r;
    if (det < 0.0) return false;
    det = sqrt(det);
    t = b - det;
    return t > 0.0;
}

static float3 rotateX(float3 p, float a) {
    float sa = sin(a);
    float ca = cos(a);
    return float3(p.x, ca * p.y - sa * p.z, sa * p.y + ca * p.z);
}

static float3 rotateY(float3 p, float a) {
    float sa = sin(a);
    float ca = cos(a);
    return float3(ca * p.x + sa * p.z, p.y, -sa * p.x + ca * p.z);
}

static float2 cartesianToSpherical(float3 p, float iTime) {
    float r = length(p);
    float t = (r - (1.0 - furDepth)) / furDepth;
    p = rotateX(p.zyx, -cos(iTime * 1.5) * t * t * 0.4).zyx;
    p /= r;
    float2 uv = float2(atan2(p.y, p.x), acos(p.z));
    uv.y -= t * t * 0.1;
    return uv;
}

static float furDensity(float3 pos, thread float2 &uv,
                        texture2d<float> ch0, sampler s, float iTime) {
    uv = cartesianToSpherical(pos.xzy, iTime);
    // iChannel0 sampled with Y-flip to mimic the original Shadertoy setup.
    float4 tex = ch0.sample(s, float2(uv.x, -uv.y) * uvScale, level(0.0));
    float density = smoothstep(furThreshold, 1.0, tex.x);
    float r = length(pos);
    float t = (r - (1.0 - furDepth)) / furDepth;
    float len = tex.y;
    density *= smoothstep(len, len - 0.2, t);
    return density;
}

static float3 furNormal(float3 pos, float density,
                        texture2d<float> ch0, sampler s, float iTime) {
    float eps = 0.01;
    float3 n;
    float2 uv;
    n.x = furDensity(float3(pos.x + eps, pos.y, pos.z), uv, ch0, s, iTime) - density;
    n.y = furDensity(float3(pos.x, pos.y + eps, pos.z), uv, ch0, s, iTime) - density;
    n.z = furDensity(float3(pos.x, pos.y, pos.z + eps), uv, ch0, s, iTime) - density;
    return normalize(n);
}

static float3 furShade(float3 pos, float2 uv, float3 ro, float density,
                       texture2d<float> ch0, texture2d<float> ch1, sampler s, float iTime) {
    const float3 L = float3(0, 1, 0);
    float3 V = normalize(ro - pos);
    float3 H = normalize(V + L);

    float3 N = -furNormal(pos, density, ch0, s, iTime);
    float diff = max(0.0, dot(N, L) * 0.5 + 0.5);
    float spec = pow(max(0.0, dot(N, H)), shininess);

    float3 color = ch1.sample(s, uv * colorUvScale, level(0.0)).xyz;

    float r = length(pos);
    float t = (r - (1.0 - furDepth)) / furDepth;
    t = clamp(t, 0.0, 1.0);
    float i = t * 0.5 + 0.5;

    return color * diff * i + float3(spec * i);
}

static float4 scene(float3 ro, float3 rd,
                    texture2d<float> ch0, texture2d<float> ch1, sampler s, float iTime) {
    float3 p = float3(0.0);
    const float r = 1.0;
    float t;
    bool hit = intersectSphere(ro - p, rd, r, t);

    float4 c = float4(0.0);
    if (hit) {
        float3 pos = ro + rd * t;
        for (int i = 0; i < furLayers; i++) {
            float4 sampleCol;
            float2 uv;
            sampleCol.a = furDensity(pos, uv, ch0, s, iTime);
            if (sampleCol.a > 0.0) {
                sampleCol.rgb = furShade(pos, uv, ro, sampleCol.a, ch0, ch1, s, iTime);
                sampleCol.rgb *= sampleCol.a;
                c = c + sampleCol * (1.0 - c.a);
                if (c.a > 0.95) break;
            }
            pos += rd * rayStep;
        }
    }
    return c;
}

fragment float4 furball_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(0)]],
                                  texture2d<float> iChannel0 [[texture(0)]],
                                  texture2d<float> iChannel1 [[texture(1)]],
                                  sampler s [[sampler(0)]])
{
    float2 iResolution = uniforms.iResolution;
    float iTime = uniforms.iTime;
    float4 iMouse = uniforms.iMouse;

    // Convert from Metal Y-down position to Shadertoy Y-up fragCoord.
    float2 fragCoord = float2(in.position.x, iResolution.y - in.position.y);
    float2 uv = fragCoord / iResolution;
    uv = uv * 2.0 - 1.0;
    uv.x *= iResolution.x / iResolution.y;

    float3 ro = float3(0.0, 0.0, 2.5);
    float3 rd = normalize(float3(uv, -2.0));

    float2 mouse = iMouse.xy / iResolution;
    float roty = 0.0;
    float rotx = 0.0;
    if (iMouse.z > 0.0) {
        rotx = (mouse.y - 0.5) * 3.0;
        roty = -(mouse.x - 0.5) * 6.0;
    } else {
        roty = sin(iTime * 1.5);
    }

    ro = rotateX(ro, rotx);
    ro = rotateY(ro, roty);
    rd = rotateX(rd, rotx);
    rd = rotateY(rd, roty);

    return scene(ro, rd, iChannel0, iChannel1, s, iTime);
}
