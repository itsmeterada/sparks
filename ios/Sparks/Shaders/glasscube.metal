#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Glass Cube - Ported from Shadertoy
// https://www.shadertoy.com/view/NslGRN
// Original Author: Danil (2021+) https://github.com/danilw
// License: CC BY-NC-SA 3.0
//
// Glass box with refracted, sorted, self-intersecting transparent bilinear-patch
// layers inside. Uses iq's intersectors (https://iquilezles.org/articles/intersectors).
// DEBUG / AA / wallpaper option paths (iChannel0 background compositing) of the original are folded out.

#define GC_ROTATION_SPEED 0.8999
#define GC_tshift 53.
#define GC_FDIST 0.7
#define GC_PI 3.1415926
#define GC_BOXDIMS float3(0.75, 0.75, 1.25)
#define GC_IOR 1.33

// GLSL-style mod (fmod truncates toward zero)
static float gc_mod(float x, float y) { return x - y * floor(x / y); }

static float3x3 gc_rotx(float a) { float s = sin(a); float c = cos(a); return float3x3(float3(1.0, 0.0, 0.0), float3(0.0, c, s), float3(0.0, -s, c)); }
static float3x3 gc_roty(float a) { float s = sin(a); float c = cos(a); return float3x3(float3(c, 0.0, s), float3(0.0, 1.0, 0.0), float3(-s, 0.0, c)); }
static float3x3 gc_rotz(float a) { float s = sin(a); float c = cos(a); return float3x3(float3(c, s, 0.0), float3(-s, c, 0.0), float3(0.0, 0.0, 1.0)); }

// derivative-filtered cos (fades out frequencies above the pixel footprint)
static float3 gc_fcos(float3 x, float resY) {
    float3 w = fwidth(x);
    float lw = length(w);
    if ((lw == 0.) || isnan(lw) || isinf(lw)) {
        float3 tc = float3(0.);
        for (int i = 0; i < 8; i++) tc += cos(x + x * float(i - 4) * (0.01 * 400. / resY));
        return tc / 8.;
    }
    return cos(x) * smoothstep(3.14 * 2.0, 0.0, w);
}

static float3 gc_getColor(float3 p, float resY) {
    p = abs(p);

    p *= 01.25;
    p = 0.5 * p / dot(p, p);

    float t = (0.13) * length(p);
    float3 col = float3(0.3, 0.4, 0.5);
    col += 0.12 * gc_fcos(6.28318 * t * 1.0 + float3(0.0, 0.8, 1.1), resY);
    col += 0.11 * gc_fcos(6.28318 * t * 3.1 + float3(0.3, 0.4, 0.1), resY);
    col += 0.10 * gc_fcos(6.28318 * t * 5.1 + float3(0.1, 0.7, 1.1), resY);
    col += 0.10 * gc_fcos(6.28318 * t * 17.1 + float3(0.2, 0.6, 0.7), resY);
    col += 0.10 * gc_fcos(6.28318 * t * 31.1 + float3(0.1, 0.6, 0.7), resY);
    col += 0.10 * gc_fcos(6.28318 * t * 65.1 + float3(0.0, 0.5, 0.8), resY);
    col += 0.10 * gc_fcos(6.28318 * t * 115.1 + float3(0.1, 0.4, 0.7), resY);
    col += 0.10 * gc_fcos(6.28318 * t * 265.1 + float3(1.1, 1.4, 2.7), resY);
    col = clamp(col, 0., 1.);

    return col;
}

static void gc_calcColor(float3 ro, float3 rd, float d, float len, bool si, float td,
                         thread float4& colx, thread float4& colsi, float resY) {
    float3 pos = (ro + rd * d);
    float a = 1. - smoothstep(len - 0.15 * 0.5, len + 0.00001, length(pos));
    float3 col = gc_getColor(pos, resY);
    colx = float4(col, a);
    colsi = float4(0.);
    if (si) {
        pos = (ro + rd * td);
        float ta = 1. - smoothstep(len - 0.15 * 0.5, len + 0.00001, length(pos));
        col = gc_getColor(pos, resY);
        colsi = float4(col, ta);
    }
}

