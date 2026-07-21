#version 450

// Water Cave - Ported from Shadertoy
// https://www.shadertoy.com/view/XcVyWD
// Volumetric glass/water underground river with a glowing moving ball.
// (References in the original: "Rio Subterraneo" 4cyyRc, "glass volumetric dda test" 4fGyWG.)

layout(location = 0) in vec2 vUV;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PushConstants {
    vec2 iResolution;
    float iTime;
    int preRotate;
    vec4 iMouse;
    int mode;
    int iFrame;
};

#define h21(p) fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123)
#define path(z) vec2(sin(z * .15) * 2.4, cos(z * .25) * 1.7)
#define openCave(t)  (tanh(cos(t * .05) * 12. + 10.) * .5 + .5)
#define ballMovez(t)  tanh(cos(t * .5) * 6. + 4.) * 3. + 7.
#define ballMoveXY(t) tanh(sin(t) * 5. - 3.) * 4.
#define tri(x) abs(x - floor(x) - .5)
#define trap(x, pf) (tri(x - pf * .125) + tri(x + pf * .125)) * .5

bool G = false;
float FAR = 40., ID = 0., svObjID = 0.;
vec2 e = vec2(0, 1);
vec3 lp = vec3(0);

// waterSurf :: (p) -> .8 .. 1.2
float waterSurf(vec3 p) {
    p += vec3(0, 0, iTime * 4.);
    return dot(
               sin(
                   p + sin(p.yzx * 2.) * cos(p.y)
               ),
               vec3(.2)
           ) + 1.;
}

float map(vec3 p) {
    float sf = dot(
                   trap(p * .384 + trap(p.yzx * .192, .75), .75),
                   vec3(.666)
               );

          sf = (1. - sf) * (cos(p.z * .4) + 1.02);

    p.xy -= path(p.z);

    float tunel = 1.5 - length(p.xy * vec2(.5, .7071)) * openCave(iTime) + sf,
          ball = length(p - lp) - 1.;

    tunel = min(tunel, ball);

    if(G){
        ID = 1.;
        return tunel;
    }

    p.y += waterSurf(p);

    ID = step(tunel, p.y);

    return min(tunel, p.y);
}

vec3 getNormal(vec3 p, inout float edge) {
    vec2 e = vec2(6. / iResolution.y, 0);

    edge = abs(map(p + e.xyy) + map(p - e.xyy) - map(p) * 2.)
           + abs(map(p + e.yxy) + map(p - e.yxy) - map(p) * 2.)
           + abs(map(p + e.yyx) + map(p - e.yyx) - map(p) * 2.);

    edge = smoothstep(0., 1., sqrt(edge / e.x * 2.));

    e = vec2(.01, 0);
    return normalize(
               vec3(
                   map(p + e.xyy) - map(p - e.xyy),
                   map(p + e.yxy) - map(p - e.yxy),
                   map(p + e.yyx) - map(p - e.yyx)
               )
           );
}

vec3 doColor(vec3 sp, vec3 rd, vec3 sn, vec3 lp, float edge, float dist) {
    vec3 col = vec3(0);

    if(dist < 40.) {
        vec3 ld = lp - sp;
        float lDist = max(length(ld), .001);
        ld /= lDist;

        float atten = 1.5 / (1. + lDist * .125 + lDist * lDist * .025);

        float diff = max(dot(sn, ld), 0.);
        diff = pow(diff, 4.) * .66  +  pow(diff, 8.) * .34;

        float spec = pow(max(dot(reflect(-ld, sn), -rd), .0), 32.);

        vec3 objCol = vec3(.6, .8, 1);
        if(svObjID > .5)
            objCol = vec3(1, .55, .35);

        col = (objCol * (diff + .7 + vec3(1, .6, .2) * spec * 2.));
        col *= 1. - edge * .9;
        col *= atten;
    }

    return col;
}

