#version 450
// Fluid Buffer C (vorticity confinement)
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

layout(set = 0, binding = 0) uniform sampler2D iChannel0; // turbulence
layout(set = 0, binding = 1) uniform sampler2D iChannel1; // unused
layout(set = 0, binding = 2) uniform sampler2D iChannel2; // unused
layout(set = 0, binding = 3) uniform sampler2D iChannel3; // unused

#define VORTICITY_SCALES 11
#define CONF_ISOTROPY 0.25
#define CONF_W_FUNCTION 1.0

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

#define CURL_SAMPLER iChannel0
#define DEGREE VORTICITY_SCALES

float reduce(mat3 a, mat3 b) {
    mat3 p = matrixCompMult(a, b);
    return p[0][0] + p[0][1] + p[0][2] +
        p[1][0] + p[1][1] + p[1][2] +
        p[2][0] + p[2][1] + p[2][2];
}

void tex(vec2 uv, out mat3 mc, out float curl, int degree) {
    vec2 texel = 1.0 / iResolution.xy;
    float stride = float(1 << degree);
    float mip = float(degree);
    vec4 t = stride * vec4(texel, -texel.y, 0.0);

    float d = abs(textureLod(CURL_SAMPLER, fract(uv + t.ww), mip).w);
    float d_n = abs(textureLod(CURL_SAMPLER, fract(uv + t.wy), mip).w);
    float d_e = abs(textureLod(CURL_SAMPLER, fract(uv + t.xw), mip).w);
    float d_s = abs(textureLod(CURL_SAMPLER, fract(uv + t.wz), mip).w);
    float d_w = abs(textureLod(CURL_SAMPLER, fract(uv - t.xw), mip).w);
    float d_nw = abs(textureLod(CURL_SAMPLER, fract(uv - t.xz), mip).w);
    float d_sw = abs(textureLod(CURL_SAMPLER, fract(uv - t.xy), mip).w);
    float d_ne = abs(textureLod(CURL_SAMPLER, fract(uv + t.xy), mip).w);
    float d_se = abs(textureLod(CURL_SAMPLER, fract(uv + t.xz), mip).w);

    mc = mat3(d_nw, d_n, d_ne, d_w, d, d_e, d_sw, d_s, d_se);
    curl = textureLod(CURL_SAMPLER, fract(uv), mip).w;
}

vec2 confinement(vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;

    float k0 = CONF_ISOTROPY;
    float k1 = 1.0 - 2.0 * CONF_ISOTROPY;

    mat3 conf_x = mat3(-k0, -k1, -k0, 0.0, 0.0, 0.0, k0, k1, k0);
    mat3 conf_y = mat3(-k0, 0.0, k0, -k1, 0.0, k1, -k0, 0.0, k0);

    mat3 mc; vec2 v = vec2(0.0); float curl; float wc = 0.0;
    for (int i = 0; i < DEGREE; i++) {
        tex(uv, mc, curl, i);
        float w = CONF_W_FUNCTION;
        vec2 n = w * normz(vec2(reduce(conf_x, mc), reduce(conf_y, mc)));
        v += curl * n;
        wc += w;
    }
    return v / wc;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(confinement(fragCoord), 0.0, 0.0);
    if (iFrame == 0) {
        fragColor = 1e-6 * rand4(fragCoord, iResolution.xy, iFrame);
    }
}

void main() {
    vec4 fc;
    mainImage(fc, gl_FragCoord.xy);
    outColor = fc;
}
