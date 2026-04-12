#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Smooth Heart - Ported from Shadertoy
// https://www.shadertoy.com/view/4lByWK
// Based on iq's heart (CC BY-NC-SA 3.0)

constant float PI_H = 3.1415926535897932384626433832795;
constant float PHI_H = 1.6180339887498948482045868343656;

static float hash1(float n) { return fract(sin(n)*43758.5453123); }

static float3 forwardSF(float i, float n) {
    float phi = 2.0*PI_H*fract(i/PHI_H);
    float zi = 1.0 - (2.0*i+1.0)/n;
    float sinTheta = sqrt(1.0 - zi*zi);
    return float3(cos(phi)*sinTheta, sin(phi)*sinTheta, zi);
}

static float almostIdentity2(float x, float m, float n) {
    if (x > m) return x;
    float a = 2.0*n - m;
    float b = 2.0*m - 3.0*n;
    float t = x/m;
    return (a*t + b)*t*t + n;
}

static float almostIdentity1(float x, float m) {
    if (x >= m) return x;
    float t = x/m;
    return (t*t+1.0)*(0.5*m);
}

static float2 heart_map(float3 q, float iTime, float4 iMouse, float2 iRes) {
    q *= 100.0;
    float2 res = float2(q.y, 2.0);
    float r = 15.0;
    q.y -= r;
    float ani = pow(0.5+0.5*sin(6.28318*iTime + q.y/25.0), 4.0);
    q *= 1.0 - 0.2*float3(1.0,0.5,1.0)*ani;
    q.y -= 1.5*ani;
    float x = abs(q.x);
    float m = iMouse.y*20.0/iRes.y;
    x = almostIdentity1(x, m);
    float y = q.y;
    float z = q.z;
    y = 4.0 + y*1.2 - x*sqrt(max((20.0-x)/15.0, 0.0));
    z *= 2.0 - y/15.0;
    float d = sqrt(x*x+y*y+z*z) - r;
    d = d/3.0;
    if (d < res.x) res = float2(d, 1.0);
    res.x /= 100.0;
    return res;
}

static float2 heart_intersect(float3 ro, float3 rd, float iTime, float4 iMouse, float2 iRes) {
    const float maxd = 1.0;
    float2 res = float2(0.0);
    float t = 0.2;
    for (int i = 0; i < 300; i++) {
        float2 h = heart_map(ro+rd*t, iTime, iMouse, iRes);
        if ((h.x < 0.0) || (t > maxd)) break;
        t += h.x;
        res = float2(t, h.y);
    }
    if (t > maxd) res = float2(-1.0);
    return res;
}

static float3 heart_calcNormal(float3 pos, float iTime, float4 iMouse, float2 iRes) {
    float3 eps = float3(0.005, 0.0, 0.0);
    return normalize(float3(
        heart_map(pos+eps.xyy, iTime, iMouse, iRes).x - heart_map(pos-eps.xyy, iTime, iMouse, iRes).x,
        heart_map(pos+eps.yxy, iTime, iMouse, iRes).x - heart_map(pos-eps.yxy, iTime, iMouse, iRes).x,
        heart_map(pos+eps.yyx, iTime, iMouse, iRes).x - heart_map(pos-eps.yyx, iTime, iMouse, iRes).x));
}

static float heart_calcAO(float3 pos, float3 nor, float iTime, float4 iMouse, float2 iRes) {
    float ao = 0.0;
    for (int i = 0; i < 64; i++) {
        float3 ap = forwardSF(float(i), 64.0);
        ap *= sign(dot(ap, nor)) * hash1(float(i));
        ao += clamp(heart_map(pos + nor*0.01 + ap*0.2, iTime, iMouse, iRes).x*20.0, 0.0, 1.0);
    }
    ao /= 64.0;
    return clamp(ao, 0.0, 1.0);
}

static float3 heart_render(float2 p, float iTime, float4 iMouse, float2 iRes) {
    float an = 0.2*(iMouse.x*40.0/iRes.x+2.0);
    float3 ro = float3(0.4*sin(an), 0.25, 0.4*cos(an));
    float3 ta = float3(0.0, 0.15, 0.0);
    float3 ww = normalize(ta - ro);
    float3 uu = normalize(cross(ww, float3(0.0, 1.0, 0.0)));
    float3 vv = normalize(cross(uu, ww));
    float3 rd = normalize(p.x*uu + p.y*vv + 1.7*ww);
    float3 col = float3(1.0, 0.82, 0.9);
    float2 res = heart_intersect(ro, rd, iTime, iMouse, iRes);
    float t = res.x;
    if (t > 0.0) {
        float3 pos = ro + t*rd;
        float3 nor = heart_calcNormal(pos, iTime, iMouse, iRes);
        float3 ref = reflect(rd, nor);
        float fre = clamp(1.0 + dot(nor, rd), 0.0, 1.0);
        float occ = heart_calcAO(pos, nor, iTime, iMouse, iRes); occ = occ*occ;
        if (res.y < 1.5) {
            col = float3(0.9, 0.02, 0.01);
            col = col*0.72 + 0.2*fre*float3(1.0, 0.8, 0.2);
            float3 lin = 4.0*float3(0.7, 0.80, 1.00)*(0.5+0.5*nor.y)*occ;
            lin += 0.5*fre*float3(1.0, 1.0, 1.00)*(0.6+0.4*occ);
            col = col * lin;
            col += 4.0*float3(0.7, 0.8, 1.00)*smoothstep(0.0, 0.4, ref.y)*(0.06+0.94*pow(fre, 5.0))*occ;
            col = pow(col, float3(0.4545));
        } else {
            col *= clamp(sqrt(occ*1.8), 0.0, 1.0);
        }
    }
    col = clamp(col, 0.0, 1.0);
    return col;
}

fragment float4 heart_fragment(VertexOut in [[stage_in]],
                               constant Uniforms& uniforms [[buffer(0)]]) {
    float2 iRes = uniforms.iResolution;
    float2 fragCoord = in.uv * iRes;
    float2 p = (-iRes + 2.0*fragCoord) / iRes.y;
    float3 col = heart_render(p, uniforms.iTime, uniforms.iMouse, iRes);
    return float4(col, 1.0);
}
