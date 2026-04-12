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
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;

    float a = max(abs(p.x)-0.001,abs(p.y)-h);

    p = abs(p);
    float b = max(abs(p.x-w*0.5)-w*0.5,abs(p.y)-0.001);

    float d = min(a,b);
    return d;
}

float seg0(vec2 p){
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;
    float d = max(abs(p.x)-w,abs(p.y)-h);
    d = max(d,-(max(abs(p.x)-w+padding,abs(p.y)-h+padding)));
    return d;
}

float seg1(vec2 p){
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;
    p.x -= w-padding*0.5;
    float d = max(abs(p.x)-padding*0.5,abs(p.y)-h);
    return d;
}

float seg2(vec2 p){
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;
    float hh = padding*2.5;

    float d = max(abs(p.x)-w,abs(p.y)-h);
    d = max(d,-(max(abs(p.x+w*0.5-padding*0.5)-w*0.5+padding*0.5,abs(p.y-hh*0.5)-hh*0.5+padding)));
    d = max(d,-(max(abs(p.x-w*0.5+padding*0.5)-w*0.5+padding*0.5,abs(p.y+hh*0.5)-hh*0.5+padding)));
    return d;
}

float seg3(vec2 p){
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;
    float hh = padding*2.5;

    float d = max(abs(p.x)-w,abs(p.y)-h);
    d = max(d,-(max(abs(p.x+w*0.5-padding*0.5)-w*0.5+padding*0.5,abs(p.y-hh*0.5)-hh*0.5+padding)));
    d = max(d,-(max(abs(p.x+w*0.5-padding*0.5)-w*0.5+padding*0.5,abs(p.y+hh*0.5)-hh*0.5+padding)));
    return d;
}

float seg4(vec2 p){
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;
    float hh = padding*2.5;

    float d = max(abs(p.x)-w,abs(p.y)-h);
    d = max(d,-(max(abs(p.x+w*0.5-padding*0.5)-w*0.5+padding*0.5,abs(p.y+hh*0.5)-hh*0.5+padding)));
    d = max(d,-(max(abs(p.x)-w+padding,abs(p.y-hh*0.5)-hh*0.5+padding)));
    return d;
}

float seg5(vec2 p){
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;
    float hh = padding*2.5;

    float d = max(abs(p.x)-w,abs(p.y)-h);
    d = max(d,-(max(abs(p.x-w*0.5+padding*0.5)-w*0.5+padding*0.5,abs(p.y-hh*0.5)-hh*0.5+padding)));
    d = max(d,-(max(abs(p.x+w*0.5-padding*0.5)-w*0.5+padding*0.5,abs(p.y+hh*0.5)-hh*0.5+padding)));
    return d;
}

float seg6(vec2 p){
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;
    float hh = padding*2.5;

    float d = max(abs(p.x)-w,abs(p.y)-h);
    d = max(d,-(max(abs(p.x-w*0.5+padding*0.5)-w*0.5+padding*0.5,abs(p.y-hh*0.5)-hh*0.5+padding)));
    d = max(d,-(max(abs(p.x)-w+padding,abs(p.y+hh*0.5)-hh*0.5+padding)));
    return d;
}

float seg7(vec2 p){
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;

    float d = max(abs(p.x)-w,abs(p.y)-h);
    d = max(d,-(max(abs(p.x+w*0.5-padding*0.5)-w*0.5+padding*0.5,abs(p.y+padding)-h+padding)));
    return d;
}

float seg8(vec2 p){
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;
    float hh = padding*2.5;

    float d = max(abs(p.x)-w,abs(p.y)-h);
    d = max(d,-(max(abs(p.x)-w+padding,abs(p.y-hh*0.5)-hh*0.5+padding)));
    d = max(d,-(max(abs(p.x)-w+padding,abs(p.y+hh*0.5)-hh*0.5+padding)));
    return d;
}

float seg9(vec2 p){
    float padding = 0.05;
    float w = padding*3.0;
    float h = padding*5.0;
    float hh = padding*2.5;

    float d = max(abs(p.x)-w,abs(p.y)-h);
    d = max(d,-(max(abs(p.x)-w+padding,abs(p.y-hh*0.5)-hh*0.5+padding)));
    d = max(d,-(max(abs(p.x+w*0.5-padding*0.5)-w*0.5+padding*0.5,abs(p.y-hh*0.5)-hh*0.5+padding)));
    return d;
}