// xSI is self intersect data, fade to fix dFd on edges
static bool gc_iBilinearPatch(float3 ro, float3 rd, float4 ps, float4 ph, float sz,
                              thread float& t, thread float3& norm,
                              thread bool& si, thread float& tsi, thread float3& normsi,
                              thread float& fade, thread float& fadesi) {
    float3 va = float3(0.0, 0.0, ph.x + ph.w - ph.y - ph.z);
    float3 vb = float3(0.0, ps.w - ps.y, ph.z - ph.x);
    float3 vc = float3(ps.z - ps.x, 0.0, ph.y - ph.x);
    float3 vd = float3(ps.xy, ph.x);
    t = -1.;
    tsi = -1.;
    si = false;
    fade = 1.;
    fadesi = 1.;
    norm = float3(0., 1., 0.); normsi = float3(0., 1., 0.);

    float tmp = 1.0 / (vb.y * vc.x);
    float a = 0.0;
    float b = 0.0;
    float c = 0.0;
    float d = va.z * tmp;
    float e = 0.0;
    float f = 0.0;
    float g = (vc.z * vb.y - vd.y * va.z) * tmp;
    float h = (vb.z * vc.x - va.z * vd.x) * tmp;
    float i = -1.0;
    float j = (vd.x * vd.y * va.z + vd.z * vb.y * vc.x) * tmp - (vd.y * vb.z * vc.x + vd.x * vc.z * vb.y) * tmp;

    float p = dot(float3(a, b, c), rd.xzy * rd.xzy) + dot(float3(d, e, f), rd.xzy * rd.zyx);
    float q = dot(float3(2.0, 2.0, 2.0) * ro.xzy * rd.xyz, float3(a, b, c)) + dot(ro.xzz * rd.zxy, float3(d, d, e)) +
              dot(ro.yyx * rd.zxy, float3(e, f, f)) + dot(float3(g, h, i), rd.xzy);
    float r =
        dot(float3(a, b, c), ro.xzy * ro.xzy) + dot(float3(d, e, f), ro.xzy * ro.zyx) + dot(float3(g, h, i), ro.xzy) + j;

    if (abs(p) < 0.000001) {
        float tt = -r / q;
        if (tt <= 0.)
            return false;
        t = tt;
        // normal
        float3 pos = ro + t * rd;
        if (length(pos) > sz) return false;
        float3 grad =
            float3(2.0) * pos.xzy * float3(a, b, c) + pos.zxz * float3(d, d, e) + pos.yyx * float3(f, e, f) + float3(g, h, i);
        norm = -normalize(grad);
        return true;
    } else {
        float sq = q * q - 4.0 * p * r;
        if (sq < 0.0) {
            return false;
        } else {
            float s = sqrt(sq);
            float t0 = (-q + s) / (2.0 * p);
            float t1 = (-q - s) / (2.0 * p);
            float tt1 = min(t0 < 0.0 ? t1 : t0, t1 < 0.0 ? t0 : t1);
            float tt2 = max(t0 > 0.0 ? t1 : t0, t1 > 0.0 ? t0 : t1);
            float tt0 = tt1;
            if (tt0 <= 0.)
                return false;
            float3 pos = ro + tt0 * rd;
            // black border on end of circle and self intersection with alpha come because dFd
            bool ru = step(sz, length(pos)) > 0.5;
            if (ru) {
                tt0 = tt2;
                pos = ro + tt0 * rd;
            }
            if (tt0 <= 0.)
                return false;
            bool ru2 = step(sz, length(pos)) > 0.5;
            if (ru2)
                return false;

            // self intersect
            if ((tt2 > 0.) && ((!ru)) && !(step(sz, length(ro + tt2 * rd)) > 0.5)) {
                si = true;
                fadesi = s;
                tsi = tt2;
                float3 tpos = ro + tsi * rd;
                // normal
                float3 tgrad = float3(2.0) * tpos.xzy * float3(a, b, c) + tpos.zxz * float3(d, d, e) +
                               tpos.yyx * float3(f, e, f) + float3(g, h, i);
                normsi = -normalize(tgrad);
            }

            fade = s;
            t = tt0;
            // normal
            float3 grad =
                float3(2.0) * pos.xzy * float3(a, b, c) + pos.zxz * float3(d, d, e) + pos.yyx * float3(f, e, f) + float3(g, h, i);
            norm = -normalize(grad);

            return true;
        }
    }
}

