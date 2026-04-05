#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Rainforest - Ported from Shadertoy (single-pass, no temporal reprojection)
// https://www.shadertoy.com/view/4ttSWf
// Original Author: Inigo Quilez - 2016
// License: Educational use only (see original for full terms)

#define LOWQUALITY

//==========================================================================================
// file-scope constants
//==========================================================================================

constant float3 rf_kSunDir = float3(-0.624695, 0.468521, -0.624695);
constant float  rf_kMaxTreeHeight = 4.8;
constant float  rf_kMaxHeight = 840.0;

// GLSL mat3(col0, col1, col2) — columns left to right
// mat3( 0.00,  0.80,  0.60,
//      -0.80,  0.36, -0.48,
//      -0.60, -0.48,  0.64 )
// columns: (0.00, 0.80, 0.60), (-0.80, 0.36, -0.48), (-0.60, -0.48, 0.64)
constant float3x3 rf_m3  = float3x3(float3( 0.00,  0.80,  0.60),
                                     float3(-0.80,  0.36, -0.48),
                                     float3(-0.60, -0.48,  0.64));
constant float3x3 rf_m3i = float3x3(float3( 0.00, -0.80, -0.60),
                                     float3( 0.80,  0.36, -0.48),
                                     float3( 0.60, -0.48,  0.64));
constant float2x2 rf_m2  = float2x2(float2( 0.80,  0.60),
                                     float2(-0.60,  0.80));
constant float2x2 rf_m2i = float2x2(float2( 0.80, -0.60),
                                     float2( 0.60,  0.80));

//==========================================================================================
// general utilities
//==========================================================================================

static float rf_sdEllipsoidY(float3 p, float2 r)
{
    float k0 = length(p / r.xyx);
    float k1 = length(p / (r.xyx * r.xyx));
    return k0 * (k0 - 1.0) / k1;
}

static float2 rf_smoothstepd(float a, float b, float x)
{
    if (x < a) return float2(0.0, 0.0);
    if (x > b) return float2(1.0, 0.0);
    float ir = 1.0 / (b - a);
    x = (x - a) * ir;
    return float2(x * x * (3.0 - 2.0 * x), 6.0 * x * (1.0 - x) * ir);
}

static float3x3 rf_setCamera(float3 ro, float3 ta, float cr)
{
    float3 cw = normalize(ta - ro);
    float3 cp = float3(sin(cr), cos(cr), 0.0);
    float3 cu = normalize(cross(cw, cp));
    float3 cv = normalize(cross(cu, cw));
    return float3x3(cu, cv, cw);
}

//==========================================================================================
// hashes
//==========================================================================================

static float rf_hash1(float2 p)
{
    p = 50.0 * fract(p * 0.3183099);
    return fract(p.x * p.y * (p.x + p.y));
}

static float rf_hash1(float n)
{
    return fract(n * 17.0 * fract(n * 0.3183099));
}

static float2 rf_hash2(float2 p)
{
    float2 k = float2(0.3183099, 0.3678794);
    float n = 111.0 * p.x + 113.0 * p.y;
    return fract(n * fract(k * n));
}

//==========================================================================================
// noises
//==========================================================================================

// noised(vec3) -> vec4
static float4 rf_noised3(float3 x)
{
    float3 p = floor(x);
    float3 w = fract(x);
    float3 u = w * w * w * (w * (w * 6.0 - 15.0) + 10.0);
    float3 du = 30.0 * w * w * (w * (w - 2.0) + 1.0);

    float n = p.x + 317.0 * p.y + 157.0 * p.z;

    float a = rf_hash1(n + 0.0);
    float b = rf_hash1(n + 1.0);
    float c = rf_hash1(n + 317.0);
    float d = rf_hash1(n + 318.0);
    float e = rf_hash1(n + 157.0);
    float f = rf_hash1(n + 158.0);
    float g = rf_hash1(n + 474.0);
    float h = rf_hash1(n + 475.0);

    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   e - a;
    float k4 =   a - b - c + d;
    float k5 =   a - c - e + g;
    float k6 =   a - b - e + f;
    float k7 = - a + b + c - d + e - f - g + h;

    return float4(-1.0 + 2.0 * (k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z),
                  2.0 * du * float3(k1 + k4*u.y + k6*u.z + k7*u.y*u.z,
                                    k2 + k5*u.z + k4*u.x + k7*u.z*u.x,
                                    k3 + k6*u.x + k5*u.y + k7*u.x*u.y));
}

