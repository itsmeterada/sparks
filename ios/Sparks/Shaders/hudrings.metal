#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// HUD Rings - Ported from Shadertoy
// https://www.shadertoy.com/view/Dsf3WH
// Original Author: kishimisu
// License: CC BY-NC-SA 3.0

#define MAX_STEPS 64

// GLSL-compatible mod (matches floor-based definition for negative values)
static float hr_mod(float x, float y) { return x - y * floor(x / y); }
static float2 hr_mod(float2 x, float2 y) { return x - y * floor(x / y); }

// MSL does not provide GLSL's radians(); supply a scalar version for the port.
static float radians(float deg) { return deg * 0.01745329251994329577f; }

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
    float r1 = -dot(p, float2(cos(-a), sin(-a)));
    float r2 =  dot(p, float2(cos( a), sin( a)));
    float r3 = max(abs(p.x) - s.x, abs(p.y) - s.y);
    return max(r1, max(r2, r3));
}

static float2 DF(float2 a, float b) {
    float phi = atan2(a.y, a.x);
    float k = 6.28 / (b * 8.0);
    float kk = 6.28 / ((b * 8.0) * 0.5);
    float x = hr_mod(phi + k, kk) + (b - 1.0) * k;
    return length(a) * cos(x + float2(0.0, 11.0));
}

#define seg_0 0
#define seg_1 1
#define seg_2 2
#define seg_3 3
#define seg_4 4
#define seg_5 5
#define seg_6 6
#define seg_7 7
#define seg_8 8
#define seg_9 9
#define seg_DP 39

static float Hash21(float2 p) {
    p = fract(p * float2(234.56, 789.34));
    p += dot(p, p + 34.56);
    return fract(p.x + p.y);
}

static float cubicInOut(float t) {
    return t < 0.5
        ? 4.0 * t * t * t
        : 0.5 * pow(2.0 * t - 2.0, 3.0) + 1.0;
}

static float getTime(float t, float duration) {
    return clamp(t, 0.0, duration) / duration;
}

static float segBase(float2 p) {
    float2 prevP = p;
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;

    p = hr_mod(p, float2(0.05)) - 0.025;
    float thickness = 0.005;
    float gridMask = min(abs(p.x) - thickness, abs(p.y) - thickness);

    p = prevP;
    float d = B(p, float2(w * 0.5, h * 0.5));
    float a = radians(45.0);
    p.x = abs(p.x) - 0.1;
    p.y = abs(p.y) - 0.05;
    float d2 = dot(p, float2(cos(a), sin(a)));
    d = max(d2, d);
    d = max(-gridMask, d);
    return d;
}

static float seg0(float2 p) {
    float d = segBase(p);
    float size = 0.03;
    float mask = B(p, float2(size, size * 2.7));
    return max(-mask, d);
}

static float seg1(float2 p) {
    float2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.x += size;
    p.y += size;
    float mask = B(p, float2(size * 2.0, size * 3.7));
    d = max(-mask, d);

    p = prevP;
    p.x += size * 1.8;
    p.y -= size * 3.5;
    mask = B(p, float2(size));
    return max(-mask, d);
}

static float seg2(float2 p) {
    float2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.x += size;
    p.y -= 0.05;
    float mask = B(p, float2(size * 2.0, size));
    d = max(-mask, d);

    p = prevP;
    p.x -= size;
    p.y += 0.05;
    mask = B(p, float2(size * 2.0, size));
    return max(-mask, d);
}

static float seg3(float2 p) {
    float2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.y = abs(p.y);
    p.x += size;
    p.y -= 0.05;
    float mask = B(p, float2(size * 2.0, size));
    d = max(-mask, d);

    p = prevP;
    p.x += 0.05;
    mask = B(p, float2(size, size));
    return max(-mask, d);
}

static float seg4(float2 p) {
    float2 prevP = p;
    float d = segBase(p);
    float size = 0.03;

    p.x += size;
    p.y += 0.08;
    float mask = B(p, float2(size * 2.0, size * 2.0));
    d = max(-mask, d);

    p = prevP;
    p.y -= 0.08;
    mask = B(p, float2(size, size * 2.0));
    return max(-mask, d);
}

