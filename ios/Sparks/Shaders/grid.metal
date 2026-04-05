#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Warped Extruded Skewed Grid - Ported from Shadertoy
// https://www.shadertoy.com/view/wtfBDf
// Original Author: Shane
// License: CC BY-NC-SA 3.0

#define SKEW_GRID
#define GRID_FAR 20.

static float2x2 grid_rot2(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

static float grid_hash21(float2 p) {
    return fract(sin(dot(p, float2(27.609, 57.583))) * 43758.5453);
}

static float grid_hash31(float3 p) {
    return fract(sin(dot(p, float3(12.989, 78.233, 57.263))) * 43758.5453);
}

static float2 grid_path(float z) {
    return float2(3.0 * sin(z * 0.1) + 0.5 * cos(z * 0.4), 0.0);
}

static float3 grid_getTex(float2 p, texture2d<float> tex, sampler samp) {
    float3 tx = tex.sample(samp, p / 8.0).xyz;
    return tx * tx;
}

static float grid_hm(float2 p, texture2d<float> tex, sampler samp) {
    return dot(grid_getTex(p, tex, samp), float3(0.299, 0.587, 0.114));
}

static float grid_opExtrusion(float sdf, float pz, float h, float sf) {
    float2 w = float2(sdf, abs(pz) - h) + sf;
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0)) - sf;
}

static float grid_sBoxS(float2 p, float2 b, float sf) {
    p = abs(p) - b + sf;
    return length(max(p, 0.0)) + min(max(p.x, p.y), 0.0) - sf;
}

static float2 grid_skewXY(float2 p, float2 s) {
    return float2x2(float2(1.0, -s.x), float2(-s.y, 1.0)) * p;
}

static float2 grid_unskewXY(float2 p, float2 s) {
    float2x2 m = float2x2(float2(1.0, -s.x), float2(-s.y, 1.0));
    // inverse of [[1, -sy], [-sx, 1]] = 1/(1-sx*sy) * [[1, sy], [sx, 1]]
    float det = 1.0 - s.x * s.y;
    float2x2 inv = float2x2(float2(1.0, s.x), float2(s.y, 1.0)) / det;
    return inv * p;
}

struct GridState {
    float objID;
    float3 gID;
    float4 gGlow;
    float2 gP;
};

static float4 grid_blocks(float3 q, texture2d<float> tex, sampler samp, thread float2& gP) {
    const float2 scale = float2(1.0 / 5.0);
    const float2 dim = scale;
    const float2 s = dim * 2.0;

#ifdef SKEW_GRID
    const float2 sk = float2(-0.5, 0.5);
#else
    const float2 sk = float2(0.0);
#endif

    float d = 1e5;
    float2 p, ip;
    float2 id = float2(0.0);

    const float2 ps4[4] = {float2(-0.5, 0.5), float2(0.5), float2(0.5, -0.5), float2(-0.5)};
    const float hs = 0.4;
    float height = 0.0;
    gP = float2(0.0);

    for (int i = 0; i < 4; i++) {
        float2 cntr = ps4[i] / 2.0 - ps4[0] / 2.0;
        p = grid_skewXY(q.xz, sk);
        ip = floor(p / s - cntr) + 0.5;
        p -= (ip + cntr) * s;
        p = grid_unskewXY(p, sk);
        float2 idi = ip + cntr;
        idi = grid_unskewXY(idi * s, sk);

        float2 idi1 = idi;
        float h1 = grid_hm(idi1, tex, samp);
        h1 *= hs;
        float face1 = grid_sBoxS(p, 2.0 / 5.0 * dim - 0.02 * scale.x, 0.015);
        float face1Ext = grid_opExtrusion(face1, q.y + h1, h1, 0.006);

        float2 offs = grid_unskewXY(dim * 0.5, sk);
        float2 idi2 = idi + offs;
        float h2 = grid_hm(idi2, tex, samp);
        h2 *= hs;
        float face2 = grid_sBoxS(p - offs, 1.0 / 5.0 * dim - 0.02 * scale.x, 0.015);
        float face2Ext = grid_opExtrusion(face2, q.y + h2, h2, 0.006);

        float4 di = face1Ext < face2Ext ? float4(face1Ext, idi1, h1) : float4(face2Ext, idi2, h2);

        if (di.x < d) {
            d = di.x;
            id = di.yz;
            height = di.w;
            gP = p;
        }
    }
    return float4(d, id, height);
}

static float grid_getTwist(float z) { return z * 0.08; }

