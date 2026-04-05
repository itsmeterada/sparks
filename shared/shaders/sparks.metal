#include <metal_stdlib>
using namespace metal;

// Sparks - Ported from Shadertoy
// Original Shader License: CC BY 3.0
// Original Author: Jan Mróz (jaszunio15)

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float2 iResolution;
    float iTime;
    float _pad;
    float4 iMouse;
    int mode;
};

vertex VertexOut sparks_vertex(uint vid [[vertex_id]]) {
    VertexOut out;
    float2 pos = float2((vid << 1) & 2, vid & 2);
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = pos;
    return out;
}

// --- Common functions ---

static float hash1_2(float2 x) {
    return fract(sin(dot(x, float2(52.127, 61.2871))) * 521.582);
}

static float2 hash2_2(float2 x) {
    float2x2 m = float2x2(float2(20.52, 24.1994), float2(70.291, 80.171));
    return fract(sin(x * m) * 492.194);
}

static float2 noise2_2(float2 uv) {
    float2 f = smoothstep(0.0, 1.0, fract(uv));

    float2 uv00 = floor(uv);
    float2 uv01 = uv00 + float2(0, 1);
    float2 uv10 = uv00 + float2(1, 0);
    float2 uv11 = uv00 + 1.0;
    float2 v00 = hash2_2(uv00);
    float2 v01 = hash2_2(uv01);
    float2 v10 = hash2_2(uv10);
    float2 v11 = hash2_2(uv11);

    float2 v0 = mix(v00, v01, f.y);
    float2 v1 = mix(v10, v11, f.y);
    return mix(v0, v1, f.x);
}

static float noise1_2(float2 uv) {
    float2 f = fract(uv);

    float2 uv00 = floor(uv);
    float2 uv01 = uv00 + float2(0, 1);
    float2 uv10 = uv00 + float2(1, 0);
    float2 uv11 = uv00 + 1.0;

    float v00 = hash1_2(uv00);
    float v01 = hash1_2(uv01);
    float v10 = hash1_2(uv10);
    float v11 = hash1_2(uv11);

    float v0 = mix(v00, v01, f.y);
    float v1 = mix(v10, v11, f.y);
    return mix(v0, v1, f.x);
}

// --- Constants ---

#define ANIMATION_SPEED 1.5
#define MOVEMENT_SPEED 1.0
#define MOVEMENT_DIRECTION float2(0.7, -1.0)

#define PARTICLE_SIZE 0.009

#define PARTICLE_SCALE (float2(0.5, 1.6))
#define PARTICLE_SCALE_VAR (float2(0.25, 0.2))

#define PARTICLE_BLOOM_SCALE (float2(0.5, 0.8))
#define PARTICLE_BLOOM_SCALE_VAR (float2(0.3, 0.1))

#define SPARK_COLOR (float3(1.0, 0.4, 0.05) * 1.5)
#define BLOOM_COLOR (float3(1.0, 0.4, 0.05) * 0.8)
#define SMOKE_COLOR (float3(1.0, 0.43, 0.1) * 0.8)

#define SIZE_MOD 1.05
#define ALPHA_MOD 0.9
#define LAYERS_COUNT 15

// --- Image functions ---

static float layeredNoise1_2(float2 uv, float sizeMod, float alphaMod, int layers, float animation, float iTime) {
    float noise = 0.0;
    float alpha = 1.0;
    float size = 1.0;
    float2 offset = float2(0.0);
    for (int i = 0; i < layers; i++) {
        offset += hash2_2(float2(alpha, size)) * 10.0;
        noise += noise1_2(uv * size + iTime * animation * 8.0 * MOVEMENT_DIRECTION * MOVEMENT_SPEED + offset) * alpha;
        alpha *= alphaMod;
        size *= sizeMod;
    }
    noise *= (1.0 - alphaMod) / (1.0 - pow(alphaMod, float(layers)));
    return noise;
}

static float2 rotate(float2 point, float deg) {
    float s = sin(deg);
    float c = cos(deg);
    return float2x2(float2(s, c), float2(-c, s)) * point;
}