// noise(vec3) -> float
static float rf_noise3(float3 x)
{
    float3 p = floor(x);
    float3 w = fract(x);
    float3 u = w * w * w * (w * (w * 6.0 - 15.0) + 10.0);

    float n = p.x + 317.0 * p.y + 157.0 * p.z;

    float a = rf_hash1(n + 0.0);
    float b = rf_hash1(n + 1.0);
    float c = rf_hash1(n + 317.0);
    float d = rf_hash1(n + 318.0);
    float e = rf_hash1(n + 157.0);
    float f = rf_hash1(n + 158.0);
    float g = rf_hash1(n + 474.0);
    float h = rf_hash1(n + 475.0);

    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   e - a;
    float k4 =   a - b - c + d;
    float k5 =   a - c - e + g;
    float k6 =   a - b - e + f;
    float k7 = - a + b + c - d + e - f - g + h;

    return -1.0 + 2.0 * (k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z);
}

// noised(vec2) -> vec3
static float3 rf_noised2(float2 x)
{
    float2 p = floor(x);
    float2 w = fract(x);
    float2 u = w * w * w * (w * (w * 6.0 - 15.0) + 10.0);
    float2 du = 30.0 * w * w * (w * (w - 2.0) + 1.0);

    float a = rf_hash1(p + float2(0, 0));
    float b = rf_hash1(p + float2(1, 0));
    float c = rf_hash1(p + float2(0, 1));
    float d = rf_hash1(p + float2(1, 1));

    float k0 = a;
    float k1 = b - a;
    float k2 = c - a;
    float k4 = a - b - c + d;

    return float3(-1.0 + 2.0 * (k0 + k1*u.x + k2*u.y + k4*u.x*u.y),
                  2.0 * du * float2(k1 + k4*u.y, k2 + k4*u.x));
}

// noise(vec2) -> float
static float rf_noise2(float2 x)
{
    float2 p = floor(x);
    float2 w = fract(x);
    float2 u = w * w * w * (w * (w * 6.0 - 15.0) + 10.0);

    float a = rf_hash1(p + float2(0, 0));
    float b = rf_hash1(p + float2(1, 0));
    float c = rf_hash1(p + float2(0, 1));
    float d = rf_hash1(p + float2(1, 1));

    return -1.0 + 2.0 * (a + (b - a)*u.x + (c - a)*u.y + (a - b - c + d)*u.x*u.y);
}

//==========================================================================================
// fbm constructions
//==========================================================================================

static float rf_fbm_4_2(float2 x)
{
    float f = 1.9, s = 0.55, a = 0.0, b = 0.5;
    for (int i = 0; i < 4; i++) { float n = rf_noise2(x); a += b*n; b *= s; x = f * rf_m2 * x; }
    return a;
}

static float rf_fbm_4_3(float3 x)
{
    float f = 2.0, s = 0.5, a = 0.0, b = 0.5;
    for (int i = 0; i < 4; i++) { float n = rf_noise3(x); a += b*n; b *= s; x = f * rf_m3 * x; }
    return a;
}

static float4 rf_fbmd_7(float3 x)
{
    float f = 1.92, s = 0.5, a = 0.0, b = 0.5;
    float3 d = float3(0.0);
    float3x3 m = float3x3(float3(1,0,0), float3(0,1,0), float3(0,0,1));
    for (int i = 0; i < 7; i++) { float4 n = rf_noised3(x); a += b*n.x; d += b * m * n.yzw; b *= s; x = f * rf_m3 * x; m = f * rf_m3i * m; }
    return float4(a, d);
}