float checkChar(vec2 p, int ch){
    float d = 1e6;
    if(ch==seg_0) d = seg0(p);
    else if(ch==seg_1) d = seg1(p);
    else if(ch==seg_2) d = seg2(p);
    else if(ch==seg_3) d = seg3(p);
    else if(ch==seg_4) d = seg4(p);
    else if(ch==seg_5) d = seg5(p);
    else if(ch==seg_6) d = seg6(p);
    else if(ch==seg_7) d = seg7(p);
    else if(ch==seg_8) d = seg8(p);
    else if(ch==seg_9) d = seg9(p);
    return d;
}

float drawFont(vec2 p, int ch){
    float d = segBase(p);
    float c = checkChar(p,ch);
    d = max(d,c);
    return d;
}

vec3 paperPlane(vec2 p, vec3 col){
    vec2 prevP = p;
    float scale = 0.06;
    p /= scale;

    float wing = Tri(p,vec2(0.4,0.3),1.2);
    wing = min(wing,Tri(p*vec2(1,-1),vec2(0.4,0.3),1.2));

    float body = max(abs(p.x)-0.05,abs(p.y)-0.5);
    body = max(body,-Tri(p-vec2(0,0.5),vec2(0.08,0.2),0.5));

    float tail = Tri(p-vec2(0,-0.35),vec2(0.15,0.12),0.8);
    tail = min(tail,Tri((p-vec2(0,-0.35))*vec2(1,-1),vec2(0.15,0.12),0.8));

    float d = min(wing,min(body,tail));
    d *= scale;

    col = mix(col,vec3(1),S(d,0.0));

    return col;
}

vec3 radar(vec2 p, vec3 col){
    vec2 prevP = p;
    float r = 0.12;

    float circle = abs(length(p)-r)-0.001;
    col = mix(col,vec3(1),S(circle,0.0)*0.3);

    float circle2 = abs(length(p)-r*0.5)-0.001;
    col = mix(col,vec3(1),S(circle2,0.0)*0.15);

    float mask = length(p)-r;

    float a = atan(p.y,p.x);
    float sweep = mod(a-iTime*2.0,6.2832);
    float sweepLine = abs(sweep-0.01)-0.005;
    sweepLine = max(sweepLine,-mask);
    col = mix(col,vec3(0,1,0.5),S(sweepLine,0.0)*0.6);

    float trail = smoothstep(0.0,2.0,sweep);
    float trailD = length(p)-r;
    col = mix(col,vec3(0,1,0.5)*0.3,trail*S(-trailD,0.0)*0.2);

    float cross_h = max(abs(p.x)-r,abs(p.y)-0.001);
    float cross_v = max(abs(p.x)-0.001,abs(p.y)-r);
    float crosshair = min(cross_h,cross_v);
    col = mix(col,vec3(1),S(crosshair,0.0)*0.2);

    for(int i=0;i<5;i++){
        float fi = float(i);
        vec2 bp = vec2(rand(vec2(fi,0.0))-0.5,rand(vec2(0.0,fi))-0.5)*r*1.8;
        float blip = length(p-bp)-0.005;
        float blipMask = step(length(bp),r);
        col = mix(col,vec3(0,1,0.5),S(blip,0.0)*0.8*blipMask);
    }

    return col;
}

vec3 grids(vec2 p, vec3 col){
    vec2 prevP = p;

    float gridSize = 0.05;
    vec2 gp = mod(p,gridSize)-gridSize*0.5;
    float grid = min(abs(gp.x),abs(gp.y))-0.0005;
    float gridMask = max(abs(p.x)-0.45,abs(p.y)-0.45);
    col = mix(col,vec3(1),S(grid,0.0)*S(gridMask,0.0)*0.08);

    float gridSize2 = 0.1;
    vec2 gp2 = mod(p,gridSize2)-gridSize2*0.5;
    float grid2 = min(abs(gp2.x),abs(gp2.y))-0.001;
    col = mix(col,vec3(1),S(grid2,0.0)*S(gridMask,0.0)*0.12);

    float axis_h = max(abs(p.x)-0.45,abs(p.y)-0.001);
    float axis_v = max(abs(p.x)-0.001,abs(p.y)-0.45);
    float axes = min(axis_h,axis_v);
    col = mix(col,vec3(1),S(axes,0.0)*0.25);

    float border = abs(max(abs(p.x)-0.45,abs(p.y)-0.45))-0.002;
    col = mix(col,vec3(1),S(border,0.0)*0.4);

    return col;
}

