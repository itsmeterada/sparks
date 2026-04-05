#version 450

// FXAA post-process pass
// Based on XorDev's GM_FXAA: https://github.com/XorDev/GM_FXAA

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

layout(set = 0, binding = 0) uniform sampler2D iChannel0;

vec4 fxaa(sampler2D tex, vec2 uv, vec2 texelSz) {
    const float span_max   = 8.0;
    const float reduce_min = 1.0/128.0;
    const float reduce_mul = 1.0/32.0;
    const vec3  luma       = vec3(0.299, 0.587, 0.114);

    vec3 rgbCC = texture(tex, uv).rgb;
    vec3 rgb00 = texture(tex, uv+vec2(-0.5,-0.5)*texelSz).rgb;
    vec3 rgb10 = texture(tex, uv+vec2(+0.5,-0.5)*texelSz).rgb;
    vec3 rgb01 = texture(tex, uv+vec2(-0.5,+0.5)*texelSz).rgb;
    vec3 rgb11 = texture(tex, uv+vec2(+0.5,+0.5)*texelSz).rgb;

    float lumaCC = dot(rgbCC, luma);
    float luma00 = dot(rgb00, luma);
    float luma10 = dot(rgb10, luma);
    float luma01 = dot(rgb01, luma);
    float luma11 = dot(rgb11, luma);

    vec2 dir = vec2((luma01 + luma11) - (luma00 + luma10),
                    (luma00 + luma01) - (luma10 + luma11));

    float dirReduce = max((luma00 + luma10 + luma01 + luma11) * reduce_mul, reduce_min);
    float rcpDir = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcpDir, -span_max, span_max) * texelSz;

    vec4 A = 0.5 * (
        texture(tex, uv - dir * (1.0/6.0)) +
        texture(tex, uv + dir * (1.0/6.0)));

    vec4 B = A * 0.5 + 0.25 * (
        texture(tex, uv - dir * 0.5) +
        texture(tex, uv + dir * 0.5));

    float lumaMin = min(lumaCC, min(min(luma00, luma10), min(luma01, luma11)));
    float lumaMax = max(lumaCC, max(max(luma00, luma10), max(luma01, luma11)));
    float lumaB = dot(B.rgb, luma);

    return ((lumaB < lumaMin) || (lumaB > lumaMax)) ? A : B;
}

void main() {
    // vUV is in swapchain space (no Y flip needed for post-process)
    outColor = fxaa(iChannel0, vUV, sqrt(2.0)/iResolution.xy);
}
