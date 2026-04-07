#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Voxel Lines - Ported from Shadertoy
// https://www.shadertoy.com/view/4dfGzs
// Original Author: Inigo Quilez
// License: Educational use only (see original for full terms)

static float noise(float3 x, texture2d<float> iChannel0, sampler samp)
{
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float2 uv = (i.xy + float2(37.0, 17.0) * i.z) + f.xy;
    float2 rg = iChannel0.sample(samp, (uv + 0.5) / 256.0, level(0.0)).yx;
    return mix(rg.x, rg.y, f.z);
}

static float mapTerrain(float3 p, float iTime, texture2d<float> iChannel0, sampler samp)
{
    p *= 0.1;
    p.xz *= 0.6;
    float time = 0.5 + 0.15 * iTime;
    float ft = fract(time);
    float it = floor(time);
    ft = smoothstep(0.7, 1.0, ft);
    time = it + ft;
    float spe = 1.4;
    float f;
    f  = 0.5000 * noise(p * 1.00 + float3(0.0, 1.0, 0.0) * spe * time, iChannel0, samp);
    f += 0.2500 * noise(p * 2.02 + float3(0.0, 2.0, 0.0) * spe * time, iChannel0, samp);
    f += 0.1250 * noise(p * 4.01, iChannel0, samp);
    return 25.0 * f - 10.0;
}

static float map(float3 c, float3 gro, float iTime, texture2d<float> iChannel0, sampler samp)
{
    float3 p = c + 0.5;
    float f = mapTerrain(p, iTime, iChannel0, samp) + 0.25 * p.y;
    f = mix(f, 1.0, step(length(gro - p), 5.0));
    return step(f, 0.5);
}

static float raycast(float3 ro, float3 rd, thread float3 &oVos, thread float3 &oDir,
                     float3 gro, float iTime, texture2d<float> iChannel0, sampler samp)
{
    float3 pos = floor(ro);
    float3 ri = 1.0 / rd;
    float3 rs = sign(rd);
    float3 dis = (pos - ro + 0.5 + rs * 0.5) * ri;
    float res = -1.0;
    float3 mm = float3(0.0);
    for (int i = 0; i < 128; i++)
    {
        if (map(pos, gro, iTime, iChannel0, samp) > 0.5) { res = 1.0; break; }
        mm = step(dis.xyz, dis.yzx) * step(dis.xyz, dis.zxy);
        dis += mm * rs * ri;
        pos += mm * rs;
    }
    float3 mini = (pos - ro + 0.5 - 0.5 * float3(rs)) * ri;
    float t = max(mini.x, max(mini.y, mini.z));
    oDir = mm;
    oVos = pos;
    return t * res;
}

static float3 path(float t, float ya)
{
    float2 p  = 100.0 * sin(0.02 * t * float2(1.0, 1.2) + float2(0.1, 0.9));
         p += 50.0 * sin(0.04 * t * float2(1.3, 1.0) + float2(1.0, 4.5));
    return float3(p.x, 18.0 + ya * 4.0 * sin(0.05 * t), p.y);
}

static float3x3 setCamera(float3 ro, float3 ta, float cr)
{
    float3 cw = normalize(ta - ro);
    float3 cp = float3(sin(cr), cos(cr), 0.0);
    float3 cu = normalize(cross(cw, cp));
    float3 cv = normalize(cross(cu, cw));
    return float3x3(cu, cv, -cw);
}

static float maxcomp(float4 v)
{
    return max(max(v.x, v.y), max(v.z, v.w));
}

static float isEdge(float2 uv, float4 va, float4 vb, float4 vc, float4 vd)
{
    float2 st = 1.0 - uv;
    float4 wb = smoothstep(0.85, 0.99, float4(uv.x, st.x, uv.y, st.y)) * (1.0 - va + va * vc);
    float4 wc = smoothstep(0.85, 0.99, float4(uv.x * uv.y, st.x * uv.y, st.x * st.y, uv.x * st.y)) * (1.0 - vb + vd * vb);
    return maxcomp(max(wb, wc));
}

