#version 450

// Rocaille - Ported from Shadertoy
// https://www.shadertoy.com/view/WXyczK
// Original Author: @XorDev
// License: CC BY-NC-SA 3.0

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

void main()
{
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    vec2 v = iResolution.xy;
    vec2 p = (fragCoord + fragCoord - v) / v.y / .3;

    vec4 O = vec4(0);
    float i, f;
    for(i = 0.; i < 9.; i++)
    {
        v = p;
        for(f = 0.; f < 9.; f++)
            v += sin(v.yx * (f+1.) + i + iTime) / (f+1.);
        O += (cos(i + 1. + vec4(0,1,2,3)) + 1.) / 6. / length(v);
    }

    O = tanh(O*O);
    outColor = vec4(O.rgb, 1.0);
}
