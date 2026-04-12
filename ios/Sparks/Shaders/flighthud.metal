#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Flight HUD - Ported from Shadertoy
// https://www.shadertoy.com/view/Dl2XRz
// Original Author: kishimisu
// License: CC BY-NC-SA 3.0

// GLSL-compatible mod (matches floor-based definition for negative values)
static float hr_mod(float x, float y) { return x - y * floor(x / y); }
static float2 hr_mod(float2 x, float2 y) { return x - y * floor(x / y); }
static float2 hr_mod(float2 x, float y) { return x - y * floor(x / y); }

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

static float fh_rand(float2 co) {
    return fract(sin(dot(co.xy, float2(12.9898, 78.233))) * 43758.5453);
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

    float a = max(abs(p.x) - 0.001, abs(p.y) - h);

    p = abs(p);
    float b = max(abs(p.x - w * 0.5) - w * 0.5, abs(p.y) - 0.001);

    float d = min(a, b);
    return d;
}

static float seg0(float2 p) {
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;
    float d = max(abs(p.x) - w, abs(p.y) - h);
    d = max(d, -(max(abs(p.x) - w + padding, abs(p.y) - h + padding)));
    return d;
}

static float seg1(float2 p) {
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;
    p.x -= w - padding * 0.5;
    float d = max(abs(p.x) - padding * 0.5, abs(p.y) - h);
    return d;
}

static float seg2(float2 p) {
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;
    float hh = padding * 2.5;

    float d = max(abs(p.x) - w, abs(p.y) - h);
    d = max(d, -(max(abs(p.x + w * 0.5 - padding * 0.5) - w * 0.5 + padding * 0.5, abs(p.y - hh * 0.5) - hh * 0.5 + padding)));
    d = max(d, -(max(abs(p.x - w * 0.5 + padding * 0.5) - w * 0.5 + padding * 0.5, abs(p.y + hh * 0.5) - hh * 0.5 + padding)));
    return d;
}

static float seg3(float2 p) {
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;
    float hh = padding * 2.5;

    float d = max(abs(p.x) - w, abs(p.y) - h);
    d = max(d, -(max(abs(p.x + w * 0.5 - padding * 0.5) - w * 0.5 + padding * 0.5, abs(p.y - hh * 0.5) - hh * 0.5 + padding)));
    d = max(d, -(max(abs(p.x + w * 0.5 - padding * 0.5) - w * 0.5 + padding * 0.5, abs(p.y + hh * 0.5) - hh * 0.5 + padding)));
    return d;
}

static float seg4(float2 p) {
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;
    float hh = padding * 2.5;

    float d = max(abs(p.x) - w, abs(p.y) - h);
    d = max(d, -(max(abs(p.x + w * 0.5 - padding * 0.5) - w * 0.5 + padding * 0.5, abs(p.y + hh * 0.5) - hh * 0.5 + padding)));
    d = max(d, -(max(abs(p.x) - w + padding, abs(p.y - hh * 0.5) - hh * 0.5 + padding)));
    return d;
}

static float seg5(float2 p) {
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;
    float hh = padding * 2.5;

    float d = max(abs(p.x) - w, abs(p.y) - h);
    d = max(d, -(max(abs(p.x - w * 0.5 + padding * 0.5) - w * 0.5 + padding * 0.5, abs(p.y - hh * 0.5) - hh * 0.5 + padding)));
    d = max(d, -(max(abs(p.x + w * 0.5 - padding * 0.5) - w * 0.5 + padding * 0.5, abs(p.y + hh * 0.5) - hh * 0.5 + padding)));
    return d;
}

static float seg6(float2 p) {
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;
    float hh = padding * 2.5;

    float d = max(abs(p.x) - w, abs(p.y) - h);
    d = max(d, -(max(abs(p.x - w * 0.5 + padding * 0.5) - w * 0.5 + padding * 0.5, abs(p.y - hh * 0.5) - hh * 0.5 + padding)));
    d = max(d, -(max(abs(p.x) - w + padding, abs(p.y + hh * 0.5) - hh * 0.5 + padding)));
    return d;
}