static float2 voronoiPointFromRoot(float2 root, float deg) {
    float2 point = hash2_2(root) - 0.5;
    float s = sin(deg);
    float c = cos(deg);
    point = float2x2(float2(s, c), float2(-c, s)) * point * 0.66;
    point += root + 0.5;
    return point;
}

static float degFromRootUV(float2 uv, float iTime) {
    return iTime * ANIMATION_SPEED * (hash1_2(uv) - 0.5) * 2.0;
}

static float2 randomAround2_2(float2 point, float2 range, float2 uv) {
    return point + (hash2_2(uv) - 0.5) * range;
}

static float3 fireParticles(float2 uv, float2 originalUV, float iTime) {
    float3 particles = float3(0.0);
    float2 rootUV = floor(uv);
    float deg = degFromRootUV(rootUV, iTime);
    float2 pointUV = voronoiPointFromRoot(rootUV, deg);

    float2 tempUV = uv + (noise2_2(uv * 2.0) - 0.5) * 0.1;
    tempUV += -(noise2_2(uv * 3.0 + iTime) - 0.5) * 0.07;

    float dist = length(rotate(tempUV - pointUV, 0.7) * randomAround2_2(PARTICLE_SCALE, PARTICLE_SCALE_VAR, rootUV));
    float distBloom = length(rotate(tempUV - pointUV, 0.7) * randomAround2_2(PARTICLE_BLOOM_SCALE, PARTICLE_BLOOM_SCALE_VAR, rootUV));

    particles += (1.0 - smoothstep(PARTICLE_SIZE * 0.6, PARTICLE_SIZE * 3.0, dist)) * SPARK_COLOR;
    particles += pow((1.0 - smoothstep(0.0, PARTICLE_SIZE * 6.0, distBloom)) * 1.0, 3.0) * BLOOM_COLOR;

    float border = (hash1_2(rootUV) - 0.5) * 2.0;
    float disappear = 1.0 - smoothstep(border, border + 0.5, originalUV.y);

    border = (hash1_2(rootUV + 0.214) - 1.8) * 0.7;
    float appear = smoothstep(border, border + 0.4, originalUV.y);

    return particles * disappear * appear;
}

static float3 layeredParticles(float2 uv, float sizeMod, float alphaMod, int layers, float smoke, float iTime,
                                int mode, float4 iMouse, float2 iResolution) {
    float3 particles = float3(0);
    float size = 1.0;
    float alpha = 1.0;
    float2 offset = float2(0.0);

    float2 parallaxDir = float2(0.0);
    if (mode == 1) {
        if (iMouse.z > 0.0) {
            parallaxDir = (iMouse.xy / iResolution - 0.5) * 2.0;
        } else {
            parallaxDir = float2(sin(iTime * 0.3) * 0.3, cos(iTime * 0.2) * 0.15);
        }
    }

    for (int i = 0; i < layers; i++) {
        float2 noiseOffset = (noise2_2(uv * size * 2.0 + 0.5) - 0.5) * 0.15;
        float2 bokehUV = (uv * size + iTime * MOVEMENT_DIRECTION * MOVEMENT_SPEED) + offset + noiseOffset;

        if (mode == 1) {
            float depth = float(i) / float(layers);
            bokehUV += parallaxDir * depth * 0.5;
        }

        particles += fireParticles(bokehUV, uv, iTime) * alpha * (1.0 - smoothstep(0.0, 1.0, smoke) * (float(i) / float(layers)));
        offset += hash2_2(float2(alpha, alpha)) * 10.0;
        alpha *= alphaMod;
        size *= sizeMod;
    }

    return particles;
}

// --- Clouds shader (Shader 4) ---
// Ported from https://www.shadertoy.com/view/XslGRr
// Original Author: Inigo Quilez
// License: Educational use only

