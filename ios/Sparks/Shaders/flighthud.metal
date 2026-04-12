#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Flight HUD - Ported from Shadertoy
// https://www.shadertoy.com/view/Dl2XRz
// Original Author: kishimisu
// License: CC BY-NC-SA 3.0

static float fh_mod(float x, float y) { return x - y * floor(x / y); }
static float2 fh_mod(float2 x, float2 y) { return x - y * floor(x / y); }

static float2x2 Rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, -s), float2(s, c));
}
static float2x2 SkewX(float a) {
    return float2x2(float2(1.0, tan(a)), float2(0.0, 1.0));
}
static float B(float2 p, float2 s) {
    return max(abs(p.x) - s.x, abs(p.y) - s.y);
}
static float Tri(float2 p, float2 s, float a) {
    return max(-dot(p, float2(cos(-a), sin(-a))),
           max(dot(p, float2(cos(a), sin(a))),
           max(abs(p.x) - s.x, abs(p.y) - s.y)));
}
static float2 DF(float2 a, float b) {
    float phi = atan2(a.y, a.x);
    float k = 6.28 / (b * 8.0);
    float kk = 6.28 / ((b * 8.0) * 0.5);
    float x = fh_mod(phi + k, kk) + (b - 1.0) * k;
    return length(a) * cos(x + float2(0.0, 11.0));
}

static float fh_rand(float2 co) {
    return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
}

static float dSlopeLines(float2 p, float iTime) {
    float lineSize = 80.0;
    float d = tan((mix(p.x, p.y, 0.5) + (-iTime * 5.0 / lineSize)) * lineSize) * lineSize;
    return d;
}

static float segBase(float2 p) {
    float2 prevP = p;
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;
    p = fh_mod(p, float2(0.05)) - 0.025;
    float thickness = 0.005;
    float gridMask = min(abs(p.x) - thickness, abs(p.y) - thickness);
    p = prevP;
    float d = B(p, float2(w * 0.5, h * 0.5));
    float a = radians(40.0);
    p.x = abs(p.x) - 0.1;
    p.y = abs(p.y) - 0.05;
    float d2 = dot(p, float2(cos(a), sin(a)));
    return d;
}

static float seg0(float2 p) { float d = segBase(p); float size = 0.03; float mask = B(p, float2(size, size * 2.7)); return max(-mask, d); }
static float seg1(float2 p) { float2 prevP = p; float d = segBase(p); float size = 0.03; p.x += size; p.y += size; float mask = B(p, float2(size * 2.0, size * 3.7)); d = max(-mask, d); p = prevP; p.x += size * 1.9; p.y -= size * 3.2; mask = B(p, float2(size, size + 0.01)); return max(-mask, d); }
static float seg2(float2 p) { float2 prevP = p; float d = segBase(p); float size = 0.03; p.x += size; p.y -= 0.05; float mask = B(p, float2(size * 2.0, size)); d = max(-mask, d); p = prevP; p.x -= size; p.y += 0.05; mask = B(p, float2(size * 2.0, size)); return max(-mask, d); }
static float seg3(float2 p) { float2 prevP = p; float d = segBase(p); float size = 0.03; p.y = abs(p.y); p.x += size; p.y -= 0.05; float mask = B(p, float2(size * 2.0, size)); d = max(-mask, d); p = prevP; p.x += 0.06; mask = B(p, float2(size, size + 0.01)); return max(-mask, d); }
static float seg4(float2 p) { float2 prevP = p; float d = segBase(p); float size = 0.03; p.x += size; p.y += 0.08; float mask = B(p, float2(size * 2.0, size * 2.0)); d = max(-mask, d); p = prevP; p.y -= 0.08; mask = B(p, float2(size, size * 2.0)); return max(-mask, d); }
static float seg5(float2 p) { float2 prevP = p; float d = segBase(p); float size = 0.03; p.x -= size; p.y -= 0.05; float mask = B(p, float2(size * 2.0, size)); d = max(-mask, d); p = prevP; p.x += size; p.y += 0.05; mask = B(p, float2(size * 2.0, size)); return max(-mask, d); }
static float seg6(float2 p) { float2 prevP = p; float d = segBase(p); float size = 0.03; p.x -= size; p.y -= 0.05; float mask = B(p, float2(size * 2.0, size)); d = max(-mask, d); p = prevP; p.y += 0.05; mask = B(p, float2(size, size)); return max(-mask, d); }
static float seg7(float2 p) { float d = segBase(p); float size = 0.03; p.x += size; p.y += size; float mask = B(p, float2(size * 2.0, size * 3.7)); return max(-mask, d); }
static float seg8(float2 p) { float d = segBase(p); float size = 0.03; p.y = abs(p.y); p.y -= 0.05; float mask = B(p, float2(size, size)); return max(-mask, d); }
static float seg9(float2 p) { float2 prevP = p; float d = segBase(p); float size = 0.03; p.y -= 0.05; float mask = B(p, float2(size, size)); d = max(-mask, d); p = prevP; p.x += size; p.y += 0.05; mask = B(p, float2(size * 2.0, size)); return max(-mask, d); }

