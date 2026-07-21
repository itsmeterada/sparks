#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Water Cave - Ported from Shadertoy
// https://www.shadertoy.com/view/XcVyWD
// Volumetric glass/water underground river with a glowing moving ball.
// (References in the original: "Rio Subterraneo" 4cyyRc, "glass volumetric dda test" 4fGyWG.)

#define WC_h21(p) fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123)
#define WC_path(z) float2(sin(z * .15) * 2.4, cos(z * .25) * 1.7)
#define WC_openCave(t)  (tanh(cos(t * .05) * 12. + 10.) * .5 + .5)
#define WC_ballMovez(t)  tanh(cos(t * .5) * 6. + 4.) * 3. + 7.
#define WC_ballMoveXY(t) tanh(sin(t) * 5. - 3.) * 4.
#define WC_tri(x) abs(x - floor(x) - .5)
#define WC_trap(x, pf) (WC_tri(x - pf * .125) + WC_tri(x + pf * .125)) * .5

constant float WC_FAR = 40.0;

// Mutable globals from the original, threaded through as state.
struct WCState {
    bool   G;
    float  ID;
    float  svObjID;
    float3 lp;
    float  iTime;
    float2 iResolution;
};

// waterSurf :: (p) -> .8 .. 1.2
static float wc_waterSurf(float3 p, thread WCState& S) {
    p += float3(0, 0, S.iTime * 4.);
    return dot(
               sin(
                   p + sin(p.yzx * 2.) * cos(p.y)
               ),
               float3(.2)
           ) + 1.;
}

static float wc_map(float3 p, thread WCState& S) {
    float sf = dot(
                   WC_trap(p * .384 + WC_trap(p.yzx * .192, .75), .75),
                   float3(.666)
               );

          sf = (1. - sf) * (cos(p.z * .4) + 1.02);

    p.xy -= WC_path(p.z);

    float tunel = 1.5 - length(p.xy * float2(.5, .7071)) * WC_openCave(S.iTime) + sf,
          ball = length(p - S.lp) - 1.;

    tunel = min(tunel, ball);

    if(S.G){
        S.ID = 1.;
        return tunel;
    }

    p.y += wc_waterSurf(p, S);

    S.ID = step(tunel, p.y);

    return min(tunel, p.y);
}

static float3 wc_getNormal(float3 p, thread float& edge, thread WCState& S) {
    float2 e = float2(6. / S.iResolution.y, 0);

    edge = abs(wc_map(p + e.xyy, S) + wc_map(p - e.xyy, S) - wc_map(p, S) * 2.)
           + abs(wc_map(p + e.yxy, S) + wc_map(p - e.yxy, S) - wc_map(p, S) * 2.)
           + abs(wc_map(p + e.yyx, S) + wc_map(p - e.yyx, S) - wc_map(p, S) * 2.);

    edge = smoothstep(0., 1., sqrt(edge / e.x * 2.));

    e = float2(.01, 0);
    return normalize(
               float3(
                   wc_map(p + e.xyy, S) - wc_map(p - e.xyy, S),
                   wc_map(p + e.yxy, S) - wc_map(p - e.yxy, S),
                   wc_map(p + e.yyx, S) - wc_map(p - e.yyx, S)
               )
           );
}

static float3 wc_doColor(float3 sp, float3 rd, float3 sn, float3 lp, float edge, float dist, thread WCState& S) {
    float3 col = float3(0);

    if(dist < 40.) {
        float3 ld = lp - sp;
        float lDist = max(length(ld), .001);
        ld /= lDist;

        float atten = 1.5 / (1. + lDist * .125 + lDist * lDist * .025);

        float diff = max(dot(sn, ld), 0.);
        diff = pow(diff, 4.) * .66  +  pow(diff, 8.) * .34;

        float spec = pow(max(dot(reflect(-ld, sn), -rd), .0), 32.);

        float3 objCol = float3(.6, .8, 1);
        if(S.svObjID > .5)
            objCol = float3(1, .55, .35);

        col = (objCol * (diff + .7 + float3(1, .6, .2) * spec * 2.));
        col *= 1. - edge * .9;
        col *= atten;
    }

    return col;
}

static float wc_calculateAO(float3 pos, float3 nor, thread WCState& S) {
    float sca = 2., occ = 0.;

    for(int i = 0; i < 4; i ++) {
        float hr = .01 + float(i) * .5 / 4.;
        float dd = wc_map(nor * hr + pos, S);
        occ += (hr - dd) * sca;
        sca *= .6;
    }
    return clamp(1. - occ, 0., 1.);
}

