#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Chrome Metaball - Ported from Shadertoy
// https://www.shadertoy.com/view/7dtSDf
// License: CC BY-NC-SA 3.0

constant float PI = 3.14159;
constant float DEG2RAD = PI / 180.0;

#define S(x, y, z) smoothstep(x, y, z)

static float2x2 rot2D(float angle) {
    float ca = cos(angle), sa = sin(angle);
    return float2x2(float2(ca, -sa), float2(sa, ca));
}
static float3x3 lookAtMatrix(float3 dir) {
    float3 ww = normalize(dir);
    float3 uu = cross(ww, float3(0, 1, 0));
    float3 vv = cross(uu, ww);
    return float3x3(uu, vv, -ww);
}

static float4 linearTosRGB(float4 c) {
    bool4 cutoff = c < float4(0.0031308);
    float4 higher = float4(1.055) * pow(c, float4(1.0/2.4)) - float4(0.055);
    float4 lower = c * float4(12.92);
    return select(higher, lower, cutoff);
}
static float4 ACESFilm(float4 x) {
    float a=2.51, b=0.03, c=2.43, d=0.59, e=0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
}
static float mb_smin(float a, float b, float k) {
    float h = clamp(0.5+0.5*(b-a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0-h);
}
static float sdSphere(float3 p, float r) { return length(p) - r; }

struct MBHit { int id; float d; };
struct MBTrace { int id; float d; float3 ro; float3 rd; };
struct MBLight { float3 direction; float3 ambient; float3 color; };
struct MBSurface { int materialId; float dist; float3 p; float3 n; float ao; float3 rd; };
struct MBMaterial { float3 albedo; float metallic; float roughness; float3 emissive; float ao; };
struct MBCamera { float3 position; float3 direction; };
struct MBLightingResult { MBMaterial mat; float3 color; };

static MBHit mb_hmin(MBHit a, MBHit b) { return a.d < b.d ? a : b; }
static MBHit mb_hsmin(MBHit a, MBHit b, float k) {
    MBHit h = mb_hmin(a, b);
    h.d = mb_smin(a.d, b.d, k);
    return h;
}

// PBR
static float3 F_Schlick(float HoV, float3 f0) {
    return f0 + (float3(1) - f0) * pow(1.0 - HoV, 5.0);
}
static float D_GGX(float NoH, float a) {
    float a2 = a*a;
    float f = (NoH*a2 - NoH)*NoH + 1.0;
    return a2 / (PI * f * f);
}
static float V_SmithGGX(float NoV, float NoL, float a) {
    float a2 = a*a;
    float GGL = NoL * sqrt(NoV*NoV*(1.0-a2)+a2);
    float GGV = NoV * sqrt(NoL*NoL*(1.0-a2)+a2);
    return 0.5 / (GGL + GGV);
}

static float3 mb_BRDF(MBLight l, MBSurface surf, MBMaterial mat) {
    float3 V = -surf.rd, N = surf.n, L = l.direction;
    float3 H = normalize(V + L);
    float NoV = max(dot(N,V), 0.0);
    float NoL = max(dot(N,L), 0.0);
    float NoH = max(dot(N,H), 0.0);
    float HoV = max(dot(H,V), 0.0);
    float a = mat.roughness * mat.roughness;
    float3 F0 = mix(float3(0.04), mat.albedo, mat.metallic);
    float3 F = F_Schlick(HoV, F0);
    float D = D_GGX(NoH, a);
    float Vis = V_SmithGGX(NoV, NoL, a);
    float3 spec = F * (Vis * D);
    float3 kD = float3(1) - F;
    float3 c_diff = mix(mat.albedo * (1.0 - float3(0.04)), float3(0), mat.metallic);
    float3 diff = kD * (c_diff / PI);
    return l.ambient * mat.albedo + mat.emissive + l.color * NoL * (diff + spec);
}

static float3 mb_calcLights(MBSurface s, MBMaterial m) {
    MBLight l0; l0.direction = normalize(float3(1,1,0)); l0.ambient = float3(0.01); l0.color = float3(3.0);
    MBLight l1; l1.direction = normalize(float3(-1,1,0)); l1.ambient = float3(0.01); l1.color = float3(3.0);
    return max(mb_BRDF(l0,s,m), float3(0)) + max(mb_BRDF(l1,s,m), float3(0));
}

static MBHit mb_ground(float3 p) {
    return MBHit{0, -(length(p - float3(0, 198.8, 0)) - 200.0)};
}

static MBHit mb_metaBall(float3 p, float iTime) {
    float at = fmod(iTime, 11.0);
    #define MB_A(v1,v2,t1,t2) mix(v1,v2,S(t1,t2,at))
    float3 q = p;
    q.y += MB_A(cos(at * PI) * 1.0 + 1.7, 0.0, 0.0, 4.0);
    if (at > 10.0) { float t = at - 10.0; q.y += -2.5*t + 0.5*10.0*t*t; }
    q.xz = q.xz * rot2D(q.y);
    float3 sc = MB_A(float3(1), float3(0.5, 1.0, 0.5), 10., 11.);
    q *= sc;
    float r = 1.0;
    r = MB_A(r, 0.2, 10., 10.5);
    float amp = 0.1;
    amp = MB_A(amp, sin(at * 30.0) * .05 + 0.1, 8.0, 10.);
    amp = MB_A(amp, 1., 10., 10.5);
    r += amp * sin(q.x*8.0+at*5.0) * sin(q.y*8.0) * sin(q.z*8.0);
    float sphere = sdSphere(q, r);
    float def = MB_A(0.7, 0.3, 10., 10.5);
    sphere *= def;
    #undef MB_A
    return MBHit{1, sphere};
}

static MBHit mb_map(float3 p, float iTime) {
    float at = fmod(iTime, 11.0);
    #define MB_A2(v1,v2,t1,t2) mix(v1,v2,S(t1,t2,at))
    float blend = MB_A2(0.5, 0.0, 0.0, 8.0);
    blend = MB_A2(blend, 0.5, 10.0, 11.0);
    #undef MB_A2
    return mb_hsmin(mb_metaBall(p, iTime), mb_ground(p), blend);
}

static float3 mb_normal(float3 p, float iTime) {
    float2 e = float2(0.01, 0.0);
    float d = mb_map(p, iTime).d;
    return normalize(float3(
        d - mb_map(p - e.xyy, iTime).d,
        d - mb_map(p - e.yxy, iTime).d,
        d - mb_map(p - e.yyx, iTime).d
    ));
}

constant float MB_SURF = 0.01;
constant float MB_FAR = 20.0;
constant int MB_STEPS = 128;

static MBTrace mb_trace(float3 ro, float3 rd, float iTime) {
    float d = 0.0;
    float closestD = MB_FAR;
    MBHit closest = MBHit{-1, MB_FAR};
    for (int i=0; i < MB_STEPS && d < MB_FAR; i++) {
        float3 p = ro + rd * d;
        MBHit h = mb_map(p, iTime);
        if (h.d < closest.d) { closest = h; closestD = d; }
        if (h.d <= MB_SURF) return MBTrace{closest.id, d, ro, rd};
        d += h.d;
    }
    if (d >= MB_FAR) return MBTrace{-1, MB_FAR, ro, rd};
    return MBTrace{-2, closestD, ro, rd};
}

static MBSurface mb_getSurf(MBTrace tr, float iTime) {
    float3 p = tr.ro + tr.rd * tr.d;
    float3 n = mb_normal(p, iTime);
    return MBSurface{tr.id, tr.d, p, n, 0.0, tr.rd};
}

static MBTrace mb_traceRefl(MBSurface s, float iTime) {
    float3 ro = s.p + s.n * MB_SURF * 2.0;
    float3 rd = reflect(s.rd, s.n);
    float d = MB_SURF * 2.0;
    for (int i=0; i < MB_STEPS && d < MB_FAR; i++) {
        float3 p = ro + rd * d;
        MBHit h = mb_map(p, iTime);
        if (h.d < MB_SURF) return MBTrace{h.id, d, ro, rd};
        d += h.d;
    }
    return MBTrace{-1, MB_FAR, ro, rd};
}

static MBMaterial mb_matFromSurf(MBSurface s) {
    MBMaterial m;
    m.albedo = float3(0); m.emissive = float3(0); m.roughness = 1.0; m.metallic = 0.0; m.ao = s.ao;
    if (s.materialId == -1) { m.albedo = float3(0.01); m.roughness = 0.85; }
    else if (s.materialId == 0) { m.albedo = float3(0.01); m.roughness = 0.0; }
    else if (s.materialId == 1) { m.albedo = float3(0.1); m.roughness = 0.1; m.metallic = 1.0; }
    else { m.emissive = float3(1, 0, 1); }
    return m;
}

static MBLightingResult mb_surfLight(thread MBSurface& s) {
    if (s.materialId == -1) {
        s.p.y += 1.1;
        float3 n = normalize(s.p);
        MBSurface floorS = MBSurface{0, s.dist, s.p, float3(0,1,0), s.ao, s.rd};
        MBMaterial floorM = mb_matFromSurf(s);
        float3 floorColor = mb_calcLights(floorS, floorM);
        float floorBlend = S(-0.2, 1.2, n.y);
        MBMaterial m = mb_matFromSurf(s);
        s.n = n; m.roughness = 1.0;
        float3 color = mix(floorColor, float3(0), floorBlend);
        return MBLightingResult{m, color};
    } else if (s.materialId == 0) {
        MBMaterial m = mb_matFromSurf(s);
        return MBLightingResult{m, mb_calcLights(s, m)};
    } else if (s.materialId == 1) {
        MBSurface floorS = MBSurface{0, s.dist, s.p, s.n, s.ao, s.rd};
        MBMaterial floorM = mb_matFromSurf(floorS);
        float3 floorColor = mb_calcLights(floorS, floorM);
        MBMaterial m = mb_matFromSurf(s);
        float3 ballColor = mb_calcLights(s, m);
        float blend = S(-1.1, -0.9, s.p.y);
        float3 color = mix(floorColor, ballColor, blend);
        m.metallic = mix(floorM.metallic, m.metallic, blend);
        m.roughness = mix(floorM.roughness, m.roughness, blend);
        return MBLightingResult{m, color};
    } else {
        MBMaterial m = mb_matFromSurf(s);
        return MBLightingResult{m, mb_calcLights(s, m)};
    }
}

static float3 mb_lighting(MBSurface s, float iTime) {
    MBLightingResult cur = mb_surfLight(s);
    float3 color = cur.color;
    float extinction = 1.0;
    for (int i = 0; i < 5; i++) {
        MBTrace rh = mb_traceRefl(s, iTime);
        s = mb_getSurf(rh, iTime);
        float refAmt = 1.0 - cur.mat.roughness;
        extinction *= refAmt;
        cur = mb_surfLight(s);
        color += extinction * clamp(cur.color, 0.0, 1.0) * 0.6;
    }
    return color;
}

static MBCamera mb_createOrbitCam(float2 uv, float2 mouse, float2 res, float fov,
                                   float3 target, float height, float dist) {
    float halfFov = fov * 0.5;
    float zoom = cos(halfFov) / sin(halfFov);
    float3 pos = target + float3(0, height, 0) + float3(sin(mouse.x), 0, cos(mouse.x)) * dist;
    float3 dir = normalize(float3(uv, -zoom));
    dir.yz = rot2D(-mouse.y) * dir.yz;
    dir = lookAtMatrix(target - pos) * dir;
    return MBCamera{pos, dir};
}

fragment float4 metalball_fragment(VertexOut in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 iRes = uniforms.iResolution;
    float2 fragCoord = in.uv * iRes;
    float2 uv = fragCoord / iRes;
    float2 screen = uv * 2.0 - 1.0;
    screen.x *= iRes.x / iRes.y;

    float at = fmod(iTime, 11.0);
    #define MB_A(v1,v2,t1,t2) mix(v1,v2,S(t1,t2,at))

    float xCam = MB_A(0.0, -0.2, 0.0, 3.0);
    xCam = MB_A(xCam, -0.65, 0.0, 9.0);
    xCam = MB_A(xCam, -0.95, 8.5, 10.0);
    xCam = MB_A(xCam, -1.0, 10.0, 11.0);

    float yCam = MB_A(-0.25, -0.08, 0.3, 1.0);
    yCam = MB_A(yCam, -0.3, 0.5, 2.5);
    yCam = MB_A(yCam, -0.08, 0.5, 3.0);
    yCam = MB_A(yCam, -0.06, 4.0, 10.0);
    yCam = MB_A(yCam, 0.15, 10.0, 10.5);
    yCam = MB_A(yCam, -0.25, 10.0, 11.0);

    float camDist = MB_A(1.5, 5.5, 0.0, 2.0);
    camDist = MB_A(camDist, 3.5, 0.0, 3.0);
    camDist = MB_A(camDist, 4.0, 3.0, 5.0);
    camDist = MB_A(camDist, 4.5, 4.0, 7.0);
    camDist = MB_A(camDist, 3.5, 7.0, 10.0);
    camDist = MB_A(camDist, 2.0, 9.5, 10.5);
    camDist = MB_A(camDist, 2.5, 10.0, 11.);

    #undef MB_A

    MBCamera cam = mb_createOrbitCam(screen, float2(xCam, yCam) * PI, iRes,
                                      60.0 * DEG2RAD, float3(0, 0.5, 0), 0.0, camDist);
    float3 ro = cam.position;
    float3 rd = cam.direction;

    MBTrace tr = mb_trace(ro, rd, iTime);
    MBSurface s = mb_getSurf(tr, iTime);

    float4 col = float4(mb_lighting(s, iTime), 1.0);
    col = ACESFilm(col);
    col = linearTosRGB(col);
    return col;
}