static float3x3 setCamera( float3 ro, float3 ta, float cr )
{
    float3 cw = normalize(ta-ro);
    float3 cp = float3(sin(cr), cos(cr), 0.0);
    float3 cu = normalize( cross(cw,cp) );
    float3 cv = normalize( cross(cu,cw) );
    return float3x3( cu, cv, cw );
}

static float clouds_noise( float3 x, texture3d<float> ch2, sampler s )
{
    float3 p = floor(x);
    float3 f = fract(x);
    f = f*f*(3.0-2.0*f);
    float3 uvw = p + f;
    return ch2.sample(s, (uvw+0.5)/32.0, level(0)).x * 2.0 - 1.0;
}

static float clouds_map5( float3 p, float iTime, texture3d<float> ch2, sampler s )
{
    float3 q = p - float3(0.0,0.1,1.0)*iTime;
    float f; float a = 0.5;
    f  = a*clouds_noise(q,ch2,s); q = q*2.02; a = a*0.5;
    f += a*clouds_noise(q,ch2,s); q = q*2.03; a = a*0.5;
    f += a*clouds_noise(q,ch2,s); q = q*2.01; a = a*0.5;
    f += a*clouds_noise(q,ch2,s); q = q*2.02; a = a*0.5;
    f += a*clouds_noise(q,ch2,s);
    return clamp( 1.5 - p.y - 2.0 + 1.75*f, 0.0, 1.0 );
}
static float clouds_map4( float3 p, float iTime, texture3d<float> ch2, sampler s )
{
    float3 q = p - float3(0.0,0.1,1.0)*iTime;
    float f; float a = 0.5;
    f  = a*clouds_noise(q,ch2,s); q = q*2.02; a = a*0.5;
    f += a*clouds_noise(q,ch2,s); q = q*2.03; a = a*0.5;
    f += a*clouds_noise(q,ch2,s); q = q*2.01; a = a*0.5;
    f += a*clouds_noise(q,ch2,s);
    return clamp( 1.5 - p.y - 2.0 + 1.75*f, 0.0, 1.0 );
}
static float clouds_map3( float3 p, float iTime, texture3d<float> ch2, sampler s )
{
    float3 q = p - float3(0.0,0.1,1.0)*iTime;
    float f; float a = 0.5;
    f  = a*clouds_noise(q,ch2,s); q = q*2.02; a = a*0.5;
    f += a*clouds_noise(q,ch2,s); q = q*2.03; a = a*0.5;
    f += a*clouds_noise(q,ch2,s);
    return clamp( 1.5 - p.y - 2.0 + 1.75*f, 0.0, 1.0 );
}
static float clouds_map2( float3 p, float iTime, texture3d<float> ch2, sampler s )
{
    float3 q = p - float3(0.0,0.1,1.0)*iTime;
    float f; float a = 0.5;
    f  = a*clouds_noise(q,ch2,s); q = q*2.02; a = a*0.5;
    f += a*clouds_noise(q,ch2,s);
    return clamp( 1.5 - p.y - 2.0 + 1.75*f, 0.0, 1.0 );
}

