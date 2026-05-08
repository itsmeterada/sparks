#version 450

// Star Nest - Ported from Shadertoy
// https://www.shadertoy.com/view/XlfGRj
// Original Author: Pablo Roman Andrioli
// License: MIT

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

const int   iterations = 17;
const float formuparam = 0.53;

const int   volsteps = 20;
const float stepsize = 0.1;

const float zoom  = 0.800;
const float tile  = 0.850;
const float speed = 0.010;

const float brightness = 0.0015;
const float darkmatter = 0.300;
const float distfading = 0.730;
const float saturation = 0.850;

void main() {
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;

    // get coords and direction
    vec2 uv = fragCoord / iResolution - 0.5;
    uv.y *= iResolution.y / iResolution.x;
    vec3 dir = vec3(uv * zoom, 1.0);
    float time = iTime * speed + 0.25;

    // mouse rotation
    float a1 = 0.5 + iMouse.x / iResolution.x * 2.0;
    float a2 = 0.8 + iMouse.y / iResolution.y * 2.0;
    mat2 rot1 = mat2(cos(a1), sin(a1), -sin(a1), cos(a1));
    mat2 rot2 = mat2(cos(a2), sin(a2), -sin(a2), cos(a2));
    dir.xz *= rot1;
    dir.xy *= rot2;
    vec3 from = vec3(1.0, 0.5, 0.5);
    from += vec3(time * 2.0, time, -2.0);
    from.xz *= rot1;
    from.xy *= rot2;

    // volumetric rendering
    float s = 0.1, fade = 1.0;
    vec3 v = vec3(0.0);
    for (int r = 0; r < volsteps; r++) {
        vec3 p = from + s * dir * 0.5;
        p = abs(vec3(tile) - mod(p, vec3(tile * 2.0))); // tiling fold
        float pa, a = pa = 0.0;
        for (int i = 0; i < iterations; i++) {
            p = abs(p) / dot(p, p) - formuparam; // the magic formula
            a += abs(length(p) - pa); // absolute sum of average change
            pa = length(p);
        }
        float dm = max(0.0, darkmatter - a * a * 0.001); // dark matter
        a *= a * a; // add contrast
        if (r > 6) fade *= 1.0 - dm; // dark matter, don't render near
        v += fade;
        v += vec3(s, s * s, s * s * s * s) * a * brightness * fade; // coloring based on distance
        fade *= distfading; // distance fading
        s += stepsize;
    }
    v = mix(vec3(length(v)), v, saturation); // color adjust
    outColor = vec4(v * 0.01, 1.0);
}