static float seg5(float2 p) {
    float2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.x -= size;
    p.y -= 0.05;
    float mask = B(p, float2(size * 2.0, size));
    d = max(-mask, d);

    p = prevP;
    p.x += size;
    p.y += 0.05;
    mask = B(p, float2(size * 2.0, size));
    return max(-mask, d);
}

static float seg6(float2 p) {
    float2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.x -= size;
    p.y -= 0.05;
    float mask = B(p, float2(size * 2.0, size));
    d = max(-mask, d);

    p = prevP;
    p.y += 0.05;
    mask = B(p, float2(size, size));
    return max(-mask, d);
}

static float seg7(float2 p) {
    float d = segBase(p);
    float size = 0.03;
    p.x += size;
    p.y += size;
    float mask = B(p, float2(size * 2.0, size * 3.7));
    return max(-mask, d);
}

static float seg8(float2 p) {
    float d = segBase(p);
    float size = 0.03;
    p.y = abs(p.y);
    p.y -= 0.05;
    float mask = B(p, float2(size, size));
    return max(-mask, d);
}

static float seg9(float2 p) {
    float2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.y -= 0.05;
    float mask = B(p, float2(size, size));
    d = max(-mask, d);

    p = prevP;
    p.x += size;
    p.y += 0.05;
    mask = B(p, float2(size * 2.0, size));
    return max(-mask, d);
}

static float segDecimalPoint(float2 p) {
    float d = segBase(p);
    float size = 0.028;
    p.y += 0.1;
    float mask = B(p, float2(size, size));
    return max(mask, d);
}

static float drawFont(float2 p, int ch) {
    p *= 2.0;
    float d = 10.0;
    if (ch == seg_0) d = seg0(p);
    else if (ch == seg_1) d = seg1(p);
    else if (ch == seg_2) d = seg2(p);
    else if (ch == seg_3) d = seg3(p);
    else if (ch == seg_4) d = seg4(p);
    else if (ch == seg_5) d = seg5(p);
    else if (ch == seg_6) d = seg6(p);
    else if (ch == seg_7) d = seg7(p);
    else if (ch == seg_8) d = seg8(p);
    else if (ch == seg_9) d = seg9(p);
    else if (ch == seg_DP) d = segDecimalPoint(p);
    return d;
}

static float ring0(float2 p, float iTime) {
    float2 prevP = p;
    p = p * Rot(radians(-iTime * 30.0 + 50.0));
    p = DF(p, 16.0);
    p -= float2(0.35);
    float d = B(p * Rot(radians(45.0)), float2(0.005, 0.03));
    p = prevP;

    p = p * Rot(radians(-iTime * 30.0 + 50.0));
    float deg = 165.0;
    float a = radians(deg);
    d = max(dot(p, float2(cos(a), sin(a))), d);
    a = radians(-deg);
    d = max(dot(p, float2(cos(a), sin(a))), d);

    p = prevP;
    p = p * Rot(radians(iTime * 30.0 + 30.0));
    float d2 = abs(length(p) - 0.55) - 0.015;
    d2 = max(-(abs(p.x) - 0.4), d2);
    d = min(d, d2);
    p = prevP;
    d2 = abs(length(p) - 0.55) - 0.001;
    d = min(d, d2);

    p = prevP;
    p = p * Rot(radians(-iTime * 50.0 + 30.0));
    p += sin(p * 25.0 - radians(iTime * 80.0)) * 0.01;
    d2 = abs(length(p) - 0.65) - 0.0001;
    d = min(d, d2);

    p = prevP;
    a = radians(-sin(iTime * 1.2)) * 120.0;
    a += radians(-70.0);
    p.x += cos(a) * 0.58;
    p.y += sin(a) * 0.58;

    d2 = abs(Tri(p * Rot(-a) * Rot(radians(90.0)), float2(0.03), radians(45.0))) - 0.003;
    d = min(d, d2);

    p = prevP;
    a = radians(sin(iTime * 1.3)) * 100.0;
    a += radians(-10.0);
    p.x += cos(a) * 0.58;
    p.y += sin(a) * 0.58;

    d2 = abs(Tri(p * Rot(-a) * Rot(radians(90.0)), float2(0.03), radians(45.0))) - 0.003;
    d = min(d, d2);

    return d;
}

