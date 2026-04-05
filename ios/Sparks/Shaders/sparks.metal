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

static float3 layeredParticles(float2 uv, float sizeMod, float alphaMod, int layers, float smoke, float iTime) {
    float3 particles = float3(0);
    float size = 1.0;
    float alpha = 1.0;
    float2 offset = float2(0.0);

    for (int i = 0; i < layers; i++) {
        float2 noiseOffset = (noise2_2(uv * size * 2.0 + 0.5) - 0.5) * 0.15;
        float2 bokehUV = (uv * size + iTime * MOVEMENT_DIRECTION * MOVEMENT_SPEED) + offset + noiseOffset;
        particles += fireParticles(bokehUV, uv, iTime) * alpha * (1.0 - smoothstep(0.0, 1.0, smoke) * (float(i) / float(layers)));
        offset += hash2_2(float2(alpha, alpha)) * 10.0;
        alpha *= alphaMod;
        size *= sizeMod;
    }

    return particles;
}

// Cosmic - Ported from Shadertoy
// https://www.shadertoy.com/view/XXyGzh
// Original Author: Nguyen2007
// License: CC BY-NC-SA 3.0

fragment float4 cosmic_fragment(VertexOut in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;

    float2 v = uniforms.iResolution;
    float2 u = 0.035 * (fragCoord + fragCoord - v) / v.y;

    float4 z = float4(1.0, 2.0, 3.0, 0.0);
    float4 o = z;

    float a = 0.5;
    float t = iTime;
    for (float i = 1.0; i < 19.0; i += 1.0) {
        t += 1.0;
        a += 0.03;
        v = cos(t - 7.0 * u * pow(a, i)) - 5.0 * u;

        float4 cv = cos(i + 0.02 * t - z.wxzw * 11.0);
        float2x2 m = float2x2(float2(cv.x, cv.y), float2(cv.z, cv.w));
        u = u * m;

        float d = dot(u, u);
        u += tanh(40.0 * d * cos(1e2 * u.yx + t)) / 2e2
           + 0.2 * a * u
           + cos(4.0 / exp(dot(o, o) / 1e2) + t) / 3e2;

        // Protect against NaN from sin(inf) when dot(u,u) approaches 0.5
        float duu = dot(u, u);
        float divisor = 0.5 - duu;
        divisor = divisor >= 0.0 ? max(divisor, 1e-4) : min(divisor, -1e-4);

        float len = length((1.0 + i * dot(v, v))
                  * sin(1.5 * u / divisor - 9.0 * u.yx + t));
        if (len > 0.0 && !isnan(len)) {
            o += (1.0 + cos(z + t)) / len;
        }
    }

    o = 25.6 / (min(o, 13.0) + 164.0 / o)
      - dot(u, u) / 250.0;

    return float4(o.rgb, 1.0);
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

    float3 particles = layeredParticles(uv, SIZE_MOD, ALPHA_MOD, LAYERS_COUNT, smokeIntensity, iTime);

    float3 col = particles + smoke + SMOKE_COLOR * 0.02;
    col *= vignette;

    col = smoothstep(-0.08, 1.0, col);

    return float4(col, 1.0);
}

// Starship - Ported from Shadertoy
// https://www.shadertoy.com/view/l3cfW4
// Original Author: @XorDev
// License: CC BY-NC-SA 3.0

struct StarshipUniforms {
    float2 iResolution;
    float iTime;
    float _pad;
    float4 iMouse;
};

