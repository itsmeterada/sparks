#version 450

// Warped Extruded Skewed Grid - Ported from Shadertoy
// https://www.shadertoy.com/view/wtfBDf
// Original Author: Shane
// License: CC BY-NC-SA 3.0

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

layout(set = 0, binding = 0) uniform sampler2D iChannel0;

#define SKEW_GRID
#define FAR 20.

float objID;

mat2 rot2(in float a){ float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }
float hash21(vec2 p){ return fract(sin(dot(p, vec2(27.609, 57.583)))*43758.5453); }
float hash31(vec3 p){ return fract(sin(dot(p, vec3(12.989, 78.233, 57.263)))*43758.5453); }

vec2 path(in float z){ return vec2(3.*sin(z*.1) + .5*cos(z*.4), 0); }

vec3 getTex(in vec2 p){
    vec3 tx = texture(iChannel0, p/8.).xyz;
    return tx*tx;
}

float hm(in vec2 p){ return dot(getTex(p), vec3(.299, .587, .114)); }

float opExtrusion(in float sdf, in float pz, in float h, in float sf){
    vec2 w = vec2( sdf, abs(pz) - h) + sf;
    return min(max(w.x, w.y), 0.) + length(max(w, 0.)) - sf;
}

float sBoxS(in vec2 p, in vec2 b, in float sf){
    p = abs(p) - b + sf;
    return length(max(p, 0.)) + min(max(p.x, p.y), 0.) - sf;
}

vec2 skewXY(vec2 p, vec2 s){ return mat2(1, -s.y, -s.x, 1)*p; }
vec2 unskewXY(vec2 p, vec2 s){ return inverse(mat2(1, -s.y, -s.x, 1))*p; }

vec2 gP;

vec4 blocks(vec3 q){
    const vec2 scale = vec2(1./5.);
    const vec2 dim = scale;
    const vec2 s = dim*2.;

    #ifdef SKEW_GRID
    const vec2 sk = vec2(-.5, .5);
    #else
    const vec2 sk = vec2(0);
    #endif

    float d = 1e5;
    vec2 p, ip;
    vec2 id = vec2(0);
    vec2 cntr = vec2(0);

    const vec2[4] ps4 = vec2[4](vec2(-.5, .5), vec2(.5), vec2(.5, -.5), vec2(-.5));
    const float hs = .4;
    float height = 0.;
    gP = vec2(0);

    for(int i = 0; i<4; i++){
        cntr = ps4[i]/2. - ps4[0]/2.;
        p = skewXY(q.xz, sk);
        ip = floor(p/s - cntr) + .5;
        p -= (ip + cntr)*s;
        p = unskewXY(p, sk);
        vec2 idi = ip + cntr;
        idi = unskewXY(idi*s, sk);

        vec2 idi1 = idi;
        float h1 = hm(idi1);
        h1 *= hs;
        float face1 = sBoxS(p, 2./5.*dim - .02*scale.x, .015);
        float face1Ext = opExtrusion(face1, q.y + h1, h1, .006);

        vec2 offs = unskewXY(dim*.5, sk);
        vec2 idi2 = idi + offs;
        float h2 = hm(idi2);
        h2 *= hs;
        float face2 = sBoxS(p - offs, 1./5.*dim - .02*scale.x, .015);
        float face2Ext = opExtrusion(face2, q.y + h2, h2, .006);

        vec4 di = face1Ext<face2Ext? vec4(face1Ext, idi1, h1) : vec4(face2Ext, idi2, h2);

        if(di.x<d){
            d = di.x;
            id = di.yz;
            height = di.w;
            gP = p;
        }
    }
    return vec4(d, id, height);
}

float getTwist(float z){ return z*.08; }

vec3 gID;
vec4 gGlow = vec4(0);

float map(vec3 p){
    p.xy -= path(p.z);
    p.xy *= rot2(getTwist(p.z));
    p.y = abs(p.y) - 1.25;
    float fl = -p.y + .01;

    vec4 d4 = blocks(p);
    gID = d4.yzw;

    float rnd = hash21(gID.xy);
    gGlow.w = smoothstep(.992, .997, sin(rnd*6.2831 + iTime/4.)*.5 + .5);

    objID = fl<d4.x? 1. : 0.;
    return min(fl, d4.x);
}

float trace(in vec3 ro, in vec3 rd){
    float t = 0., d;
    gGlow = vec4(0);
    t = hash31(ro.zxy + rd.yzx)*.25;

    for(int i = 0; i<128; i++){
        d = map(ro + rd*t);
        float ad = abs(d + (hash31(ro + rd) - .5)*.05);
        const float dst = .25;
        if(ad<dst) gGlow.xyz += gGlow.w*(dst - ad)*(dst - ad)/(1. + t);
        if(abs(d)<.001*(1. + t*.05) || t>FAR) break;
        t += i<32? d*.4 : d*.7;
    }
    return min(t, FAR);
}

vec3 getNormal(in vec3 p){
    const vec2 e = vec2(.001, 0);
    float sgn = 1.;
    float mp[6];
    vec3[3] e6 = vec3[3](e.xyy, e.yxy, e.yyx);
    for(int i = 0; i<6; i++){
        mp[i] = map(p + sgn*e6[i/2]);
        sgn = -sgn;
    }
    return normalize(vec3(mp[0] - mp[1], mp[2] - mp[3], mp[4] - mp[5]));
}