static float checkChar(int targetChar, int ch) {
    return 1.0 - abs(sign(float(targetChar) - float(ch)));
}

static float drawFont(float2 p, int ch) {
    p = p * SkewX(-0.4);
    float d = seg0(p) * checkChar(0, ch);
    d += seg1(p) * checkChar(1, ch);
    d += seg2(p) * checkChar(2, ch);
    d += seg3(p) * checkChar(3, ch);
    d += seg4(p) * checkChar(4, ch);
    d += seg5(p) * checkChar(5, ch);
    d += seg6(p) * checkChar(6, ch);
    d += seg7(p) * checkChar(7, ch);
    d += seg8(p) * checkChar(8, ch);
    d += seg9(p) * checkChar(9, ch);
    return d;
}

static float3 paperPlane(float2 p, float3 col, float aa) {
    p.y -= 0.1; p *= 1.5;
    float2 prevP = p;
    p *= float2(1.0, 0.4);
    float d = Tri(p, float2(0.1), radians(45.0));
    p = prevP; p.y += 0.23; p *= float2(2.0);
    float d2 = Tri(p, float2(0.1), radians(45.0));
    d = max(-d2, d);
    col = mix(col, float3(0.9), smoothstep(aa, 0.0, d));
    p = prevP; p *= float2(6.0, 0.4);
    d = Tri(p, float2(0.1), radians(45.0));
    p = prevP; p.y += 0.23; p *= float2(2.0);
    d2 = Tri(p, float2(0.1), radians(45.0));
    d = max(-d2, d);
    col = mix(col, float3(0.75), smoothstep(aa, 0.0, d));
    p = prevP; p *= float2(1.0, 0.4);
    d = Tri(p, float2(0.1), radians(45.0));
    p = prevP; p.y += 0.16; p *= float2(0.9, 1.0);
    d2 = Tri(p, float2(0.1), radians(45.0));
    d = max(-d2, d);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    p = prevP; p *= float2(11.0, 0.59);
    d = Tri(p, float2(0.1), radians(45.0));
    p = prevP; p.y += 0.23; p *= float2(2.0);
    d2 = Tri(p, float2(0.1), radians(45.0));
    d = max(-d2, d);
    col = mix(col, float3(0.85), smoothstep(aa, 0.0, d));
    p = prevP; p.y += 0.18; p.x *= 1.2;
    d = Tri(p, float2(0.01), radians(-45.0));
    col = mix(col, float3(0.85), smoothstep(aa, 0.0, d));
    p = prevP;
    d = B(p - float2(0.0, -0.12), float2(0.004, 0.11));
    col = mix(col, float3(0.95), smoothstep(aa, -0.01, d));
    return col;
}

static float3 radar(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    p = p * Rot(radians(25.0 * iTime));
    float a = atan2(p.x, p.y);
    float d = length(p) - 0.4;
    col = mix(col, float3(1.0) * a * 0.01, smoothstep(aa, 0.0, d));
    d = length(p) - 0.4;
    a = radians(1.0);
    p.x = abs(p.x);
    d = max(dot(p, float2(cos(a), sin(a))), d);
    col = mix(col, float3(0.2), smoothstep(aa, 0.0, d));
    return col;
}