static float seg7(float2 p) {
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;

    float d = max(abs(p.x) - w, abs(p.y) - h);
    d = max(d, -(max(abs(p.x + w * 0.5 - padding * 0.5) - w * 0.5 + padding * 0.5, abs(p.y + padding) - h + padding)));
    return d;
}

static float seg8(float2 p) {
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;
    float hh = padding * 2.5;

    float d = max(abs(p.x) - w, abs(p.y) - h);
    d = max(d, -(max(abs(p.x) - w + padding, abs(p.y - hh * 0.5) - hh * 0.5 + padding)));
    d = max(d, -(max(abs(p.x) - w + padding, abs(p.y + hh * 0.5) - hh * 0.5 + padding)));
    return d;
}

static float seg9(float2 p) {
    float padding = 0.05;
    float w = padding * 3.0;
    float h = padding * 5.0;
    float hh = padding * 2.5;

    float d = max(abs(p.x) - w, abs(p.y) - h);
    d = max(d, -(max(abs(p.x) - w + padding, abs(p.y - hh * 0.5) - hh * 0.5 + padding)));
    d = max(d, -(max(abs(p.x + w * 0.5 - padding * 0.5) - w * 0.5 + padding * 0.5, abs(p.y - hh * 0.5) - hh * 0.5 + padding)));
    return d;
}

static float checkChar(float2 p, int ch) {
    float d = 1e6;
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
    return d;
}

static float drawFont(float2 p, int ch) {
    float d = segBase(p);
    float c = checkChar(p, ch);
    d = max(d, c);
    return d;
}

static float3 paperPlane(float2 p, float3 col, float aa) {
    float2 prevP = p;
    float scale = 0.06;
    p /= scale;

    float wing = Tri(p, float2(0.4, 0.3), 1.2);
    wing = min(wing, Tri(p * float2(1.0, -1.0), float2(0.4, 0.3), 1.2));

    float body = max(abs(p.x) - 0.05, abs(p.y) - 0.5);
    body = max(body, -Tri(p - float2(0.0, 0.5), float2(0.08, 0.2), 0.5));

    float tail = Tri(p - float2(0.0, -0.35), float2(0.15, 0.12), 0.8);
    tail = min(tail, Tri((p - float2(0.0, -0.35)) * float2(1.0, -1.0), float2(0.15, 0.12), 0.8));

    float d = min(wing, min(body, tail));
    d *= scale;

    col = mix(col, float3(1.0), smoothstep(aa, 0.0, d));

    return col;
}

static float3 radar(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    float r = 0.12;

    float circle = abs(length(p) - r) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, circle) * 0.3);

    float circle2 = abs(length(p) - r * 0.5) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, circle2) * 0.15);

    float mask = length(p) - r;

    float a = atan2(p.y, p.x);
    float sweep = hr_mod(a - iTime * 2.0, 6.2832);
    float sweepLine = abs(sweep - 0.01) - 0.005;
    sweepLine = max(sweepLine, -mask);
    col = mix(col, float3(0.0, 1.0, 0.5), smoothstep(aa, 0.0, sweepLine) * 0.6);

    float trail = smoothstep(0.0, 2.0, sweep);
    float trailD = length(p) - r;
    col = mix(col, float3(0.0, 1.0, 0.5) * 0.3, trail * smoothstep(aa, 0.0, -trailD) * 0.2);

    float cross_h = max(abs(p.x) - r, abs(p.y) - 0.001);
    float cross_v = max(abs(p.x) - 0.001, abs(p.y) - r);
    float crosshair = min(cross_h, cross_v);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, crosshair) * 0.2);

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float2 bp = float2(fh_rand(float2(fi, 0.0)) - 0.5, fh_rand(float2(0.0, fi)) - 0.5) * r * 1.8;
        float blip = length(p - bp) - 0.005;
        float blipMask = step(length(bp), r);
        col = mix(col, float3(0.0, 1.0, 0.5), smoothstep(aa, 0.0, blip) * 0.8 * blipMask);
    }

    return col;
}

