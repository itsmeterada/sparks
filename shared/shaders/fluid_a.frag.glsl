#version 450
// Fluid Buffer A (velocity field)
// Ported from Shadertoy "mipmap-based multiscale fluid dynamics" by Cornus Ammonis

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

layout(set = 0, binding = 0) uniform sampler2D iChannel0; // velocity.src
layout(set = 0, binding = 1) uniform sampler2D iChannel1; // pressure.src
layout(set = 0, binding = 2) uniform sampler2D iChannel2; // confinement
layout(set = 0, binding = 3) uniform sampler2D iChannel3; // turbulence

// --- common defines ---
#define ADVECTION_STEPS 3
#define ADVECTION_SCALE 40.0
#define ADVECTION_TURBULENCE 1.0
#define VELOCITY_TURBULENCE 0.0000
#define VELOCITY_CONFINEMENT 0.01
#define VELOCITY_LAPLACIAN 0.02
#define ADVECTION_CONFINEMENT 0.6
#define ADVECTION_DIVERGENCE 0.0
#define ADVECTION_VELOCITY -0.05
#define DIVERGENCE_MINIMIZATION 0.1
#define DIVERGENCE_LOOKAHEAD 1.0
#define LAPLACIAN_LOOKAHEAD 1.0
#define DAMPING 0.0001
#define VELOCITY_SCALE 1.0
#define UPDATE_SMOOTHING 0.0
#define MOUSE_AMP 0.05
#define MOUSE_RADIUS 0.001
#define PUMP_SCALE 0.001
#define PUMP_CYCLE 0.2

vec2 normz(vec2 x) {
    return x == vec2(0.0) ? vec2(0.0) : normalize(x);
}

float hash1(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffffU);
}

vec3 hash3(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    uvec3 k = n * uvec3(n, n * 16807U, n * 48271U);
    return vec3(k & uvec3(0x7fffffffU)) / float(0x7fffffffU);
}

vec4 rand4(vec2 fragCoord, vec2 resolution, int frame) {
    uvec2 p = uvec2(fragCoord);
    uvec2 r = uvec2(resolution);
    uint c = p.x + r.x * p.y + r.x * r.y * uint(frame);
    return vec4(hash3(c), hash1(c + 75132895U));
}

// --- buffer_a specific ---
#define TURBULENCE_SAMPLER iChannel3
#define CONFINEMENT_SAMPLER iChannel2
#define POISSON_SAMPLER iChannel1
#define VELOCITY_SAMPLER iChannel0

#define V(d) texture(TURBULENCE_SAMPLER, fract((uvArg) + (d + 0.0))).xy

vec2 gaussian_turbulence(vec2 uvArg) {
    vec2 texel = 1.0 / iResolution.xy;
    vec4 t = vec4(texel, -texel.y, 0.0);
    vec2 d = V(t.ww); vec2 d_n = V(t.wy); vec2 d_e = V(t.xw); vec2 d_s = V(t.wz);
    vec2 d_w = V(-t.xw); vec2 d_nw = V(-t.xz); vec2 d_sw = V(-t.xy);
    vec2 d_ne = V(t.xy); vec2 d_se = V(t.xz);
    return 0.25 * d + 0.125 * (d_e + d_w + d_n + d_s) + 0.0625 * (d_ne + d_nw + d_se + d_sw);
}

#define C(d) texture(CONFINEMENT_SAMPLER, fract((uvArg) + (d + 0.0))).xy

vec2 gaussian_confinement(vec2 uvArg) {
    vec2 texel = 1.0 / iResolution.xy;
    vec4 t = vec4(texel, -texel.y, 0.0);
    vec2 d = C(t.ww); vec2 d_n = C(t.wy); vec2 d_e = C(t.xw); vec2 d_s = C(t.wz);
    vec2 d_w = C(-t.xw); vec2 d_nw = C(-t.xz); vec2 d_sw = C(-t.xy);
    vec2 d_ne = C(t.xy); vec2 d_se = C(t.xz);
    return 0.25 * d + 0.125 * (d_e + d_w + d_n + d_s) + 0.0625 * (d_ne + d_nw + d_se + d_sw);
}

#define D(d) texture(POISSON_SAMPLER, fract((uvArg) + d)).x

vec2 diff(vec2 uvArg) {
    vec2 texel = 1.0 / iResolution.xy;
    vec4 t = vec4(texel, -texel.y, 0.0);
    float d = D(t.ww); float d_n = D(t.wy); float d_e = D(t.xw); float d_s = D(t.wz);
    float d_w = D(-t.xw); float d_nw = D(-t.xz); float d_sw = D(-t.xy);
    float d_ne = D(t.xy); float d_se = D(t.xz);
    return vec2(
        0.5 * (d_e - d_w) + 0.25 * (d_ne - d_nw + d_se - d_sw),
        0.5 * (d_n - d_s) + 0.25 * (d_ne + d_nw - d_se - d_sw)
    );
}

#define N(d) texture(VELOCITY_SAMPLER, fract((uvArg) + (d + 0.0)))

vec4 gaussian_velocity(vec2 uvArg) {
    vec2 texel = 1.0 / iResolution.xy;
    vec4 t = vec4(texel, -texel.y, 0.0);
    vec4 d = N(t.ww); vec4 d_n = N(t.wy); vec4 d_e = N(t.xw); vec4 d_s = N(t.wz);
    vec4 d_w = N(-t.xw); vec4 d_nw = N(-t.xz); vec4 d_sw = N(-t.xy);
    vec4 d_ne = N(t.xy); vec4 d_se = N(t.xz);
    return 0.25 * d + 0.125 * (d_e + d_w + d_n + d_s) + 0.0625 * (d_ne + d_nw + d_se + d_sw);
}