fragment float4 starship_fragment(VertexOut in [[stage_in]],
                                  constant StarshipUniforms& uniforms [[buffer(0)]],
                                  texture2d<float> iChannel0 [[texture(0)]],
                                  sampler samp [[sampler(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;

    float2 r = uniforms.iResolution;
    float2x2 rm = float2x2(float2(3.0, 4.0), float2(4.0, -3.0));
    float2 p = (fragCoord + fragCoord - r) / r.y * rm / 1e2;

    float4 S = float4(0.0);
    float4 C = float4(1.0, 2.0, 3.0, 0.0);
    float4 W;

    float t = iTime;
    float T = 0.1 * t + p.y;
    for (float i = 1.0; i <= 50.0; i += 1.0) {
        W = sin(i) * C;

        p += 0.02 * cos(i * (C.xzxz + 8.0 + i) + T + T).xy;

        float texVal = iChannel0.sample(samp, p / exp(W.x) + float2(i, t) / 8.0).x;
        float2 p2 = p / float2(2.0, texVal * 40.0);
        float2 mp = max(p, p2);
        float l = length(mp);

        S += (cos(W) + 1.0) * exp(sin(i + i * T)) / l / 1e4;
    }

    C -= 1.0;
    float4 col = tanh(p.x * C + S * S);
    col.a = 1.0;
    return col;
}

// Clouds - Ported from Shadertoy
// https://www.shadertoy.com/view/XslGRr
// Original Author: Inigo Quilez
// License: Educational use only (see original for full terms)

struct CloudsUniforms {
    float2 iResolution;
    float iTime;
    float _pad;
    float4 iMouse;
};

static float3x3 setCamera(float3 ro, float3 ta, float cr) {
    float3 cw = normalize(ta - ro);
    float3 cp = float3(sin(cr), cos(cr), 0.0);
    float3 cu = normalize(cross(cw, cp));
    float3 cv = normalize(cross(cu, cw));
    return float3x3(cu, cv, cw);
}

static float clouds_noise(float3 x, texture3d<float> noiseTex, sampler samp) {
    float3 p = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float3 uvw = p + f;
    return noiseTex.sample(samp, (uvw + 0.5) / 32.0, level(0.0)).x * 2.0 - 1.0;
}

static float map5(float3 p, float iTime, texture3d<float> noiseTex, sampler samp) {
    float3 q = p - float3(0.0, 0.1, 1.0) * iTime;
    float a = 0.5;
    float f = 0.0;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.02; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.03; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.01; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.02; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp);
    return clamp(1.5 - p.y - 2.0 + 1.75 * f, 0.0, 1.0);
}

static float map4(float3 p, float iTime, texture3d<float> noiseTex, sampler samp) {
    float3 q = p - float3(0.0, 0.1, 1.0) * iTime;
    float a = 0.5;
    float f = 0.0;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.02; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.03; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.01; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp);
    return clamp(1.5 - p.y - 2.0 + 1.75 * f, 0.0, 1.0);
}

static float map3(float3 p, float iTime, texture3d<float> noiseTex, sampler samp) {
    float3 q = p - float3(0.0, 0.1, 1.0) * iTime;
    float a = 0.5;
    float f = 0.0;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.02; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.03; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp);
    return clamp(1.5 - p.y - 2.0 + 1.75 * f, 0.0, 1.0);
}

static float map2(float3 p, float iTime, texture3d<float> noiseTex, sampler samp) {
    float3 q = p - float3(0.0, 0.1, 1.0) * iTime;
    float a = 0.5;
    float f = 0.0;
    f += a * clouds_noise(q, noiseTex, samp); q = q * 2.02; a *= 0.5;
    f += a * clouds_noise(q, noiseTex, samp);
    return clamp(1.5 - p.y - 2.0 + 1.75 * f, 0.0, 1.0);
}

constant float3 sundir = float3(-0.7071, 0.0, -0.7071);