static float3 grids(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    p.y += iTime * 0.1;
    p = fh_mod(p, float2(0.05)) - 0.025;
    float thickness = 0.00001;
    float d = min(abs(p.x) - thickness, abs(p.y) - thickness);
    p = prevP;
    float c = length(p) - 0.4;
    d = max(c, d);
    col = mix(col, float3(0.2), smoothstep(aa, 0.0, d));
    p = p * Rot(radians(-20.0 * iTime));
    p = DF(p, 40.0); p -= float2(0.28);
    p = p * Rot(radians(45.0));
    d = B(p, float2(0.001, 0.01));
    p = prevP;
    p = p * Rot(radians(-20.0 * iTime));
    p = DF(p, 10.0); p -= float2(0.27);
    p = p * Rot(radians(45.0));
    float d2 = B(p, float2(0.001, 0.02));
    d = min(d, d2);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    int num = 8;
    d = 10.0;
    for (int i = 0; i < num; i++) {
        float r = radians(135.0 + (360.0 / float(num)) * float(i));
        float dist = 3.7;
        float x = cos(r) * dist;
        float y = sin(r) * dist;
        p = prevP; p *= 8.0;
        d2 = drawFont(p - float2(x, y), (num - 1) - int(fh_mod(float(i), 10.0)));
        d = min(d, d2);
    }
    col = mix(col, float3(0.6), smoothstep(aa, 0.0, d));
    p = prevP;
    p = p * Rot(radians(20.0 * iTime));
    p = DF(p, 30.0); p -= float2(0.3);
    p = p * Rot(radians(45.0));
    d = B(p, float2(0.001, 0.008));
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    return col;
}

static float3 objects(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    p.y += iTime * 0.1;
    p *= 5.0;
    float2 id = floor(p);
    float2 gr = fract(p) - 0.5;
    float2 prevGr = gr;
    float r = fh_rand(id);
    float d = 10.0;
    float bd = 10.0;
    if (r < 0.2) {
        gr.x *= 1.7;
        d = Tri(gr - float2(0.0, -0.09), float2(0.15), radians(-45.0));
        gr = prevGr;
        float d2 = abs(length(gr) - 0.16) - 0.02;
        float dir = (r >= 0.1) ? -1.0 : 1.0;
        gr = gr * Rot(radians(iTime * 30.0 * dir));
        d2 = max(-(abs(gr.x) - 0.05), d2);
        d = min(d, d2);
    } else if (r >= 0.2 && r < 0.35) {
        bd = B(gr, float2(0.2, 0.11));
        gr.x = abs(gr.x) - 0.2;
        bd = min(B(gr, float2(0.07, 0.2)), bd);
        gr = prevGr;
        bd = max(dSlopeLines(gr, iTime), bd);
    }
    p = prevP;
    float c = length(p) - 0.4;
    d = max(c, d);
    bd = max(c, bd);
    col = mix(col, float3(0.5), smoothstep(aa, 0.0, d));
    col = mix(col, float3(0.4), smoothstep(aa, 0.0, bd));
    return col;
}

static float3 graph0(float2 p, float3 col, float iTime, float aa) {
    p *= 1.3; float2 prevP = p;
    p.x += iTime * 0.2; p *= 120.0;
    float2 id = floor(p); float2 gr = fract(p) - 0.5;
    float r = fh_rand(float2(id.x, id.x)) * 10.0;
    gr.y = p.y;
    float d = B(gr, float2(0.35, 0.3 + r));
    p = prevP;
    float d2 = B(p, float2(0.25, 0.12));
    d = max(d2, d);
    d2 = abs(d2) - 0.0005;
    d2 = max(-min(abs(p.x) - 0.23, abs(p.y) - 0.1), d2);
    d = min(d, d2);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    return col;
}

static float3 graph1(float2 p, float3 col, float iTime, float aa) {
    p *= 1.3; float2 prevP = p;
    p.y += 0.11; p.x += -iTime * 0.1; p *= 50.0;
    float2 id = floor(p); float2 gr = fract(p) - 0.5;
    float r = fh_rand(float2(id.x, id.x)) * 10.0;
    gr.y = p.y;
    float d = B(gr, float2(0.4, (0.5 + abs(sin(0.3 + 0.2 * iTime * r)) * r)));
    p = prevP;
    float d2 = B(p, float2(0.25, 0.12));
    d = max(d2, d); p.y += 0.11; d = max(-p.y, d);
    p = prevP;
    d2 = B(p, float2(0.25, 0.12));
    d2 = abs(d2) - 0.0005;
    d2 = max(-min(abs(p.x) - 0.23, abs(p.y) - 0.1), d2);
    d = min(d, d2);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    return col;
}

