#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Icosphere - Ported from Shadertoy
// https://www.shadertoy.com/view/XcXXzS
// (Comments in the original by Shane.)
// License: CC BY-NC-SA 3.0

#define ICO_PI  3.14159265359
#define ICO_PHI ((1.0 + sqrt(5.0)) / 2.0)

struct IcoState {
    int   hexid;
    float3 hpos;
    float3 point_;
    float3 pt;
    float tcol;
    float bcol;
    float hitbol;
    float hexpos;
    float fparam;
    float iTime;
};

static float glsl_mod(float a, float b) {
    return a - b * floor(a / b);
}
static float2 glsl_mod(float2 a, float b) {
    return a - b * floor(a / b);
}

static float2x2 ico_rot(float a) {
    float s = sin(a), c = cos(a);
    return float2x2(float2(c, s), float2(-s, c));
}

static float3 ico_path(float t) {
    return float3(sin(t * 0.3 + cos(t * 0.2) * 0.5) * 4.0, cos(t * 0.2) * 3.0, t);
}

static float ico_hexagon(float2 p, float r) {
    const float3 k = float3(-0.866025404, 0.5, 0.577350269);
    p = abs(p);
    p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
    p -= float2(clamp(p.x, -k.z * r, k.z * r), r);
    return length(p) * sign(p.y);
}

static float ico_hex(float2 p) {
    p.x *= 0.57735 * 2.0;
    p.y += glsl_mod(floor(p.x), 2.0) * 0.5;
    p = abs(glsl_mod(p, 1.0) - 0.5);
    return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}

static float3x3 ico_lookat(float3 dir) {
    float3 up = float3(0.0, 1.0, 0.0);
    float3 rt = normalize(cross(dir, up));
    return float3x3(rt, cross(rt, dir), dir);
}

static float ico_sphereLineAB(float3 p, float3 a, float3 b, float rad) {
    p = normalize(p);
    return dot(p, cross(a, b)) / length(a - b);
}

static float3 ico_erot(float3 p, float3 ax, float ro) {
    return mix(dot(ax, p) * ax, p, cos(ro)) + sin(ro) * cross(ax, p);
}

static void ico_icosahedronVerts(float3 p,
                                 thread float3 &face,
                                 thread float3 &a,
                                 thread float3 &b,
                                 thread float3 &c) {
    float3 V = float3(ICO_PHI, 1.0, 0.0);
    float3 ap = abs(p), v = V;
    if (dot(ap, V.yzx - v) > 0.0) v = V.yzx;
    if (dot(ap, V.zxy - v) > 0.0) v = V.zxy;
    a = normalize(v) * sign(p);

    v = V.xxx;
    V = float3(V.zy, V.x + V.y);
    if (dot(ap, V - v) > 0.0) v = V;
    if (dot(ap, V.yzx - v) > 0.0) v = V.yzx;
    if (dot(ap, V.zxy - v) > 0.0) v = V.zxy;
    face = normalize(v) * sign(p);

    float r = ICO_PI * 2.0 / 3.0;
    b = ico_erot(a, face, -r);
    c = ico_erot(a, face,  r);
}

static float ico_de(float3 p, thread IcoState &S) {
    S.pt = float3(p.xy - ico_path(p.z).xy, p.z);
    float h = abs(ico_hexagon(S.pt.xy, 3.0 + S.fparam));
    S.hexpos = ico_hex(S.pt.yz);
    S.tcol = smoothstep(0.0, 0.15, S.hexpos);
    h -= S.tcol * 0.1;
    float3 pp = p - S.hpos;
    pp = ico_lookat(S.point_) * pp;
    pp.y -= abs(sin(S.iTime)) * 3.0 + (S.fparam - (2.0 - S.fparam));
    pp.yz = pp.yz * ico_rot(-S.iTime);

    float bola = length(pp) - 1.0;

    if (length(pp) < 1.5) {
        float3 face;
        float3 v0, v1, v2;
        ico_icosahedronVerts(pp, face, v0, v1, v2);
        float3 v[3] = { v0, v1, v2 };

        float3 mid[6];
        for (int i = 0; i < 3; i++) {
            mid[i * 2]     = mix(v[i], v[(i + 1) % 3], 1.0 / 3.0);
            mid[i * 2 + 1] = mix(v[i], v[(i + 1) % 3], 2.0 / 3.0);
        }
        float poly = -1e5;
        for (int i = 0; i < 6; i++) {
            poly = max(poly, ico_sphereLineAB(pp, mid[i], mid[(i + 1) % 6], 1.0));
        }
        S.bcol = smoothstep(0.0, 0.05, abs(poly));
        bola += S.bcol * 0.1;
    }

    float d = min(h, bola);
    if (d == bola) {
        S.tcol = 1.0;
        S.hitbol = 1.0;
    } else {
        S.hitbol = 0.0;
        S.bcol = 1.0;
    }
    return d * 0.5;
}