static float4 raymarch(float3 ro, float3 rd, float3 bgcol, int2 px,
                        float iTime, texture3d<float> noiseTex,
                        texture2d<float> noiseTex2d, sampler samp) {
    float4 sum = float4(0.0);
    float t = 0.05 * noiseTex2d.read(uint2(px & 255), 0).x;

    // MARCH macro expanded: map5 x40
    for (int i = 0; i < 40; i++) {
        float3 pos = ro + t * rd;
        if (pos.y < -3.0 || pos.y > 2.0 || sum.a > 0.99) break;
        float den = map5(pos, iTime, noiseTex, samp);
        if (den > 0.01) {
            float dif = clamp((den - map5(pos + 0.3 * sundir, iTime, noiseTex, samp)) / 0.6, 0.0, 1.0);
            float3 lin = float3(1.0, 0.6, 0.3) * dif + float3(0.91, 0.98, 1.05);
            float4 col = float4(mix(float3(1.0, 0.95, 0.8), float3(0.25, 0.3, 0.35), den), den);
            col.xyz *= lin;
            col.xyz = mix(col.xyz, bgcol, 1.0 - exp(-0.003 * t * t));
            col.w *= 0.4;
            col.rgb *= col.a;
            sum += col * (1.0 - sum.a);
        }
        t += max(0.06, 0.05 * t);
    }
    // MARCH: map4 x40
    for (int i = 0; i < 40; i++) {
        float3 pos = ro + t * rd;
        if (pos.y < -3.0 || pos.y > 2.0 || sum.a > 0.99) break;
        float den = map4(pos, iTime, noiseTex, samp);
        if (den > 0.01) {
            float dif = clamp((den - map4(pos + 0.3 * sundir, iTime, noiseTex, samp)) / 0.6, 0.0, 1.0);
            float3 lin = float3(1.0, 0.6, 0.3) * dif + float3(0.91, 0.98, 1.05);
            float4 col = float4(mix(float3(1.0, 0.95, 0.8), float3(0.25, 0.3, 0.35), den), den);
            col.xyz *= lin;
            col.xyz = mix(col.xyz, bgcol, 1.0 - exp(-0.003 * t * t));
            col.w *= 0.4;
            col.rgb *= col.a;
            sum += col * (1.0 - sum.a);
        }
        t += max(0.06, 0.05 * t);
    }
    // MARCH: map3 x30
    for (int i = 0; i < 30; i++) {
        float3 pos = ro + t * rd;
        if (pos.y < -3.0 || pos.y > 2.0 || sum.a > 0.99) break;
        float den = map3(pos, iTime, noiseTex, samp);
        if (den > 0.01) {
            float dif = clamp((den - map3(pos + 0.3 * sundir, iTime, noiseTex, samp)) / 0.6, 0.0, 1.0);
            float3 lin = float3(1.0, 0.6, 0.3) * dif + float3(0.91, 0.98, 1.05);
            float4 col = float4(mix(float3(1.0, 0.95, 0.8), float3(0.25, 0.3, 0.35), den), den);
            col.xyz *= lin;
            col.xyz = mix(col.xyz, bgcol, 1.0 - exp(-0.003 * t * t));
            col.w *= 0.4;
            col.rgb *= col.a;
            sum += col * (1.0 - sum.a);
        }
        t += max(0.06, 0.05 * t);
    }
    // MARCH: map2 x30
    for (int i = 0; i < 30; i++) {
        float3 pos = ro + t * rd;
        if (pos.y < -3.0 || pos.y > 2.0 || sum.a > 0.99) break;
        float den = map2(pos, iTime, noiseTex, samp);
        if (den > 0.01) {
            float dif = clamp((den - map2(pos + 0.3 * sundir, iTime, noiseTex, samp)) / 0.6, 0.0, 1.0);
            float3 lin = float3(1.0, 0.6, 0.3) * dif + float3(0.91, 0.98, 1.05);
            float4 col = float4(mix(float3(1.0, 0.95, 0.8), float3(0.25, 0.3, 0.35), den), den);
            col.xyz *= lin;
            col.xyz = mix(col.xyz, bgcol, 1.0 - exp(-0.003 * t * t));
            col.w *= 0.4;
            col.rgb *= col.a;
            sum += col * (1.0 - sum.a);
        }
        t += max(0.06, 0.05 * t);
    }

    return clamp(sum, 0.0, 1.0);
}

static float4 clouds_render(float3 ro, float3 rd, int2 px,
                             float iTime, texture3d<float> noiseTex,
                             texture2d<float> noiseTex2d, sampler samp) {
    float sun = clamp(dot(sundir, rd), 0.0, 1.0);
    float3 col = float3(0.6, 0.71, 0.75) - rd.y * 0.2 * float3(1.0, 0.5, 1.0) + 0.15 * 0.5;
    col += 0.2 * float3(1.0, 0.6, 0.1) * pow(sun, 8.0);
    float4 res = raymarch(ro, rd, col, px, iTime, noiseTex, noiseTex2d, samp);
    col = col * (1.0 - res.w) + res.xyz;
    col += float3(0.2, 0.08, 0.04) * pow(sun, 3.0);
    return float4(col, 1.0);
}

fragment float4 clouds_fragment(VertexOut in [[stage_in]],
                                constant CloudsUniforms& uniforms [[buffer(0)]],
                                texture2d<float> iChannel0 [[texture(0)]],
                                texture2d<float> iChannel1 [[texture(1)]],
                                texture3d<float> iChannel2 [[texture(2)]],
                                sampler samp [[sampler(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 p = (2.0 * fragCoord - uniforms.iResolution) / uniforms.iResolution.y;

    float2 m;
    if (uniforms.iMouse.z > 0.0) {
        m = uniforms.iMouse.xy / uniforms.iResolution;
    } else {
        m = float2(0.5 + 0.15 * sin(iTime * 0.1), 0.4);
    }

    float3 ro = 4.0 * normalize(float3(sin(3.0 * m.x), 0.8 * m.y, cos(3.0 * m.x))) - float3(0.0, 0.1, 0.0);
    float3 ta = float3(0.0, -1.0, 0.0);
    float3x3 ca = setCamera(ro, ta, 0.07 * cos(0.25 * iTime));
    float3 rd = ca * normalize(float3(p, 1.5));

    return clouds_render(ro, rd, int2(fragCoord - 0.5), iTime, iChannel2, iChannel1, samp);
}
