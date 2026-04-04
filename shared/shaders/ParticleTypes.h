// ParticleTypes.h
// Shared particle data structures for Sparks GPU particle demo
// Used by both GLSL (Vulkan) and MSL (Metal) shaders

#ifndef PARTICLE_TYPES_H
#define PARTICLE_TYPES_H

#ifdef __METAL_VERSION__
using namespace metal;
typedef float4 vec4;
typedef uint uint32_t;
#endif

struct Particle {
    vec4 position;  // xyz = position, w = size
    vec4 velocity;  // xyz = velocity, w = lifetime (seconds remaining)
    vec4 color;     // rgba
};

struct SimParams {
    float deltaTime;
    float emitterX;
    float emitterY;
    float emitterZ;
    uint32_t emitCount;
    uint32_t maxParticles;
    float gravity;
    float damping;
    float baseLifetime;
    float lifetimeVariance;
    float sparkBrightness;
    uint32_t frameNumber;
};

#endif // PARTICLE_TYPES_H