static float4 clouds_raymarch( float3 ro, float3 rd, float3 bgcol, int2 px,
                                float iTime, texture3d<float> ch2, texture2d<float> ch1, sampler s )
{
    constant float3 sundir = float3(-0.7071, 0.0, -0.7071);
    float4 sum = float4(0.0);
    float t = 0.05 * ch1.read(uint2(px & 255), 0).x;

    for(int i=0; i<40; i++) { float3 pos = ro + t*rd; if( pos.y<-3.0 || pos.y>2.0 || sum.a>0.99 ) break; float den = clouds_map5(pos,iTime,ch2,s); if( den>0.01 ) { float dif = clamp((den - clouds_map5(pos+0.3*sundir,iTime,ch2,s))/0.6, 0.0, 1.0); float3 lin = float3(1.0,0.6,0.3)*dif+float3(0.91,0.98,1.05); float4 col = float4( mix(float3(1.0,0.95,0.8), float3(0.25,0.3,0.35), den), den); col.xyz *= lin; col.xyz = mix(col.xyz, bgcol, 1.0-exp(-0.003*t*t)); col.w *= 0.4; col.rgb *= col.a; sum += col*(1.0-sum.a); } t += max(0.06f,0.05f*t); }
    for(int i=0; i<40; i++) { float3 pos = ro + t*rd; if( pos.y<-3.0 || pos.y>2.0 || sum.a>0.99 ) break; float den = clouds_map4(pos,iTime,ch2,s); if( den>0.01 ) { float dif = clamp((den - clouds_map4(pos+0.3*sundir,iTime,ch2,s))/0.6, 0.0, 1.0); float3 lin = float3(1.0,0.6,0.3)*dif+float3(0.91,0.98,1.05); float4 col = float4( mix(float3(1.0,0.95,0.8), float3(0.25,0.3,0.35), den), den); col.xyz *= lin; col.xyz = mix(col.xyz, bgcol, 1.0-exp(-0.003*t*t)); col.w *= 0.4; col.rgb *= col.a; sum += col*(1.0-sum.a); } t += max(0.06f,0.05f*t); }
    for(int i=0; i<30; i++) { float3 pos = ro + t*rd; if( pos.y<-3.0 || pos.y>2.0 || sum.a>0.99 ) break; float den = clouds_map3(pos,iTime,ch2,s); if( den>0.01 ) { float dif = clamp((den - clouds_map3(pos+0.3*sundir,iTime,ch2,s))/0.6, 0.0, 1.0); float3 lin = float3(1.0,0.6,0.3)*dif+float3(0.91,0.98,1.05); float4 col = float4( mix(float3(1.0,0.95,0.8), float3(0.25,0.3,0.35), den), den); col.xyz *= lin; col.xyz = mix(col.xyz, bgcol, 1.0-exp(-0.003*t*t)); col.w *= 0.4; col.rgb *= col.a; sum += col*(1.0-sum.a); } t += max(0.06f,0.05f*t); }
    for(int i=0; i<30; i++) { float3 pos = ro + t*rd; if( pos.y<-3.0 || pos.y>2.0 || sum.a>0.99 ) break; float den = clouds_map2(pos,iTime,ch2,s); if( den>0.01 ) { float dif = clamp((den - clouds_map2(pos+0.3*sundir,iTime,ch2,s))/0.6, 0.0, 1.0); float3 lin = float3(1.0,0.6,0.3)*dif+float3(0.91,0.98,1.05); float4 col = float4( mix(float3(1.0,0.95,0.8), float3(0.25,0.3,0.35), den), den); col.xyz *= lin; col.xyz = mix(col.xyz, bgcol, 1.0-exp(-0.003*t*t)); col.w *= 0.4; col.rgb *= col.a; sum += col*(1.0-sum.a); } t += max(0.06f,0.05f*t); }

    return clamp( sum, 0.0, 1.0 );
}

fragment float4 clouds_fragment(VertexOut in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]],
                                texture2d<float> iChannel0 [[texture(0)]],
                                texture2d<float> iChannel1 [[texture(1)]],
                                texture3d<float> iChannel2 [[texture(2)]],
                                sampler texSampler [[sampler(0)]]) {
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 p = (2.0*fragCoord - uniforms.iResolution) / uniforms.iResolution.y;
    float iTime = uniforms.iTime;

    float2 m;
    if (uniforms.iMouse.z > 0.0) {
        m = uniforms.iMouse.xy / uniforms.iResolution;
    } else {
        m = float2(0.5 + 0.15*sin(iTime*0.1), 0.4);
    }
    float3 ro = 4.0*normalize(float3(sin(3.0*m.x), 0.8*m.y, cos(3.0*m.x))) - float3(0.0,0.1,0.0);
    float3 ta = float3(0.0, -1.0, 0.0);
    float3x3 ca = setCamera(ro, ta, 0.07*cos(0.25*iTime));
    float3 rd = ca * normalize(float3(p.xy, 1.5));

    constant float3 sundir = float3(-0.7071, 0.0, -0.7071);
    float sun = clamp( dot(sundir,rd), 0.0, 1.0 );
    float3 col = float3(0.6,0.71,0.75) - rd.y*0.2*float3(1.0,0.5,1.0) + 0.15*0.5;
    col += 0.2*float3(1.0,.6,0.1)*pow( sun, 8.0 );

    int2 px = int2(fragCoord - 0.5);
    float4 res = clouds_raymarch(ro, rd, col, px, iTime, iChannel2, iChannel1, texSampler);
    col = col*(1.0-res.w) + res.xyz;
    col += float3(0.2,0.08,0.04)*pow( sun, 3.0 );

    return float4(col, 1.0);
}