static float ring1(float2 p, float iTime) {
    float2 prevP = p;
    float size = 0.45;
    float deg = 140.0;
    float thickness = 0.02;
    float d = abs(length(p) - size) - thickness;

    p = p * Rot(radians(iTime * 60.0));
    float a = radians(deg);
    d = max(dot(p, float2(cos(a), sin(a))), d);
    a = radians(-deg);
    d = max(dot(p, float2(cos(a), sin(a))), d);

    p = prevP;
    float d2 = abs(length(p) - size) - 0.001;
    return min(d, d2);
}

static float ring2(float2 p, float iTime) {
    float size = 0.3;
    float deg = 120.0;
    float thickness = 0.02;

    p = p * Rot(-radians(sin(iTime * 2.0) * 90.0));
    float d = abs(length(p) - size) - thickness;
    float a = radians(-deg);
    d = max(dot(p, float2(cos(a), sin(a))), d);
    a = radians(deg);
    d = max(dot(p, float2(cos(a), sin(a))), d);

    float d2 = abs(length(p) - size) - thickness;
    a = radians(-deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);
    a = radians(deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);

    return min(d, d2);
}

static float ring3(float2 p, float iTime) {
    p = p * Rot(radians(-iTime * 80.0 - 120.0));

    float2 prevP = p;
    float deg = 140.0;

    p = DF(p, 6.0);
    p -= float2(0.3);
    float d = abs(B(p * Rot(radians(45.0)), float2(0.03, 0.025))) - 0.003;

    p = prevP;
    float a = radians(-deg);
    d = max(dot(p, float2(cos(a), sin(a))), d);
    a = radians(deg);
    d = max(dot(p, float2(cos(a), sin(a))), d);

    p = prevP;
    p = DF(p, 6.0);
    p -= float2(0.3);
    float d2 = abs(B(p * Rot(radians(45.0)), float2(0.03, 0.025))) - 0.003;

    p = prevP;
    a = radians(-deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);
    a = radians(deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);

    return min(d, d2);
}

static float ring4(float2 p, float iTime) {
    p = p * Rot(radians(iTime * 75.0 - 220.0));

    float deg = 20.0;
    float d = abs(length(p) - 0.25) - 0.01;

    p = DF(p, 2.0);
    p -= float2(0.1);

    float a = radians(-deg);
    d = max(-dot(p, float2(cos(a), sin(a))), d);
    a = radians(deg);
    d = max(-dot(p, float2(cos(a), sin(a))), d);

    return d;
}

static float ring5(float2 p, float iTime) {
    p = p * Rot(radians(-iTime * 70.0 + 170.0));

    float2 prevP = p;
    float deg = 150.0;

    float d = abs(length(p) - 0.16) - 0.02;

    float a = radians(-deg);
    d = max(dot(p, float2(cos(a), sin(a))), d);
    a = radians(deg);
    d = max(dot(p, float2(cos(a), sin(a))), d);

    p = prevP;
    p = p * Rot(radians(-30.0));
    float d2 = abs(length(p) - 0.136) - 0.02;

    deg = 60.0;
    a = radians(-deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);
    a = radians(deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);

    return min(d, d2);
}

static float ring6(float2 p, float iTime) {
    float2 prevP = p;
    p = p * Rot(radians(iTime * 72.0 + 110.0));

    float d = abs(length(p) - 0.95) - 0.001;
    d = max(-(abs(p.x) - 0.4), d);
    d = max(-(abs(p.y) - 0.4), d);

    p = prevP;
    p = p * Rot(radians(-iTime * 30.0 + 50.0));
    p = DF(p, 16.0);
    p -= float2(0.6);
    float d2 = B(p * Rot(radians(45.0)), float2(0.02, 0.03));
    p = prevP;

    p = p * Rot(radians(-iTime * 30.0 + 50.0));
    float deg = 155.0;
    float a = radians(deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);
    a = radians(-deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);

    return min(d, d2);
}