static float3 grids(float2 p, float3 col, float aa) {
    float2 prevP = p;

    float gridSize = 0.05;
    float2 gp = hr_mod(p, gridSize) - gridSize * 0.5;
    float grid = min(abs(gp.x), abs(gp.y)) - 0.0005;
    float gridMask = max(abs(p.x) - 0.45, abs(p.y) - 0.45);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, grid) * smoothstep(aa, 0.0, gridMask) * 0.08);

    float gridSize2 = 0.1;
    float2 gp2 = hr_mod(p, gridSize2) - gridSize2 * 0.5;
    float grid2 = min(abs(gp2.x), abs(gp2.y)) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, grid2) * smoothstep(aa, 0.0, gridMask) * 0.12);

    float axis_h = max(abs(p.x) - 0.45, abs(p.y) - 0.001);
    float axis_v = max(abs(p.x) - 0.001, abs(p.y) - 0.45);
    float axes = min(axis_h, axis_v);
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, axes) * 0.25);

    float border = abs(max(abs(p.x) - 0.45, abs(p.y) - 0.45)) - 0.002;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, border) * 0.4);

    return col;
}

static float3 objects(float2 p, float3 col, float iTime, float2 iResolution, float aa) {
    float2 prevP = p;

    // Corner brackets
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float2 corner = float2(hr_mod(fi, 2.0) * 2.0 - 1.0, floor(fi / 2.0) * 2.0 - 1.0) * 0.42;
        float2 cp = p - corner;
        float bracket_h = max(abs(cp.x) - 0.03, abs(cp.y) - 0.001);
        float bracket_v = max(abs(cp.x) - 0.001, abs(cp.y) - 0.03);
        float bracket = min(bracket_h, bracket_v);
        col = mix(col, float3(1.0), smoothstep(aa, 0.0, bracket) * 0.6);
    }

    // Moving tick marks on axes
    float t = iTime * 0.5;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float offset = hr_mod(fi * 0.1 + t, 0.8) - 0.4;

        float2 tp = p - float2(offset, 0.0);
        float tick = max(abs(tp.x) - 0.001, abs(tp.y) - 0.01);
        float tickMask = step(abs(offset), 0.4);
        col = mix(col, float3(1.0), smoothstep(aa, 0.0, tick) * 0.3 * tickMask);

        float2 tp2 = p - float2(0.0, offset);
        float tick2 = max(abs(tp2.x) - 0.01, abs(tp2.y) - 0.001);
        col = mix(col, float3(1.0), smoothstep(aa, 0.0, tick2) * 0.3 * tickMask);
    }

    // Center diamond
    float diamond = abs(p.x) + abs(p.y) - 0.015;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, diamond) * 0.8);

    // Heading indicator at top
    {
        float2 hp = p - float2(0.0, 0.42);
        float heading = hr_mod(iTime * 20.0, 360.0);

        for (int i = -3; i <= 3; i++) {
            float fi = float(i);
            float deg = hr_mod(heading + fi * 10.0, 360.0);
            float xpos = fi * 0.06;
            float2 tp = hp - float2(xpos, 0.0);

            float tick3 = max(abs(tp.x) - 0.0008, abs(tp.y) - 0.015);
            col = mix(col, float3(1.0), smoothstep(aa, 0.0, tick3) * 0.5);

            int d0 = int(hr_mod(deg, 10.0));
            int d1 = int(hr_mod(deg / 10.0, 10.0));
            int d2 = int(hr_mod(deg / 100.0, 10.0));

            float font = drawFont(tp * 15.0 - float2(-0.35, 0.5), d2);
            font = min(font, drawFont(tp * 15.0 - float2(0.0, 0.5), d1));
            font = min(font, drawFont(tp * 15.0 - float2(0.35, 0.5), d0));
            col = mix(col, float3(1.0), smoothstep(aa, 0.0, font / 15.0) * 0.5);
        }

        float headingBox = max(abs(hp.x) - 0.025, abs(hp.y - 0.015) - 0.02);
        headingBox = abs(headingBox) - 0.001;
        col = mix(col, float3(1.0), smoothstep(aa, 0.0, headingBox) * 0.6);
    }

    // Altitude indicator on right
    {
        float2 ap = p - float2(0.48, 0.0);
        float alt = hr_mod(iTime * 100.0, 10000.0);

        for (int i = -4; i <= 4; i++) {
            float fi = float(i);
            float val = hr_mod(alt + fi * 100.0, 10000.0);
            float ypos = fi * 0.05;
            float2 tp = ap - float2(0.0, ypos);

            float tick4 = max(abs(tp.x) - 0.01, abs(tp.y) - 0.0008);
            col = mix(col, float3(1.0), smoothstep(aa, 0.0, tick4) * 0.4);

            int d0 = int(hr_mod(val / 100.0, 10.0));
            int d1 = int(hr_mod(val / 1000.0, 10.0));

            float font2 = drawFont(tp * 18.0 - float2(0.5, 0.0), d1);
            font2 = min(font2, drawFont(tp * 18.0 - float2(0.85, 0.0), d0));
            col = mix(col, float3(1.0), smoothstep(aa, 0.0, font2 / 18.0) * 0.4);
        }
    }

    // Speed indicator on left
    {
        float2 sp = p - float2(-0.48, 0.0);
        float spd = hr_mod(iTime * 50.0, 1000.0);

        for (int i = -4; i <= 4; i++) {
            float fi = float(i);
            float val = hr_mod(spd + fi * 50.0, 1000.0);
            float ypos = fi * 0.05;
            float2 tp = sp - float2(0.0, ypos);

            float tick5 = max(abs(tp.x) - 0.01, abs(tp.y) - 0.0008);
            col = mix(col, float3(1.0), smoothstep(aa, 0.0, tick5) * 0.4);

            int d0 = int(hr_mod(val / 10.0, 10.0));
            int d1 = int(hr_mod(val / 100.0, 10.0));

            float font3 = drawFont(tp * 18.0 - float2(-0.85, 0.0), d1);
            font3 = min(font3, drawFont(tp * 18.0 - float2(-0.5, 0.0), d0));
            col = mix(col, float3(1.0), smoothstep(aa, 0.0, font3 / 18.0) * 0.4);
        }
    }

    return col;
}