static float wc_march(float3 ro, float3 rd, thread WCState& S) {
    float t = 0., d, i = 0.;
    while(i++ < 96.) {
        d = wc_map(ro + rd * t, S);
        if(abs(d) < .001 * (t * .5 + 1.) || t > WC_FAR) break;
        t += d * .8;
    }
    return t;
}

static float wc_noise(float3 q) {
    float2 p = float2(length(q.zy), q.x);

    float2 i = floor(p),
           f = fract(p),
           c = float2(1, 0);

    f *= f * (3. - 2. * f);
    return mix(
               mix(
                   WC_h21(i + c.yy),
                   WC_h21(i + c.xy),
                   f.x
               ),
               mix(
                   WC_h21(i + c.yx),
                   WC_h21(i + c.xx),
                   f.x
               ),
               f.y
           );
}

static float wc_bumpFunc(float3 p, thread WCState& S) {
    float2 e = float2(S.iTime, 0);
    return (
                 wc_noise(p * 5. + e.yxy * -12.)
               + wc_noise(p * 4. + e.xyy * -4.)
               + wc_noise(p * 6. + e.xyy * 7.)
           ) / 2.;
}

static float3 wc_bumpMap(float3 p, float3 n, float bumpfactor, thread WCState& S) {
    float2 e = float2(.002, 0);
    float3 grad = float3(
                    wc_bumpFunc(p - e.xyy, S),
                    wc_bumpFunc(p - e.yxy, S),
                    wc_bumpFunc(p - e.yyx, S)
                ) - wc_bumpFunc(p, S);

    return normalize(
               (1. - n * dot(n, n)) * grad * bumpfactor / e.x + n
           );
}

fragment float4 watercave_fragment(VertexOut in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    float2 iResolution = uniforms.iResolution;
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * iResolution;

    WCState S;
    S.G = false;
    S.ID = 0.;
    S.svObjID = 0.;
    S.lp = float3(0);
    S.iTime = iTime;
    S.iResolution = iResolution;

    float2 r = iResolution;
    float2 u = (fragCoord - r / 2.) / r.y;

    float3 ro = float3(0, 0, iTime);
    float3 lk = ro + float3(0, 0, .25);
    S.lp = ro + float3(0, .25, WC_ballMovez(iTime));

    ro.xy += WC_path(ro.z);
    lk.xy += WC_path(lk.z);
    S.lp.xy += WC_path(S.lp.z + WC_ballMoveXY(iTime)) - float2(0, 1);

    float3 forward = normalize(lk - ro);
    float3 right = normalize(float3(forward.z, 0., - forward.x));
    float3 up = cross(forward, right);
    float3 rd = normalize(forward + (u.x * right + u.y * up));

    // ------------------------------------------------
    float dist = wc_march(ro, rd, S);

    S.svObjID = S.ID;
    float oSvObjID = S.svObjID;
    float3 sp = ro + rd * dist;

    float edge = 0.;
    float3 sn = wc_getNormal(sp, edge, S);

    if(oSvObjID < .5)
        sn = wc_bumpMap(sp, sn, .04, S);

    float3 col = wc_doColor(sp, rd, sn, S.lp, edge, dist, S);

    float fog = dist / WC_FAR + .2;
    float ao = wc_calculateAO(sp, sn, S);

    float3 refr = refract(rd, sn, 1. / 1.33);
    float fr = clamp(1. + dot(rd, sn), 0., 1.);

    // ------------------------------------------------
    S.svObjID = S.ID;

    if(oSvObjID < .5) {
        S.G = true;
        dist = wc_march(sp, refr, S);
        S.svObjID = S.ID;
        float3 refSp = sp + refr * dist;
        sn = wc_getNormal(refSp, edge, S);

        float3 refrColor = wc_doColor(refSp, refr, sn, S.lp, edge, dist, S);
        col = col * .2
                + mix(
                      refrColor,
                      col,
                      pow(fr, 5.) * .4 + .2
                  );
    }

    else
        col = pow(col, float3(.5)) * (ao + .5) * .5 - fog * .3;

    float3 outCol = pow(smoothstep(.05, .4, col * fog), float3(.45));
    return float4(outCol, 1.0);
}
