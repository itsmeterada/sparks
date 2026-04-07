#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

// Cyberspace data warehouse - Ported from Shadertoy
// https://www.shadertoy.com/view/NlK3Wt
// Original Author: bitless
// License: CC BY-NC-SA 3.0

#define h21(p) ( fract(sin(dot(p,float2(12.9898,78.233)))*43758.5453) )
#define BC float3(.26,.4,.6)

static float4 getHex(float2 p)
{
    float2 s = float2(1, 1.7320508);
    float4 hC = floor(float4(p, p - float2(.5, 1))/s.xyxy) + .5;
    float4 h = float4(p - hC.xy*s, p - (hC.zw + .5)*s);
    return dot(h.xy, h.xy)<dot(h.zw, h.zw) ? float4(h.xy, hC.xy) : float4(h.zw, hC.zw + .5);
}

static float noise( float2 f )
{
    float2 i = floor( f );
    f -= i;
    float2 u = f*f*(3.-2.*f);
    return mix( mix( h21( i + float2(0,0) ),
                     h21( i + float2(1,0) ), u.x),
                mix( h21( i + float2(0,1) ),
                     h21( i + float2(1,1) ), u.x), u.y);
}

static float3 HexToSqr (float2 st, thread float2 &uf)
{
    float3 r;
    uf = float2((st.x+st.y*1.73),(st.x-st.y*1.73))-.5;
    if (st.y > 0.-abs(st.x)*0.57777)
        if (st.x > 0.)
            r = float3(fract(float2(-st.x,(st.y+st.x/1.73)*0.86)*2.),2.);
        else
            r = float3(fract(float2(st.x,(st.y-st.x/1.73)*0.86)*2.),3.);
    else
        r = float3 (fract(uf+.5),1);
    return r;
}

static void sphere (float4 hx, float2 st, float sm, float iTime, thread float4 &R)
{
    R = float4(0);
    float   T = fmod(iTime+h21(hx.zw*20.)*20.,20.)
        ,   d = .4* ((T < 3.) ? sin(T*.52) :
                    ((T < 6.) ? 1. :
                    ((T < 9.) ? sin((9.-T)*.52) :
                                0.)))
        ,   y = .4* ((T < 4.) ? sin((T-1.)*.52) :
                    ((T < 5.5) ? 1. :
                    ((T < 8.5) ? sin((8.5-T)*.52) :
                    0.))) - .06
        ,   f = (.9 + noise(float2(hx.x*50.+iTime*4.))*.3)
                * smoothstep(-.57,1.7,st.y-st.x);

    R = mix (float4(0), float4(BC*f,1.), smoothstep(d+sm, d-sm, length(st)));
    R = mix (R, float4(BC*.5,1.), smoothstep(sm, -sm, abs(length(st)-d)-.02)*smoothstep(0.,.02,d));

    f = noise(hx.xy*float2(12,7)+float2(0,iTime*-4.))*.25+.5;

    R = mix (R,
                float4(mix(
                float3(BC*8.)*f,
                float3(.15,.1,.1)
                ,sin(T*.48-1.8))
                *(smoothstep(.1,.2,length(hx.xy+float2(.0,y)))*.5 + .5)
                *(smoothstep(-.02,-0.52,hx.y)),1.) ,
            smoothstep (.2+sm,.2-sm,length(hx.xy+float2(.0,y)))
            *((st.y-st.x >0.) ? 1. : smoothstep(d-.02+sm, d-.02-sm, abs(length(st))))
        );
}

static void pixel (float hh, float sm, float2 st, float2 s, float n, float4 R, float iTime, thread float4 &C)
{
    st = float2(st.x,1.-st.y);
    float2  lc = 1.-fract(st*10.)
        ,   id = floor(st*10.) + s;

    float   b = ((4.-n)*2.2+.8)*.05
        ,   th = .05
        ,   T = fmod(iTime+hh*20.,20.)
        ,   d = ((T < 3.) ? sin((T)*.52) :
                        ((T < 6.5) ? 1. :
                        ((T < 9.5) ? sin((9.5-T)*.52) :
                                0.)))
        ,   f =  min(
                (pow(noise(id*hh*n+iTime*(.75+h21(id)*.15)*1.),8.)*2.
                + (noise(id*.2 + iTime*(.5+hh*n)*.5)-.1))
                * smoothstep (6.,2.,length(id-4.5))
                * ((n == 1.) ? (smoothstep(d*5., d*5.+2. ,length(id-4.5)+.5)) : 1.)
                , 0.95);

    float4 P =  float4(BC*(1.+hh*.75)*b,1);
    if (s.x == 0. && s.y == 0.) C = mix (P*.7, P*.9, step(0.,lc.x-lc.y));

    float2 m = s*2.-1.;

    if (s.x!=s.y) C = mix (C
                            ,   mix(    P*.7
                                    ,   P*.9
                                    ,   step(lc.x-lc.y,0.))
                            , step(lc.x+lc.y,f+f)
                    *((m.y==-1.)?step(lc.x-lc.y+1.,1.):step(1.,lc.x-lc.y+1.)));
    C = mix (C, P,smoothstep(f+sm*m.x,f-sm*m.x,lc.x)*smoothstep(f+sm*m.y,f-sm*m.y,lc.y));
    C = mix (C, mix(P*(.4+(f+pow(f,2.))*4.),R,.25)
    ,smoothstep(f-(th-sm)*m.x,f-(th+sm)*m.x,lc.x)*smoothstep(f-(th-sm)*m.y,f-(th+sm)*m.y,lc.y));
}

static void tile(float2 uv, float2 iResolution, float iTime, thread float4 &C)
{
    float4 hx = getHex(uv);
    float2 s;
    float3 sqr = HexToSqr(hx.xy, s);
    float n = sqr.z
          ,sm = 3./iResolution.y
          ,hh = h21(hx.zw*20.);

    float2 st = sqr.xy;
    float4 R;

    if (n == 1.) sphere (hx, st-float2(.5), sm, iTime, R);
    else if (n == 2.) sphere (hx + float4(0,-.6,.5,.5), s + float2(0,1), .01, iTime, R);
    else sphere (hx + float4(0,-.6,-.5,.5), s + float2(0,1), .01, iTime, R);

    pixel (hh, sm, st, float2(0,0), n, R, iTime, C);
    pixel (hh, sm, st, float2(1,0), n, R, iTime, C);
    pixel (hh, sm, st, float2(0,1), n, R, iTime, C);
    pixel (hh, sm, st, float2(1,1), n, R, iTime, C);

    if (n==1.) C = mix (C,R,R.a);
}

fragment float4 cyberspace_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(0)]]) {
    float iTime = uniforms.iTime;
    float2 fragCoord = in.uv * uniforms.iResolution;
    float2 rz = uniforms.iResolution;
    float2 uv = (fragCoord+fragCoord-rz)/-rz.y;

    uv *= .8+sin(iTime*.3)*.25;
    uv -= uv * pow(length(uv),2.5-sin(iTime*.3)*.5)*.025 +
        float2(iTime*.2,cos(iTime*.2));

    float4 C = float4(0);
    tile(uv, uniforms.iResolution, iTime, C);
    return C;
}