static float3 graph0(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    float w = 0.12;
    float h = 0.08;

    float border = abs(max(abs(p.x) - w, abs(p.y) - h)) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, border) * 0.3);

    float mask = max(abs(p.x) - w, abs(p.y) - h);

    // Graph line
    float x = p.x / w;
    float y = sin(x * 12.0 + iTime * 3.0) * 0.5 + sin(x * 6.0 - iTime * 2.0) * 0.3;
    float graphLine = abs(p.y - y * h) - 0.002;
    graphLine = max(graphLine, -mask);
    col = mix(col, float3(0.0, 0.8, 1.0), smoothstep(aa, 0.0, graphLine) * 0.6);

    // Fill below
    float fill = max(p.y - y * h, -mask);
    col = mix(col, float3(0.0, 0.8, 1.0) * 0.2, smoothstep(aa, 0.0, fill) * 0.15);

    return col;
}

static float3 graph1(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    float w = 0.12;
    float h = 0.08;

    float border = abs(max(abs(p.x) - w, abs(p.y) - h)) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, border) * 0.3);

    float mask = max(abs(p.x) - w, abs(p.y) - h);

    // Bar graph
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float bx = -w + w * 0.25 * 0.5 + fi * w * 0.25;
        float bh = (sin(fi * 1.3 + iTime * 2.0) * 0.5 + 0.5) * h * 0.8;
        float2 bp = p - float2(bx, -h + bh);
        float bar = max(abs(bp.x) - w * 0.1, abs(bp.y) - bh);
        bar = max(bar, -mask);
        col = mix(col, float3(0.0, 1.0, 0.5), smoothstep(aa, 0.0, bar) * 0.4);
    }

    return col;
}

