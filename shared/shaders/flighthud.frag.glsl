#version 450

// Flight HUD - Ported from Shadertoy
// https://www.shadertoy.com/view/Dl2XRz
// Original Author: kishimisu
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

#define Rot(a) mat2(cos(a),-sin(a),sin(a),cos(a))
#define antialiasing(n) n/min(iResolution.y,iResolution.x)
#define S(d,b) smoothstep(antialiasing(1.0),b,d)
#define B(p,s) max(abs(p).x-s.x,abs(p).y-s.y)
#define Tri(p,s,a) max(-dot(p,vec2(cos(-a),sin(-a))),max(dot(p,vec2(cos(a),sin(a))),max(abs(p).x-s.x,abs(p).y-s.y)))
#define DF(a,b) length(a) * cos( mod( atan(a.y,a.x)+6.28/(b*8.0), 6.28/((b*8.0)*0.5))+(b-1.)*6.28/(b*8.0) + vec2(0,11) )
#define SkewX(a) mat2(1.0,tan(a),0.0,1.0)
#define seg_0 0
#define seg_1 1
#define seg_2 2
#define seg_3 3
#define seg_4 4
#define seg_5 5
#define seg_6 6
#define seg_7 7
#define seg_8 8
#define seg_9 9

float rand(vec2 co){
    return fract(sin(dot(co.xy,vec2(12.9898,78.233)))*43758.5453);
}

float dSlopeLines(vec2 p){
    float lineSize = 80.;
    float d = tan((mix(p.x,p.y,0.5)+(-iTime*5./lineSize))*lineSize)*lineSize;
    return d;
}

float segBase(vec2 p){
    vec2 prevP = p;
    float size = 0.02;
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;
    p = mod(p,0.05)-0.025;
    float thickness = 0.005;
    float gridMask = min(abs(p.x)-thickness,abs(p.y)-thickness);
    p = prevP;
    float d = B(p,vec2(w*0.5,h*0.5));
    float a = radians(40.0);
    p.x = abs(p.x)-0.1;
    p.y = abs(p.y)-0.05;
    float d2 = dot(p,vec2(cos(a),sin(a)));
    return d;
}

float seg0(vec2 p){
    vec2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    float mask = B(p,vec2(size,size*2.7));
    d = max(-mask,d);
    return d;
}

float seg1(vec2 p){
    vec2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.x+=size;
    p.y+=size;
    float mask = B(p,vec2(size*2.,size*3.7));
    d = max(-mask,d);
    p = prevP;
    p.x+=size*1.9;
    p.y-=size*3.2;
    mask = B(p,vec2(size,size+0.01));
    d = max(-mask,d);
    return d;
}

float seg2(vec2 p){
    vec2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.x+=size;
    p.y-=0.05;
    float mask = B(p,vec2(size*2.,size));
    d = max(-mask,d);
    p = prevP;
    p.x-=size;
    p.y+=0.05;
    mask = B(p,vec2(size*2.,size));
    d = max(-mask,d);
    return d;
}

float seg3(vec2 p){
    vec2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.y = abs(p.y);
    p.x+=size;
    p.y-=0.05;
    float mask = B(p,vec2(size*2.,size));
    d = max(-mask,d);
    p = prevP;
    p.x+=0.06;
    mask = B(p,vec2(size,size+0.01));
    d = max(-mask,d);
    return d;
}

float seg4(vec2 p){
    vec2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.x+=size;
    p.y+=0.08;
    float mask = B(p,vec2(size*2.,size*2.0));
    d = max(-mask,d);
    p = prevP;
    p.y-=0.08;
    mask = B(p,vec2(size,size*2.0));
    d = max(-mask,d);
    return d;
}

float seg5(vec2 p){
    vec2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.x-=size;
    p.y-=0.05;
    float mask = B(p,vec2(size*2.,size));
    d = max(-mask,d);
    p = prevP;
    p.x+=size;
    p.y+=0.05;
    mask = B(p,vec2(size*2.,size));
    d = max(-mask,d);
    return d;
}

float seg6(vec2 p){
    vec2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.x-=size;
    p.y-=0.05;
    float mask = B(p,vec2(size*2.,size));
    d = max(-mask,d);
    p = prevP;
    p.y+=0.05;
    mask = B(p,vec2(size,size));
    d = max(-mask,d);
    return d;
}

