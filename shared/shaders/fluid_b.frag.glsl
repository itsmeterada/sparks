#version 450
// Fluid Buffer B (turbulence field)
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
layout(set = 0, binding = 1) uniform sampler2D iChannel1; // unused
layout(set = 0, binding = 2) uniform sampler2D iChannel2; // unused
layout(set = 0, binding = 3) uniform sampler2D iChannel3; // unused

#define TURBULENCE_SCALES 11
#define TURB_ISOTROPY 0.9
#define CURL_ISOTROPY 0.6
#define TURB_W_FUNCTION 1.0
#define CURL_W_FUNCTION (1.0 / float(i + 1))
#define PREMULTIPLY_CURL

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

#define TURB_CH xy
#define TURB_SAMPLER iChannel0
#define DEGREE TURBULENCE_SCALES

float reduce(mat3 a, mat3 b) {
    mat3 p = matrixCompMult(a, b);
    return p[0][0] + p[0][1] + p[0][2] +
        p[1][0] + p[1][1] + p[1][2] +
        p[2][0] + p[2][1] + p[2][2];
}

void tex(vec2 uv, out mat3 mx, out mat3 my, int degree) {
    vec2 texel = 1.0 / iResolution.xy;
    float stride = float(1 << degree);
    float mip = float(degree);
    vec4 t = stride * vec4(texel, -texel.y, 0.0);

    vec2 d = textureLod(TURB_SAMPLER, fract(uv + t.ww), mip).xy;
    vec2 d_n = textureLod(TURB_SAMPLER, fract(uv + t.wy), mip).xy;
    vec2 d_e = textureLod(TURB_SAMPLER, fract(uv + t.xw), mip).xy;
    vec2 d_s = textureLod(TURB_SAMPLER, fract(uv + t.wz), mip).xy;
    vec2 d_w = textureLod(TURB_SAMPLER, fract(uv - t.xw), mip).xy;
    vec2 d_nw = textureLod(TURB_SAMPLER, fract(uv - t.xz), mip).xy;
    vec2 d_sw = textureLod(TURB_SAMPLER, fract(uv - t.xy), mip).xy;
    vec2 d_ne = textureLod(TURB_SAMPLER, fract(uv + t.xy), mip).xy;
    vec2 d_se = textureLod(TURB_SAMPLER, fract(uv + t.xz), mip).xy;

    mx = mat3(d_nw.x, d_n.x, d_ne.x, d_w.x, d.x, d_e.x, d_sw.x, d_s.x, d_se.x);
    my = mat3(d_nw.y, d_n.y, d_ne.y, d_w.y, d.y, d_e.y, d_sw.y, d_s.y, d_se.y);
}

void turbulence(vec2 fragCoord, out vec2 turb, out float curl) {
    vec2 uv = fragCoord.xy / iResolution.xy;

    mat3 turb_xx = (2.0 - TURB_ISOTROPY) * mat3(
        0.125, 0.25, 0.125, -0.25, -0.5, -0.25, 0.125, 0.25, 0.125);
    mat3 turb_yy = (2.0 - TURB_ISOTROPY) * mat3(
        0.125, -0.25, 0.125, 0.25, -0.5, 0.25, 0.125, -0.25, 0.125);
    mat3 turb_xy = TURB_ISOTROPY * mat3(
        0.25, 0.0, -0.25, 0.0, 0.0, 0.0, -0.25, 0.0, 0.25);

    const float norm = 8.8 / (4.0 + 8.0 * CURL_ISOTROPY);
    float c0 = CURL_ISOTROPY;
    mat3 curl_x = mat3(c0, 1.0, c0, 0.0, 0.0, 0.0, -c0, -1.0, -c0);
    mat3 curl_y = mat3(c0, 0.0, -c0, 1.0, 0.0, -1.0, c0, 0.0, -c0);

    mat3 mx; mat3 my;
    vec2 v = vec2(0.0);
    float turb_wc = 0.0; float curl_wc = 0.0;
    curl = 0.0;
    for (int i = 0; i < DEGREE; i++) {
        tex(uv, mx, my, i);
        float turb_w = TURB_W_FUNCTION;
        float curl_w = CURL_W_FUNCTION;
        v += turb_w * vec2(
            reduce(turb_xx, mx) + reduce(turb_xy, my),
            reduce(turb_yy, my) + reduce(turb_xy, mx));
        curl += curl_w * (reduce(curl_x, mx) + reduce(curl_y, my));
        turb_wc += turb_w;
        curl_wc += curl_w;
    }
    turb = float(DEGREE) * v / turb_wc;
    curl = norm * curl / curl_wc;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 turb; float curl;
    turbulence(fragCoord, turb, curl);
    fragColor = vec4(turb, 0.0, curl);
    if (iFrame == 0) {
        fragColor = 1e-6 * rand4(fragCoord, iResolution.xy, iFrame);
    }
}

void main() {
    vec4 fc;
    mainImage(fc, gl_FragCoord.xy);
    outColor = fc;
}