static float3 graph2(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    float w = 0.12;
    float h = 0.08;

    float border = abs(max(abs(p.x) - w, abs(p.y) - h)) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, border) * 0.3);

    float mask = max(abs(p.x) - w, abs(p.y) - h);

    // Stepped line
    float x = p.x / w;
    float y = 0.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float seg_x = -1.0 + fi * 0.4;
        float seg_val = sin(fi * 2.1 + iTime) * 0.5;
        if (x >= seg_x && x < seg_x + 0.4) {
            y = seg_val;
        }
    }
    float stepLine = abs(p.y - y * h) - 0.002;
    stepLine = max(stepLine, -mask);
    col = mix(col, float3(1.0, 0.5, 0.0), smoothstep(aa, 0.0, stepLine) * 0.5);

    return col;
}

static float3 graph3(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    float w = 0.12;
    float h = 0.08;

    float border = abs(max(abs(p.x) - w, abs(p.y) - h)) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, border) * 0.3);

    float mask = max(abs(p.x) - w, abs(p.y) - h);

    // Scatter dots
    for (int i = 0; i < 12; i++) {
        float fi = float(i);
        float2 dp = float2(fh_rand(float2(fi, 1.0)) - 0.5, fh_rand(float2(1.0, fi)) - 0.5) * float2(w, h) * 1.8;
        float pulse = sin(iTime * 2.0 + fi) * 0.003;
        float dot_d = length(p - dp) - 0.004 - pulse;
        dot_d = max(dot_d, -mask);
        col = mix(col, float3(1.0, 0.3, 0.3), smoothstep(aa, 0.0, dot_d) * 0.5);
    }

    return col;
}

static float3 smallCircleUI(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    float r = 0.05;

    float circle = abs(length(p) - r) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, circle) * 0.4);

    // Rotating ticks
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float a = fi * 0.785 + iTime;
        float2 tp = p - float2(cos(a), sin(a)) * r;
        float tick = length(tp) - 0.003;
        col = mix(col, float3(1.0), smoothstep(aa, 0.0, tick) * 0.5);
    }

    // Center dot
    float center = length(p) - 0.005;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, center) * 0.6);

    // Value arc
    float arcAngle = sin(iTime) * 1.5 + 1.5;
    float arc_a = atan2(p.y, p.x);
    float arc_d = abs(length(p) - r * 0.7) - 0.002;
    float arcMask = step(arc_a, -3.14159 + arcAngle);
    arc_d = max(arc_d, -(length(p) - r * 0.5));
    col = mix(col, float3(0.0, 0.8, 1.0), smoothstep(aa, 0.0, arc_d) * 0.5 * arcMask);

    return col;
}

static float3 smallCircleUI2(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    float r = 0.05;

    float circle = abs(length(p) - r) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, circle) * 0.4);

    // Pie segments
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float a1 = fi * 1.5708;
        float a2 = a1 + 1.2;
        float pa = atan2(p.y, p.x);
        float pie_d = length(p) - r * 0.8;
        float angMask = step(a1, pa) * step(pa, a2);
        pie_d = max(pie_d, -(length(p) - r * 0.3));
        float brightness = 0.2 + sin(iTime + fi) * 0.15;
        col = mix(col, float3(0.0, 1.0, 0.5) * brightness, smoothstep(aa, 0.0, pie_d) * angMask);
    }

    // Inner circle
    float inner = abs(length(p) - r * 0.25) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, inner) * 0.3);

    return col;
}