float seg7(vec2 p){
    vec2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.x+=size;
    p.y+=size;
    float mask = B(p,vec2(size*2.,size*3.7));
    d = max(-mask,d);
    return d;
}

float seg8(vec2 p){
    vec2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.y = abs(p.y);
    p.y-=0.05;
    float mask = B(p,vec2(size,size));
    d = max(-mask,d);
    return d;
}

float seg9(vec2 p){
    vec2 prevP = p;
    float d = segBase(p);
    float size = 0.03;
    p.y-=0.05;
    float mask = B(p,vec2(size,size));
    d = max(-mask,d);
    p = prevP;
    p.x+=size;
    p.y+=0.05;
    mask = B(p,vec2(size*2.,size));
    d = max(-mask,d);
    return d;
}

float checkChar(int targetChar, int ch){
    return 1.-abs(sign(float(targetChar) - float(ch)));
}

float drawFont(vec2 p, int ch){
    p*=SkewX(-0.4);
    float d = seg0(p)*checkChar(seg_0,ch);
    d += seg1(p)*checkChar(seg_1,ch);
    d += seg2(p)*checkChar(seg_2,ch);
    d += seg3(p)*checkChar(seg_3,ch);
    d += seg4(p)*checkChar(seg_4,ch);
    d += seg5(p)*checkChar(seg_5,ch);
    d += seg6(p)*checkChar(seg_6,ch);
    d += seg7(p)*checkChar(seg_7,ch);
    d += seg8(p)*checkChar(seg_8,ch);
    d += seg9(p)*checkChar(seg_9,ch);
    return d;
}

vec3 paperPlane(vec2 p, vec3 col){
    p.y-=0.1;
    p*=1.5;
    vec2 prevP = p;
    p *= vec2(1.,0.4);
    float d = Tri(p,vec2(0.1,0.1),radians(45.));
    p = prevP;
    p.y+=0.23;
    p *= vec2(2.,2.);
    float d2 = Tri(p,vec2(0.1,0.1),radians(45.));
    d = max(-d2,d);
    col = mix(col,vec3(0.9),S(d,0.0));
    p = prevP;
    p *= vec2(6.,0.4);
    d = Tri(p,vec2(0.1,0.1),radians(45.));
    p = prevP;
    p.y+=0.23;
    p *= vec2(2.,2.);
    d2 = Tri(p,vec2(0.1,0.1),radians(45.));
    d = max(-d2,d);
    col = mix(col,vec3(0.75),S(d,0.0));
    p = prevP;
    p *= vec2(1.,0.4);
    d = Tri(p,vec2(0.1,0.1),radians(45.));
    p = prevP;
    p.y+=0.16;
    p *= vec2(0.9,1.);
    d2 = Tri(p,vec2(0.1,0.1),radians(45.));
    d = max(-d2,d);
    col = mix(col,vec3(1.),S(d,0.0));
    p = prevP;
    p *= vec2(11.,0.59);
    d = Tri(p,vec2(0.1,0.1),radians(45.));
    p = prevP;
    p.y+=0.23;
    p *= vec2(2.,2.);
    d2 = Tri(p,vec2(0.1,0.1),radians(45.));
    d = max(-d2,d);
    col = mix(col,vec3(0.85),S(d,0.0));
    p = prevP;
    p.y+=0.18;
    p.x*=1.2;
    d = Tri(p,vec2(0.01),radians(-45.));
    col = mix(col,vec3(0.85),S(d,0.0));
    p = prevP;
    d = B(p-vec2(0.0,-0.12),vec2(0.004,0.11));
    col = mix(col,vec3(0.95),S(d,-0.01));
    return col;
}

vec3 radar(vec2 p, vec3 col){
    vec2 prevP = p;
    p*=Rot(radians(25.0*iTime));
    float a = atan(p.x,p.y);
    float d = length(p)-0.4;
    col = mix(col,vec3(1.)*a*0.01,S(d,0.0));
    d = length(p)-0.4;
    a = radians(1.);
    p.x = abs(p.x);
    d = max(dot(p,vec2(cos(a),sin(a))),d);
    col = mix(col,vec3(0.2),S(d,0.0));
    return col;
}