static float grid_map(float3 p, float iTime, texture2d<float> tex, sampler samp,
                       thread float& objID, thread float3& gID, thread float4& gGlow, thread float2& gP) {
    p.xy -= grid_path(p.z);
    p.xy = grid_rot2(grid_getTwist(p.z)) * p.xy;
    p.y = abs(p.y) - 1.25;
    float fl = -p.y + 0.01;

    float4 d4 = grid_blocks(p, tex, samp, gP);
    gID = d4.yzw;

    float rnd = grid_hash21(gID.xy);
    gGlow.w = smoothstep(0.992, 0.997, sin(rnd * 6.2831 + iTime / 4.0) * 0.5 + 0.5);

    objID = fl < d4.x ? 1.0 : 0.0;
    return min(fl, d4.x);
}

static float grid_trace(float3 ro, float3 rd, float iTime, texture2d<float> tex, sampler samp,
                          thread float& objID, thread float3& gID, thread float4& gGlow, thread float2& gP) {
    float t = 0.0, d;
    gGlow = float4(0.0);
    t = grid_hash31(ro.zxy + rd.yzx) * 0.25;

    for (int i = 0; i < 128; i++) {
        d = grid_map(ro + rd * t, iTime, tex, samp, objID, gID, gGlow, gP);
        float ad = abs(d + (grid_hash31(ro + rd) - 0.5) * 0.05);
        const float dst = 0.25;
        if (ad < dst) gGlow.xyz += gGlow.w * (dst - ad) * (dst - ad) / (1.0 + t);
        if (abs(d) < 0.001 * (1.0 + t * 0.05) || t > GRID_FAR) break;
        t += i < 32 ? d * 0.4 : d * 0.7;
    }
    return min(t, GRID_FAR);
}

static float3 grid_getNormal(float3 p, float iTime, texture2d<float> tex, sampler samp) {
    const float2 e = float2(0.001, 0.0);
    float objID_dummy;
    float3 gID_dummy;
    float4 gGlow_dummy;
    float2 gP_dummy;
    float mp[6];
    float3 e6[3] = {float3(e.x, e.y, e.y), float3(e.y, e.x, e.y), float3(e.y, e.y, e.x)};
    float sgn = 1.0;
    for (int i = 0; i < 6; i++) {
        mp[i] = grid_map(p + sgn * e6[i / 2], iTime, tex, samp, objID_dummy, gID_dummy, gGlow_dummy, gP_dummy);
        sgn = -sgn;
    }
    return normalize(float3(mp[0] - mp[1], mp[2] - mp[3], mp[4] - mp[5]));
}

static float grid_softShadow(float3 ro, float3 lp, float3 n, float k,
                               float iTime, texture2d<float> tex, sampler samp) {
    float objID_dummy;
    float3 gID_dummy;
    float4 gGlow_dummy;
    float2 gP_dummy;
    ro += n * 0.0015;
    float3 rd = lp - ro;
    float shade = 1.0;
    float t = 0.0;
    float end = max(length(rd), 0.0001);
    rd /= end;
    for (int i = 0; i < 24; i++) {
        float d = grid_map(ro + rd * t, iTime, tex, samp, objID_dummy, gID_dummy, gGlow_dummy, gP_dummy);
        shade = min(shade, k * d / t);
        t += clamp(d, 0.01, 0.25);
        if (d < 0.0 || t > end) break;
    }
    return max(shade, 0.0);
}

static float grid_calcAO(float3 p, float3 n, float iTime, texture2d<float> tex, sampler samp) {
    float objID_dummy;
    float3 gID_dummy;
    float4 gGlow_dummy;
    float2 gP_dummy;
    float sca = 3.0, occ = 0.0;
    for (int i = 0; i < 5; i++) {
        float hr = float(i + 1) * 0.15 / 5.0;
        float d = grid_map(p + n * hr, iTime, tex, samp, objID_dummy, gID_dummy, gGlow_dummy, gP_dummy);
        occ += (hr - d) * sca;
        sca *= 0.7;
    }
    return clamp(1.0 - occ, 0.0, 1.0);
}