float calculateAO(vec3 pos, vec3 nor) {
    float sca = 2., occ = 0.;

    for(int i = 0; i < 4; i ++) {
        float hr = .01 + float(i) * .5 / 4.;
        float dd = map(nor * hr + pos);
        occ += (hr - dd) * sca;
        sca *= .6;
    }
    return clamp(1. - occ, 0., 1.);
}

float march(vec3 ro, vec3 rd) {
    float t = 0., d, i = 0.;
    while(i++ < 96.) {
        d = map(ro + rd * t);
        if(abs(d) < .001 * (t * .5 + 1.) || t > FAR) break;
        t += d * .8;
    }
    return t;
}

float noise(vec3 q) {
    vec2 p = vec2(length(q.zy), q.x);

    vec2 i = floor(p),
         f = fract(p),
         c = vec2(1, 0);

    f *= f * (3. - 2. * f);
    return mix(
               mix(
                   h21(i + c.yy),
                   h21(i + c.xy),
                   f.x
               ),
               mix(
                   h21(i + c.yx),
                   h21(i + c.xx),
                   f.x
               ),
               f.y
           );
}

float bumpFunc(vec3 p) {
    vec2 e = vec2(iTime, 0);
    return (
                 noise(p * 5. + e.yxy * -12.)
               + noise(p * 4. + e.xyy * -4.)
               + noise(p * 6. + e.xyy * 7.)
           ) / 2.;
}

vec3 bumpMap(vec3 p, vec3 n, float bumpfactor) {
    vec2 e = vec2(.002, 0);
    vec3 grad = vec3(
                    bumpFunc(p - e.xyy),
                    bumpFunc(p - e.yxy),
                    bumpFunc(p - e.yyx)
                ) - bumpFunc(p);

    return normalize(
               (1. - n * dot(n, n)) * grad * bumpfactor / e.x + n
           );
}

void mainImage(out vec4 o, vec2 u) {
    vec2 r = iResolution.xy;
         u = (u - r / 2.) / r.y;

    vec3 ro = vec3(0, 0, iTime);
    vec3 lk = ro + vec3(0, 0, .25);
    lp = ro + vec3(0, .25, ballMovez(iTime));

    ro.xy += path(ro.z);
    lk.xy += path(lk.z);
    lp.xy += path(lp.z + ballMoveXY(iTime)) - vec2(0, 1);

    vec3 forward = normalize(lk - ro);
    vec3 right = normalize(vec3(forward.z, 0., - forward.x));
    vec3 up = cross(forward, right);
    vec3 rd = normalize(forward + (u.x * right + u.y * up));

    // ------------------------------------------------
    float dist = march(ro, rd);

    svObjID = ID;
    float oSvObjID = svObjID;
    vec3 sp = ro + rd * dist;

    float edge = 0.;
    vec3 sn = getNormal(sp, edge);

    if(oSvObjID < .5)
        sn = bumpMap(sp, sn, .04);

    vec3 col = doColor(sp, rd, sn, lp, edge, dist);

    float fog = dist / FAR + .2;
    float ao = calculateAO(sp, sn);

    vec3 refr = refract(rd, sn, 1. / 1.33);
    float fr = clamp(1. + dot(rd, sn), 0., 1.);

    // ------------------------------------------------
    svObjID = ID;

    if(oSvObjID < .5) {
        G = true;
        dist = march(sp, refr);
        svObjID = ID;
        vec3 refSp = sp + refr * dist;
        sn = getNormal(refSp, edge);

        vec3 refrColor = doColor(refSp, refr, sn, lp, edge, dist);
        col = col * .2
                + mix(
                      refrColor,
                      col,
                      pow(fr, 5.) * .4 + .2
                  );
    }

    else
        col = pow(col, vec3(.5)) * (ao + .5) * .5 - fog * .3;

    o.rgb = pow(smoothstep(.05, .4, col * fog), vec3(.45));
    o.a = 1.;
}

void main() {
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    vec4 o;
    mainImage(o, fragCoord);
    outColor = vec4(o.rgb, 1.0);
}
