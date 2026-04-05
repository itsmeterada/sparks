#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Inside the Mandelbulb II - Ported from Shadertoy (single-pass, FXAA omitted)
// https://www.shadertoy.com/view/mtScRc
// License: CC0 (Public Domain)

#define LOOPS   2
#define POWER   8.0

#define MB_PI              3.141592654
#define MB_TAU             (2.0 * MB_PI)

#define TOLERANCE       0.0001
#define MAX_RAY_LENGTH  20.0
#define MAX_RAY_MARCHES 60
#define NORM_OFF        0.005
#define MAX_BOUNCES     5

constant float4 hsv2rgb_K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);

static float3 mb_hsv2rgb(float3 c) {
    float3 p = abs(fract(c.xxx + hsv2rgb_K.xyz) * 6.0 - hsv2rgb_K.www);
    return c.z * mix(hsv2rgb_K.xxx, clamp(p - hsv2rgb_K.xxx, 0.0, 1.0), c.y);
}

constant float3 skyCol     = float3(0.14, 0.484, 1.0);         // HSV(0.6, 0.86, 1.0)
constant float3 diffuseCol = float3(0.15, 0.49, 1.0);          // HSV(0.6, 0.85, 1.0)
constant float3 lightPos   = float3(0.0, 10.0, 0.0);
constant float3 matParam   = float3(0.8, 0.5, 1.05);
constant float initt = 0.1;

static float3 mb_sRGB(float3 t) {
    return mix(1.055 * pow(t, float3(1.0 / 2.4)) - 0.055, 12.92 * t, step(t, float3(0.0031308)));
}

static float3 mb_aces_approx(float3 v) {
    v = max(v, 0.0);
    v *= 0.6;
    float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return clamp((v * (a * v + b)) / (v * (c * v + d) + e), 0.0, 1.0);
}