vec3 grids(vec2 p, vec3 col){
    vec2 prevP = p;
    p.y+= iTime*0.1;
    p = mod(p,0.05)-0.025;
    float thickness = 0.00001;
    float d = min(abs(p.x)-thickness,abs(p.y)-thickness);
    p = prevP;
    float c = length(p)-0.4;
    d = max(c,d);
    col = mix(col,vec3(0.2),S(d,0.0));
    p*=Rot(radians(-20.*iTime));
    p=DF(p,40.);
    p-=vec2(0.28);
    p*=Rot(radians(45.));
    d = B(p,vec2(0.001,0.01));
    p = prevP;
    p*=Rot(radians(-20.*iTime));
    p=DF(p,10.);
    p-=vec2(0.27);
    p*=Rot(radians(45.));
    float d2 = B(p,vec2(0.001,0.02));
    d = min(d,d2);
    col = mix(col,vec3(1.),S(d,0.0));
    int num = 8;
    d = 10.;
    for(int i = 0; i<num; i++){
        float r = radians(135.0+(360.0/float(num))*float(i));
        float dist = 3.7;
        float x = cos(r)*dist;
        float y = sin(r)*dist;
        p = prevP;
        p*=8.0;
        d2 = drawFont(p-vec2(x,y),(num-1)-int(mod(float(i),10.)));
        d = min(d,d2);
    }
    col = mix(col,vec3(0.6),S(d,0.0));
    p = prevP;
    p*=Rot(radians(20.*iTime));
    p=DF(p,30.);
    p-=vec2(0.3);
    p*=Rot(radians(45.));
    d = B(p,vec2(0.001,0.008));
    col = mix(col,vec3(1.),S(d,0.0));
    return col;
}

vec3 objects(vec2 p, vec3 col){
    vec2 prevP = p;
    p.y+= iTime*0.1;
    p*=5.;
    vec2 id = floor(p);
    vec2 gr = fract(p)-0.5;
    vec2 prevGr = gr;
    float r = rand(id);
    float d = 10.;
    float bd = 10.;
    if(r<0.2){
        gr.x*=1.7;
        d = Tri(gr-vec2(0.0,-0.09),vec2(0.15),radians(-45.));
        gr = prevGr;
        float d2 = abs(length(gr)-0.16)-0.02;
        float dir = (r>=0.1)?-1.:1.;
        gr*=Rot(radians(iTime*30.*dir));
        d2 = max(-(abs(gr.x)-0.05),d2);
        d = min(d,d2);
    } else if(r>=0.2 && r<0.35){
        bd = B(gr,vec2(0.2,0.11));
        gr.x = abs(gr.x)-0.2;
        bd = min(B(gr,vec2(0.07,0.2)),bd);
        gr = prevGr;
        bd = max(dSlopeLines(gr),bd);
    }
    p = prevP;
    float c = length(p)-0.4;
    d = max(c,d);
    bd = max(c,bd);
    col = mix(col,vec3(0.5),S(d,0.0));
    col = mix(col,vec3(0.4),S(bd,0.0));
    return col;
}

vec3 graph0(vec2 p, vec3 col){
    p*=1.3;
    vec2 prevP = p;
    p.x+=iTime*0.2;
    p*=120.;
    vec2 id = floor(p);
    vec2 gr = fract(p)-0.5;
    float r = rand(vec2(id.x,id.x))*10.;
    gr.y = p.y;
    float d = B(gr,vec2(0.35,0.3+r));
    p = prevP;
    float d2 = B(p,vec2(0.25,0.12));
    d = max(d2,d);
    d2 = abs(d2)-0.0005;
    d2 = max(-min(abs(p.x)-0.23,abs(p.y)-0.1),d2);
    d = min(d,d2);
    col = mix(col,vec3(1.),S(d,0.0));
    return col;
}

vec3 graph1(vec2 p, vec3 col){
    p*=1.3;
    vec2 prevP = p;
    p.y+=0.11;
    p.x+=-iTime*0.1;
    p*=50.;
    vec2 id = floor(p);
    vec2 gr = fract(p)-0.5;
    float r = rand(vec2(id.x,id.x))*10.;
    gr.y = p.y;
    float d = B(gr,vec2(0.4,(0.5+abs(sin(0.3+0.2*iTime*r))*r)));
    p = prevP;
    float d2 = B(p,vec2(0.25,0.12));
    d = max(d2,d);
    p.y+=0.11;
    d = max(-p.y,d);
    p = prevP;
    d2 = B(p,vec2(0.25,0.12));
    d2 = abs(d2)-0.0005;
    d2 = max(-min(abs(p.x)-0.23,abs(p.y)-0.1),d2);
    d = min(d,d2);
    col = mix(col,vec3(1.),S(d,0.0));
    return col;
}

