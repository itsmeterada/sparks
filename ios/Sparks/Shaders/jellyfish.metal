#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Luminescence - Ported from Shadertoy
// https://www.shadertoy.com/view/4sXBRn
// Martijn Steinrucken aka BigWings - 2017 (CC BY-NC-SA 3.0)

#define J_INVERTMOUSE -1.0
#define J_MAX_STEPS 100.0
#define J_VOLUME_STEPS 8.0
#define J_MAX_DISTANCE 100.0
#define J_HIT_DISTANCE 0.01

constant float3 J_UP = float3(0.0, 1.0, 0.0);
constant float J_PI = 3.141592653589793238;
constant float J_TWOPI = 6.283185307179586;

static float j_sat(float x) { return clamp(x, 0.0, 1.0); }
static float j_SIN(float x) { return sin(x)*0.5+0.5; }
static float j_S(float a, float b, float x) { return smoothstep(a, b, x); }
static float j_B(float a, float b, float e, float x) { return j_S(a-e, a+e, x)*j_S(b+e, b-e, x); }

static float j_N1(float x) { return fract(sin(x)*5346.1764); }
static float j_N3(float3 p) {
    p = fract(p*0.3183099+0.1);
    p *= 17.0;
    return fract(p.x*p.y*p.z*(p.x+p.y+p.z));
}
static float3 j_N31(float p) {
    float3 p3 = fract(float3(p) * float3(0.1031, 0.11369, 0.13787));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract(float3((p3.x+p3.y)*p3.z, (p3.x+p3.z)*p3.y, (p3.y+p3.z)*p3.x));
}