// --- Seascape shader (Shader 5) ---
// Ported from https://www.shadertoy.com/view/Ms2SD1
// Original Author: Alexander Alekseev aka TDM - 2014
// License: CC BY-NC-SA 3.0

static float sea_hash(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

static float sea_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return -1.0 + 2.0 * mix(
        mix(sea_hash(i + float2(0,0)), sea_hash(i + float2(1,0)), u.x),
        mix(sea_hash(i + float2(0,1)), sea_hash(i + float2(1,1)), u.x), u.y);
}

static float sea_diffuse(float3 n, float3 l, float p) {
    return pow(dot(n, l) * 0.4 + 0.6, p);
}

static float sea_specular(float3 n, float3 l, float3 e, float s) {
    float nrm = (s + 8.0) / (3.141592 * 8.0);
    return pow(max(dot(reflect(e, n), l), 0.0), s) * nrm;
}

static float3 sea_getSkyColor(float3 e) {
    e.y = (max(e.y, 0.0) * 0.8 + 0.2) * 0.8;
    return float3(pow(1.0 - e.y, 2.0), 1.0 - e.y, 0.6 + (1.0 - e.y) * 0.4) * 1.1;
}

static float sea_octave(float2 uv, float choppy) {
    uv += sea_noise(uv);
    float2 wv = 1.0 - abs(sin(uv));
    float2 swv = abs(cos(uv));
    wv = mix(wv, swv, wv);
    return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

static float sea_map(float3 p, float SEA_TIME) {
    constant float2x2 octave_m = float2x2(float2(1.6,1.2), float2(-1.2,1.6));
    float freq = 0.16, amp = 0.6, choppy = 4.0;
    float2 uv = p.xz; uv.x *= 0.75;
    float d, h = 0.0;
    for (int i = 0; i < 3; i++) {
        d = sea_octave((uv + SEA_TIME) * freq, choppy);
        d += sea_octave((uv - SEA_TIME) * freq, choppy);
        h += d * amp;
        uv *= octave_m; freq *= 1.9; amp *= 0.22;
        choppy = mix(choppy, 1.0, 0.2);
    }
    return p.y - h;
}

static float sea_map_detailed(float3 p, float SEA_TIME) {
    constant float2x2 octave_m = float2x2(float2(1.6,1.2), float2(-1.2,1.6));
    float freq = 0.16, amp = 0.6, choppy = 4.0;
    float2 uv = p.xz; uv.x *= 0.75;
    float d, h = 0.0;
    for (int i = 0; i < 5; i++) {
        d = sea_octave((uv + SEA_TIME) * freq, choppy);
        d += sea_octave((uv - SEA_TIME) * freq, choppy);
        h += d * amp;
        uv *= octave_m; freq *= 1.9; amp *= 0.22;
        choppy = mix(choppy, 1.0, 0.2);
    }
    return p.y - h;
}

static float3 sea_getNormal(float3 p, float eps, float SEA_TIME) {
    float3 n;
    n.y = sea_map_detailed(p, SEA_TIME);
    n.x = sea_map_detailed(float3(p.x+eps, p.y, p.z), SEA_TIME) - n.y;
    n.z = sea_map_detailed(float3(p.x, p.y, p.z+eps), SEA_TIME) - n.y;
    n.y = eps;
    return normalize(n);
}

static float3 sea_getSeaColor(float3 p, float3 n, float3 l, float3 eye, float3 dist) {
    constant float3 SEA_BASE = float3(0.0, 0.09, 0.18);
    constant float3 SEA_WATER_COLOR = float3(0.8, 0.9, 0.6) * 0.6;
    float fresnel = clamp(1.0 - dot(n, -eye), 0.0, 1.0);
    fresnel = min(fresnel * fresnel * fresnel, 0.5);
    float3 reflected = sea_getSkyColor(reflect(eye, n));
    float3 refracted = SEA_BASE + sea_diffuse(n, l, 80.0) * SEA_WATER_COLOR * 0.12;
    float3 color = mix(refracted, reflected, fresnel);
    float atten = max(1.0 - dot(dist, dist) * 0.001, 0.0);
    color += SEA_WATER_COLOR * (p.y - 0.6) * 0.18 * atten;
    color += sea_specular(n, l, eye, 600.0 * rsqrt(dot(dist, dist)));
    return color;
}

static float3x3 sea_fromEuler(float3 ang) {
    float2 a1 = float2(sin(ang.x), cos(ang.x));
    float2 a2 = float2(sin(ang.y), cos(ang.y));
    float2 a3 = float2(sin(ang.z), cos(ang.z));
    float3x3 m;
    m[0] = float3(a1.y*a3.y+a1.x*a2.x*a3.x, a1.y*a2.x*a3.x+a3.y*a1.x, -a2.y*a3.x);
    m[1] = float3(-a2.y*a1.x, a1.y*a2.y, a2.x);
    m[2] = float3(a3.y*a1.x*a2.x+a1.y*a3.x, a1.x*a3.x-a1.y*a3.y*a2.x, a2.y*a3.y);
    return m;
}

fragment float4 seascape_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
    float2 fragCoord = in.uv * uniforms.iResolution;
    float time = uniforms.iTime * 0.3 + uniforms.iMouse.x * 0.01;
    float SEA_TIME = 1.0 + uniforms.iTime * 0.8;

    float2 uv = fragCoord / uniforms.iResolution;
    uv = uv * 2.0 - 1.0;
    uv.x *= uniforms.iResolution.x / uniforms.iResolution.y;

    float3 ang = float3(sin(time*3.0)*0.1, sin(time)*0.2+0.3, time);
    float3 ori = float3(0.0, 3.5, time*5.0);
    float3 dir = normalize(float3(uv.xy, -2.0));
    dir.z += length(uv) * 0.14;
    dir = normalize(dir) * sea_fromEuler(ang);

    // heightmap tracing
    float3 p;
    float tm = 0.0, tx = 1000.0;
    float hx = sea_map(ori + dir * tx, SEA_TIME);
    if (hx > 0.0) { p = ori + dir * tx; }
    else {
        float hm = sea_map(ori, SEA_TIME);
        for (int i = 0; i < 32; i++) {
            float tmid = mix(tm, tx, hm / (hm - hx));
            p = ori + dir * tmid;
            float hmid = sea_map(p, SEA_TIME);
            if (hmid < 0.0) { tx = tmid; hx = hmid; }
            else { tm = tmid; hm = hmid; }
            if (abs(hmid) < 1e-3) break;
        }
    }

    float3 dist = p - ori;
    float3 n = sea_getNormal(p, dot(dist, dist) * 0.1 / uniforms.iResolution.x, SEA_TIME);
    float3 light = normalize(float3(0.0, 1.0, 0.8));
    float3 color = mix(
        sea_getSkyColor(dir),
        sea_getSeaColor(p, n, light, dir, dist),
        pow(smoothstep(0.0, -0.02, dir.y), 0.2));
    return float4(pow(color, float3(0.65)), 1.0);
}

