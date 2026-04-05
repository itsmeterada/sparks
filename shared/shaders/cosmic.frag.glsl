#version 450

// Cosmic - Ported from Shadertoy
// https://www.shadertoy.com/view/XXyGzh
// Original Author: Nguyen2007
// License: CC BY-NC-SA 3.0

layout(location = 0) in vec2 vUV;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PushConstants {
    vec2 iResolution;
    float iTime;
    int preRotate;
    vec4 iMouse;
};

void main() {
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;

    vec2 v = iResolution.xy;
    vec2 u = 0.2 * (fragCoord + fragCoord - v) / v.y;

    vec4 z = vec4(1.0, 2.0, 3.0, 0.0);
    vec4 o = z;

    for (float a = 0.5, t = iTime, i = 0.0;
         ++i < 19.0;
         o += (1.0 + cos(z + t))
            / length((1.0 + i * dot(v, v))
                   * sin(1.5 * u / (0.5 - dot(u, u)) - 9.0 * u.yx + t))
         )
    {
        t += 1.0;
        a += 0.03;
        v = cos(t - 7.0 * u * pow(a, i)) - 5.0 * u;

        vec4 cv = cos(i + 0.02 * t - z.wxzw * 11.0);
        u *= mat2(cv);

        float d = dot(u, u);
        u += tanh(40.0 * d * cos(1e2 * u.yx + t)) / 2e2
           + 0.2 * a * u
           + cos(4.0 / exp(dot(o, o) / 1e2) + t) / 3e2;
    }

    o = 25.6 / (min(o, 13.0) + 164.0 / o)
      - dot(u, u) / 250.0;

    outColor = vec4(o.rgb, 1.0);
}