vec3 graph2(vec2 p, vec3 col){
    p*=1.3;
    vec2 prevP = p;
    p*=15.;
    p.x+=iTime*1.5;
    float d = sin(p.y*0.6)*0.3+cos(p.x*1.5)*0.2;
    d = abs(d)-0.005;
    p = prevP;
    p*=15.;
    p.x+=-iTime*1.2;
    float d3 = sin(-p.y*0.7)*0.3+cos(-p.x*1.2)*0.2;
    d3 = abs(d3)-0.005;
    d = min(d,d3);
    p = prevP;
    float d2 = B(p,vec2(0.25,0.12));
    d = max(d2,d);
    d2 = abs(d2)-0.0005;
    d2 = max(-min(abs(p.x)-0.23,abs(p.y)-0.1),d2);
    d = min(d,d2);
    col = mix(col,vec3(1.),S(d,0.0));
    d = max(abs(p.x)-0.25,abs(p.y)-0.0001);
    col = mix(col,vec3(0.5),S(d,0.0));
    d = max(abs(p.x)-0.0001,abs(p.y)-0.15);
    p.x+=iTime*0.05;
    p.x = mod(p.x,0.02)-0.01;
    d2 = B(p,vec2(0.001,0.01));
    d = min(d,d2);
    p = prevP;
    d = max(abs(p.x)-0.25,d);
    p = prevP;
    p.y-=iTime*0.05;
    p.y = mod(p.y,0.02)-0.01;
    d2 = B(p,vec2(0.01,0.001));
    d = min(d,d2);
    p = prevP;
    d = max(abs(p.y)-0.11,d);
    col = mix(col,vec3(0.5),S(d,0.0));
    return col;
}

vec3 graph3(vec2 p, vec3 col){
    p*=1.3;
    vec2 prevP = p;
    p.x+=iTime*0.2;
    p = mod(p,0.03)-0.015;
    float thickness = 0.0001;
    float d = min(abs(p.x)-thickness,abs(p.y)-thickness);
    p = prevP;
    d = max(B(p,vec2(0.24,0.11)),d);
    col = mix(col,vec3(0.3),S(d,0.0));
    p.x+=iTime*0.2;
    p*=12.;
    vec2 id = floor(p);
    vec2 gr = fract(p)-0.5;
    float r = rand(id);
    d = length(gr+r*0.5)-0.08;
    if(r>0.5)d = 10.;
    p = prevP;
    float d2 = B(p,vec2(0.25,0.12));
    d = max(B(p,vec2(0.25,0.08)),d);
    d2 = abs(d2)-0.0005;
    d2 = max(-min(abs(p.x)-0.23,abs(p.y)-0.1),d2);
    d = min(d,d2);
    col = mix(col,vec3(1.),S(d,0.0));
    return col;
}

vec3 smallCircleUI(vec2 p, vec3 col){
    vec2 prevP = p;
    p*=Rot(radians(20.*iTime));
    p=DF(p,15.);
    p-=vec2(0.09);
    p*=Rot(radians(45.));
    float d = B(p,vec2(0.001,0.01));
    p = prevP;
    p*=Rot(radians(20.*iTime));
    p=DF(p,5.);
    p-=vec2(0.1);
    p*=Rot(radians(45.));
    float d2 = B(p,vec2(0.001,0.012));
    d = min(d,d2);
    col = mix(col,vec3(1.),S(d,0.0));
    p = prevP;
    p.y*=-1.;
    p*=Rot(radians(25.0*iTime));
    float a = atan(p.x,p.y);
    d = length(p)-0.1;
    col = mix(col,vec3(1.)*a*0.05,S(d,0.0));
    d = length(p)-0.1;
    a = radians(1.);
    p.x = abs(p.x);
    d = max(dot(p,vec2(cos(a),sin(a))),d);
    p = prevP;
    p.y*=-1.;
    p*=Rot(radians(25.0*iTime));
    d = max(p.y,d);
    col = mix(col,vec3(0.2),S(d,0.0));
    p = prevP;
    d2 = abs(length(p)-0.1)-0.0001;
    d = min(d,d2);
    d2 = abs(length(p)-0.07)-0.0001;
    d = min(d,d2);
    d2 = abs(length(p)-0.04)-0.0001;
    d = min(d,d2);
    d2 = max(length(p)-0.1,min(abs(p.x)-0.0001,abs(p.y)-0.0001));
    d = min(d,d2);
    col = mix(col,vec3(1.),S(d,0.0));
    return col;
}