static float4 rf_fbmd_8(float3 x)
{
    float f = 2.0, s = 0.65, a = 0.0, b = 0.5;
    float3 d = float3(0.0);
    float3x3 m = float3x3(float3(1,0,0), float3(0,1,0), float3(0,0,1));
    for (int i = 0; i < 8; i++) { float4 n = rf_noised3(x); a += b*n.x; if(i<4) d += b * m * n.yzw; b *= s; x = f * rf_m3 * x; m = f * rf_m3i * m; }
    return float4(a, d);
}

static float rf_fbm_9(float2 x)
{
    float f = 1.9, s = 0.55, a = 0.0, b = 0.5;
    for (int i = 0; i < 9; i++) { float n = rf_noise2(x); a += b*n; b *= s; x = f * rf_m2 * x; }
    return a;
}

static float3 rf_fbmd_9(float2 x)
{
    float f = 1.9, s = 0.55, a = 0.0, b = 0.5;
    float2 d = float2(0.0);
    float2x2 m = float2x2(float2(1,0), float2(0,1));
    for (int i = 0; i < 9; i++) { float3 n = rf_noised2(x); a += b*n.x; d += b * m * n.yz; b *= s; x = f * rf_m2 * x; m = f * rf_m2i * m; }
    return float3(a, d);
}

//==========================================================================================
// specifics to the actual painting
//==========================================================================================

static float3 rf_fog(float3 col, float t)
{
    float3 ext = exp2(-t * 0.00025 * float3(1, 1.5, 4));
    return col * ext + (1.0 - ext) * float3(0.55, 0.55, 0.58);
}

//------------------------------------------------------------------------------------------
// clouds
//------------------------------------------------------------------------------------------

static float4 rf_cloudsFbm(float3 pos, float iTime)
{
    return rf_fbmd_8(pos * 0.0015 + float3(2.0, 1.1, 1.0) + 0.07 * float3(iTime, 0.5 * iTime, -0.15 * iTime));
}

static float rf_cloudsShadowFlat(float3 ro, float3 rd, float iTime)
{
    float t = (900.0 - ro.y) / rd.y;
    if (t < 0.0) return 1.0;
    float3 pos = ro + rd * t;
    return rf_cloudsFbm(pos, iTime).x;
}

//------------------------------------------------------------------------------------------
// terrain
//------------------------------------------------------------------------------------------

static float2 rf_terrainMap(float2 p)
{
    float e = rf_fbm_9(p / 2000.0 + float2(1.0, -2.0));
    float a = 1.0 - smoothstep(0.12, 0.13, abs(e + 0.12));
    e = 600.0 * e + 600.0;
    e += 90.0 * smoothstep(552.0, 594.0, e);
    return float2(e, a);
}

static float4 rf_terrainMapD(float2 p)
{
    float3 e = rf_fbmd_9(p / 2000.0 + float2(1.0, -2.0));
    e.x = 600.0 * e.x + 600.0;
    e.yz = 600.0 * e.yz;
    float2 c = rf_smoothstepd(550.0, 600.0, e.x);
    e.x  = e.x  + 90.0 * c.x;
    e.yz = e.yz + 90.0 * c.y * e.yz;
    e.yz /= 2000.0;
    return float4(e.x, normalize(float3(-e.y, 1.0, -e.z)));
}

static float3 rf_terrainNormal(float2 pos)
{
    return rf_terrainMapD(pos).yzw;
}

static float rf_terrainShadow(float3 ro, float3 rd, float mint)
{
    float res = 1.0;
    float t = mint;
    for (int i = 0; i < 32; i++)
    {
        float3 pos = ro + t * rd;
        float2 env = rf_terrainMap(pos.xz);
        float hei = pos.y - env.x;
        res = min(res, 32.0 * hei / t);
        if (res < 0.0001 || pos.y > rf_kMaxHeight) break;
        t += clamp(hei, 2.0 + t * 0.1, 100.0);
    }
    return clamp(res, 0.0, 1.0);
}

