#version 450

// Tunnel - Ported from Shadertoy
// https://www.shadertoy.com/view/scS3Wm
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

#define T (sin(iTime*.6)*64.+iTime*2e2)
#define P(z) (vec3(cos((z)*.015)*16.+cos((z) * .006)*64., \
                   cos((z)*.011)*24.+cos((z) * .009)*32., (z)))
#define R(a) mat2(cos(a+vec4(0,33,11,0)))
#define N normalize

float boxen(vec3 p) {
    p = abs(fract(p/4e1)*4e1 - 2e1) - 2.;
    return min(p.x, min(p.y, p.z));
}

vec4 lights;
float map(vec3 p) {
    vec3 q = P(p.z);
    float m, g = q.y-p.y + 6.;

    m = boxen(p);

    p.xy -= q.xy;

    float red, blue;
    float e = min(red=length(p.xy - sin(p.y / 12. + vec2(5., 1.))*12.) - 1.,
                  blue=length(p.xy - sin(p.y / 12. + vec2(0, 1.))*12.) - 1.);

    lights += vec4(2,1e1,1e1,0)/(.1+abs(red)/1e1);
    lights += vec4(1e1,2,1e1,0)/(.1+abs(blue)/1e1);

    p = abs(p);

    float tex = abs(length(sin(p*cos(p.yzx/3e1)*4.)/(p*4.)));
    float tun = min(64.-p.x - p.y + m, 32.-p.y - m);

    float d = max(min(m, g), tun)-tex;
    return min(e, d);
}

void main() {
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    float i, s, d = 0.0;
    vec3 r = vec3(iResolution, 1.0);

    vec2 u = (fragCoord - r.xy/2.)/r.y;
    u.y -= .2;

    vec4 o = vec4(0);
    lights = vec4(0);
    vec3 p = P(T), ro = p,
         Z = N( P(T+1e1) - p),
         X = N(vec3(Z.z, 0, -Z.x)),
         D = N(vec3(R(sin(T*.005)*.4)*u, 1)
            * mat3(-X, cross(X, Z), Z));

    // main march - lights accumulates across all iterations (volumetric glow)
    for(i = 0.; i < 128.; i++) {
        p = ro + D * d;
        s = map(p)*.8;
        d += s;
        o += lights + 1./max(s, .01);
    }

    // normal (tetrahedron technique)
    const float h = 0.005;
    const vec2 k = vec2(1,-1);
    vec3 n = N(k.xyy*map( p + k.xyy*h ) +
               k.yyx*map( p + k.yyx*h ) +
               k.yxy*map( p + k.yxy*h ) +
               k.xxx*map( p + k.xxx*h ) );

    // diffuse
    o *= (.1 + max(dot(n, -D), 0.));

    // reflection march
    vec4 ref = vec4(0);
    lights = vec4(0); // reset before reflection
    p += n*.05;
    D = reflect(D, n);
    s = 0.;
    for(i = 0.; i < 40.; i++) {
        p += D*s;
        s = map(p)*.8;
        ref += lights + 1./max(s, .01);
    }

    o += o*ref;
    o = tanh(o / 6e6 / d);

    outColor = vec4(o.rgb, 1.0);
}