vec3 smallCircleUI2(vec2 p, vec3 col){
    vec2 prevP = p;
    p*=Rot(radians(-25.*iTime));
    p=DF(p,15.);
    p-=vec2(0.09);
    p*=Rot(radians(45.));
    float d = B(p,vec2(0.001,0.01));
    col = mix(col,vec3(1.),S(d,0.0));
    p = prevP;
    p*=3.5;
    d = drawFont(p-vec2(-0.1,0.0),int(mod(iTime*5.,10.0)));
    float d2 = drawFont(p-vec2(0.1,0.0),int(mod(iTime*10.,10.0)));
    d = min(d,d2);
    col = mix(col,vec3(1.),S(d,0.0));
    p = prevP;
    d = abs(length(p)-0.1)-0.01;
    col = mix(col,vec3(.2),S(d,0.0));
    d = abs(length(p)-0.1)-0.01;
    p*=Rot(radians(20.*iTime));
    float a = radians(60.);
    p.x = abs(p.x);
    d = max(dot(p,vec2(cos(a),sin(a))),d);
    col = mix(col,vec3(.7),S(d,0.0));
    p = prevP;
    p*=Rot(radians(sin(iTime)*160.));
    d = abs(length(p)-0.152)-0.003;
    d = max(abs(p.y)-0.08,d);
    col = mix(col,vec3(1.),S(d,0.0));
    return col;
}

vec3 smallCircleUI3(vec2 p, vec3 col, float dir){
    vec2 prevP = p;
    float d = length(p)-0.007;
    float d2 = abs(length(p)-0.03)-0.0005;
    d = min(d,d2);
    col = mix(col,vec3(1.),S(d,0.0));
    p*=Rot(radians(22.0*iTime*dir));
    float a = radians(30.);
    d2 = abs(length(p)-0.03)-0.016;
    p.x = abs(p.x);
    d2 = max(dot(p,vec2(cos(a),sin(a))),d2);
    p = prevP;
    p*=Rot(radians(22.0*iTime*dir));
    p.x = abs(p.x);
    p*=Rot(radians(-120.));
    float d3 = abs(length(p)-0.03)-0.016;
    p.x = abs(p.x);
    float d4 = max(dot(p,vec2(cos(a),sin(a))),d3);
    d2 = min(d2,d4);
    col = mix(col,vec3(0.3),S(d2,0.0));
    return col;
}

vec3 smallUI0(vec2 p, vec3 col){
    float d = B(p,vec2(0.001,0.03));
    float d2 = B(p,vec2(0.03,0.001));
    d = min(d,d2);
    d = max(-B(p,vec2(0.01)),d);
    col = mix(col,vec3(0.5),S(d,0.0));
    return col;
}

vec3 smallUI1(vec2 p, vec3 col){
    float d = abs(length(p-vec2(0,-0.015))-0.01)-0.0005;
    p.x = abs(p.x);
    float d2 = abs(length(p-vec2(0.017,0.015))-0.01)-0.0005;
    d = min(d,d2);
    col = mix(col,vec3(0.5),S(d,0.0));
    return col;
}

void main()
{
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    vec2 p = (fragCoord-0.5*iResolution.xy)/iResolution.y;
    vec2 prevP = p;

    vec3 col = vec3(0.);

    col = radar(p,col);
    col = grids(p,col);
    col = objects(p,col);
    col = paperPlane(p,col);

    col = graph0(p-vec2(-0.6,0.35),col);
    col = graph1(p-vec2(-0.6,-0.35),col);

    col = graph2(p-vec2(0.6,0.35),col);
    col = graph3(p-vec2(0.6,-0.35),col);

    col = smallCircleUI(p-vec2(-0.64,0.0),col);
    col = smallCircleUI2(p-vec2(0.64,0.0),col);

    p = abs(p);
    col = smallCircleUI3(p-vec2(0.48,0.18),col,1.);

    p = prevP;
    p = abs(p);
    col = smallUI0(p-vec2(0.32,0.41),col);

    p = prevP;
    p = abs(p);
    col = smallUI1(p-vec2(0.76,0.18),col);

    outColor = vec4(sqrt(col),1.0);
}