vec3 objects(vec2 p, vec3 col){
    vec2 prevP = p;

    // Corner brackets
    for(int i=0;i<4;i++){
        float fi = float(i);
        vec2 corner = vec2(mod(fi,2.0)*2.0-1.0,floor(fi/2.0)*2.0-1.0)*0.42;
        vec2 cp = p-corner;
        float bracket_h = max(abs(cp.x)-0.03,abs(cp.y)-0.001);
        float bracket_v = max(abs(cp.x)-0.001,abs(cp.y)-0.03);
        float bracket = min(bracket_h,bracket_v);
        col = mix(col,vec3(1),S(bracket,0.0)*0.6);
    }

    // Moving tick marks on axes
    float t = iTime*0.5;
    for(int i=0;i<8;i++){
        float fi = float(i);
        float offset = mod(fi*0.1+t,0.8)-0.4;

        vec2 tp = p-vec2(offset,0.0);
        float tick = max(abs(tp.x)-0.001,abs(tp.y)-0.01);
        float tickMask = step(abs(offset),0.4);
        col = mix(col,vec3(1),S(tick,0.0)*0.3*tickMask);

        vec2 tp2 = p-vec2(0.0,offset);
        float tick2 = max(abs(tp2.x)-0.01,abs(tp2.y)-0.001);
        col = mix(col,vec3(1),S(tick2,0.0)*0.3*tickMask);
    }

    // Center diamond
    float diamond = abs(p.x)+abs(p.y)-0.015;
    col = mix(col,vec3(1),S(diamond,0.0)*0.8);

    // Heading indicator at top
    {
        vec2 hp = p-vec2(0.0,0.42);
        float heading = mod(iTime*20.0,360.0);

        for(int i=-3;i<=3;i++){
            float fi = float(i);
            float deg = mod(heading+fi*10.0,360.0);
            float xpos = fi*0.06;
            vec2 tp = hp-vec2(xpos,0.0);

            float tick3 = max(abs(tp.x)-0.0008,abs(tp.y)-0.015);
            col = mix(col,vec3(1),S(tick3,0.0)*0.5);

            int d0 = int(mod(deg,10.0));
            int d1 = int(mod(deg/10.0,10.0));
            int d2 = int(mod(deg/100.0,10.0));

            float font = drawFont(tp*15.0-vec2(-0.35,0.5),d2);
            font = min(font,drawFont(tp*15.0-vec2(0.0,0.5),d1));
            font = min(font,drawFont(tp*15.0-vec2(0.35,0.5),d0));
            col = mix(col,vec3(1),S(font/15.0,0.0)*0.5);
        }

        float headingBox = max(abs(hp.x)-0.025,abs(hp.y-0.015)-0.02);
        headingBox = abs(headingBox)-0.001;
        col = mix(col,vec3(1),S(headingBox,0.0)*0.6);
    }

    // Altitude indicator on right
    {
        vec2 ap = p-vec2(0.48,0.0);
        float alt = mod(iTime*100.0,10000.0);

        for(int i=-4;i<=4;i++){
            float fi = float(i);
            float val = mod(alt+fi*100.0,10000.0);
            float ypos = fi*0.05;
            vec2 tp = ap-vec2(0.0,ypos);

            float tick4 = max(abs(tp.x)-0.01,abs(tp.y)-0.0008);
            col = mix(col,vec3(1),S(tick4,0.0)*0.4);

            int d0 = int(mod(val/100.0,10.0));
            int d1 = int(mod(val/1000.0,10.0));

            float font2 = drawFont(tp*18.0-vec2(0.5,0.0),d1);
            font2 = min(font2,drawFont(tp*18.0-vec2(0.85,0.0),d0));
            col = mix(col,vec3(1),S(font2/18.0,0.0)*0.4);
        }
    }

    // Speed indicator on left
    {
        vec2 sp = p-vec2(-0.48,0.0);
        float spd = mod(iTime*50.0,1000.0);

        for(int i=-4;i<=4;i++){
            float fi = float(i);
            float val = mod(spd+fi*50.0,1000.0);
            float ypos = fi*0.05;
            vec2 tp = sp-vec2(0.0,ypos);

            float tick5 = max(abs(tp.x)-0.01,abs(tp.y)-0.0008);
            col = mix(col,vec3(1),S(tick5,0.0)*0.4);

            int d0 = int(mod(val/10.0,10.0));
            int d1 = int(mod(val/100.0,10.0));

            float font3 = drawFont(tp*18.0-vec2(-0.85,0.0),d1);
            font3 = min(font3,drawFont(tp*18.0-vec2(-0.5,0.0),d0));
            col = mix(col,vec3(1),S(font3/18.0,0.0)*0.4);
        }
    }

    return col;
}