static float bg(float2 p, float iTime) {
    p.y -= iTime * 0.1;
    float2 prevP = p;

    p *= 2.8;
    float2 gv = fract(p) - 0.5;
    float2 gv2 = fract(p * 3.0) - 0.5;
    float2 id = floor(p);

    float d = min(B(gv2, float2(0.02, 0.09)), B(gv2, float2(0.09, 0.02)));

    float n = Hash21(id);
    gv += float2(0.166, 0.17);
    float d2 = abs(B(gv, float2(0.169))) - 0.004;

    if (n < 0.3) {
        gv = gv * Rot(radians(iTime * 60.0));
        d2 = max(-(abs(gv.x) - 0.08), d2);
        d2 = max(-(abs(gv.y) - 0.08), d2);
        d = min(d, d2);
    } else if (n >= 0.3 && n < 0.6) {
        gv = gv * Rot(radians(-iTime * 60.0));
        d2 = max(-(abs(gv.x) - 0.08), d2);
        d2 = max(-(abs(gv.y) - 0.08), d2);
        d = min(d, d2);
    } else if (n >= 0.6 && n < 1.0) {
        gv = gv * Rot(radians(iTime * 60.0) + n);
        d2 = abs(length(gv) - 0.1) - 0.025;
        d2 = max(-(abs(gv.x) - 0.03), d2);
        d = min(d, abs(d2) - 0.003);
    }

    p = prevP;
    p = hr_mod(p, float2(0.02)) - 0.01;
    d2 = B(p, float2(0.001));
    d = min(d, d2);

    return d;
}

static float numberWithCIrcleUI(float2 p, float iTime) {
    float2 prevP = p;

    p = p * SkewX(radians(-15.0));
    int num = int(hr_mod(iTime * 6.0, 10.0));
    float d = drawFont(p - float2(-0.16, 0.0), num);
    num = int(hr_mod(iTime * 3.0, 10.0));
    float d2 = drawFont(p - float2(-0.08, 0.0), num);
    d = min(d, d2);
    d2 = drawFont(p - float2(-0.02, 0.0), seg_DP);
    d = min(d, d2);

    p *= 1.5;
    num = int(hr_mod(iTime * 10.0, 10.0));
    d2 = drawFont(p - float2(0.04, -0.03), num);
    d = min(d, d2);
    num = int(hr_mod(iTime * 15.0, 10.0));
    d2 = drawFont(p - float2(0.12, -0.03), num);
    d = abs(min(d, d2)) - 0.002;

    p = prevP;

    p.x -= 0.07;
    p = p * Rot(radians(-iTime * 50.0));
    p = DF(p, 4.0);
    p -= float2(0.085);
    d2 = B(p * Rot(radians(45.0)), float2(0.015, 0.018));
    p = prevP;
    d2 = max(-B(p, float2(0.13, 0.07)), d2);
    d = min(d, abs(d2) - 0.0005);

    return d;
}

static float blockUI(float2 p, float iTime) {
    float2 prevP = p;
    p.x += iTime * 0.05;
    p.y = abs(p.y) - 0.02;
    p.x = hr_mod(p.x, 0.04) - 0.02;
    float d = B(p, float2(0.0085));
    p = prevP;
    p.x += iTime * 0.05;
    p.x += 0.02;
    p.x = hr_mod(p.x, 0.04) - 0.02;
    float d2 = B(p, float2(0.0085));
    d = min(d, d2);
    p = prevP;
    d = max(abs(p.x) - 0.2, d);
    return abs(d) - 0.0002;
}