float softShadow(vec3 ro, vec3 lp, vec3 n, float k){
    const int iter = 24;
    ro += n*.0015;
    vec3 rd = lp - ro;
    float shade = 1.;
    float t = 0.;
    float end = max(length(rd), 0.0001);
    rd /= end;
    for (int i = 0; i<iter; i++){
        float d = map(ro + rd*t);
        shade = min(shade, k*d/t);
        t += clamp(d, .01, .25);
        if (d<0. || t>end) break;
    }
    return max(shade, 0.);
}

float calcAO(in vec3 p, in vec3 n){
    float sca = 3., occ = 0.;
    for( int i = 0; i<5; i++ ){
        float hr = float(i + 1)*.15/5.;
        float d = map(p + n*hr);
        occ += (hr - d)*sca;
        sca *= .7;
    }
    return clamp(1. - occ, 0., 1.);
}

void main(){
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    vec2 uv = (fragCoord - iResolution.xy*.5)/iResolution.y;

    vec3 ro = vec3(0, 0, iTime*1.5);
    ro.xy += path(ro.z);
    vec2 roTwist = vec2(0, 0);
    roTwist *= rot2(-getTwist(ro.z));
    ro.xy += roTwist;

    vec3 lk = vec3(0, 0, ro.z + .25);
    lk.xy += path(lk.z);
    vec2 lkTwist = vec2(0, -.1);
    lkTwist *= rot2(-getTwist(lk.z));
    lk.xy += lkTwist;

    vec3 lp = vec3(0, 0, ro.z + 3.);
    lp.xy += path(lp.z);
    vec2 lpTwist = vec2(0, -.3);
    lpTwist *= rot2(-getTwist(lp.z));
    lp.xy += lpTwist;

    float FOV = 1.;
    float a = getTwist(ro.z);
    a += (path(ro.z).x - path(lk.z).x)/(ro.z - lk.z)/4.;
    vec3 fw = normalize(lk - ro);
    vec3 up = vec3(sin(a), cos(a), 0);
    vec3 cu = normalize(cross(up, fw));
    vec3 cv = cross(fw, cu);
    vec3 rd = normalize(uv.x*cu + uv.y*cv + fw/FOV);

    float t = trace(ro, rd);

    vec3 svGID = gID;
    float svObjID = objID;
    vec2 svP = gP;
    vec3 svGlow = gGlow.xyz;

    vec3 col = vec3(0);

    if(t < FAR){
        vec3 sp = ro + rd*t;
        vec3 sn = getNormal(sp);
        vec3 texCol;

        vec3 txP = sp;
        txP.xy -= path(txP.z);
        txP.xy *= rot2(getTwist(txP.z));

        if(svObjID<.5){
            vec3 tx = getTex(svGID.xy);
            texCol = smoothstep(-.5, 1., tx)*vec3(1, .8, 1.8);

            const float lvls = 8.;
            float yDist = (1.25 + abs(txP.y) + svGID.z*2.);
            float hLn = abs(mod(yDist + .5/lvls, 1./lvls) - .5/lvls);
            float hLn2 = abs(mod(yDist + .5/lvls - .008, 1./lvls) - .5/lvls);
            if(yDist - 2.5<.25/lvls) hLn = 1e5;
            if(yDist - 2.5<.25/lvls) hLn2 = 1e5;
            texCol = mix(texCol, texCol*2., 1. - smoothstep(0., .003, hLn2 - .0035));
            texCol = mix(texCol, texCol/2.5, 1. - smoothstep(0., .003, hLn - .0035));

            float fDot = length(txP.xz - svGID.xy) - .0086;
            texCol = mix(texCol, texCol*2., 1. - smoothstep(0., .005, fDot - .0035));
            texCol = mix(texCol, vec3(0), 1. - smoothstep(0., .005, fDot));
        } else {
            texCol = vec3(0);
        }

        vec3 ld = lp - sp;
        float lDist = max(length(ld), .001);
        ld /= lDist;

        float sh = softShadow(sp, lp, sn, 16.);
        float ao = calcAO(sp, sn);
        sh = min(sh + ao*.25, 1.);
        float atten = 3./(1. + lDist*lDist*.5);
        float diff = max( dot(sn, ld), 0.);
        diff *= diff*1.35;
        float spec = pow(max(dot(reflect(ld, sn), rd ), 0.), 32.);
        float fre = pow(clamp(1. - abs(dot(sn, rd))*.5, 0., 1.), 4.);

        col = texCol*(diff + ao*.25 + vec3(1, .4, .2)*fre*.25 + vec3(1, .4, .2)*spec*4.);
        col *= ao*sh*atten;
    }

    svGlow.xyz *= mix(vec3(4, 1, 2), vec3(4, 2, 1), min(svGlow.xyz*3.5, 1.25));
    col *= .25 + svGlow.xyz*8.;

    vec3 fog = mix(vec3(4, 1, 2), vec3(4, 2, 1), rd.y*.5 + .5);
    fog = mix(fog, fog.zyx, smoothstep(0., .35, uv.y - .35));
    col = mix(col, fog/1.5, smoothstep(0., .99, t*t/FAR/FAR));

    outColor = vec4(sqrt(max(col, 0.)), 1);
}
