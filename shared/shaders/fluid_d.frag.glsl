#version 450
// Fluid Buffer D (pressure field)
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

layout(set = 0, binding = 0) uniform sampler2D iChannel0; // velocity (current)
layout(set = 0, binding = 1) uniform sampler2D iChannel1; // pressure.src
layout(set = 0, binding = 2) uniform sampler2D iChannel2; // unused
layout(set = 0, binding = 3) uniform sampler2D iChannel3; // unused

#define POISSON_SCALES 11
#define POIS_ISOTROPY 0.16
#define POIS_W_FUNCTION (1.0 / float(i + 1))
#define PRESSURE_ADVECTION 0.0002
#define PRESSURE_LAPLACIAN 0.1
#define PRESSURE_UPDATE_SMOOTHING 0.0

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

#define VORT_SAMPLER iChannel0
#define POIS_SAMPLER iChannel1
#define DEGREE POISSON_SCALES

float reduce(mat3 a, mat3 b) {
    mat3 p = matrixCompMult(a, b);
    return p[0][0] + p[0][1] + p[0][2] +
        p[1][0] + p[1][1] + p[1][2] +
        p[2][0] + p[2][1] + p[2][2];
}

float laplacian_poisson(vec2 fragCoord) {
    const float k0 = -20.0 / 6.0;
    const float k1 = 4.0 / 6.0;
    const float k2 = 1.0 / 6.0;
    vec2 texel = 1.0 / iResolution.xy;
    vec2 uv = fragCoord * texel;
    vec4 t = vec4(texel, -texel.y, 0.0);
    float mip = 0.0;

    float p = textureLod(POIS_SAMPLER, fract(uv + t.ww), mip).x;
    float p_n = textureLod(POIS_SAMPLER, fract(uv + t.wy), mip).x;
    float p_e = textureLod(POIS_SAMPLER, fract(uv + t.xw), mip).x;
    float p_s = textureLod(POIS_SAMPLER, fract(uv + t.wz), mip).x;
    float p_w = textureLod(POIS_SAMPLER, fract(uv - t.xw), mip).x;
    float p_nw = textureLod(POIS_SAMPLER, fract(uv - t.xz), mip).x;
    float p_sw = textureLod(POIS_SAMPLER, fract(uv - t.xy), mip).x;
    float p_ne = textureLod(POIS_SAMPLER, fract(uv + t.xy), mip).x;
    float p_se = textureLod(POIS_SAMPLER, fract(uv + t.xz), mip).x;

    return k0 * p + k1 * (p_e + p_w + p_n + p_s) + k2 * (p_ne + p_nw + p_se + p_sw);
}

void tex(vec2 uv, out mat3 mx, out mat3 my, out mat3 mp, int degree) {
    vec2 texel = 1.0 / iResolution.xy;
    float stride = float(1 << degree);
    float mip = float(degree);
    vec4 t = stride * vec4(texel, -texel.y, 0.0);

    vec2 d = textureLod(VORT_SAMPLER, fract(uv + t.ww), mip).xy;
    vec2 d_n = textureLod(VORT_SAMPLER, fract(uv + t.wy), mip).xy;
    vec2 d_e = textureLod(VORT_SAMPLER, fract(uv + t.xw), mip).xy;
    vec2 d_s = textureLod(VORT_SAMPLER, fract(uv + t.wz), mip).xy;
    vec2 d_w = textureLod(VORT_SAMPLER, fract(uv - t.xw), mip).xy;
    vec2 d_nw = textureLod(VORT_SAMPLER, fract(uv - t.xz), mip).xy;
    vec2 d_sw = textureLod(VORT_SAMPLER, fract(uv - t.xy), mip).xy;
    vec2 d_ne = textureLod(VORT_SAMPLER, fract(uv + t.xy), mip).xy;
    vec2 d_se = textureLod(VORT_SAMPLER, fract(uv + t.xz), mip).xy;

    float p = textureLod(POIS_SAMPLER, fract(uv + t.ww), mip).x;
    float p_n = textureLod(POIS_SAMPLER, fract(uv + t.wy), mip).x;
    float p_e = textureLod(POIS_SAMPLER, fract(uv + t.xw), mip).x;
    float p_s = textureLod(POIS_SAMPLER, fract(uv + t.wz), mip).x;
    float p_w = textureLod(POIS_SAMPLER, fract(uv - t.xw), mip).x;
    float p_nw = textureLod(POIS_SAMPLER, fract(uv - t.xz), mip).x;
    float p_sw = textureLod(POIS_SAMPLER, fract(uv - t.xy), mip).x;
    float p_ne = textureLod(POIS_SAMPLER, fract(uv + t.xy), mip).x;
    float p_se = textureLod(POIS_SAMPLER, fract(uv + t.xz), mip).x;

    mx = mat3(d_nw.x, d_n.x, d_ne.x, d_w.x, d.x, d_e.x, d_sw.x, d_s.x, d_se.x);
    my = mat3(d_nw.y, d_n.y, d_ne.y, d_w.y, d.y, d_e.y, d_sw.y, d_s.y, d_se.y);
    mp = mat3(p_nw, p_n, p_ne, p_w, p, p_e, p_sw, p_s, p_se);
}

vec2 pois(vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;

    float k0 = POIS_ISOTROPY;
    float k1 = 1.0 - 2.0 * POIS_ISOTROPY;

    mat3 pois_x = mat3(k0, 0.0, -k0, k1, 0.0, -k1, k0, 0.0, -k0);
    mat3 pois_y = mat3(-k0, -k1, -k0, 0.0, 0.0, 0.0, k0, k1, k0);
    mat3 gauss = mat3(0.0625, 0.125, 0.0625, 0.125, 0.25, 0.125, 0.0625, 0.125, 0.0625);

    mat3 mx; mat3 my; mat3 mp;
    vec2 v = vec2(0.0); float wc = 0.0;
    for (int i = 0; i < DEGREE; i++) {
        tex(uv, mx, my, mp, i);
        float w = POIS_W_FUNCTION;
        wc += w;
        v += w * vec2(reduce(pois_x, mx) + reduce(pois_y, my), reduce(gauss, mp));
    }
    return v / wc;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = pois(fragCoord);
    fragColor = vec4(p.x + p.y);
    if (iFrame == 0) {
        fragColor = 1e-6 * rand4(fragCoord, iResolution.xy, iFrame);
    }
}

void main() {
    vec4 fc;
    mainImage(fc, gl_FragCoord.xy);
    outColor = fc;
}