vec2 vector_laplacian(vec2 uvArg) {
    const float k0 = -20.0 / 6.0;
    const float k1 = 4.0 / 6.0;
    const float k2 = 1.0 / 6.0;
    vec2 texel = 1.0 / iResolution.xy;
    vec4 t = vec4(texel, -texel.y, 0.0);
    vec4 d = N(t.ww); vec4 d_n = N(t.wy); vec4 d_e = N(t.xw); vec4 d_s = N(t.wz);
    vec4 d_w = N(-t.xw); vec4 d_nw = N(-t.xz); vec4 d_sw = N(-t.xy);
    vec4 d_ne = N(t.xy); vec4 d_se = N(t.xz);
    return (k0 * d + k1 * (d_e + d_w + d_n + d_s) + k2 * (d_ne + d_nw + d_se + d_sw)).xy;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uvArg = fragCoord / iResolution.xy;
    vec2 tx = 1.0 / iResolution.xy;

    vec2 turb = vec2(0.0); vec2 confine = vec2(0.0); vec2 div = vec2(0.0);
    vec2 delta_v = vec2(0.0); vec2 offset = vec2(0.0); vec2 lapl = vec2(0.0);
    vec4 vel; vec4 adv = vec4(0.0);
    vec4 init = N(vec2(0.0));

    for (int i = 0; i < ADVECTION_STEPS; i++) {
        turb = texture(TURBULENCE_SAMPLER, fract(uvArg + tx * offset)).xy;
        confine = texture(CONFINEMENT_SAMPLER, fract(uvArg + tx * offset)).xy;
        vel = texture(VELOCITY_SAMPLER, fract(uvArg + tx * offset));
        offset = (float(i + 1) / float(ADVECTION_STEPS)) * -ADVECTION_SCALE *
            (ADVECTION_VELOCITY * vel.xy +
                ADVECTION_TURBULENCE * turb -
                ADVECTION_CONFINEMENT * confine +
                ADVECTION_DIVERGENCE * div);
        div = diff(uvArg + tx * DIVERGENCE_LOOKAHEAD * offset);
        lapl = vector_laplacian(uvArg + tx * LAPLACIAN_LOOKAHEAD * offset);
        adv += texture(VELOCITY_SAMPLER, fract(uvArg + tx * offset));
        delta_v += VELOCITY_LAPLACIAN * lapl +
            VELOCITY_TURBULENCE * turb +
            VELOCITY_CONFINEMENT * confine -
            DAMPING * vel.xy -
            DIVERGENCE_MINIMIZATION * div;
    }
    adv /= float(ADVECTION_STEPS);
    delta_v /= float(ADVECTION_STEPS);

    vec2 pq = 2.0 * (uvArg * 2.0 - 1.0) * vec2(1.0, tx.x / tx.y);
    vec2 pump = vec2(0.0);

    const float amp = 15.0;
    const float scl = -50.0;
    float uvy0 = exp(scl * pow(pq.y, 2.0));
    float uvx0 = exp(scl * pow(uvArg.x, 2.0));
    pump += -amp * vec2(max(0.0, cos(PUMP_CYCLE * iTime)) * PUMP_SCALE * uvx0 * uvy0, 0.0);

    float uvy1 = exp(scl * pow(pq.y, 2.0));
    float uvx1 = exp(scl * pow(1.0 - uvArg.x, 2.0));
    pump += amp * vec2(max(0.0, cos(PUMP_CYCLE * iTime + 3.1416)) * PUMP_SCALE * uvx1 * uvy1, 0.0);

    float uvy2 = exp(scl * pow(pq.x, 2.0));
    float uvx2 = exp(scl * pow(uvArg.y, 2.0));
    pump += -amp * vec2(0.0, max(0.0, sin(PUMP_CYCLE * iTime)) * PUMP_SCALE * uvx2 * uvy2);

    float uvy3 = exp(scl * pow(pq.x, 2.0));
    float uvx3 = exp(scl * pow(1.0 - uvArg.y, 2.0));
    pump += amp * vec2(0.0, max(0.0, sin(PUMP_CYCLE * iTime + 3.1416)) * PUMP_SCALE * uvx3 * uvy3);

    fragColor = mix(adv + vec4(VELOCITY_SCALE * (delta_v + pump), offset), init, UPDATE_SMOOTHING);

    if (iMouse.z > 0.0) {
        vec4 mouseUV = iMouse / vec4(iResolution.xy, iResolution.xy);
        vec2 delta = normz(mouseUV.zw - mouseUV.xy);
        vec2 md = (mouseUV.xy - uvArg) * vec2(1.0, tx.x / tx.y);
        float ampMouse = exp(max(-12.0, -dot(md, md) / MOUSE_RADIUS));
        fragColor.xy += VELOCITY_SCALE * MOUSE_AMP * clamp(ampMouse * delta, -1.0, 1.0);
    }

    if (iFrame == 0) {
        fragColor = 1e-6 * rand4(fragCoord, iResolution.xy, iFrame);
    }
}

void main() {
    vec4 fc;
    mainImage(fc, gl_FragCoord.xy);
    outColor = fc;
}
