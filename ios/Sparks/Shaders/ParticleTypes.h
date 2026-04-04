#ifndef ParticleTypes_h
#define ParticleTypes_h

#include <simd/simd.h>

struct ParticleTypesSimParams {
    float deltaTime;
    float emitterX;
    float emitterY;
    float emitterZ;
    unsigned int emitCount;
    unsigned int maxParticles;
    float gravity;
    float damping;
    float baseLifetime;
    float lifetimeVariance;
    float sparkBrightness;
    unsigned int frameNumber;
};

struct ParticleTypesRenderUniforms {
    simd_float4x4 viewProjection;
    float sparkBrightness;
    float screenHeight;
};

#endif /* ParticleTypes_h */