static float2 rf_raymarchTerrain(float3 ro, float3 rd, float tmin, float tmax)
{
    float tp = (rf_kMaxHeight + rf_kMaxTreeHeight - ro.y) / rd.y;
    if (tp > 0.0) tmax = min(tmax, tp);

    float dis, th;
    float t2 = -1.0;
    float t = tmin;
    float ot = t;
    float odis = 0.0;
    float odis2 = 0.0;
    for (int i = 0; i < 400; i++)
    {
        th = 0.001 * t;
        float3 pos = ro + t * rd;
        float2 env = rf_terrainMap(pos.xz);
        float hei = env.x;

        float dis2 = pos.y - (hei + rf_kMaxTreeHeight * 1.1);
        if (dis2 < th)
        {
            if (t2 < 0.0)
            {
                t2 = ot + (th - odis2) * (t - ot) / (dis2 - odis2);
            }
        }
        odis2 = dis2;

        dis = pos.y - hei;
        if (dis < th) break;

        ot = t;
        odis = dis;
        t += dis * 0.8 * (1.0 - 0.75 * env.y);
        if (t > tmax) break;
    }

    if (t > tmax) t = -1.0;
    else t = ot + (th - odis) * (t - ot) / (dis - odis);

    return float2(t, t2);
}

//------------------------------------------------------------------------------------------
// trees
//------------------------------------------------------------------------------------------

static float rf_treesMap(float3 p, float rt, thread float &oHei, thread float &oMat, thread float &oDis)
{
    oHei = 1.0;
    oDis = 0.0;
    oMat = 0.0;

    float base = rf_terrainMap(p.xz).x;

    float bb = rf_fbm_4_2(p.xz * 0.075);

    float d = 20.0;
    float2 n = floor(p.xz / 2.0);
    float2 f = fract(p.xz / 2.0);
    for (int j = 0; j <= 1; j++)
    for (int i = 0; i <= 1; i++)
    {
        float2 g = float2(float(i), float(j)) - step(f, float2(0.5));
        float2 o = rf_hash2(n + g);
        float2 v = rf_hash2(n + g + float2(13.1, 71.7));
        float2 r = g - f + o;

        float height = rf_kMaxTreeHeight * (0.4 + 0.8 * v.x);
        float width = 0.5 + 0.2 * v.x + 0.3 * v.y;

        if (bb < 0.0) width *= 0.5; else height *= 0.7;

        float3 q = float3(r.x, p.y - base - height * 0.5, r.y);

        float k = rf_sdEllipsoidY(q, float2(width, 0.5 * height));

        if (k < d)
        {
            d = k;
            oMat = 0.5 * rf_hash1(n + g + 111.0);
            if (bb > 0.0) oMat += 0.5;
            oHei = (p.y - base) / height;
            oHei *= 0.5 + 0.5 * length(q) / width;
        }
    }

    if (rt < 1200.0)
    {
        float3 pp = p;
        pp.y -= 600.0;
        float s = rf_fbm_4_3(pp * 3.0);
        s = s * s;
        float att = 1.0 - smoothstep(100.0, 1200.0, rt);
        d += 4.0 * s * att;
        oDis = s * att;
    }

    return d;
}

static float rf_treesShadow(float3 ro, float3 rd)
{
    float res = 1.0;
    float t = 0.02;
    for (int i = 0; i < 64; i++)
    {
        float kk1, kk2, kk3;
        float3 pos = ro + rd * t;
        float h = rf_treesMap(pos, t, kk1, kk2, kk3);
        res = min(res, 32.0 * h / t);
        t += h;
        if (res < 0.001 || t > 50.0 || pos.y > rf_kMaxHeight + rf_kMaxTreeHeight) break;
    }
    return clamp(res, 0.0, 1.0);
}

static float3 rf_treesNormal(float3 pos, float t)
{
    float kk1, kk2, kk3;
    float3 n = float3(0.0);
    for (int i = 0; i < 4; i++)
    {
        float3 e = 0.5773 * (2.0 * float3((((i+3)>>1)&1), ((i>>1)&1), (i&1)) - 1.0);
        n += e * rf_treesMap(pos + 0.005 * e, t, kk1, kk2, kk3);
    }
    return normalize(n);
}