static float3 ico_normal(float3 p, thread IcoState &S) {
    float2 e = float2(0.0, 0.005);
    float d0 = ico_de(p,                       S);
    float dx = ico_de(p + float3(e.y, e.x, e.x), S);
    float dy = ico_de(p + float3(e.x, e.y, e.x), S);
    float dz = ico_de(p + float3(e.x, e.x, e.y), S);
    return normalize(float3(dx, dy, dz) - d0);
}

static float3 ico_march(float3 from, float3 dir, thread IcoState &S) {
    float3 odir = dir;
    float3 p = from, col = float3(0.0);
    float d = 0.0, td = 0.0;
    float3 g = float3(0.0);
    for (int i = 0; i < 200; i++) {
        d = ico_de(p, S);
        if (d < 0.001 || td > 200.0) break;
        p += dir * d;
        td += d;
        g += 0.1 / (0.1 + d) * S.hitbol * abs(normalize(S.point_));
    }
    float hp = S.hexpos * (1.0 - S.hitbol);
    p -= dir * 0.01;
    float3 n = ico_normal(p, S);
    if (d < 0.001) {
        col = pow(max(0.0, dot(-dir, n)), 2.0) * float3(0.6, 0.7, 0.8) * S.tcol * S.bcol;
    }
    col += float(S.hexid);
    float3 pr = S.pt;
    dir = reflect(dir, n);
    td = 0.0;
    for (int i = 0; i < 200; i++) {
        d = ico_de(p, S);
        if (d < 0.001 || td > 200.0) break;
        p += dir * d;
        td += d;
        g += 0.1 / (0.1 + d) * abs(normalize(S.point_));
    }
    float zz = p.z;
    if (d < 0.001) {
        float3 refcol = pow(max(0.0, dot(-odir, n)), 2.0) * float3(0.6, 0.7, 0.8) * S.tcol * S.bcol;
        p = pr;
        p = abs(0.5 - fract(p * 0.1));
        float m = 100.0;
        for (int i = 0; i < 10; i++) {
            p = abs(p) / dot(p, p) - 0.8;
            m = min(m, length(p));
        }
        col = mix(col, refcol, m) - m * 0.3;
        col += step(0.3, hp) * step(0.9, fract(pr.z * 0.05 + S.iTime * 0.5 + hp * 0.1)) * 0.7;
        col += step(0.3, S.hexpos) * step(0.9, fract(zz * 0.05 + S.iTime + S.hexpos * 0.1)) * 0.3;
    }
    col += g * 0.03;
    col.rb = col.rb * ico_rot(odir.y * 0.5);
    return col;
}

fragment float4 icosphere_fragment(VertexOut in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    float2 iResolution = uniforms.iResolution;
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * iResolution;

    IcoState S;
    S.hexid = 0;
    S.hpos = float3(0.0);
    S.point_ = float3(0.0, 0.0, 1.0);
    S.pt = float3(0.0);
    S.tcol = 0.0;
    S.bcol = 1.0;
    S.hitbol = 0.0;
    S.hexpos = 0.0;
    S.fparam = 0.0;
    S.iTime = iTime;

    float2 uv = fragCoord / iResolution - 0.5;
    uv.x *= iResolution.x / iResolution.y;
    float t = iTime * 2.0;
    float3 from = ico_path(t);
    if (glsl_mod(iTime - 10.0, 20.0) > 10.0) {
        from = ico_path(floor(t / 20.0) * 20.0 + 10.0);
        from.x += 2.0;
    }
    S.hpos = ico_path(t + 3.0);
    float3 adv = ico_path(t + 2.0);
    float3 dir = normalize(float3(uv, 0.7));
    float3 dd = normalize(adv - from);
    S.point_ = normalize(adv - S.hpos);
    S.point_.xz = S.point_.xz * ico_rot(sin(iTime) * 0.2);
    dir = ico_lookat(dd) * dir;
    float3 col = ico_march(from, dir, S);
    col *= float3(1.0, 0.9, 0.8);
    return float4(col, 1.0);
}