static float gc_dot2(float3 v) { return dot(v, v); }

static float gc_segShadow(float3 ro, float3 rd, float3 pa, float sh) {
    float dm = dot(rd.yz, rd.yz);
    float k1 = (ro.x - pa.x) * dm;
    float k2 = (ro.x + pa.x) * dm;
    float2 k5 = (ro.yz + pa.yz) * dm;
    float k3 = dot(ro.yz + pa.yz, rd.yz);
    float2 k4 = (pa.yz + pa.yz) * rd.yz;
    float2 k6 = (pa.yz + pa.yz) * dm;

    for (int i = 0; i < 4; i++) {
        float2 s = float2(float(i & 1), float(i >> 1));
        float t = dot(s, k4) - k3;

        if (t > 0.0)
            sh = min(sh, gc_dot2(float3(clamp(-rd.x * t, k1, k2), k5 - k6 * s) + rd * t) / (t * t));
    }
    return sh;
}

static float gc_boxSoftShadow(float3 ro, float3 rd, float3 rad, float sk) {
    rd += 0.0001 * (1.0 - abs(sign(rd)));
    float3 rdd = rd;
    float3 roo = ro;

    float3 m = 1.0 / rdd;
    float3 n = m * roo;
    float3 k = abs(m) * rad;

    float3 t1 = -n - k;
    float3 t2 = -n + k;

    float tN = max(max(t1.x, t1.y), t1.z);
    float tF = min(min(t2.x, t2.y), t2.z);

    if (tN < tF && tF > 0.0) return 0.0;

    float sh = 1.0;
    sh = gc_segShadow(roo.xyz, rdd.xyz, rad.xyz, sh);
    sh = gc_segShadow(roo.yzx, rdd.yzx, rad.yzx, sh);
    sh = gc_segShadow(roo.zxy, rdd.zxy, rad.zxy, sh);
    sh = clamp(sk * sqrt(sh), 0.0, 1.0);
    return sh * sh * (3.0 - 2.0 * sh);
}

static float gc_box(float3 ro, float3 rd, float3 r, thread float3& nn, bool entering) {
    rd += 0.0001 * (1.0 - abs(sign(rd)));
    float3 dr = 1.0 / rd;
    float3 n = ro * dr;
    float3 k = r * abs(dr);

    float3 pin = -k - n;
    float3 pout = k - n;
    float tin = max(pin.x, max(pin.y, pin.z));
    float tout = min(pout.x, min(pout.y, pout.z));
    nn = float3(0.);
    if (tin > tout)
        return -1.;
    if (entering) {
        nn = -sign(rd) * step(pin.zxy, pin.xyz) * step(pin.yzx, pin.xyz);
    } else {
        nn = sign(rd) * step(pout.xyz, pout.zxy) * step(pout.xyz, pout.yzx);
    }
    return entering ? tin : tout;
}

static float3 gc_bgcol(float3 rd) {
    return mix(float3(0.01), float3(0.336, 0.458, .668), 1. - pow(abs(rd.z + 0.25), 1.3));
}

