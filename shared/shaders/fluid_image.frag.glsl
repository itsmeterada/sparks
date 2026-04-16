#version 450
// Fluid Image pass (final visualization)
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

layout(set = 0, binding = 0) uniform sampler2D iChannel0; // velocity
layout(set = 0, binding = 1) uniform sampler2D iChannel1; // pressure
layout(set = 0, binding = 2) uniform sampler2D iChannel2; // turbulence
layout(set = 0, binding = 3) uniform sampler2D iChannel3; // confinement

float softmax(float a, float b, float k) {
    return log(exp(k * a) + exp(k * b)) / k;
}

float softmin(float a, float b, float k) {
    return -log(exp(-k * a) + exp(-k * b)) / k;
}

vec4 softmax(vec4 a, vec4 b, float k) {
    return log(exp(k * a) + exp(k * b)) / k;
}

vec4 softmin(vec4 a, vec4 b, float k) {
    return -log(exp(-k * a) + exp(-k * b)) / k;
}

float softclamp(float a, float b, float x, float k) {
    return (softmin(b, softmax(a, x, k), k) + softmax(a, softmin(b, x, k), k)) / 2.0;
}

vec4 softclamp(vec4 a, vec4 b, vec4 x, float k) {
    return (softmin(b, softmax(a, x, k), k) + softmax(a, softmin(b, x, k), k)) / 2.0;
}

vec4 softclamp(float a, float b, vec4 x, float k) {
    return (softmin(vec4(b), softmax(vec4(a), x, k), k) + softmax(vec4(a), softmin(vec4(b), x, k), k)) / 2.0;
}

float G1V(float dnv, float k) {
    return 1.0 / (dnv * (1.0 - k) + k);
}

float ggx(vec3 n, vec3 v, vec3 l, float rough, float f0) {
    float alpha = rough * rough;
    vec3 h = normalize(v + l);
    float dnl = clamp(dot(n, l), 0.0, 1.0);
    float dnv = clamp(dot(n, v), 0.0, 1.0);
    float dnh = clamp(dot(n, h), 0.0, 1.0);
    float dlh = clamp(dot(l, h), 0.0, 1.0);
    float asqr = alpha * alpha;
    const float pi = 3.14159;
    float den = dnh * dnh * (asqr - 1.0) + 1.0;
    float d = asqr / (pi * den * den);
    float f = f0 + (1.0 - f0) * pow(1.0 - dlh, 5.0);
    float vis = G1V(dnl, alpha) * G1V(dnv, alpha);
    return dnl * d * f * vis;
}

vec3 light(vec2 uv, float bump, float srcDist, vec2 dxy, float time, inout vec3 avd) {
    vec3 sp = vec3(uv - 0.5, 0.0);
    vec3 lightPos = vec3(cos(time / 2.0) * 0.5, sin(time / 2.0) * 0.5, -srcDist);
    vec3 ld = lightPos - sp;
    float lDist = max(length(ld), 0.001);
    ld /= lDist;
    avd = reflect(normalize(vec3(bump * dxy, -1.0)), vec3(0.0, 1.0, 0.0));
    return ld;
}

#define BUMP 3200.0

vec2 diff(vec2 uv, float mip) {
    vec2 texel = 1.0 / iResolution.xy;
    vec4 t = float(1 << int(mip)) * vec4(texel, -texel.y, 0.0);

    float d = -textureLod(iChannel1, fract(uv + t.ww), mip).w;
    float d_n = -textureLod(iChannel1, fract(uv + t.wy), mip).w;
    float d_e = -textureLod(iChannel1, fract(uv + t.xw), mip).w;
    float d_s = -textureLod(iChannel1, fract(uv + t.wz), mip).w;
    float d_w = -textureLod(iChannel1, fract(uv - t.xw), mip).w;
    float d_nw = -textureLod(iChannel1, fract(uv - t.xz), mip).w;
    float d_sw = -textureLod(iChannel1, fract(uv - t.xy), mip).w;
    float d_ne = -textureLod(iChannel1, fract(uv + t.xy), mip).w;
    float d_se = -textureLod(iChannel1, fract(uv + t.xz), mip).w;

    return vec2(
        0.5 * (d_e - d_w) + 0.25 * (d_ne - d_nw + d_se - d_sw),
        0.5 * (d_n - d_s) + 0.25 * (d_ne + d_nw - d_se - d_sw)
    );
}

vec4 contrast(vec4 col, float x) {
    return x * (col - 0.5) + 0.5;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;

    vec2 dxy = vec2(0.0);
    float occ = 0.0;
    float d = -textureLod(iChannel1, fract(uv), 0.0).w;

    const float steps = 10.0;
    const float oDist = 2.0;
    for (float mip = 1.0; mip <= steps; mip += 1.0) {
        dxy += (1.0 / pow(2.0, mip)) * diff(uv, mip - 1.0);
        occ += softclamp(
            -oDist, oDist,
            d - (-textureLod(iChannel1, fract(uv), mip).w),
            1.0
        ) / pow(1.5, mip);
    }
    dxy /= steps;

    occ = pow(max(0.0, softclamp(0.2, 0.8, 100.0 * occ + 0.5, 1.0)), 0.5);

    vec3 avd;
    vec3 ld = light(uv, BUMP, 0.5, dxy, iTime, avd);
    float spec = ggx(avd, vec3(0.0, 1.0, 0.0), ld, 0.1, 0.1);

    const float logSpec = 1000.0;
    spec = (log(logSpec + 1.0) / logSpec) * log(1.0 + logSpec * spec);

    vec4 diffuse = softclamp(0.0, 1.0, 6.0 * vec4(texture(iChannel0, uv).xy, 0.0, 0.0) + 0.5, 2.0);
    fragColor = diffuse + 4.0 * mix(vec4(spec), 1.5 * diffuse * spec, 0.3);
    fragColor = mix(vec4(1.0), vec4(occ), vec4(0.7)) * softclamp(0.0, 1.0, contrast(fragColor, 4.5), 3.0);
}

void main() {
    vec4 fc;
    // vUV is pre-rotated by vertex shader for display orientation.
    // Y flip: Vulkan Y-down -> Shadertoy Y-up convention.
    mainImage(fc, vec2(vUV.x, 1.0 - vUV.y) * iResolution);
    outColor = fc;
}
