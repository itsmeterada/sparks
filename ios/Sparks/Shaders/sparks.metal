#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Shared fullscreen vertex shader
vertex VertexOut sparks_vertex(uint vid [[vertex_id]]) {
    VertexOut out;
    float2 pos = float2((vid << 1) & 2, vid & 2);
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = pos;
    return out;
}

// Sparks - Ported from Shadertoy
// Original Shader License: CC BY 3.0
// Original Author: Jan Mróz (jaszunio15)

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
