#version 450

// Starship - Ported from Shadertoy
// https://www.shadertoy.com/view/l3cfW4
// Original Author: @XorDev
// License: CC BY-NC-SA 3.0

layout(location = 0) in vec2 vUV;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PushConstants {
    vec2 iResolution;
    float iTime;
    int preRotate;
    vec4 iMouse;
};

layout(set = 0, binding = 0) uniform sampler2D iChannel0;

void main() {
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;

    vec2 r = iResolution.xy;
    vec2 p = (fragCoord + fragCoord - r) / r.y * mat2(3, 4, 4, -3) / 1e2;

    vec4 S = vec4(0.0);
    vec4 C = vec4(1, 2, 3, 0);
    vec4 W;

    for (float t = iTime, T = 0.1 * t + p.y, i = 0.0; i++ < 50.0;

        S += (cos(W = sin(i) * C) + 1.0)
           * exp(sin(i + i * T))
           / length(max(p,
               p / vec2(2.0, texture(iChannel0, p / exp(W.x) + vec2(i, t) / 8.0).x * 40.0))
           ) / 1e4)

        p += 0.02 * cos(i * (C.xz + 8.0 + i) + T + T);

    C -= 1.0;
    outColor = tanh(p.x * C + S * S);
    outColor.a = 1.0;
}