static float3 render(float3 ro, float3 rd, float3 gro, float iTime,
                     texture2d<float> iChannel0, sampler samp)
{
    float3 lig = normalize(float3(-0.4, 0.3, 0.7));

    float3 col = float3(0.0);
    float3 vos, dir;
    float t = raycast(ro, rd, vos, dir, gro, iTime, iChannel0, samp);
    if (t > 0.0)
    {
        float3 nor = -dir * sign(rd);
        float3 pos = ro + rd * t;
        float3 uvw = pos - vos;

        float3 v1  = vos + nor + dir.yzx;
        float3 v2  = vos + nor - dir.yzx;
        float3 v3  = vos + nor + dir.zxy;
        float3 v4  = vos + nor - dir.zxy;
        float3 v5  = vos + nor + dir.yzx + dir.zxy;
        float3 v6  = vos + nor - dir.yzx + dir.zxy;
        float3 v7  = vos + nor - dir.yzx - dir.zxy;
        float3 v8  = vos + nor + dir.yzx - dir.zxy;
        float3 v9  = vos + dir.yzx;
        float3 v10 = vos - dir.yzx;
        float3 v11 = vos + dir.zxy;
        float3 v12 = vos - dir.zxy;
        float3 v13 = vos + dir.yzx + dir.zxy;
        float3 v14 = vos - dir.yzx + dir.zxy;
        float3 v15 = vos - dir.yzx - dir.zxy;
        float3 v16 = vos + dir.yzx - dir.zxy;

        float4 vc = float4(map(v1, gro, iTime, iChannel0, samp),
                           map(v2, gro, iTime, iChannel0, samp),
                           map(v3, gro, iTime, iChannel0, samp),
                           map(v4, gro, iTime, iChannel0, samp));
        float4 vd = float4(map(v5, gro, iTime, iChannel0, samp),
                           map(v6, gro, iTime, iChannel0, samp),
                           map(v7, gro, iTime, iChannel0, samp),
                           map(v8, gro, iTime, iChannel0, samp));
        float4 va = float4(map(v9, gro, iTime, iChannel0, samp),
                           map(v10, gro, iTime, iChannel0, samp),
                           map(v11, gro, iTime, iChannel0, samp),
                           map(v12, gro, iTime, iChannel0, samp));
        float4 vb = float4(map(v13, gro, iTime, iChannel0, samp),
                           map(v14, gro, iTime, iChannel0, samp),
                           map(v15, gro, iTime, iChannel0, samp),
                           map(v16, gro, iTime, iChannel0, samp));

        float2 uv = float2(dot(dir.yzx, uvw), dot(dir.zxy, uvw));

        float www = 1.0 - isEdge(uv, va, vb, vc, vd);

        float3 wir = smoothstep(0.4, 0.5, abs(uvw - 0.5));
        float vvv = (1.0 - wir.x * wir.y) * (1.0 - wir.x * wir.z) * (1.0 - wir.y * wir.z);

        col = float3(0.5);
        col += 0.8 * float3(0.1, 0.3, 0.4);
        col *= 1.0 - 0.75 * (1.0 - vvv) * www;

        float dif = clamp(dot(nor, lig), 0.0, 1.0);
        float bac = clamp(dot(nor, normalize(lig * float3(-1.0, 0.0, -1.0))), 0.0, 1.0);
        float sky = 0.5 + 0.5 * nor.y;
        float amb = clamp(0.75 + pos.y / 25.0, 0.0, 1.0);
        float occ = 1.0;

        float2 st = 1.0 - uv;
        float4 wa = float4(uv.x, st.x, uv.y, st.y) * vc;
        float4 wb = float4(uv.x * uv.y, st.x * uv.y, st.x * st.y, uv.x * st.y) * vd * (1.0 - vc.xzyw) * (1.0 - vc.zywx);
        occ = wa.x + wa.y + wa.z + wa.w + wb.x + wb.y + wb.z + wb.w;
        occ = 1.0 - occ / 8.0;
        occ = occ * occ;
        occ = occ * occ;
        occ *= amb;

        float3 lin = float3(0.0);
        lin += 2.5 * dif * float3(1.00, 0.90, 0.70) * (0.5 + 0.5 * occ);
        lin += 0.5 * bac * float3(0.15, 0.10, 0.10) * occ;
        lin += 2.0 * sky * float3(0.40, 0.30, 0.15) * occ;

        float lineglow = 0.0;
        lineglow += smoothstep(0.4, 1.0,     uv.x) * (1.0 - va.x * (1.0 - vc.x));
        lineglow += smoothstep(0.4, 1.0, 1.0 - uv.x) * (1.0 - va.y * (1.0 - vc.y));
        lineglow += smoothstep(0.4, 1.0,     uv.y) * (1.0 - va.z * (1.0 - vc.z));
        lineglow += smoothstep(0.4, 1.0, 1.0 - uv.y) * (1.0 - va.w * (1.0 - vc.w));
        lineglow += smoothstep(0.4, 1.0,      uv.y *       uv.x) * (1.0 - vb.x * (1.0 - vd.x));
        lineglow += smoothstep(0.4, 1.0,      uv.y * (1.0 - uv.x)) * (1.0 - vb.y * (1.0 - vd.y));
        lineglow += smoothstep(0.4, 1.0, (1.0 - uv.y) * (1.0 - uv.x)) * (1.0 - vb.z * (1.0 - vd.z));
        lineglow += smoothstep(0.4, 1.0, (1.0 - uv.y) *      uv.x) * (1.0 - vb.w * (1.0 - vd.w));

        float3 linCol = 2.0 * float3(5.0, 0.6, 0.0);
        linCol *= (0.5 + 0.5 * occ) * 0.5;
        lin += lineglow * linCol;

        col = col * lin;
        col += 8.0 * linCol * float3(1.0, 2.0, 3.0) * (1.0 - www);
        col += 0.1 * lineglow * linCol;
        col *= min(0.1, exp(-0.07 * t));

        float3 col2 = float3(1.3) * (0.5 + 0.5 * nor.y) * occ * exp(-0.04 * t);
        float mi = cos(-0.7 + 0.5 * iTime);
        mi = smoothstep(0.70, 0.75, mi);
        col = mix(col, col2, mi);
    }

    col = pow(col, float3(0.45));
    return col;
}