vec3 graph0(vec2 p, vec3 col){
    vec2 prevP = p;
    float w = 0.12;
    float h = 0.08;

    float border = abs(max(abs(p.x)-w,abs(p.y)-h))-0.001;
    col = mix(col,vec3(1),S(border,0.0)*0.3);

    float mask = max(abs(p.x)-w,abs(p.y)-h);

    // Graph line
    float x = p.x/w;
    float y = sin(x*12.0+iTime*3.0)*0.5+sin(x*6.0-iTime*2.0)*0.3;
    float graphLine = abs(p.y-y*h)-0.002;
    graphLine = max(graphLine,-mask);
    col = mix(col,vec3(0,0.8,1),S(graphLine,0.0)*0.6);

    // Fill below
    float fill = max(p.y-y*h,-mask);
    col = mix(col,vec3(0,0.8,1)*0.2,S(fill,0.0)*0.15);

    return col;
}

vec3 graph1(vec2 p, vec3 col){
    vec2 prevP = p;
    float w = 0.12;
    float h = 0.08;

    float border = abs(max(abs(p.x)-w,abs(p.y)-h))-0.001;
    col = mix(col,vec3(1),S(border,0.0)*0.3);

    float mask = max(abs(p.x)-w,abs(p.y)-h);

    // Bar graph
    for(int i=0;i<8;i++){
        float fi = float(i);
        float bx = -w+w*0.25*0.5+fi*w*0.25;
        float bh = (sin(fi*1.3+iTime*2.0)*0.5+0.5)*h*0.8;
        vec2 bp = p-vec2(bx,-h+bh);
        float bar = max(abs(bp.x)-w*0.1,abs(bp.y)-bh);
        bar = max(bar,-mask);
        col = mix(col,vec3(0,1,0.5),S(bar,0.0)*0.4);
    }

    return col;
}

vec3 graph2(vec2 p, vec3 col){
    vec2 prevP = p;
    float w = 0.12;
    float h = 0.08;

    float border = abs(max(abs(p.x)-w,abs(p.y)-h))-0.001;
    col = mix(col,vec3(1),S(border,0.0)*0.3);

    float mask = max(abs(p.x)-w,abs(p.y)-h);

    // Stepped line
    float x = p.x/w;
    float y = 0.0;
    for(int i=0;i<6;i++){
        float fi = float(i);
        float seg_x = -1.0+fi*0.4;
        float seg_val = sin(fi*2.1+iTime)*0.5;
        float next_val = sin((fi+1.0)*2.1+iTime)*0.5;
        if(x>=seg_x && x<seg_x+0.4){
            y = seg_val;
        }
    }
    float stepLine = abs(p.y-y*h)-0.002;
    stepLine = max(stepLine,-mask);
    col = mix(col,vec3(1,0.5,0),S(stepLine,0.0)*0.5);

    return col;
}

vec3 graph3(vec2 p, vec3 col){
    vec2 prevP = p;
    float w = 0.12;
    float h = 0.08;

    float border = abs(max(abs(p.x)-w,abs(p.y)-h))-0.001;
    col = mix(col,vec3(1),S(border,0.0)*0.3);

    float mask = max(abs(p.x)-w,abs(p.y)-h);

    // Scatter dots
    for(int i=0;i<12;i++){
        float fi = float(i);
        vec2 dp = vec2(rand(vec2(fi,1.0))-0.5,rand(vec2(1.0,fi))-0.5)*vec2(w,h)*1.8;
        float pulse = sin(iTime*2.0+fi)*0.003;
        float dot_d = length(p-dp)-0.004-pulse;
        dot_d = max(dot_d,-mask);
        col = mix(col,vec3(1,0.3,0.3),S(dot_d,0.0)*0.5);
    }

    return col;
}

vec3 smallCircleUI(vec2 p, vec3 col){
    vec2 prevP = p;
    float r = 0.05;

    float circle = abs(length(p)-r)-0.001;
    col = mix(col,vec3(1),S(circle,0.0)*0.4);

    // Rotating ticks
    for(int i=0;i<8;i++){
        float fi = float(i);
        float a = fi*0.785+iTime;
        vec2 tp = p-vec2(cos(a),sin(a))*r;
        float tick = length(tp)-0.003;
        col = mix(col,vec3(1),S(tick,0.0)*0.5);
    }

    // Center dot
    float center = length(p)-0.005;
    col = mix(col,vec3(1),S(center,0.0)*0.6);

    // Value arc
    float arcAngle = sin(iTime)*1.5+1.5;
    float arc_a = atan(p.y,p.x);
    float arc_d = abs(length(p)-r*0.7)-0.002;
    float arcMask = step(arc_a,-3.14159+arcAngle);
    arc_d = max(arc_d,-(length(p)-r*0.5));
    col = mix(col,vec3(0,0.8,1),S(arc_d,0.0)*0.5*arcMask);

    return col;
}

