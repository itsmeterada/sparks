#include <metal_stdlib>
using namespace metal;

struct Particle {
    float4 position;  // xyz = position, w = size
    float4 velocity;  // xyz = velocity, w = lifetime
    float4 color;     // rgba
};

struct RenderUniforms {
    float4x4 viewProjection;
    float sparkBrightness;
    float screenHeight;
};

struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

vertex VertexOut particle_vertex(
    device const Particle* particles [[buffer(0)]],
    constant RenderUniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]])
{
    VertexOut out;

    Particle p = particles[vid];

    // Skip dead particles
    if (p.velocity.w <= 0.0f) {
        out.position = float4(0.0f, 0.0f, -2.0f, 1.0f);
        out.pointSize = 0.0f;
        out.color = float4(0.0f);
        return out;
    }

    float4 clipPos = uniforms.viewProjection * float4(p.position.xyz, 1.0f);
    out.position = clipPos;

    // Point size attenuated by distance
    float dist = max(clipPos.w, 0.1f);
    out.pointSize = p.position.w * (uniforms.screenHeight * 0.1f) / dist;
    out.pointSize = clamp(out.pointSize, 1.0f, 64.0f);

    out.color = float4(p.color.rgb * uniforms.sparkBrightness, p.color.a);

    return out;
}

fragment float4 particle_fragment(
    VertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]])
{
    // Soft circle
    float2 coord = pointCoord - float2(0.5f);
    float d = length(coord) * 2.0f;
    float alpha = smoothstep(1.0f, 0.3f, d);

    if (alpha * in.color.a < 0.001f) {
        discard_fragment();
    }

    return float4(in.color.rgb, in.color.a * alpha);
}