fragment float4 grid_fragment(VertexOut in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(0)]],
                              texture2d<float> iChannel0 [[texture(0)]],
                              sampler samp [[sampler(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 uv = (fragCoord - uniforms.iResolution * 0.5) / uniforms.iResolution.y;

    float3 ro = float3(0.0, 0.0, iTime * 1.5);
    ro.xy += grid_path(ro.z);
    float2 roTwist = float2(0.0, 0.0);
    roTwist = grid_rot2(-grid_getTwist(ro.z)) * roTwist;
    ro.xy += roTwist;

    float3 lk = float3(0.0, 0.0, ro.z + 0.25);
    lk.xy += grid_path(lk.z);
    float2 lkTwist = float2(0.0, -0.1);
    lkTwist = grid_rot2(-grid_getTwist(lk.z)) * lkTwist;
    lk.xy += lkTwist;

    float3 lp = float3(0.0, 0.0, ro.z + 3.0);
    lp.xy += grid_path(lp.z);
    float2 lpTwist = float2(0.0, -0.3);
    lpTwist = grid_rot2(-grid_getTwist(lp.z)) * lpTwist;
    lp.xy += lpTwist;

    float FOV = 1.0;
    float a = grid_getTwist(ro.z);
    a += (grid_path(ro.z).x - grid_path(lk.z).x) / (ro.z - lk.z) / 4.0;
    float3 fw = normalize(lk - ro);
    float3 up = float3(sin(a), cos(a), 0.0);
    float3 cu = normalize(cross(up, fw));
    float3 cv = cross(fw, cu);
    float3 rd = normalize(uv.x * cu + uv.y * cv + fw / FOV);

    float objID;
    float3 gID;
    float4 gGlow;
    float2 gP;
    float t = grid_trace(ro, rd, iTime, iChannel0, samp, objID, gID, gGlow, gP);

    float3 svGID = gID;
    float svObjID = objID;
    float2 svP = gP;
    float3 svGlow = gGlow.xyz;

    float3 col = float3(0.0);

    if (t < GRID_FAR) {
        float3 sp = ro + rd * t;
        float3 sn = grid_getNormal(sp, iTime, iChannel0, samp);

        float3 txP = sp;
        txP.xy -= grid_path(txP.z);
        txP.xy = grid_rot2(grid_getTwist(txP.z)) * txP.xy;

        float3 texCol;
        if (svObjID < 0.5) {
            float3 tx = grid_getTex(svGID.xy, iChannel0, samp);
            texCol = smoothstep(-0.5, 1.0, tx) * float3(1.0, 0.8, 1.8);

            const float lvls = 8.0;
            float yDist = (1.25 + abs(txP.y) + svGID.z * 2.0);
            float hLn = abs(fmod(yDist + 0.5 / lvls, 1.0 / lvls) - 0.5 / lvls);
            float hLn2 = abs(fmod(yDist + 0.5 / lvls - 0.008, 1.0 / lvls) - 0.5 / lvls);
            if (yDist - 2.5 < 0.25 / lvls) hLn = 1e5;
            if (yDist - 2.5 < 0.25 / lvls) hLn2 = 1e5;
            texCol = mix(texCol, texCol * 2.0, 1.0 - smoothstep(0.0, 0.003, hLn2 - 0.0035));
            texCol = mix(texCol, texCol / 2.5, 1.0 - smoothstep(0.0, 0.003, hLn - 0.0035));

            float fDot = length(txP.xz - svGID.xy) - 0.0086;
            texCol = mix(texCol, texCol * 2.0, 1.0 - smoothstep(0.0, 0.005, fDot - 0.0035));
            texCol = mix(texCol, float3(0.0), 1.0 - smoothstep(0.0, 0.005, fDot));
        } else {
            texCol = float3(0.0);
        }

        float3 ld = lp - sp;
        float lDist = max(length(ld), 0.001);
        ld /= lDist;

        float sh = grid_softShadow(sp, lp, sn, 16.0, iTime, iChannel0, samp);
        float ao = grid_calcAO(sp, sn, iTime, iChannel0, samp);
        sh = min(sh + ao * 0.25, 1.0);
        float atten = 3.0 / (1.0 + lDist * lDist * 0.5);
        float diff = max(dot(sn, ld), 0.0);
        diff *= diff * 1.35;
        float spec = pow(max(dot(reflect(ld, sn), rd), 0.0), 32.0);
        float fre = pow(clamp(1.0 - abs(dot(sn, rd)) * 0.5, 0.0, 1.0), 4.0);

        col = texCol * (diff + ao * 0.25 + float3(1.0, 0.4, 0.2) * fre * 0.25 + float3(1.0, 0.4, 0.2) * spec * 4.0);
        col *= ao * sh * atten;
    }

    svGlow.xyz *= mix(float3(4.0, 1.0, 2.0), float3(4.0, 2.0, 1.0), min(svGlow.xyz * 3.5, 1.25));
    col *= 0.25 + svGlow.xyz * 8.0;

    float3 fog = mix(float3(4.0, 1.0, 2.0), float3(4.0, 2.0, 1.0), rd.y * 0.5 + 0.5);
    fog = mix(fog, fog.zyx, smoothstep(0.0, 0.35, uv.y - 0.35));
    col = mix(col, fog / 1.5, smoothstep(0.0, 0.99, t * t / GRID_FAR / GRID_FAR));

    return float4(sqrt(max(col, 0.0)), 1.0);
}