static float smallCircleUI(float2 p, float iTime) {
    p *= 1.1;
    float2 prevP = p;

    float deg = 20.0;

    p = p * Rot(radians(sin(iTime * 3.0) * 50.0));
    float d = abs(length(p) - 0.1) - 0.003;

    p = DF(p, 0.75);
    p -= float2(0.02);

    float a = radians(-deg);
    d = max(-dot(p, float2(cos(a), sin(a))), d);
    a = radians(deg);
    d = max(-dot(p, float2(cos(a), sin(a))), d);

    p = prevP;
    p = p * Rot(radians(-sin(iTime * 2.0) * 80.0));
    float d2 = abs(length(p) - 0.08) - 0.001;
    d2 = max(-p.x, d2);
    d = min(d, d2);

    p = prevP;
    p = p * Rot(radians(-iTime * 50.0));
    d2 = abs(length(p) - 0.05) - 0.015;
    deg = 170.0;
    a = radians(deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);
    a = radians(-deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);
    d = min(d, abs(d2) - 0.0005);

    return d;
}

static float smallCircleUI2(float2 p, float iTime) {
    float d = abs(length(p) - 0.04) - 0.0001;
    float d2 = length(p) - 0.03;

    p = p * Rot(radians(iTime * 30.0));
    float deg = 140.0;
    float a = radians(deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);
    a = radians(-deg);
    d2 = max(-dot(p, float2(cos(a), sin(a))), d2);
    d = min(d, d2);

    d2 = length(p) - 0.03;
    a = radians(deg);
    d2 = max(dot(p, float2(cos(a), sin(a))), d2);
    a = radians(-deg);
    d2 = max(dot(p, float2(cos(a), sin(a))), d2);
    d = min(d, d2);

    d = max(-(length(p) - 0.02), d);
    return d;
}

static float rectUI(float2 p, float iTime) {
    p = p * Rot(radians(45.0));
    float2 prevP = p;
    float d = abs(B(p, float2(0.12))) - 0.003;
    p = p * Rot(radians(iTime * 60.0));
    d = max(-(abs(p.x) - 0.05), d);
    d = max(-(abs(p.y) - 0.05), d);
    p = prevP;
    float d2 = abs(B(p, float2(0.12))) - 0.0005;
    d = min(d, d2);

    d2 = abs(B(p, float2(0.09))) - 0.003;
    p = p * Rot(radians(-iTime * 50.0));
    d2 = max(-(abs(p.x) - 0.03), d2);
    d2 = max(-(abs(p.y) - 0.03), d2);
    d = min(d, d2);
    p = prevP;
    d2 = abs(B(p, float2(0.09))) - 0.0005;
    d = min(d, d2);

    p = p * Rot(radians(-45.0));
    p.y = abs(p.y) - 0.07 - sin(iTime * 3.0) * 0.01;
    d2 = Tri(p, float2(0.02), radians(45.0));
    d = min(d, d2);

    p = prevP;
    p = p * Rot(radians(45.0));
    p.y = abs(p.y) - 0.07 - sin(iTime * 3.0) * 0.01;
    d2 = Tri(p, float2(0.02), radians(45.0));
    d = min(d, d2);

    p = prevP;
    p = p * Rot(radians(45.0));
    d2 = abs(B(p, float2(0.025))) - 0.0005;
    d2 = max(-(abs(p.x) - 0.01), d2);
    d2 = max(-(abs(p.y) - 0.01), d2);
    d = min(d, d2);

    return d;
}

static float graphUI(float2 p, float iTime) {
    float2 prevP = p;
    p.x += 0.5;
    p.y -= iTime * 0.25;
    p *= float2(1.0, 100.0);

    float2 gv = fract(p) - 0.5;
    float2 id = floor(p);

    float n = Hash21(float2(id.y)) * 2.0;

    float w = (abs(sin(iTime * n) + 0.25) * 0.03) * n * 0.5;
    float d = B(gv, float2(w, 0.1));

    p = prevP;
    d = max(abs(p.x) - 0.2, d);
    d = max(abs(p.y) - 0.2, d);

    return d;
}