static float3 gc_background(float3 ro, float3 rd, float3 l_dir, thread float& alpha) {
    float t = (-GC_BOXDIMS.z - ro.z) / rd.z;
    alpha = 0.;
    float3 bgc = gc_bgcol(rd);
    if (t < 0.)
        return bgc;
    float2 uv = ro.xy + t * rd.xy;
    float shad = gc_boxSoftShadow((ro + t * rd), normalize(l_dir + float3(0., 0., 1.)) * gc_rotz(GC_PI * 0.65), GC_BOXDIMS, 1.5);
    float aofac = smoothstep(-0.95, .75, length(abs(uv) - min(abs(uv), float2(0.45))));
    aofac = min(aofac, smoothstep(-0.65, 1., shad));
    float lght = max(dot(normalize(ro + t * rd + float3(0., -0., -5.)), normalize(l_dir - float3(0., 0., 1.)) * gc_rotz(GC_PI * 0.65)), 0.0);
    float3 col = mix(float3(0.4), float3(.71, .772, 0.895), lght * lght * aofac + 0.05) * aofac;
    alpha = 1. - smoothstep(7., 10., length(uv));
    return mix(col * length(col) * 0.8, bgc, smoothstep(7., 10., length(uv)));
}

static float4 gc_insides(float3 ro, float3 rd, float3 nor_c, float3 l_dir, thread float& tout, float resY) {
    tout = -1.;

    float3 col = float3(0.);

    float pi = 3.1415926;

    if (abs(nor_c.x) > 0.5) {
        rd = rd.xzy * nor_c.x;
        ro = ro.xzy * nor_c.x;
    } else if (abs(nor_c.z) > 0.5) {
        l_dir = l_dir * gc_roty(pi);
        rd = rd.yxz * nor_c.z;
        ro = ro.yxz * nor_c.z;
    } else if (abs(nor_c.y) > 0.5) {
        l_dir = l_dir * gc_rotz(-pi * 0.5);
        rd = rd * nor_c.y;
        ro = ro * nor_c.y;
    }

    const float curvature = .5;
    float bil_size = 1.;
    float4 ps = float4(-bil_size, -bil_size, bil_size, bil_size) * curvature;
    float4 ph = float4(-bil_size, bil_size, bil_size, -bil_size) * curvature;

    float4 colx[3] = {float4(0.), float4(0.), float4(0.)};
    float3 dx[3] = {float3(-1.), float3(-1.), float3(-1.)};
    float4 colxsi[3] = {float4(0.), float4(0.), float4(0.)};
    int order[3] = {0, 1, 2};

    for (int i = 0; i < 3; i++) {
        if (abs(nor_c.x) > 0.5) {
            float3x3 m = gc_rotz(-pi * (1. / float(3)));
            ro = ro * m;
            rd = rd * m;
        } else if (abs(nor_c.z) > 0.5) {
            float3x3 m = gc_rotz(pi * (1. / float(3)));
            ro = ro * m;
            rd = rd * m;
        } else if (abs(nor_c.y) > 0.5) {
            float3x3 m = gc_rotx(pi * (1. / float(3)));
            ro = ro * m;
            rd = rd * m;
        }
        float3 normnew;
        float tnew;
        bool si;
        float tsi;
        float3 normsi;
        float fade;
        float fadesi;

        if (gc_iBilinearPatch(ro, rd, ps, ph, bil_size, tnew, normnew, si, tsi, normsi, fade, fadesi)) {
            if (tnew > 0.) {
                float4 tcol, tcolsi;
                gc_calcColor(ro, rd, tnew, bil_size, si, tsi, tcol, tcolsi, resY);
                if (tcol.a > 0.0) {
                    dx[i] = float3(tnew, float(si), tsi);

                    float dif = clamp(dot(normnew, l_dir), 0.0, 1.0);
                    float amb = clamp(0.5 + 0.5 * dot(normnew, l_dir), 0.0, 1.0);

                    {
                        float3 shad = float3(0.32, 0.43, 0.54) * amb + float3(1.0, 0.9, 0.7) * dif;
                        const float3 tcr = float3(1., 0.21, 0.11);
                        float ta = clamp(length(tcol.rgb), 0., 1.);
                        tcol = clamp(tcol * tcol * 2., 0., 1.);
                        float4 tvalx =
                            float4((tcol.rgb * shad * 1.4 + 3. * (tcr * tcol.rgb) * clamp(1. - (amb + dif), 0., 1.)), min(tcol.a, ta));
                        tvalx.rgb = clamp(2. * tvalx.rgb * tvalx.rgb, 0., 1.);
                        tvalx *= (min(fade * 5., 1.));
                        colx[i] = tvalx;
                    }
                    if (si) {
                        dif = clamp(dot(normsi, l_dir), 0.0, 1.0);
                        amb = clamp(0.5 + 0.5 * dot(normsi, l_dir), 0.0, 1.0);
                        {
                            float3 shad = float3(0.32, 0.43, 0.54) * amb + float3(1.0, 0.9, 0.7) * dif;
                            const float3 tcr = float3(1., 0.21, 0.11);
                            float ta = clamp(length(tcolsi.rgb), 0., 1.);
                            tcolsi = clamp(tcolsi * tcolsi * 2., 0., 1.);
                            float4 tvalx =
                                float4(tcolsi.rgb * shad + 3. * (tcr * tcolsi.rgb) * clamp(1. - (amb + dif), 0., 1.), min(tcolsi.a, ta));
                            tvalx.rgb = clamp(2. * tvalx.rgb * tvalx.rgb, 0., 1.);
                            tvalx.rgb *= (min(fadesi * 5., 1.));
                            colxsi[i] = tvalx;
                        }
                    }
                }
            }
        }
    }
    // transparency logic and layers sorting
    float a = 1.;
    float3 tv3; int tvi;
    if (dx[0].x < dx[1].x) { tv3 = dx[0]; dx[0] = dx[1]; dx[1] = tv3; tvi = order[0]; order[0] = order[1]; order[1] = tvi; }
    if (dx[1].x < dx[2].x) { tv3 = dx[1]; dx[1] = dx[2]; dx[2] = tv3; tvi = order[1]; order[1] = order[2]; order[2] = tvi; }
    if (dx[0].x < dx[1].x) { tv3 = dx[0]; dx[0] = dx[1]; dx[1] = tv3; tvi = order[0]; order[0] = order[1]; order[1] = tvi; }

    tout = max(max(dx[0].x, dx[1].x), dx[2].x);

    if (dx[0].y < 0.5) {
        a = colx[order[0]].a;
    }

    // self intersection
    bool rul[3] = {
        ((dx[0].y > 0.5) && (dx[1].x <= 0.)),
        ((dx[1].y > 0.5) && (dx[0].x > dx[1].z)),
        ((dx[2].y > 0.5) && (dx[1].x > dx[2].z))
    };
    for (int k = 0; k < 3; k++) {
        if (rul[k]) {
            float4 tcolxsi = colxsi[order[k]];
            float4 tcolx = colx[order[k]];

            float4 tvalx = mix(tcolxsi, tcolx, tcolx.a);
            colx[order[k]] = tvalx;

            float4 tvalx2 = mix(float4(0.), tvalx, max(tcolx.a, tcolxsi.a));
            colx[order[k]] = tvalx2;
        }
    }

    float a1 = (dx[1].y < 0.5) ? colx[order[1]].a : ((dx[1].z > dx[0].x) ? colx[order[1]].a : 1.);
    float a2 = (dx[2].y < 0.5) ? colx[order[2]].a : ((dx[2].z > dx[1].x) ? colx[order[2]].a : 1.);
    col = mix(mix(colx[order[0]].rgb, colx[order[1]].rgb, a1), colx[order[2]].rgb, a2);
    a = max(max(a, a1), a2);
    return float4(col, a);
}

