#version 450

// Yet another 4D Apollonian - Ported from Shadertoy
// https://www.shadertoy.com/view/N3VXz1
// Original Author: mrange
// License: CC0 1.0 Universal (Public Domain Dedication)

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

void mainImage(out vec4 o, vec2 C) {
    float d = 0., e = 0., i = 0., j, s, z = 0.;
    vec2 r = iResolution.xy;
    vec4 p, O = vec4(0);
    mat2 R = mat2(cos(iTime / 27. + vec4(0, 11, 33, 0)));

    // Unrolled form of the original golfed for(;;) header
    for (;;) {
        p = vec4(z * normalize(vec3(C - .5 * r, r.y)), .6);
        p.z -= 1.;
        p.xw *= R;
        p.wy *= R;
        p.zw *= R;
        o = p;
        if (!(++i < 77.)) break;

        // 4D Apollonian fold: tile + sphere inversion
        for (s = j = 1.; ++j < 7.; s *= e) {
            p -= 2. * round(p * .5);
            p *= e = 2. / dot(p, p);
        }

        p = abs(p / s);
        d = min(length(p.xy) + 3e-4, min(p.z, p.w) + 3e-3);
        p = e * e + 3. + 3. * cos(30. * dot(o.xy, o.zw) + vec4(2, 7, 0, 4));
        O += p.w / d / (1. + 8. * e * e * e) * exp(-z * z * .5) * p;
        z += .6 * d + 1e-3;
    }

    // clamp guards tanh against overflow on mobile GPUs
    o = tanh(clamp(O / 2e4 - length(C / r - .5) / 5. * vec4(2, 3, 1, 0), -10., 10.)) / .9;
}

void main() {
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    vec4 o;
    mainImage(o, fragCoord);
    outColor = vec4(o.rgb, 1.0);
}