static float staticUI(float2 p) {
    float2 prevP = p;
    float d = B(p, float2(0.005, 0.13));
    p -= float2(0.02, -0.147);
    p = p * Rot(radians(-45.0));
    float d2 = B(p, float2(0.005, 0.028));
    d = min(d, d2);
    p = prevP;
    d2 = B(p - float2(0.04, -0.2135), float2(0.005, 0.049));
    d = min(d, d2);
    p -= float2(0.02, -0.28);
    p = p * Rot(radians(45.0));
    d2 = B(p, float2(0.005, 0.03));
    d = min(d, d2);
    p = prevP;
    d2 = length(p - float2(0.0, 0.13)) - 0.012;
    d = min(d, d2);
    d2 = length(p - float2(0.0, -0.3)) - 0.012;
    d = min(d, d2);
    return d;
}

static float arrowUI(float2 p, float iTime) {
    float2 prevP = p;
    p.x *= -1.0;
    p.x -= iTime * 0.12;
    p.x = hr_mod(p.x, 0.07) - 0.035;
    p.x -= 0.0325;

    p *= float2(0.9, 1.5);
    p = p * Rot(radians(90.0));
    float d = Tri(p, float2(0.05), radians(45.0));
    d = max(-Tri(p - float2(0.0, -0.03), float2(0.05), radians(45.0)), d);
    d = abs(d) - 0.0005;
    p = prevP;
    d = max(abs(p.x) - 0.15, d);
    return d;
}

static float sideLine(float2 p) {
    p.x *= -1.0;
    float2 prevP = p;
    p.y = abs(p.y) - 0.17;
    p = p * Rot(radians(45.0));
    float d = B(p, float2(0.035, 0.01));
    p = prevP;
    float d2 = B(p - float2(0.0217, 0.0), float2(0.01, 0.152));
    d = min(d, d2);
    return abs(d) - 0.0005;
}

static float sideUI(float2 p) {
    float2 prevP = p;
    p.x *= -1.0;
    p.x += 0.025;
    float d = sideLine(p);
    p = prevP;
    p.y = abs(p.y) - 0.275;
    float d2 = sideLine(p);
    return min(d, d2);
}

static float overlayUI(float2 p, float iTime) {
    float2 prevP = p;

    float d = numberWithCIrcleUI(p - float2(0.56, -0.34), iTime);
    p.x = abs(p.x) - 0.56;
    p.y -= 0.45;
    float d2 = blockUI(p, iTime);
    d = min(d, d2);
    p = prevP;

    p.x = abs(p.x) - 0.72;
    p.y -= 0.35;
    d2 = smallCircleUI2(p, iTime);
    d = min(d, d2);
    p = prevP;
    d2 = smallCircleUI2(p - float2(-0.39, -0.42), iTime);
    d = min(d, d2);

    p = prevP;
    p.x -= 0.58;
    p.y -= 0.07;
    p.y = abs(p.y) - 0.12;
    d2 = smallCircleUI(p, iTime);
    d = min(d, d2);

    p = prevP;
    d2 = rectUI(p - float2(-0.58, -0.3), iTime);
    d = min(d, d2);

    p -= float2(-0.58, 0.1);
    p.x = abs(p.x) - 0.05;
    d2 = graphUI(p, iTime);
    d = min(d, d2);
    p = prevP;

    p.x = abs(p.x) - 0.72;
    p.y -= 0.13;
    d2 = staticUI(p);
    d = min(d, d2);
    p = prevP;

    p.x = abs(p.x) - 0.51;
    p.y -= 0.35;
    d2 = arrowUI(p, iTime);
    d = min(d, d2);
    p = prevP;

    p.x = abs(p.x) - 0.82;
    d2 = sideUI(p);
    return min(d, d2);
}