fragment float4 glasscube_fragment(VertexOut in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    float2 iResolution = uniforms.iResolution;
    float iTime = uniforms.iTime;
    float4 iMouse = uniforms.iMouse;
    float2 fragCoord = in.uv * iResolution;

    float3 l_dir = normalize(float3(0., 1., 0.));
    l_dir = l_dir * gc_rotz(0.5);
    float mouseY = (1.0 - 1.15 * iMouse.y / iResolution.y) * 0.5 * GC_PI;
    if (iMouse.y < 1.)
        mouseY = GC_PI * 0.49 - smoothstep(0., 8.5, gc_mod((iTime + GC_tshift) * 0.33, 25.)) * (1. - smoothstep(14., 24.0, gc_mod((iTime + GC_tshift) * 0.33, 25.))) * 0.55 * GC_PI;
    float mouseX = -2. * GC_PI - 0.25 * (iTime * GC_ROTATION_SPEED + GC_tshift);
    mouseX += -(iMouse.x / iResolution.x) * 2. * GC_PI;

    float3 eye = 4. * float3(cos(mouseX) * cos(mouseY), sin(mouseX) * cos(mouseY), sin(mouseY));
    float3 w = normalize(-eye);
    float3 up = float3(0., 0., 1.);
    float3 u = normalize(cross(w, up));
    float3 v = cross(u, w);

    float4 tot = float4(0.);
    float2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.x;
    float3 rd = normalize(w * GC_FDIST + uv.x * u + uv.y * v);

    float3 ni;
    float t = gc_box(eye, rd, GC_BOXDIMS, ni, true);
    float3 ro = eye + t * rd;
    float2 coords = ro.xy * ni.z / GC_BOXDIMS.xy + ro.yz * ni.x / GC_BOXDIMS.yz + ro.zx * ni.y / GC_BOXDIMS.zx;
    float fadeborders = (1. - smoothstep(0.915, 1.05, abs(coords.x))) * (1. - smoothstep(0.915, 1.05, abs(coords.y)));

    if (t > 0.) {
        float3 col = float3(0.);
        float R0 = (GC_IOR - 1.) / (GC_IOR + 1.);
        R0 *= R0;

        float2 theta = float2(0.);
        float3 n = float3(cos(theta.x) * sin(theta.y), sin(theta.x) * sin(theta.y), cos(theta.y));

        float3 nr = n.zxy * ni.x + n.yzx * ni.y + n.xyz * ni.z;
        float3 rdr = reflect(rd, nr);
        float talpha;
        float3 reflcol = gc_background(ro, rdr, l_dir, talpha);

        float3 rd2 = refract(rd, nr, 1. / GC_IOR);

        float accum = 1.;
        float3 no2 = ni;
        float3 ro_refr = ro;

        float4 colo[2] = {float4(0.), float4(0.)};

        for (int j = 0; j < 2; j++) {
            float tb;
            float2 coords2 = ro_refr.xy * no2.z + ro_refr.yz * no2.x + ro_refr.zx * no2.y;
            float3 eye2 = float3(coords2, -1.);
            float3 rd2trans = rd2.yzx * no2.x + rd2.zxy * no2.y + rd2.xyz * no2.z;

            rd2trans.z = -rd2trans.z;
            float4 internalcol = gc_insides(eye2, rd2trans, no2, l_dir, tb, iResolution.y);
            if (tb > 0.) {
                internalcol.rgb *= accum;
                colo[j] = internalcol;
            }

            if ((tb <= 0.) || (internalcol.a < 1.)) {
                float tout = gc_box(ro_refr, rd2, GC_BOXDIMS, no2, false);
                no2 = n.zyx * no2.x + n.xzy * no2.y + n.yxz * no2.z;
                float3 rout = ro_refr + tout * rd2;
                float3 rdout = refract(rd2, -no2, GC_IOR);
                float fresnel2 = R0 + (1. - R0) * pow(1. - dot(rdout, no2), 1.3);
                rd2 = reflect(rd2, -no2);

                ro_refr = rout;
                ro_refr.z = max(ro_refr.z, -0.999);

                accum *= fresnel2;
            }
        }
        float fresnel = R0 + (1. - R0) * pow(1. - dot(-rd, nr), 5.);
        col = mix(mix(colo[1].rgb * colo[1].a, colo[0].rgb, colo[0].a) * fadeborders, reflcol, pow(fresnel, 1.5));
        col = clamp(col, 0., 1.);

        tot += float4(col, clamp(0.15 * dot(eye, ro), 0., 1.));
    } else {
        float alpha;
        tot += float4(gc_background(eye, rd, l_dir, alpha), 0.15);
    }
    float4 fragColor = tot;
    fragColor.rgb = clamp(fragColor.rgb, 0., 1.);
    return float4(fragColor.rgb, 1.0);
}
