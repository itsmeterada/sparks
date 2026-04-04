#include <metal_stdlib>
using namespace metal;

struct Particle {
    float4 position;  // xyz = position, w = size
    float4 velocity;  // xyz = velocity, w = lifetime
    float4 color;     // rgba
};

struct SimParams {
    float deltaTime;
    float emitterX;
    float emitterY;
    float emitterZ;
    uint emitCount;
    uint maxParticles;
    float gravity;
    float damping;
    float baseLifetime;
    float lifetimeVariance;
    float sparkBrightness;
    uint frameNumber;
};

// Simple hash-based pseudo-random number generator
static uint hashVal(uint x) {
    x ^= x >> 16;
    x *= 0x45d9f3bu;
    x ^= x >> 16;
    x *= 0x45d9f3bu;
    x ^= x >> 16;
    return x;
}

kernel void particle_simulate(
    device Particle* particles [[buffer(0)]],
    constant SimParams& params [[buffer(1)]],
    uint id [[thread_position_in_grid]])
{
    if (id >= params.maxParticles) return;

    Particle p = particles[id];
    float lifetime = p.velocity.w;

    if (lifetime <= 0.0f) {
        // Dead particle — check if we should emit
        uint emitIndex = (id + params.frameNumber * 7919u) % params.maxParticles;
        if (emitIndex < params.emitCount) {
            // Generate random seeds
            uint seed0 = hashVal(id * 1973u + params.frameNumber * 9277u);
            uint seed1 = hashVal(seed0);
            uint seed2 = hashVal(seed1);
            uint seed3 = hashVal(seed2);
            uint seed4 = hashVal(seed3);
            uint seed5 = hashVal(seed4);

            float r0 = float(seed0) / float(0xFFFFFFFFu);
            float r1 = float(seed1) / float(0xFFFFFFFFu);
            float r2 = float(seed2) / float(0xFFFFFFFFu);
            float r3 = float(seed3) / float(0xFFFFFFFFu);
            float r4 = float(seed4) / float(0xFFFFFFFFu);
            float r5 = float(seed5) / float(0xFFFFFFFFu);

            // Position: emitter + small random offset
            float3 emitterPos = float3(params.emitterX, params.emitterY, params.emitterZ);
            float3 offset = float3((r0 - 0.5f) * 0.1f, (r1 - 0.5f) * 0.1f, (r2 - 0.5f) * 0.1f);
            p.position.xyz = emitterPos + offset;

            // Size: random 2.0 - 6.0
            p.position.w = mix(2.0f, 6.0f, r3);

            // Velocity: upward cone (30-degree half-angle), speed 5-15
            float speed = mix(5.0f, 15.0f, r4);
            float angle = r0 * 6.28318530718f;
            float coneAngle = r1 * 0.5236f;
            float sinCone = sin(coneAngle);
            p.velocity.x = sinCone * cos(angle) * speed;
            p.velocity.y = cos(coneAngle) * speed;
            p.velocity.z = sinCone * sin(angle) * speed;

            // Lifetime
            p.velocity.w = params.baseLifetime + (r5 - 0.5f) * 2.0f * params.lifetimeVariance;

            // Color: hot white-yellow
            float temp = r3;
            p.color = float4(1.0f, mix(0.8f, 1.0f, temp), mix(0.3f, 0.9f, temp), 1.0f);
        }
    } else {
        // Live particle — simulate
        p.velocity.y += params.gravity * params.deltaTime;
        p.velocity.xyz *= params.damping;
        p.position.xyz += p.velocity.xyz * params.deltaTime;
        p.velocity.w -= params.deltaTime;

        float lifeRatio = clamp(p.velocity.w / params.baseLifetime, 0.0f, 1.0f);

        // Temperature-based color
        p.color.r = mix(0.8f, 1.0f, lifeRatio);
        p.color.g = mix(0.1f, 1.0f, lifeRatio * lifeRatio);
        p.color.b = mix(0.0f, 0.7f, lifeRatio * lifeRatio * lifeRatio);
        p.color.a = smoothstep(0.0f, 0.3f, p.velocity.w);

        p.position.w *= mix(0.98f, 1.0f, lifeRatio);
    }

    particles[id] = p;
}