static float3 graph2(float2 p, float3 col, float iTime, float aa) {
    p *= 1.3; float2 prevP = p;
    p *= 15.0; p.x += iTime * 1.5;
    float d = sin(p.y * 0.6) * 0.3 + cos(p.x * 1.5) * 0.2;
    d = abs(d) - 0.005;
    p = prevP; p *= 15.0; p.x += -iTime * 1.2;
    float d3 = sin(-p.y * 0.7) * 0.3 + cos(-p.x * 1.2) * 0.2;
    d3 = abs(d3) - 0.005;
    d = min(d, d3);
    p = prevP;
    float d2 = B(p, float2(0.25, 0.12));
    d = max(d2, d);
    d2 = abs(d2) - 0.0005;
    d2 = max(-min(abs(p.x) - 0.23, abs(p.y) - 0.1), d2);
    d = min(d, d2);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    d = max(abs(p.x) - 0.25, abs(p.y) - 0.0001);
    col = mix(col, float3(0.5), smoothstep(aa, 0.0, d));
    d = max(abs(p.x) - 0.0001, abs(p.y) - 0.15);
    p.x += iTime * 0.05;
    p.x = fh_mod(p.x, 0.02) - 0.01;
    d2 = B(p, float2(0.001, 0.01));
    d = min(d, d2);
    p = prevP; d = max(abs(p.x) - 0.25, d);
    p = prevP; p.y -= iTime * 0.05;
    p.y = fh_mod(p.y, 0.02) - 0.01;
    d2 = B(p, float2(0.01, 0.001));
    d = min(d, d2);
    p = prevP; d = max(abs(p.y) - 0.11, d);
    col = mix(col, float3(0.5), smoothstep(aa, 0.0, d));
    return col;
}

static float3 graph3(float2 p, float3 col, float iTime, float aa) {
    p *= 1.3; float2 prevP = p;
    p.x += iTime * 0.2;
    p = fh_mod(p, float2(0.03)) - 0.015;
    float thickness = 0.0001;
    float d = min(abs(p.x) - thickness, abs(p.y) - thickness);
    p = prevP;
    d = max(B(p, float2(0.24, 0.11)), d);
    col = mix(col, float3(0.3), smoothstep(aa, 0.0, d));
    p.x += iTime * 0.2; p *= 12.0;
    float2 id = floor(p); float2 gr = fract(p) - 0.5;
    float r = fh_rand(id);
    d = length(gr + r * 0.5) - 0.08;
    if (r > 0.5) d = 10.0;
    p = prevP;
    float d2 = B(p, float2(0.25, 0.12));
    d = max(B(p, float2(0.25, 0.08)), d);
    d2 = abs(d2) - 0.0005;
    d2 = max(-min(abs(p.x) - 0.23, abs(p.y) - 0.1), d2);
    d = min(d, d2);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    return col;
}

static float3 smallCircleUI(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    p = p * Rot(radians(20.0 * iTime));
    p = DF(p, 15.0); p -= float2(0.09); p = p * Rot(radians(45.0));
    float d = B(p, float2(0.001, 0.01));
    p = prevP;
    p = p * Rot(radians(20.0 * iTime));
    p = DF(p, 5.0); p -= float2(0.1); p = p * Rot(radians(45.0));
    float d2 = B(p, float2(0.001, 0.012));
    d = min(d, d2);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    p = prevP; p.y *= -1.0;
    p = p * Rot(radians(25.0 * iTime));
    float a = atan2(p.x, p.y);
    d = length(p) - 0.1;
    col = mix(col, float3(1.0) * a * 0.05, smoothstep(aa, 0.0, d));
    d = length(p) - 0.1;
    a = radians(1.0); p.x = abs(p.x);
    d = max(dot(p, float2(cos(a), sin(a))), d);
    p = prevP; p.y *= -1.0;
    p = p * Rot(radians(25.0 * iTime));
    d = max(p.y, d);
    col = mix(col, float3(0.2), smoothstep(aa, 0.0, d));
    p = prevP;
    d2 = abs(length(p) - 0.1) - 0.0001; d = min(d, d2);
    d2 = abs(length(p) - 0.07) - 0.0001; d = min(d, d2);
    d2 = abs(length(p) - 0.04) - 0.0001; d = min(d, d2);
    d2 = max(length(p) - 0.1, min(abs(p.x) - 0.0001, abs(p.y) - 0.0001));
    d = min(d, d2);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    return col;
}

