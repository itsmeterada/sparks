#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Tunnel - Ported from Shadertoy
// https://www.shadertoy.com/view/scS3Wm
// License: CC BY-NC-SA 3.0

#define T (sin(iTime*.6)*64.+iTime*2e2)
#define P(z) (float3(cos((z)*.015)*16.+cos((z) * .006)*64., \
                     cos((z)*.011)*24.+cos((z) * .009)*32., (z)))
#define R(a) float2x2(cos(float4(a)+float4(0,33,11,0)).xy, cos(float4(a)+float4(0,33,11,0)).zw)
#define N normalize

static float boxen(float3 p) {
    p = abs(fract(p/4e1)*4e1 - 2e1) - 2.;
    return min(p.x, min(p.y, p.z));
}

static float map(float3 p, float iTime, thread float4 &lights) {
    float3 q = P(p.z);
    float m, g = q.y-p.y + 6.;

    m = boxen(p);

    p.xy -= q.xy;

    float red, blue;
    float e = min(red=length(p.xy - sin(p.y / 12. + float2(5., 1.))*12.) - 1.,
                  blue=length(p.xy - sin(p.y / 12. + float2(0, 1.))*12.) - 1.);

    lights += float4(2,1e1,1e1,0)/(.1+abs(red)/1e1);
    lights += float4(1e1,2,1e1,0)/(.1+abs(blue)/1e1);

    p = abs(p);

    float tex = abs(length(sin(p*cos(p.yzx/3e1)*4.)/(p*4.)));
    float tun = min(64.-p.x - p.y + m, 32.-p.y - m);

    float d = max(min(m, g), tun)-tex;
    return min(e, d);
}

fragment float4 tunnel_fragment(VertexOut in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float i, s, d = 0.0;
    float3 r = float3(uniforms.iResolution, 1.0);

    float2 u = (fragCoord - r.xy/2.)/r.y;
    u.y -= .2;

    float4 o = float4(0);
    float4 lights = float4(0);
    float3 p = P(T), ro = p,
           Z = N( P(T+1e1) - p),
           X = N(float3(Z.z, 0, -Z.x)),
           D = N(float3(R(sin(T*.005)*.4)*u, 1)
              * float3x3(-X, cross(X, Z), Z));

    // main march
    for(i = 0.; i < 128.; i++) {
        p = ro + D * d;
        s = map(p, iTime, lights)*.8;
        d += s;
        o += lights + 1./max(s, .01);
    }

    // normal (tetrahedron technique)
    float4 dummy = float4(0);
    const float h = 0.005;
    const float2 k = float2(1,-1);
    float3 n = N(k.xyy*map( p + k.xyy*h, iTime, dummy ) +
                 k.yyx*map( p + k.yyx*h, iTime, dummy ) +
                 k.yxy*map( p + k.yxy*h, iTime, dummy ) +
                 k.xxx*map( p + k.xxx*h, iTime, dummy ) );

    // diffuse
    o *= (.1 + max(dot(n, -D), 0.));

    // reflection march
    float4 ref = float4(0);
    lights = float4(0);
    p += n*.05;
    D = reflect(D, n);
    s = 0.;
    for(i = 0.; i < 40.; i++) {
        p += D*s;
        s = map(p, iTime, lights)*.8;
        ref += lights + 1./max(s, .01);
    }

    o += o*ref;
    o = tanh(o / 6e6 / d);

    return float4(o.rgb, 1.0);
}