static float mb_box(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

static float mb_rayPlane(float3 ro, float3 rd, float4 p) {
    return -(dot(ro, p.xyz) + p.w) / dot(rd, p.xyz);
}

static float mb_mandelBulb(float3 p, float iTime) {
    const float power = POWER;
    float3 z = p;
    float r, theta, phi;
    float dr = 1.0;

    for (int i = 0; i < LOOPS; ++i) {
        r = length(z);
        if (r > 2.0) continue;
        theta = atan2(z.y, z.x);
        phi = asin(z.z / r) + iTime * 0.2;
        dr = pow(r, power - 1.0) * dr * power + 1.0;
        r = pow(r, power);
        theta = theta * power;
        phi = phi * power;
        z = r * float3(cos(theta) * cos(phi), sin(theta) * cos(phi), sin(phi)) + p;
    }
    return 0.5 * log(r) * r / dr;
}

static float3x3 mb_rot_y(float a) { float c = cos(a), s = sin(a); return float3x3(float3(c,0,s), float3(0,1,0), float3(-s,0,c)); }
static float3x3 mb_rot_x(float a) { float c = cos(a), s = sin(a); return float3x3(float3(1,0,0), float3(0,c,s), float3(0,-s,c)); }

static float3 mb_skyColor(float3 ro, float3 rd) {
    float3 col = clamp(float3(0.0025 / abs(rd.y)) * skyCol, 0.0, 1.0);
    float tp0 = mb_rayPlane(ro, rd, float4(float3(0.0, 1.0, 0.0), 4.0));
    float tp1 = mb_rayPlane(ro, rd, float4(float3(0.0, -1.0, 0.0), 6.0));

    if (tp1 > 0.0) {
        float3 pos = ro + tp1 * rd;
        float db = mb_box(pos.xz, float2(6.0, 9.0)) - 1.0;
        col += float3(4.0) * skyCol * rd.y * rd.y * smoothstep(0.25, 0.0, db);
        col += float3(0.8) * skyCol * exp(-0.5 * max(db, 0.0));
    }
    if (tp0 > 0.0) {
        float3 pos = ro + tp0 * rd;
        float ds = length(pos.xz) - 0.5;
        col += float3(0.25) * skyCol * exp(-0.5 * max(ds, 0.0));
    }
    return clamp(col, 0.0, 10.0);
}

static float mb_df(float3 p, float3x3 g_rot, float iTime) {
    p = g_rot * p;
    const float z1 = 2.0;
    return mb_mandelBulb(p / z1, iTime) * z1;
}

static float3 mb_normal(float3 pos, float3x3 g_rot, float iTime) {
    float2 eps = float2(NORM_OFF, 0.0);
    float3 nor;
    nor.x = mb_df(pos + eps.xyy, g_rot, iTime) - mb_df(pos - eps.xyy, g_rot, iTime);
    nor.y = mb_df(pos + eps.yxy, g_rot, iTime) - mb_df(pos - eps.yxy, g_rot, iTime);
    nor.z = mb_df(pos + eps.yyx, g_rot, iTime) - mb_df(pos - eps.yyx, g_rot, iTime);
    return normalize(nor);
}

static float mb_rayMarch(float3 ro, float3 rd, float dfactor, float3x3 g_rot, float iTime, thread int& ii) {
    float t = 0.0;
    ii = MAX_RAY_MARCHES;
    for (int i = 0; i < MAX_RAY_MARCHES; ++i) {
        if (t > MAX_RAY_LENGTH) { t = MAX_RAY_LENGTH; break; }
        float d = dfactor * mb_df(ro + rd * t, g_rot, iTime);
        if (d < TOLERANCE) { ii = i; break; }
        t += d;
    }
    return t;
}

static float3 mb_render(float3 ro, float3 rd, float3x3 g_rot, float iTime) {
    float3 agg = float3(0.0);
    float3 ragg = float3(1.0);
    bool isInside = mb_df(ro, g_rot, iTime) < 0.0;
    float3 beer = -mb_hsv2rgb(float3(0.05, 0.95, 2.0));

    for (int bounce = 0; bounce < MAX_BOUNCES; ++bounce) {
        float dfactor = isInside ? -1.0 : 1.0;
        float mragg = max(max(ragg.x, ragg.y), ragg.z);
        if (mragg < 0.025) break;
        int iter;
        float st = mb_rayMarch(ro, rd, dfactor, g_rot, iTime, iter);
        if (st >= MAX_RAY_LENGTH) { agg += ragg * mb_skyColor(ro, rd); break; }

        float3 sp = ro + rd * st;
        float3 sn = dfactor * mb_normal(sp, g_rot, iTime);
        float fre = 1.0 + dot(rd, sn);
        fre *= fre;
        fre = mix(0.1, 1.0, fre);

        float3 ld = normalize(lightPos - sp);
        float dif = max(dot(ld, sn), 0.0);
        float3 ref = reflect(rd, sn);
        float re = matParam.z;
        float ire = 1.0 / re;
        float3 refr = refract(rd, sn, !isInside ? re : ire);
        float3 rsky = mb_skyColor(sp, ref);
        float3 col = float3(0.0);
        col += diffuseCol * dif * dif * (1.0 - matParam.x);
        float edge = smoothstep(1.0, 0.9, fre);
        col += rsky * matParam.y * fre * float3(1.0) * edge;
        if (isInside) ragg *= exp(-(st + initt) * beer);
        agg += ragg * col;

        if (length(refr) < 0.001) {
            rd = ref;
        } else {
            ragg *= matParam.x;
            isInside = !isInside;
            rd = refr;
        }
        ro = sp + initt * rd;
    }
    return agg;
}

fragment float4 mandelbulb_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(0)]]) {
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 q = fragCoord / uniforms.iResolution.xy;
    float2 p = -1.0 + 2.0 * q;
    p.x *= uniforms.iResolution.x / uniforms.iResolution.y;

    float iTime = uniforms.iTime;
    float3x3 g_rot = mb_rot_x(0.2 * iTime) * mb_rot_y(0.3 * iTime);
    float3 ro = 0.6 * float3(0.0, 2.0, 5.0);
    const float3 la = float3(0.0, 0.0, 0.0);
    const float3 up = float3(0.0, 1.0, 0.0);

    float3 ww = normalize(la - ro);
    float3 uu = normalize(cross(up, ww));
    float3 vv = cross(ww, uu);
    const float fov = tan(MB_TAU / 6.0);
    float3 rd = normalize(-p.x * uu + p.y * vv + fov * ww);

    float3 col = mb_render(ro, rd, g_rot, iTime);
    col = mb_aces_approx(col);
    col = mb_sRGB(col);

    return float4(col, 1.0);
}