static float3 smallCircleUI2(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    p = p * Rot(radians(-25.0 * iTime));
    p = DF(p, 15.0); p -= float2(0.09); p = p * Rot(radians(45.0));
    float d = B(p, float2(0.001, 0.01));
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    p = prevP; p *= 3.5;
    d = drawFont(p - float2(-0.1, 0.0), int(fh_mod(iTime * 5.0, 10.0)));
    float d2 = drawFont(p - float2(0.1, 0.0), int(fh_mod(iTime * 10.0, 10.0)));
    d = min(d, d2);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    p = prevP;
    d = abs(length(p) - 0.1) - 0.01;
    col = mix(col, float3(0.2), smoothstep(aa, 0.0, d));
    d = abs(length(p) - 0.1) - 0.01;
    p = p * Rot(radians(20.0 * iTime));
    float a = radians(60.0); p.x = abs(p.x);
    d = max(dot(p, float2(cos(a), sin(a))), d);
    col = mix(col, float3(0.7), smoothstep(aa, 0.0, d));
    p = prevP;
    p = p * Rot(radians(sin(iTime) * 160.0));
    d = abs(length(p) - 0.152) - 0.003;
    d = max(abs(p.y) - 0.08, d);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    return col;
}

static float3 smallCircleUI3(float2 p, float3 col, float dir, float iTime, float aa) {
    float2 prevP = p;
    float d = length(p) - 0.007;
    float d2 = abs(length(p) - 0.03) - 0.0005;
    d = min(d, d2);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));
    p = p * Rot(radians(22.0 * iTime * dir));
    float a = radians(30.0);
    d2 = abs(length(p) - 0.03) - 0.016;
    p.x = abs(p.x);
    d2 = max(dot(p, float2(cos(a), sin(a))), d2);
    p = prevP;
    p = p * Rot(radians(22.0 * iTime * dir));
    p.x = abs(p.x);
    p = p * Rot(radians(-120.0));
    float d3 = abs(length(p) - 0.03) - 0.016;
    p.x = abs(p.x);
    float d4 = max(dot(p, float2(cos(a), sin(a))), d3);
    d2 = min(d2, d4);
    col = mix(col, float3(0.3), smoothstep(aa, 0.0, d2));
    return col;
}

static float3 smallUI0(float2 p, float3 col, float aa) {
    float d = B(p, float2(0.001, 0.03));
    float d2 = B(p, float2(0.03, 0.001));
    d = min(d, d2);
    d = max(-B(p, float2(0.01)), d);
    col = mix(col, float3(0.5), smoothstep(aa, 0.0, d));
    return col;
}

static float3 smallUI1(float2 p, float3 col, float aa) {
    float d = abs(length(p - float2(0, -0.015)) - 0.01) - 0.0005;
    p.x = abs(p.x);
    float d2 = abs(length(p - float2(0.017, 0.015)) - 0.01) - 0.0005;
    d = min(d, d2);
    col = mix(col, float3(0.5), smoothstep(aa, 0.0, d));
    return col;
}

fragment float4 flighthud_fragment(VertexOut in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 iRes = uniforms.iResolution;
    float2 fragCoord = in.uv * iRes;
    float2 p = (fragCoord - 0.5 * iRes) / iRes.y;
    float2 prevP = p;
    float aa = 1.0 / min(iRes.y, iRes.x);

    float3 col = float3(0.0);

    col = radar(p, col, iTime, aa);
    col = grids(p, col, iTime, aa);
    col = objects(p, col, iTime, aa);
    col = paperPlane(p, col, aa);

    col = graph0(p - float2(-0.6, 0.35), col, iTime, aa);
    col = graph1(p - float2(-0.6, -0.35), col, iTime, aa);
    col = graph2(p - float2(0.6, 0.35), col, iTime, aa);
    col = graph3(p - float2(0.6, -0.35), col, iTime, aa);

    col = smallCircleUI(p - float2(-0.64, 0.0), col, iTime, aa);
    col = smallCircleUI2(p - float2(0.64, 0.0), col, iTime, aa);

    p = abs(p);
    col = smallCircleUI3(p - float2(0.48, 0.18), col, 1.0, iTime, aa);

    p = prevP; p = abs(p);
    col = smallUI0(p - float2(0.32, 0.41), col, aa);

    p = prevP; p = abs(p);
    col = smallUI1(p - float2(0.76, 0.18), col, aa);

    return float4(sqrt(col), 1.0);
}