fragment float4 voxellines_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(0)]],
                                    texture2d<float> iChannel0 [[texture(0)]],
                                    sampler samp [[sampler(0)]])
{
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 p = (2.0 * fragCoord - uniforms.iResolution.xy) / uniforms.iResolution.y;
    float2 mo = uniforms.iMouse.xy / uniforms.iResolution.xy;
    if (uniforms.iMouse.z <= 0.00001) mo = float2(0.0);
    float time = 2.0 * uniforms.iTime + 50.0 * mo.x;

    float cr = 0.2 * cos(0.1 * uniforms.iTime);
    float3 ro = path(time + 0.0, 1.0);
    float3 ta = path(time + 5.0, 1.0) - float3(0.0, 6.0, 0.0);
    float3 gro = ro;

    float3x3 cam = setCamera(ro, ta, cr);

    float r2 = p.x * p.x * 0.32 + p.y * p.y;
    p *= (7.0 - sqrt(37.5 - 11.5 * r2)) / (r2 + 1.0);
    float3 rd = normalize(cam * float3(p.xy, -2.5));

    float3 col = render(ro, rd, gro, uniforms.iTime, iChannel0, samp);

    float2 q = fragCoord / uniforms.iResolution.xy;
    col *= 0.5 + 0.5 * pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.1);

    return float4(col, 1.0);
}
