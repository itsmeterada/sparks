#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Protean clouds - Ported from Shadertoy
// https://www.shadertoy.com/view/3l23Rh
// Original Author: nimitz (twitter: @stormoid)
// License: CC BY-NC-SA 3.0

static float2x2 prot_rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

constant float3x3 m3 = float3x3(
    float3(0.33338, 0.56034, -0.71817),
    float3(-0.87887, 0.32651, -0.15323),
    float3(0.15162, 0.69596, 0.61339)) * 1.93;

static float mag2(float2 p) { return dot(p, p); }
static float linstep(float mn, float mx, float x) { return clamp((x - mn) / (mx - mn), 0., 1.); }

static float2 disp(float t) { return float2(sin(t * 0.22) * 1., cos(t * 0.175) * 1.) * 2.; }

static float2 prot_map(float3 p, float iTime, float prm1, float2 bsMo) {
    float3 p2 = p;
    p2.xy -= disp(p.z);
    p.xy = p.xy * prot_rot(sin(p.z + iTime) * (0.1 + prm1 * 0.05) + iTime * 0.09);
    float cl = mag2(p2.xy);
    float d = 0.;
    p *= .61;
    float z = 1.;
    float trk = 1.;
    float dspAmp = 0.1 + prm1 * 0.2;
    for (int i = 0; i < 5; i++) {
        p += sin(p.zxy * 0.75 * trk + iTime * trk * .8) * dspAmp;
        d -= abs(dot(cos(p), sin(p.yzx)) * z);
        z *= 0.57;
        trk *= 1.4;
        p = p * m3;
    }
    d = abs(d + prm1 * 3.) + prm1 * .3 - 2.5 + bsMo.y;
    return float2(d + cl * .2 + 0.25, cl);
}

static float4 prot_render(float3 ro, float3 rd, float time, float iTime, float prm1, float2 bsMo) {
    float4 rez = float4(0);
    const float ldst = 8.;
    float3 lpos = float3(disp(time + ldst) * 0.5, time + ldst);
    float t = 1.5;
    float fogT = 0.;
    for (int i = 0; i < 130; i++) {
        if (rez.a > 0.99) break;
        float3 pos = ro + t * rd;
        float2 mpv = prot_map(pos, iTime, prm1, bsMo);
        float den = clamp(mpv.x - 0.3, 0., 1.) * 1.12;
        float dn = clamp((mpv.x + 2.), 0., 3.);

        float4 col = float4(0);
        if (mpv.x > 0.6) {
            col = float4(sin(float3(5., 0.4, 0.2) + mpv.y * 0.1 + sin(pos.z * 0.4) * 0.5 + 1.8) * 0.5 + 0.5, 0.08);
            col *= den * den * den;
            col.rgb *= linstep(4., -2.5, mpv.x) * 2.3;
            float dif = clamp((den - prot_map(pos + .8, iTime, prm1, bsMo).x) / 9., 0.001, 1.);
            dif += clamp((den - prot_map(pos + .35, iTime, prm1, bsMo).x) / 2.5, 0.001, 1.);
            col.xyz *= den * (float3(0.005, .045, .075) + 1.5 * float3(0.033, 0.07, 0.03) * dif);
        }

        float fogC = exp(t * 0.2 - 2.2);
        col.rgba += float4(0.06, 0.11, 0.11, 0.1) * clamp(fogC - fogT, 0., 1.);
        fogT = fogC;
        rez = rez + col * (1. - rez.a);
        t += clamp(0.5 - dn * dn * .05, 0.09, 0.3);
    }
    return clamp(rez, 0.0, 1.0);
}

static float getsat(float3 c) {
    float mi = min(min(c.x, c.y), c.z);
    float ma = max(max(c.x, c.y), c.z);
    return (ma - mi) / (ma + 1e-7);
}

static float3 iLerp(float3 a, float3 b, float x) {
    float3 ic = mix(a, b, x) + float3(1e-6, 0., 0.);
    float sd = abs(getsat(ic) - mix(getsat(a), getsat(b), x));
    float3 dir = normalize(float3(2. * ic.x - ic.y - ic.z, 2. * ic.y - ic.x - ic.z, 2. * ic.z - ic.y - ic.x));
    float lgt = dot(float3(1.0), ic);
    float ff = dot(dir, normalize(ic));
    ic += 1.5 * dir * sd * ff * lgt;
    return clamp(ic, 0., 1.);
}

fragment float4 protean_fragment(VertexOut in [[stage_in]],
                                 constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 q = fragCoord / uniforms.iResolution;
    float2 p = (fragCoord - 0.5 * uniforms.iResolution) / uniforms.iResolution.y;
    float2 bsMo = (uniforms.iMouse.xy - 0.5 * uniforms.iResolution) / uniforms.iResolution.y;

    float time = iTime * 3.;
    float3 ro = float3(0, 0, time);
    ro += float3(sin(iTime) * 0.5, sin(iTime * 1.) * 0., 0);
    float dspAmp = .85;
    ro.xy += disp(ro.z) * dspAmp;
    float tgtDst = 3.5;

    float3 target = normalize(ro - float3(disp(time + tgtDst) * dspAmp, time + tgtDst));
    ro.x -= bsMo.x * 2.;
    float3 rightdir = normalize(cross(target, float3(0, 1, 0)));
    float3 updir = normalize(cross(rightdir, target));
    rightdir = normalize(cross(updir, target));
    float3 rd = normalize((p.x * rightdir + p.y * updir) * 1. - target);
    rd.xy = rd.xy * prot_rot(-disp(time + 3.5).x * 0.2 + bsMo.x);
    float prm1 = smoothstep(-0.4, 0.4, sin(iTime * 0.3));
    float4 scn = prot_render(ro, rd, time, iTime, prm1, bsMo);

    float3 col = scn.rgb;
    col = iLerp(col.bgr, col.rgb, clamp(1. - prm1, 0.05, 1.));
    col = pow(col, float3(.55, 0.65, 0.6)) * float3(1., .97, .9);
    col *= pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.12) * 0.7 + 0.3;

    return float4(col, 1.0);
}