static float3 smallCircleUI3(float2 p, float3 col, float side, float iTime, float aa) {
    float2 prevP = p;
    float r = 0.04;

    float circle = abs(length(p) - r) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, circle) * 0.3);

    // Progress ring
    float progress = sin(iTime * 0.8 + side) * 0.5 + 0.5;
    float pa = atan2(p.y, p.x);
    float normalized = (pa + 3.14159) / (6.28318);
    float ring = abs(length(p) - r * 0.75) - 0.003;
    float ringMask = step(normalized, progress);
    col = mix(col, float3(0.0, 0.8, 1.0), smoothstep(aa, 0.0, ring) * 0.5 * ringMask);

    // Number in center
    int val = int(progress * 100.0);
    int d0 = int(hr_mod(float(val), 10.0));
    int d1 = int(hr_mod(float(val) / 10.0, 10.0));
    float font = drawFont(p * 60.0 - float2(-0.2, 0.0), d1);
    font = min(font, drawFont(p * 60.0 - float2(0.2, 0.0), d0));
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, font / 60.0) * 0.5);

    return col;
}

static float3 smallUI0(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;
    float w = 0.06;
    float h = 0.015;

    float border = abs(max(abs(p.x) - w, abs(p.y) - h)) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, border) * 0.3);

    // Animated fill bar
    float fillAmount = sin(iTime * 1.5) * 0.5 + 0.5;
    float fillBar = max(abs(p.x + w - fillAmount * w * 2.0) - fillAmount * w * 2.0, abs(p.y) - h + 0.003);
    fillBar = max(fillBar, -(max(abs(p.x) - w + 0.002, abs(p.y) - h + 0.002)));
    col = mix(col, float3(0.0, 1.0, 0.5) * 0.5, smoothstep(aa, 0.0, -fillBar) * 0.3);

    // Tick marks
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float xp = -w + fi * w * 0.5;
        float tick = max(abs(p.x - xp) - 0.0005, abs(p.y) - h - 0.005);
        col = mix(col, float3(1.0), smoothstep(aa, 0.0, tick) * 0.2);
    }

    return col;
}

static float3 smallUI1(float2 p, float3 col, float iTime, float aa) {
    float2 prevP = p;

    // Diamond indicator
    float size = 0.015;
    float diamond = abs(p.x) + abs(p.y) - size;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, diamond) * 0.5);

    float diamond2 = abs(abs(p.x) + abs(p.y) - size * 1.5) - 0.001;
    col = mix(col, float3(1.0), smoothstep(aa, 0.0, diamond2) * 0.3);

    // Rotating outer markers
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float a = fi * 1.5708 + iTime * 0.5;
        float2 mp = p - float2(cos(a), sin(a)) * 0.025;
        float marker = max(abs(mp.x) - 0.003, abs(mp.y) - 0.003);
        col = mix(col, float3(1.0), smoothstep(aa, 0.0, marker) * 0.4);
    }

    return col;
}

fragment float4 flighthud_fragment(VertexOut in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 iResolution = uniforms.iResolution;
    float2 fragCoord = in.uv * iResolution;
    float2 p = (fragCoord - 0.5 * iResolution) / iResolution.y;
    float2 prevP = p;
    float aa = 1.0 / min(iResolution.y, iResolution.x);

    float3 col = float3(0.0);

    col = radar(p, col, iTime, aa);
    col = grids(p, col, aa);
    col = objects(p, col, iTime, iResolution, aa);
    col = paperPlane(p, col, aa);

    col = graph0(p - float2(-0.6, 0.35), col, iTime, aa);
    col = graph1(p - float2(-0.6, -0.35), col, iTime, aa);
    col = graph2(p - float2(0.6, 0.35), col, iTime, aa);
    col = graph3(p - float2(0.6, -0.35), col, iTime, aa);

    col = smallCircleUI(p - float2(-0.64, 0.0), col, iTime, aa);
    col = smallCircleUI2(p - float2(0.64, 0.0), col, iTime, aa);

    p = abs(p);
    col = smallCircleUI3(p - float2(0.48, 0.18), col, 1.0, iTime, aa);

    p = prevP;
    p = abs(p);
    col = smallUI0(p - float2(0.32, 0.41), col, iTime, aa);

    p = prevP;
    p = abs(p);
    col = smallUI1(p - float2(0.76, 0.18), col, iTime, aa);

    return float4(sqrt(col), 1.0);
}