//------------------------------------------------------------------------------------------
// clouds (render)
//------------------------------------------------------------------------------------------

static float4 rf_renderClouds(float3 ro, float3 rd, float tmin, float tmax, thread float &resT, float iTime)
{
    float4 sum = float4(0.0);

    float tl = ( 600.0 - ro.y) / rd.y;
    float th = (1200.0 - ro.y) / rd.y;
    if (tl > 0.0) tmin = max(tmin, tl); else return sum;
    if (th > 0.0) tmax = min(tmax, th);

    float t = tmin;
    float lastT = -1.0;
    float thickness = 0.0;
    for (int i = 0; i < 128; i++)
    {
        float3 pos = ro + t * rd;
        float d = abs(pos.y - 900.0) - 40.0;
        float3 gra = float3(0.0, sign(pos.y - 900.0), 0.0);
        float4 n = rf_cloudsFbm(pos, iTime);
        d += 400.0 * n.x * (0.7 + 0.3 * gra.y);

        float dt = max(0.2, 0.011 * t);

        if (d < 0.0)
        {
            float nnd = -d;
            float den = min(-d / 100.0, 0.25);

            if (den > 0.001)
            {
                float kk;
                // shadow sample
                float3 spos = pos + rf_kSunDir * 70.0;
                float sd = abs(spos.y - 900.0) - 40.0;
                float4 sn = rf_cloudsFbm(spos, iTime);
                sd += 400.0 * sn.x * (0.7 + 0.3 * sign(spos.y - 900.0));
                kk = -sd;

                float sha = 1.0 - smoothstep(-200.0, 200.0, kk); sha *= 1.5;

                float3 nor = normalize(gra);
                float dif = clamp(0.4 + 0.6 * dot(nor, rf_kSunDir), 0.0, 1.0) * sha;
                float fre = clamp(1.0 + dot(nor, rd), 0.0, 1.0) * sha;
                float occ = 0.2 + 0.7 * max(1.0 - kk / 200.0, 0.0) + 0.1 * (1.0 - den);

                float3 lin = float3(0.0);
                lin += float3(0.70, 0.80, 1.00) * 1.0 * (0.5 + 0.5 * nor.y) * occ;
                lin += float3(0.10, 0.40, 0.20) * 1.0 * (0.5 - 0.5 * nor.y) * occ;
                lin += float3(1.00, 0.95, 0.85) * 3.0 * dif * occ + 0.1;

                float3 col = float3(0.8, 0.8, 0.8) * 0.45;
                col *= lin;
                col = rf_fog(col, t);

                float alp = clamp(den * 0.5 * 0.125 * dt, 0.0, 1.0);
                col.rgb *= alp;
                sum = sum + float4(col, alp) * (1.0 - sum.a);
                thickness += dt * den;
                if (lastT < 0.0) lastT = t;
            }
        }
        else
        {
            dt = abs(d) + 0.2;
        }
        t += dt;
        if (sum.a > 0.995 || t > tmax) break;
    }

    if (lastT > 0.0) resT = min(resT, lastT);
    sum.xyz += max(0.0, 1.0 - 0.0125 * thickness) * float3(1.00, 0.60, 0.40) * 0.3 * pow(clamp(dot(rf_kSunDir, rd), 0.0, 1.0), 32.0);

    return clamp(sum, 0.0, 1.0);
}

//------------------------------------------------------------------------------------------
// sky
//------------------------------------------------------------------------------------------

static float3 rf_renderSky(float3 ro, float3 rd)
{
    float3 col = float3(0.42, 0.62, 1.1) - rd.y * 0.4;

    float t = (2500.0 - ro.y) / rd.y;
    if (t > 0.0)
    {
        float2 uv = (ro + t * rd).xz;
        float cl = rf_fbm_9(uv * 0.00104);
        float dl = smoothstep(-0.2, 0.6, cl);
        col = mix(col, float3(1.0), 0.12 * dl);
    }

    float sun = clamp(dot(rf_kSunDir, rd), 0.0, 1.0);
    col += 0.2 * float3(1.0, 0.6, 0.3) * pow(sun, 32.0);

    return col;
}