vec3 smallCircleUI2(vec2 p, vec3 col){
    vec2 prevP = p;
    float r = 0.05;

    float circle = abs(length(p)-r)-0.001;
    col = mix(col,vec3(1),S(circle,0.0)*0.4);

    // Pie segments
    for(int i=0;i<4;i++){
        float fi = float(i);
        float a1 = fi*1.5708;
        float a2 = a1+1.2;
        float pa = atan(p.y,p.x);
        float pie_d = length(p)-r*0.8;
        float angMask = step(a1,pa)*step(pa,a2);
        pie_d = max(pie_d,-(length(p)-r*0.3));
        float brightness = 0.2+sin(iTime+fi)*0.15;
        col = mix(col,vec3(0,1,0.5)*brightness,S(pie_d,0.0)*angMask);
    }

    // Inner circle
    float inner = abs(length(p)-r*0.25)-0.001;
    col = mix(col,vec3(1),S(inner,0.0)*0.3);

    return col;
}

vec3 smallCircleUI3(vec2 p, vec3 col, float side){
    vec2 prevP = p;
    float r = 0.04;

    float circle = abs(length(p)-r)-0.001;
    col = mix(col,vec3(1),S(circle,0.0)*0.3);

    // Progress ring
    float progress = sin(iTime*0.8+side)*0.5+0.5;
    float pa = atan(p.y,p.x);
    float normalized = (pa+3.14159)/(6.28318);
    float ring = abs(length(p)-r*0.75)-0.003;
    float ringMask = step(normalized,progress);
    col = mix(col,vec3(0,0.8,1),S(ring,0.0)*0.5*ringMask);

    // Number in center
    int val = int(progress*100.0);
    int d0 = int(mod(float(val),10.0));
    int d1 = int(mod(float(val)/10.0,10.0));
    float font = drawFont(p*60.0-vec2(-0.2,0.0),d1);
    font = min(font,drawFont(p*60.0-vec2(0.2,0.0),d0));
    col = mix(col,vec3(1),S(font/60.0,0.0)*0.5);

    return col;
}

vec3 smallUI0(vec2 p, vec3 col){
    vec2 prevP = p;
    float w = 0.06;
    float h = 0.015;

    float border = abs(max(abs(p.x)-w,abs(p.y)-h))-0.001;
    col = mix(col,vec3(1),S(border,0.0)*0.3);

    // Animated fill bar
    float fillAmount = sin(iTime*1.5)*0.5+0.5;
    float fillBar = max(abs(p.x+w-fillAmount*w*2.0)-fillAmount*w*2.0,abs(p.y)-h+0.003);
    fillBar = max(fillBar,-(max(abs(p.x)-w+0.002,abs(p.y)-h+0.002)));
    col = mix(col,vec3(0,1,0.5)*0.5,S(-fillBar,0.0)*0.3);

    // Tick marks
    for(int i=0;i<5;i++){
        float fi = float(i);
        float xp = -w+fi*w*0.5;
        float tick = max(abs(p.x-xp)-0.0005,abs(p.y)-h-0.005);
        col = mix(col,vec3(1),S(tick,0.0)*0.2);
    }

    return col;
}

vec3 smallUI1(vec2 p, vec3 col){
    vec2 prevP = p;

    // Diamond indicator
    float size = 0.015;
    float diamond = abs(p.x)+abs(p.y)-size;
    col = mix(col,vec3(1),S(diamond,0.0)*0.5);

    float diamond2 = abs(abs(p.x)+abs(p.y)-size*1.5)-0.001;
    col = mix(col,vec3(1),S(diamond2,0.0)*0.3);

    // Rotating outer markers
    for(int i=0;i<4;i++){
        float fi = float(i);
        float a = fi*1.5708+iTime*0.5;
        vec2 mp = p-vec2(cos(a),sin(a))*0.025;
        float marker = max(abs(mp.x)-0.003,abs(mp.y)-0.003);
        col = mix(col,vec3(1),S(marker,0.0)*0.4);
    }

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
