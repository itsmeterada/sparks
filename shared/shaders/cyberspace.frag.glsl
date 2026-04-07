#version 450

// Cyberspace data warehouse - Ported from Shadertoy
// https://www.shadertoy.com/view/NlK3Wt
// Original Author: bitless
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

#define h21(p) ( fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453) )
#define BC vec3(.26,.4,.6)

vec4 getHex(vec2 p)
{
    vec2 s = vec2(1, 1.7320508);
    vec4 hC = floor(vec4(p, p - vec2(.5, 1))/s.xyxy) + .5;
    vec4 h = vec4(p - hC.xy*s, p - (hC.zw + .5)*s);
    return dot(h.xy, h.xy)<dot(h.zw, h.zw) ? vec4(h.xy, hC.xy) : vec4(h.zw, hC.zw + .5);
}

float noise( in vec2 f )
{
    vec2 i = floor( f );
    f -= i;
    vec2 u = f*f*(3.-2.*f);
    return mix( mix( h21( i + vec2(0,0) ),
                     h21( i + vec2(1,0) ), u.x),
                mix( h21( i + vec2(0,1) ),
                     h21( i + vec2(1,1) ), u.x), u.y);
}

vec3 HexToSqr (vec2 st, inout vec2 uf)
{
    vec3 r;
    uf = vec2((st.x+st.y*1.73),(st.x-st.y*1.73))-.5;
    if (st.y > 0.-abs(st.x)*0.57777)
        if (st.x > 0.)
            r = vec3(fract(vec2(-st.x,(st.y+st.x/1.73)*0.86)*2.),2.);
        else
            r = vec3(fract(vec2(st.x,(st.y-st.x/1.73)*0.86)*2.),3.);
    else
        r = vec3 (fract(uf+.5),1);
    return r;
}

void sphere (vec4 hx, vec2 st, float sm, inout vec4 R)
{
    R -= R;
    float   T = mod(iTime+h21(hx.zw*20.)*20.,20.)
        ,   d = .4* ((T < 3.) ? sin(T*.52) :
                    ((T < 6.) ? 1. :
                    ((T < 9.) ? sin((9.-T)*.52) :
                                0.)))
        ,   y = .4* ((T < 4.) ? sin((T-1.)*.52) :
                    ((T < 5.5) ? 1. :
                    ((T < 8.5) ? sin((8.5-T)*.52) :
                    0.))) - .06
        ,   f = (.9 + noise(vec2(hx.x*50.+iTime*4.))*.3)
                * smoothstep(-.57,1.7,st.y-st.x);

    R = mix (vec4(0), vec4(BC*f,1.), smoothstep(d+sm, d-sm, length(st)));
    R = mix (R, vec4(BC*.5,1.), smoothstep(sm, -sm, abs(length(st)-d)-.02)*smoothstep(0.,.02,d));

    f = noise(hx.xy*vec2(12,7)+vec2(0,iTime*-4.))*.25+.5;

    R = mix (R,
                vec4(mix(
                vec3(BC*8.)*f,
                vec3(.15,.1,.1)
                ,sin(T*.48-1.8))
                *(smoothstep(.1,.2,length(hx.xy+vec2(.0,y)))*.5 + .5)
                *(smoothstep(-.02,-0.52,hx.y)),1.) ,
            smoothstep (.2+sm,.2-sm,length(hx.xy+vec2(.0,y)))
            *((st.y-st.x >0.) ? 1. : smoothstep(d-.02+sm, d-.02-sm, abs(length(st))))
        );
}

void pixel (float hh, float sm, vec2 st, vec2 s, float n, vec4 R, inout vec4 C)
{
    st = vec2(st.x,1.-st.y);
    vec2    lc = 1.-fract(st*10.)
        ,   id = floor(st*10.) + s;

    float   b = ((4.-n)*2.2+.8)*.05
        ,   th = .05
        ,   T = mod(iTime+hh*20.,20.)
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

    vec4 P =  vec4(BC*(1.+hh*.75)*b,1);
    if (s == vec2(0)) C = mix (P*.7, P*.9, step(0.,lc.x-lc.y));

    vec2 m = s*2.-1.;

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

void tile(vec2 uv, inout vec4 C)
{
    vec4 hx = getHex(uv);
    vec2 s;
    vec3 sqr = HexToSqr(hx.xy, s);
    float n = sqr.z
          ,sm = 3./iResolution.y
          ,hh = h21(hx.zw*20.);

    vec2 st = sqr.xy;
    vec4 R;

    if (n == 1.) sphere (hx, st-vec2(.5), sm, R);
    else if (n == 2.) sphere (hx + vec4(0,-.6,.5,.5), s + vec2(0,1), .01, R);
    else sphere (hx + vec4(0,-.6,-.5,.5), s + vec2(0,1), .01, R);

    pixel (hh, sm, st, vec2(0,0), n, R, C);
    pixel (hh, sm, st, vec2(1,0), n, R, C);
    pixel (hh, sm, st, vec2(0,1), n, R, C);
    pixel (hh, sm, st, vec2(1,1), n, R, C);

    if (n==1.) C = mix (C,R,R.a);
}

void main()
{
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    vec2 rz = iResolution.xy
        ,uv = (fragCoord+fragCoord-rz)/-rz.y;

    uv *= .8+sin(iTime*.3)*.25;
    uv -= uv * pow(length(uv),2.5-sin(iTime*.3)*.5)*.025 +
        vec2(iTime*.2,cos(iTime*.2));

    vec4 C = vec4(0);
    tile(uv,C);
    outColor = C;
}