// --- Starship shader (Shader 3) ---
// Ported from https://www.shadertoy.com/view/l3cfW4
// Original Author: @XorDev
// License: CC BY-NC-SA 3.0

fragment float4 starship_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]],
                                  texture2d<float> iChannel0 [[texture(0)]],
                                  sampler texSampler [[sampler(0)]]) {
    float2 fragCoord = in.uv * uniforms.iResolution;

    float2 r = uniforms.iResolution;
    float2 p = (fragCoord + fragCoord - r) / r.y * float2x2(float2(3, 4), float2(4, -3)) / 1e2;

    float4 S = float4(0.0);
    float4 C = float4(1, 2, 3, 0);
    float4 W;

    for (float t = uniforms.iTime, T = 0.1 * t + p.y, i = 0.0; i++ < 50.0;

        S += (cos(W = sin(i) * C) + 1.0)
           * exp(sin(i + i * T))
           / length(max(p,
               p / float2(2.0, iChannel0.sample(texSampler, p / exp(W.x) + float2(i, t) / 8.0).x * 40.0))
           ) / 1e4)

        p += 0.02 * cos(i * (C.xz + 8.0 + i) + T + T);

    C -= 1.0;
    float4 o = tanh(p.x * C + S * S);
    o.a = 1.0;
    return o;
}