static float GetDist(float3 p, float iTime) {
    p.z += 0.7;
    float maxThick = 0.03;
    float minThick = 0.007;
    float thickness = maxThick;
    float frame = hr_mod(iTime, 30.0);
    float time = frame;
    if (frame >= 10.0 && frame < 20.0) {
        time = getTime(time - 10.0, 1.5);
        thickness = (maxThick + minThick) - cubicInOut(time) * maxThick;
    } else if (frame >= 20.0) {
        time = getTime(time - 20.0, 1.5);
        thickness = minThick + cubicInOut(time) * maxThick;
    }

    float d = ring0(p.xy, iTime);
    d = max(abs(p.z) - thickness, d);

    p.z -= 0.2;
    float d2 = ring1(p.xy, iTime);
    d2 = max(abs(p.z) - thickness, d2);
    d = min(d, d2);

    p.z -= 0.2;
    d2 = ring2(p.xy, iTime);
    d2 = max(abs(p.z) - thickness, d2);
    d = min(d, d2);

    p.z -= 0.2;
    d2 = ring3(p.xy, iTime);
    d2 = max(abs(p.z) - thickness, d2);
    d = min(d, d2);

    p.z -= 0.2;
    d2 = ring4(p.xy, iTime);
    d2 = max(abs(p.z) - thickness, d2);
    d = min(d, d2);

    p.z -= 0.2;
    d2 = ring5(p.xy, iTime);
    d2 = max(abs(p.z) - thickness, d2);
    d = min(d, d2);

    p.z -= 0.2;
    d2 = ring6(p.xy, iTime);
    d2 = max(abs(p.z) - thickness, d2);
    d = min(d, d2);

    return d;
}

static float3 RayMarch(float3 ro, float3 rd, int stepnum, float iTime) {
    float steps = 0.0;
    float alpha = 0.0;

    float tmax = 5.0;
    float t = 0.0;

    float glowVal = 0.003;

    for (float i = 0.0; i < float(stepnum); i++) {
        steps = i;
        float3 p = ro + rd * t;
        float d = GetDist(p, iTime);
        float absd = abs(d);

        if (t > tmax) break;

        alpha += 1.0 - smoothstep(0.0, glowVal, d);
        t += max(0.0001, absd * 0.6);
    }
    alpha /= steps;

    return alpha * float3(1.5);
}

static float3 R(float2 uv, float3 p, float3 l, float z) {
    float3 f = normalize(l - p);
    float3 r = normalize(cross(float3(0, 1, 0), f));
    float3 u = cross(f, r);
    float3 c = p + f * z;
    float3 i = c + uv.x * r + uv.y * u;
    return normalize(i - p);
}

fragment float4 hudrings_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 iResolution = uniforms.iResolution;
    float2 fragCoord = in.uv * iResolution;
    float2 uv = (fragCoord - 0.5 * iResolution) / iResolution.y;
    float2 m = uniforms.iMouse.xy / iResolution;

    float3 ro = float3(0.0, 0.0, -2.1);
    if (uniforms.iMouse.z > 0.0) {
        ro.yz = ro.yz * Rot(m.y * 3.14 + 1.0);
        ro.y = max(-0.9, ro.y);
        ro.xz = ro.xz * Rot(-m.x * 6.2831);
    } else {
        float YZ = 45.0;
        float ogRXZ = 50.0;
        float animRXZ = 20.0;

        float frame = hr_mod(iTime, 30.0);
        float time = frame;

        if (frame >= 10.0 && frame < 20.0) {
            time = getTime(time - 10.0, 1.5);
            YZ = 45.0 - cubicInOut(time) * 45.0;
            ogRXZ = 50.0 - cubicInOut(time) * 50.0;
            animRXZ = 20.0 - cubicInOut(time) * 20.0;
        } else if (frame >= 20.0) {
            time = getTime(time - 20.0, 1.5);
            YZ = cubicInOut(time) * 45.0;
            ogRXZ = cubicInOut(time) * 50.0;
            animRXZ = cubicInOut(time) * 20.0;
        }

        ro.yz = ro.yz * Rot(radians(YZ));
        ro.xz = ro.xz * Rot(radians(sin(iTime * 0.3) * animRXZ + ogRXZ));
    }

    float3 rd = R(uv, ro, float3(0.0, 0.0, 0.0), 1.0);
    float3 d = RayMarch(ro, rd, MAX_STEPS, iTime);
    float3 col = float3(0.0);
    float bd = bg(uv, iTime);
    float aa = 1.0 / min(iResolution.y, iResolution.x);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, bd));

    col = mix(col, d.xyz, 0.7);
    col = pow(col, float3(0.9545));

    float d2 = overlayUI(uv, iTime);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d2));

    return float4(col, 1.0);
}