//==========================================================================================
// fragment entry point
//==========================================================================================

fragment float4 rainforest_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(0)]])
{
    float2 fragCoord = in.uv * uniforms.iResolution;
    float iTime = uniforms.iTime;

    // no jitter in single-frame mode
    float2 o = float2(0.0);
    float2 p = (2.0 * (fragCoord + o) - uniforms.iResolution) / uniforms.iResolution.y;

    // camera
    float time = iTime;
    float3 ro = float3(0.0, 401.5, 6.0);
    float3 ta = float3(0.0, 403.5, -90.0 + ro.z);

    ro.x -= 80.0 * sin(0.01 * time);
    ta.x -= 86.0 * sin(0.01 * time);

    float3x3 ca = rf_setCamera(ro, ta, 0.0);
    float3 rd = ca * normalize(float3(p, 1.5));

    float resT = 2000.0;

    // sky
    float3 col = rf_renderSky(ro, rd);

    // raycast terrain and tree envelope
    float tmax = 2000.0;
    int obj = 0;
    float2 tt = rf_raymarchTerrain(ro, rd, 15.0, tmax);
    if (tt.x > 0.0)
    {
        resT = tt.x;
        obj = 1;
    }

    // raycast trees
    float hei, mid, displa;
    if (tt.y > 0.0)
    {
        float tf = tt.y;
        float tfMax = (tt.x > 0.0) ? tt.x : tmax;
        for (int i = 0; i < 64; i++)
        {
            float3 pos = ro + tf * rd;
            float dis = rf_treesMap(pos, tf, hei, mid, displa);
            if (dis < (0.000125 * tf)) break;
            tf += dis;
            if (tf > tfMax) break;
        }
        if (tf < tfMax)
        {
            resT = tf;
            obj = 2;
        }
    }

    // shade
    if (obj > 0)
    {
        float3 pos  = ro + resT * rd;
        float3 epos = pos + float3(0.0, 4.8, 0.0);

        float sha1  = rf_terrainShadow(pos + float3(0, 0.02, 0), rf_kSunDir, 0.02);
        sha1 *= smoothstep(-0.325, -0.075, rf_cloudsShadowFlat(epos, rf_kSunDir, iTime));

        float3 tnor = rf_terrainNormal(pos.xz);
        float3 nor;

        float3 speC = float3(1.0);
        // terrain
        if (obj == 1)
        {
            nor = normalize(tnor + 0.8 * (1.0 - abs(tnor.y)) * 0.8 * rf_fbmd_7((pos - float3(0, 600, 0)) * 0.15 * float3(1.0, 0.2, 1.0)).yzw);

            col = float3(0.18, 0.12, 0.10) * 0.85;
            col = 1.0 * mix(col, float3(0.1, 0.1, 0.0) * 0.2, smoothstep(0.7, 0.9, nor.y));

            float dif = clamp(dot(nor, rf_kSunDir), 0.0, 1.0);
            dif *= sha1;

            float bac = clamp(dot(normalize(float3(-rf_kSunDir.x, 0.0, -rf_kSunDir.z)), nor), 0.0, 1.0);
            float foc = clamp((pos.y / 2.0 - 180.0) / 130.0, 0.0, 1.0);
            float dom = clamp(0.5 + 0.5 * nor.y, 0.0, 1.0);
            float3 lin  = 1.0 * 0.2 * mix(0.1 * float3(0.1, 0.2, 0.1), float3(0.7, 0.9, 1.5) * 3.0, dom) * foc;
                   lin += 1.0 * 8.5 * float3(1.0, 0.9, 0.8) * dif;
                   lin += 1.0 * 0.27 * float3(1.1, 1.0, 0.9) * bac * foc;
            speC = float3(4.0) * dif * smoothstep(20.0, 0.0, abs(pos.y / 2.0 - 310.0) - 20.0);

            col *= lin;
        }
        // trees
        else
        {
            float3 gnor = rf_treesNormal(pos, resT);
            nor = normalize(gnor + 2.0 * tnor);

            float3 ref = reflect(rd, nor);
            float occ = clamp(hei, 0.0, 1.0) * pow(1.0 - 2.0 * displa, 3.0);
            float dif = clamp(0.1 + 0.9 * dot(nor, rf_kSunDir), 0.0, 1.0);
            dif *= sha1;
            if (dif > 0.0001)
            {
                float a = clamp(0.5 + 0.5 * dot(tnor, rf_kSunDir), 0.0, 1.0);
                a = a * a;
                a *= occ;
                a *= 0.6;
                a *= smoothstep(60.0, 200.0, resT);
                float sha2 = rf_treesShadow(pos + rf_kSunDir * 0.1, rf_kSunDir);
                dif *= a + (1.0 - a) * sha2;
            }
            float dom = clamp(0.5 + 0.5 * nor.y, 0.0, 1.0);
            float bac = clamp(0.5 + 0.5 * dot(normalize(float3(-rf_kSunDir.x, 0.0, -rf_kSunDir.z)), nor), 0.0, 1.0);
            float fre = clamp(1.0 + dot(nor, rd), 0.0, 1.0);

            float3 lin  = 12.0 * float3(1.2, 1.0, 0.7) * dif * occ * (2.5 - 1.5 * smoothstep(0.0, 120.0, resT));
                   lin += 0.55 * mix(0.1 * float3(0.1, 0.2, 0.0), float3(0.6, 1.0, 1.0), dom * occ);
                   lin += 0.07 * float3(1.0, 1.0, 0.9) * bac * occ;
                   lin += 1.10 * float3(0.9, 1.0, 0.8) * pow(fre, 5.0) * occ * (1.0 - smoothstep(100.0, 200.0, resT));
            speC = dif * float3(1.0, 1.1, 1.5) * 1.2;

            float brownAreas = rf_fbm_4_2(pos.zx * 0.015);
            col = float3(0.2, 0.2, 0.05);
            col = mix(col, float3(0.32, 0.2, 0.05), smoothstep(0.2, 0.9, fract(2.0 * mid)));
            col *= (mid < 0.5) ? 0.65 + 0.35 * smoothstep(300.0, 600.0, resT) * smoothstep(700.0, 500.0, pos.y) : 1.0;
            col = mix(col, float3(0.25, 0.16, 0.01) * 0.825, 0.7 * smoothstep(0.1, 0.3, brownAreas) * smoothstep(0.5, 0.8, tnor.y));
            col *= 1.0 - 0.5 * smoothstep(400.0, 700.0, pos.y);
            col *= lin;
        }

        // specular
        float3 ref = reflect(rd, nor);
        float fre = clamp(1.0 + dot(nor, rd), 0.0, 1.0);
        float spe = 3.0 * pow(clamp(dot(ref, rf_kSunDir), 0.0, 1.0), 9.0) * (0.05 + 0.95 * pow(fre, 5.0));
        col += spe * speC;

        col = rf_fog(col, resT);
    }

    // clouds
    {
        float4 res = rf_renderClouds(ro, rd, 0.0, resT, resT, iTime);
        col = col * (1.0 - res.w) + res.xyz;
    }

    // sun glare
    float sun = clamp(dot(rf_kSunDir, rd), 0.0, 1.0);
    col += 0.25 * float3(0.8, 0.4, 0.2) * pow(sun, 4.0);

    // gamma
    col = pow(clamp(col * 1.1 - 0.02, 0.0, 1.0), float3(0.4545));
    // contrast
    col = col * col * (3.0 - 2.0 * col);
    // color grade
    col = pow(col, float3(1.0, 0.92, 1.0));
    col *= float3(1.02, 0.99, 0.9);
    col.z = col.z + 0.1;

    // vignette
    float2 q = fragCoord / uniforms.iResolution;
    col *= 0.5 + 0.5 * pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.05);

    return float4(col, 1.0);
}