// --- Cosmic shader (Shader 2) ---
// Ported from https://www.shadertoy.com/view/XXyGzh
// Original Author: Nguyen2007
// License: CC BY-NC-SA 3.0

fragment float4 cosmic_fragment(VertexOut in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]]) {
    float2 fragCoord = in.uv * uniforms.iResolution;

    float2 v = uniforms.iResolution;
    float2 u = 0.2 * (fragCoord + fragCoord - v) / v.y;

    float4 z = float4(1.0, 2.0, 3.0, 0.0);
    float4 o = z;

    for (float a = 0.5, t = uniforms.iTime, i = 0.0;
         ++i < 19.0;
         o += (1.0 + cos(z + t))
            / length((1.0 + i * dot(v, v))
                   * sin(1.5 * u / (0.5 - dot(u, u)) - 9.0 * u.yx + t))
         )
    {
        t += 1.0;
        a += 0.03;
        v = cos(t - 7.0 * u * pow(a, i)) - 5.0 * u;

        float4 cv = cos(i + 0.02 * t - z.wxzw * 11.0);
        u *= float2x2(float2(cv.x, cv.y), float2(cv.z, cv.w));

        float d = dot(u, u);
        u += tanh(40.0 * d * cos(1e2 * u.yx + t)) / 2e2
           + 0.2 * a * u
           + cos(4.0 / exp(dot(o, o) / 1e2) + t) / 3e2;
    }

    o = 25.6 / (min(o, 13.0) + 164.0 / o)
      - dot(u, u) / 250.0;

    return float4(o.xyz, 1.0);
}

fragment float4 sparks_fragment(VertexOut in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 uv = (2.0 * fragCoord - uniforms.iResolution) / uniforms.iResolution.x;

    float vignette = 1.0 - smoothstep(0.4, 1.4, length(uv + float2(0.0, 0.3)));

    uv *= 1.8;

    float smokeIntensity = layeredNoise1_2(uv * 10.0 + iTime * 4.0 * MOVEMENT_DIRECTION * MOVEMENT_SPEED, 1.7, 0.7, 6, 0.2, iTime);
    smokeIntensity *= pow(1.0 - smoothstep(-1.0, 1.6, uv.y), 2.0);
    float3 smoke = smokeIntensity * SMOKE_COLOR * 0.8 * vignette;

    smoke *= pow(layeredNoise1_2(uv * 4.0 + iTime * 0.5 * MOVEMENT_DIRECTION * MOVEMENT_SPEED, 1.8, 0.5, 3, 0.2, iTime), 2.0) * 1.5;

    float3 particles = layeredParticles(uv, SIZE_MOD, ALPHA_MOD, LAYERS_COUNT, smokeIntensity, iTime,
                                        uniforms.mode, uniforms.iMouse, uniforms.iResolution);

    float3 col = particles + smoke + SMOKE_COLOR * 0.02;
    col *= vignette;

    col = smoothstep(-0.08, 1.0, col);

    return float4(col, 1.0);
}