static float j_smin(float a, float b, float k) {
    float h = clamp(0.5+0.5*(b-a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0-h);
}
static float j_smax(float a, float b, float k) {
    float h = clamp(0.5+0.5*(b-a)/k, 0.0, 1.0);
    return mix(a, b, h) + k*h*(1.0-h);
}
static float j_sdSphere(float3 p, float3 pos, float s) { return length(p-pos)-s; }

static float2 j_pModPolar(float2 p, float reps, float fix) {
    float angle = J_TWOPI/reps;
    float a = atan2(p.y, p.x) + angle/2.0;
    float r = length(p);
    a = fmod(a, angle) - (angle/2.0)*fix;
    return float2(cos(a), sin(a))*r;
}

static float j_Dist(float2 P, float2 P0, float2 P1) {
    float2 v = P1 - P0;
    float2 w = P - P0;
    float c1 = dot(w, v);
    float c2 = dot(v, v);
    if (c1 <= 0.0) return length(P-P0);
    float b = c1/c2;
    float2 Pb = P0 + b*v;
    return length(P-Pb);
}

static float2 j_sph(float3 ro, float3 rd, float3 pos, float radius) {
    float3 oc = pos - ro;
    float l = dot(rd, oc);
    float det = l*l - dot(oc, oc) + radius*radius;
    if (det < 0.0) return float2(J_MAX_DISTANCE);
    float d = sqrt(det);
    return float2(l-d, l+d);
}

static float3 j_background(float3 r, float3 bg, float iTime) {
    float x = atan2(r.x, r.z);
    float y = J_PI*0.5 - acos(r.y);
    float3 col = bg*(1.0+y);
    float t = iTime;
    float a = sin(r.x);
    float beam = j_sat(sin(10.0*x+a*y*5.0+t));
    beam *= j_sat(sin(7.0*x+a*y*3.5-t));
    float beam2 = j_sat(sin(42.0*x+a*y*21.0-t));
    beam2 *= j_sat(sin(34.0*x+a*y*17.0+t));
    beam += beam2;
    col *= 1.0+beam*0.05;
    return col;
}

static float j_remap(float a, float b, float c, float d, float t) {
    return ((t-a)/(b-a))*(d-c)+c;
}

struct j_de {
    float d;
    float m;
    float3 uv;
    float pump;
    float3 id;
    float3 pos;
};

static j_de j_map(float3 p, float3 id, float iTime) {
    float t = iTime*2.0;
    float N = j_N3(id);
    j_de o;
    o.m = 0.0;
    o.id = id;
    o.pos = float3(0.0);
    float x = (p.y+N*J_TWOPI)*1.0 + t;
    float r = 1.0;
    float pump = cos(x+cos(x))+sin(2.0*x)*0.2+sin(4.0*x)*0.02;
    x = t + N*J_TWOPI;
    p.y -= (cos(x+cos(x))+sin(2.0*x)*0.2)*0.6;
    p.xz *= 1.0 + pump*0.2;
    float d1 = j_sdSphere(p, float3(0.0), r);
    float d2 = j_sdSphere(p, float3(0.0, -0.5, 0.0), r);
    o.d = j_smax(d1, -d2, 0.1);
    o.m = 1.0;
    if (p.y < 0.5) {
        float sway = sin(t+p.y+N*J_TWOPI)*j_S(0.5, -3.0, p.y)*N*0.3;
        p.x += sway*N;
        p.z += sway*(1.0-N);
        float3 mp = p;
        mp.xz = j_pModPolar(mp.xz, 6.0, 0.0);
        float d3 = length(mp.xz-float2(0.2, 0.1)) - j_remap(0.5, -3.5, 0.1, 0.01, mp.y);
        if (d3 < o.d) o.m = 2.0;
        d3 += (sin(mp.y*10.0)+sin(mp.y*23.0))*0.03;
        float d32 = length(mp.xz-float2(0.2, 0.1)) - j_remap(0.5, -3.5, 0.1, 0.04, mp.y)*0.5;
        d3 = min(d3, d32);
        o.d = j_smin(o.d, d3, 0.5);
        if (p.y < 0.2) {
            float3 op = p;
            op.xz = j_pModPolar(op.xz, 13.0, 1.0);
            float d4 = length(op.xz-float2(0.85, 0.0)) - j_remap(0.5, -3.0, 0.04, 0.0, op.y);
            if (d4 < o.d) o.m = 3.0;
            o.d = j_smin(o.d, d4, 0.15);
        }
    }
    o.pump = pump;
    o.uv = p;
    o.d *= 0.8;
    return o;
}

static float3 j_calcNormal(float3 pos, float3 id, float iTime) {
    float3 eps = float3(0.01, 0.0, 0.0);
    float3 nor = float3(
        j_map(pos+eps.xyy, id, iTime).d - j_map(pos-eps.xyy, id, iTime).d,
        j_map(pos+eps.yxy, id, iTime).d - j_map(pos-eps.yxy, id, iTime).d,
        j_map(pos+eps.yyx, id, iTime).d - j_map(pos-eps.yyx, id, iTime).d);
    return normalize(nor);
}

struct j_rc {
    float3 id;
    float3 h;
    float3 p;
};

static j_rc j_Repeat(float3 pos, float3 size) {
    j_rc o;
    o.h = size*0.5;
    o.id = floor(pos/size);
    o.p = fmod(pos, size) - o.h;
    // fmod behaves like C fmod; need positive mod:
    o.p = pos - size*floor(pos/size) - o.h;
    return o;
}

static j_de j_CastRay(float3 ro, float3 rd, float iTime) {
    float d = 0.0;
    float3 p;
    j_rc q;
    q.id = float3(0.0); q.h = float3(0.0); q.p = float3(0.0);
    float t = iTime;
    float3 grid = float3(6.0, 30.0, 6.0);
    j_de o, s;
    s.d = J_MAX_DISTANCE;
    s.m = 0.0; s.uv = float3(0.0); s.pump = 0.0; s.id = float3(0.0); s.pos = float3(0.0);
    float dC = J_MAX_DISTANCE;

    for (float i = 0.0; i < J_MAX_STEPS; i++) {
        p = ro + rd*d;
        p.y -= t;
        p.x += t;
        q = j_Repeat(p, grid);
        float3 rC = ((2.0*step(0.0, rd)-1.0)*q.h - q.p)/rd;
        dC = min(min(rC.x, rC.y), rC.z) + 0.01;
        float N = j_N3(q.id);
        q.p += (j_N31(N)-0.5)*grid*float3(0.5, 0.7, 0.5);
        if (j_Dist(q.p.xz, rd.xz, float2(0.0)) < 1.1)
            s = j_map(q.p, q.id, iTime);
        else
            s.d = dC;
        if (s.d < J_HIT_DISTANCE || d > J_MAX_DISTANCE) break;
        d += min(s.d, dC);
    }

    if (s.d < J_HIT_DISTANCE) {
        o.m = s.m;
        o.d = d;
        o.id = q.id;
        o.uv = s.uv;
        o.pump = s.pump;
        o.pos = q.p;
    } else {
        o.m = 0.0;
        o.d = d;
        o.id = float3(0.0);
        o.uv = float3(0.0);
        o.pump = 0.0;
        o.pos = float3(0.0);
    }
    return o;
}

static float j_VolTex(float3 uv, float3 p, float scale, float pump, float iTime) {
    p.y *= scale;
    float s2 = 5.0*p.x/J_TWOPI;
    s2 = fract(s2);
    float2 ep = float2(s2-0.5, p.y-0.6);
    float ed = length(ep);
    float e = j_B(0.35, 0.45, 0.05, ed);
    float s = j_SIN(s2*J_TWOPI*15.0);
    s = s*s; s = s*s;
    s *= j_S(1.4, -0.3, uv.y-cos(s2*J_TWOPI)*0.2+0.3)*j_S(-0.6, -0.3, uv.y);
    float t = iTime*5.0;
    float mask = j_SIN(p.x*J_TWOPI*2.0 + t);
    s *= mask*mask*2.0;
    return s + e*pump*2.0;
}

static float4 j_JellyTex(float3 p) {
    float3 s = float3(atan2(p.x, p.z), length(p.xz), p.y);
    float b = 0.75 + sin(s.x*6.0)*0.25;
    b = mix(1.0, b, s.y*s.y);
    p.x += sin(s.z*10.0)*0.1;
    float b2 = cos(s.x*26.0) - s.z - 0.7;
    b2 = j_S(0.1, 0.6, b2);
    return float4(b+b2);
}

static float3 j_render(float3 ro, float3 rd, float3 camForwardDir, float iTime, float3 accent, thread float3 &bg) {
    bg = j_background(camForwardDir, bg, iTime);
    float3 col = bg;
    j_de o = j_CastRay(ro, rd, iTime);
    float3 L = J_UP;
    if (o.m > 0.0) {
        float3 n = j_calcNormal(o.pos, o.id, iTime);
        float lambert = j_sat(dot(n, L));
        float3 R = reflect(rd, n);
        float fresnel = j_sat(1.0 + dot(rd, n));
        float3 ref = j_background(R, bg, iTime);
        float fade = 0.0;
        if (o.m == 1.0) {
            float density = 0.0;
            for (float i = 0.0; i < J_VOLUME_STEPS; i++) {
                float sd = j_sph(o.uv, rd, float3(0.0), 0.8+i*0.015).x;
                if (sd != J_MAX_DISTANCE) {
                    float2 intersectPt = o.uv.xz + rd.xz*sd;
                    float3 uvv = float3(atan2(intersectPt.x, intersectPt.y), length(intersectPt.xy), o.uv.z);
                    density += j_VolTex(o.uv, uvv, 1.4+i*0.03, o.pump, iTime);
                }
            }
            float4 volTex = float4(accent, density/J_VOLUME_STEPS);
            float3 dif = j_JellyTex(o.uv).rgb;
            dif *= max(0.2, lambert);
            col = mix(col, volTex.rgb, volTex.a);
            col = mix(col, dif, 0.25);
            col += fresnel*ref*j_sat(dot(J_UP, n));
            fade = max(fade, j_S(0.0, 1.0, fresnel));
        } else if (o.m == 2.0) {
            float3 dif = accent;
            col = mix(bg, dif, fresnel);
            col *= mix(0.6, 1.0, j_S(0.0, -1.5, o.uv.y));
            float prop = o.pump + 0.25;
            prop *= prop*prop;
            col += pow(1.0-fresnel, 20.0)*dif*prop;
            fade = fresnel;
        } else if (o.m == 3.0) {
            float3 dif = accent;
            float dd = j_S(100.0, 13.0, o.d);
            col = mix(bg, dif, pow(1.0-fresnel, 5.0)*dd);
        }
        fade = max(fade, j_S(0.0, 100.0, o.d));
        col = mix(col, bg, fade);
    } else {
        col = bg;
    }
    return col;
}

fragment float4 jellyfish_fragment(VertexOut in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    float2 iRes = uniforms.iResolution;
    float iTime = uniforms.iTime;
    float4 iMouse = uniforms.iMouse;
    float2 fragCoord = in.uv * iRes;

    float t = iTime*0.04;
    float2 uv = fragCoord / iRes;
    uv -= 0.5;
    uv.y *= iRes.y/iRes.x;

    float2 m = iMouse.xy/iRes;
    if (m.x < 0.05 || m.x > 0.95) {
        m = float2(t*0.25, j_SIN(t*J_PI)*0.5+0.5);
    }

    float3 accentColor1 = float3(1.0, 0.1, 0.5);
    float3 secondColor1 = float3(0.1, 0.5, 1.0);
    float3 accentColor2 = float3(1.0, 0.5, 0.1);
    float3 secondColor2 = float3(0.1, 0.5, 0.6);
    float3 accent = mix(accentColor1, accentColor2, j_SIN(t*15.456));
    float3 bg = mix(secondColor1, secondColor2, j_SIN(t*7.345231));

    float turn = (0.1 - m.x)*J_TWOPI;
    float s = sin(turn);
    float c = cos(turn);
    float3x3 rotX = float3x3(
        float3(c, 0.0, s),
        float3(0.0, 1.0, 0.0),
        float3(s, 0.0, -c));

    float camDist = -0.1;
    float3 lookAt = float3(0.0, -1.0, 0.0);
    float3 camPosRel = float3(0.0, J_INVERTMOUSE*camDist*cos(m.y*J_PI), camDist) * rotX;
    float3 camPos = camPosRel + lookAt;

    float3 forward = normalize(lookAt - camPos);
    float3 left = cross(J_UP, forward);
    float3 camUp = cross(forward, left);
    float3 center = camPos + forward*1.0;
    float3 iPt = center + left*uv.x + camUp*uv.y;
    float3 rd = normalize(iPt - camPos);

    float3 col = j_render(camPos, rd, rd, iTime, accent, bg);
    col = pow(col, float3(mix(1.5, 2.6, j_SIN(t+J_PI))));
    float d = 1.0 - dot(uv, uv);
    col *= (d*d*d) + 0.1;
    return float4(col, 1.0);
}
