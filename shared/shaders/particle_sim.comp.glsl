#version 450

layout(local_size_x = 256) in;

struct Particle {
    vec4 position;  // xyz = position, w = size
    vec4 velocity;  // xyz = velocity, w = lifetime
    vec4 color;     // rgba
};

layout(std430, binding = 0) buffer ParticleBuffer {
    Particle particles[];
};

layout(std140, binding = 1) uniform SimParamsUBO {
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
    uint frameNumber;
    float sparkBrightness;
};

// Simple hash-based pseudo-random number generator
uint hash(uint x) {
    x ^= x >> 16;
    x *= 0x45d9f3bu;
    x ^= x >> 16;
    x *= 0x45d9f3bu;
    x ^= x >> 16;
    return x;
}

float randomFloat(uint seed) {
    return float(hash(seed)) / float(0xFFFFFFFFu);
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= maxParticles) return;

    Particle p = particles[id];
    float lifetime = p.velocity.w;

    if (lifetime <= 0.0) {
        // Dead particle — check if we should emit
        // Use ring-buffer style emission: emit particles with index < emitCount
        // offset by frameNumber to distribute across the buffer
        uint emitIndex = (id + frameNumber * 7919u) % maxParticles;
        if (emitIndex < emitCount) {
            // Generate random seeds
            uint seed0 = hash(id * 1973u + frameNumber * 9277u);
            uint seed1 = hash(seed0);
            uint seed2 = hash(seed1);
            uint seed3 = hash(seed2);
            uint seed4 = hash(seed3);
            uint seed5 = hash(seed4);

            float r0 = float(seed0) / float(0xFFFFFFFFu);
            float r1 = float(seed1) / float(0xFFFFFFFFu);
            float r2 = float(seed2) / float(0xFFFFFFFFu);
            float r3 = float(seed3) / float(0xFFFFFFFFu);
            float r4 = float(seed4) / float(0xFFFFFFFFu);
            float r5 = float(seed5) / float(0xFFFFFFFFu);

            // Position: emitter + small random offset
            vec3 emitterPos = vec3(emitterX, emitterY, emitterZ);
            vec3 offset = vec3((r0 - 0.5) * 0.1, (r1 - 0.5) * 0.1, (r2 - 0.5) * 0.1);
            p.position.xyz = emitterPos + offset;

            // Size: random 2.0 - 6.0
            p.position.w = mix(2.0, 6.0, r3);

            // Velocity: upward cone (30-degree half-angle), speed 5-15
            float speed = mix(5.0, 15.0, r4);
            float angle = r0 * 6.28318530718; // azimuth
            float coneAngle = r1 * 0.5236;     // 0 to 30 degrees in radians
            float sinCone = sin(coneAngle);
            p.velocity.x = sinCone * cos(angle) * speed;
            p.velocity.y = cos(coneAngle) * speed;  // upward
            p.velocity.z = sinCone * sin(angle) * speed;

            // Lifetime
            p.velocity.w = baseLifetime + (r5 - 0.5) * 2.0 * lifetimeVariance;

            // Color: hot white-yellow for new particles
            float temp = r3;
            p.color = vec4(1.0, mix(0.8, 1.0, temp), mix(0.3, 0.9, temp), 1.0);
        }
    } else {
        // Live particle — simulate
        // Apply gravity
        p.velocity.y += gravity * deltaTime;

        // Apply damping
        p.velocity.xyz *= damping;

        // Update position
        p.position.xyz += p.velocity.xyz * deltaTime;

        // Decay lifetime
        p.velocity.w -= deltaTime;

        // Fade color based on remaining lifetime ratio
        float lifeRatio = clamp(p.velocity.w / baseLifetime, 0.0, 1.0);

        // Temperature-based color: white -> yellow -> orange -> red
        p.color.r = mix(0.8, 1.0, lifeRatio);
        p.color.g = mix(0.1, 1.0, lifeRatio * lifeRatio);
        p.color.b = mix(0.0, 0.7, lifeRatio * lifeRatio * lifeRatio);

        // Alpha fade in last 0.3 seconds
        p.color.a = smoothstep(0.0, 0.3, p.velocity.w);

        // Shrink size
        p.position.w *= mix(0.98, 1.0, lifeRatio);
    }

    particles[id] = p;
}
