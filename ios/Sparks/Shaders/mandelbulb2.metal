#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Mandelbulb - Ported from Shadertoy
// https://www.shadertoy.com/view/MdXSWn
// Original Author: evilryu
// License: CC BY-NC-SA 3.0

static void ry(thread float3 &p, float a) {
    float c, s;
    float3 q = p;
    c = cos(a); s = sin(a);
    p.x = c * q.x + s * q.z;
    p.z = -s * q.x + c * q.z;
}

static float3 mb(float3 p) {
    p.xyz = p.xzy;
    float3 z = p;
    float power = 8.0;
    float r, theta, phi;
    float dr = 1.0;
    float t0 = 1.0;
    for (int i = 0; i < 7; ++i) {
        r = length(z);
        if (r > 2.0) continue;
        theta = atan2(z.y, z.x);
        phi = asin(z.z / r);
        dr = pow(r, power - 1.0) * dr * power + 1.0;
        r = pow(r, power);
        theta = theta * power;
        phi = phi * power;
        z = r * float3(cos(theta) * cos(phi), sin(theta) * cos(phi), sin(phi)) + p;
        t0 = min(t0, r);
    }
    return float3(0.5 * log(r) * r / dr, t0, 0.0);
}

static float3 mb2_f(float3 p, float iTime) {
    ry(p, iTime * 0.2);
    return mb(p);
}

static float mb2_softshadow(float3 ro, float3 rd, float k, float iTime) {
    float akuma = 1.0, h = 0.0;
    float t = 0.01;
    for (int i = 0; i < 50; ++i) {
        h = mb2_f(ro + rd * t, iTime).x;
        if (h < 0.001) return 0.02;
        akuma = min(akuma, k * h / t);
        t += clamp(h, 0.01, 2.0);
    }
    return akuma;
}

static float3 mb2_nor(float3 pos, float iTime) {
    float3 eps = float3(0.001, 0.0, 0.0);
    return normalize(float3(
        mb2_f(pos + eps.xyy, iTime).x - mb2_f(pos - eps.xyy, iTime).x,
        mb2_f(pos + eps.yxy, iTime).x - mb2_f(pos - eps.yxy, iTime).x,
        mb2_f(pos + eps.yyx, iTime).x - mb2_f(pos - eps.yyx, iTime).x));
}

static float3 mb2_intersect(float3 ro, float3 rd, float iTime, float pixel_size) {
    float t = 1.0;
    float res_t = 0.0;
    float3 c, res_c;
    float max_error = 1000.0;
    float d = 1.0;
    float pd = 100.0;
    float os = 0.0;
    float step_ = 0.0;
    float error = 1000.0;

    for (int i = 0; i < 48; i++) {
        if (error < pixel_size * 0.5 || t > 20.0) {
        } else {
            c = mb2_f(ro + rd * t, iTime);
            d = c.x;
            if (d > os) {
                os = 0.4 * d * d / pd;
                step_ = d + os;
                pd = d;
            } else {
                step_ = -os; os = 0.0; pd = 100.0; d = 1.0;
            }
            error = d / t;
            if (error < max_error) {
                max_error = error;
                res_t = t;
                res_c = c;
            }
            t += step_;
        }
    }
    if (t > 20.0) res_t = -1.0;
    return float3(res_t, res_c.y, res_c.z);
}

fragment float4 mandelbulb2_fragment(VertexOut in [[stage_in]],
                                     constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 q = fragCoord / uniforms.iResolution;
    float2 uv = -1.0 + 2.0 * q;
    uv.x *= uniforms.iResolution.x / uniforms.iResolution.y;

    float pixel_size = 1.0 / (uniforms.iResolution.x * 3.0);

    float stime = 0.7 + 0.3 * sin(iTime * 0.4);
    float ctime = 0.7 + 0.3 * cos(iTime * 0.4);

    float3 ta = float3(0.0);
    float3 ro = float3(0.0, 3.0 * stime * ctime, 3.0 * (1.0 - stime * ctime));

    float3 cf = normalize(ta - ro);
    float3 cs = normalize(cross(cf, float3(0.0, 1.0, 0.0)));
    float3 cu = normalize(cross(cs, cf));
    float3 rd = normalize(uv.x * cs + uv.y * cu + 3.0 * cf);

    float3 sundir = normalize(float3(0.1, 0.8, 0.6));
    float3 sun = float3(1.64, 1.27, 0.99);
    float3 skycolor = float3(0.6, 1.5, 1.0);

    float3 bg = exp(uv.y - 2.0) * float3(0.4, 1.6, 1.0);

    float halo = clamp(dot(normalize(-ro), rd), 0.0, 1.0);
    float3 col = bg + float3(1.0, 0.8, 0.4) * pow(halo, 17.0);

    float3 res = mb2_intersect(ro, rd, iTime, pixel_size);
    if (res.x > 0.0) {
        float3 p = ro + res.x * rd;
        float3 n = mb2_nor(p, iTime);
        float shadow = mb2_softshadow(p, sundir, 10.0, iTime);

        float dif = max(0.0, dot(n, sundir));
        float sky = 0.6 + 0.4 * max(0.0, dot(n, float3(0.0, 1.0, 0.0)));
        float bac = max(0.3 + 0.7 * dot(float3(-sundir.x, -1.0, -sundir.z), n), 0.0);
        float spe = max(0.0, pow(clamp(dot(sundir, reflect(rd, n)), 0.0, 1.0), 10.0));

        float3 lin = 4.5 * sun * dif * shadow;
        lin += 0.8 * bac * sun;
        lin += 0.6 * sky * skycolor * shadow;
        lin += 3.0 * spe * shadow;

        res.y = pow(clamp(res.y, 0.0, 1.0), 0.55);
        float3 tc0 = 0.5 + 0.5 * sin(3.0 + 4.2 * res.y + float3(0.0, 0.5, 1.0));
        col = lin * float3(0.9, 0.8, 0.6) * 0.2 * tc0;
        col = mix(col, bg, 1.0 - exp(-0.001 * res.x * res.x));
    }

    col = pow(clamp(col, 0.0, 1.0), float3(0.45));
    col = col * 0.6 + 0.4 * col * col * (3.0 - 2.0 * col);
    col = mix(col, float3(dot(col, float3(0.33))), -0.5);
    col *= 0.5 + 0.5 * pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.7);
    return float4(col, 1.0);
}
