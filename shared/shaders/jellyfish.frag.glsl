#version 450

// Luminescence - Ported from Shadertoy
// https://www.shadertoy.com/view/4sXBRn
// Martijn Steinrucken aka BigWings - 2017 (CC BY-NC-SA 3.0)

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

#define INVERTMOUSE -1.

#define MAX_STEPS 100.
#define VOLUME_STEPS 8.
#define MIN_DISTANCE 0.1
#define MAX_DISTANCE 100.
#define HIT_DISTANCE .01

#define S(x,y,z) smoothstep(x,y,z)
#define B(x,y,z,w) S(x-z, x+z, w)*S(y+z, y-z, w)
#define sat(x) clamp(x,0.,1.)
#define SIN(x) (sin(x)*.5+.5)

const vec3 lf = vec3(1., 0., 0.);
const vec3 up = vec3(0., 1., 0.);
const vec3 fw = vec3(0., 0., 1.);

const float halfpi = 1.570796326794896619;
const float pi = 3.141592653589793238;
const float twopi = 6.283185307179586;

vec3 accentColor1 = vec3(1., .1, .5);
vec3 secondColor1 = vec3(.1, .5, 1.);
vec3 accentColor2 = vec3(1., .5, .1);
vec3 secondColor2 = vec3(.1, .5, .6);

vec3 bg;
vec3 accent;

float N1(float x) { return fract(sin(x)*5346.1764); }
float N2(float x, float y) { return N1(x + y*23414.324); }
float N3(vec3 p) {
    p  = fract(p*0.3183099+.1);
    p *= 17.0;
    return fract(p.x*p.y*p.z*(p.x+p.y+p.z));
}

struct ray { vec3 o; vec3 d; };
struct camera {
    vec3 p;
    vec3 forward;
    vec3 left;
    vec3 up;
    vec3 center;
    vec3 i;
    ray ray;
    vec3 lookAt;
    float zoom;
};
struct de {
    float d;
    float m;
    vec3 uv;
    float pump;
    vec3 id;
    vec3 pos;
};
struct rc {
    vec3 id;
    vec3 h;
    vec3 p;
};

rc Repeat(vec3 pos, vec3 size) {
    rc o;
    o.h = size*.5;
    o.id = floor(pos/size);
    o.p = mod(pos, size)-o.h;
    return o;
}

camera cam;

void CameraSetup(vec2 uv, vec3 position, vec3 lookAt, float zoom) {
    cam.p = position;
    cam.lookAt = lookAt;
    cam.forward = normalize(cam.lookAt-cam.p);
    cam.left = cross(up, cam.forward);
    cam.up = cross(cam.forward, cam.left);
    cam.zoom = zoom;
    cam.center = cam.p+cam.forward*cam.zoom;
    cam.i = cam.center+cam.left*uv.x+cam.up*uv.y;
    cam.ray.o = cam.p;
    cam.ray.d = normalize(cam.i-cam.p);
}

vec3 N31(float p) {
    vec3 p3 = fract(vec3(p) * vec3(.1031,.11369,.13787));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract(vec3((p3.x + p3.y)*p3.z, (p3.x+p3.z)*p3.y, (p3.y+p3.z)*p3.x));
}

float smin(float a, float b, float k) {
    float h = clamp(0.5+0.5*(b-a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0-h);
}
float smax(float a, float b, float k) {
    float h = clamp(0.5 + 0.5*(b-a)/k, 0.0, 1.0);
    return mix(a, b, h) + k*h*(1.0-h);
}
float sdSphere(vec3 p, vec3 pos, float s) { return (length(p-pos)-s); }

vec2 pModPolar(inout vec2 p, float repetitions, float fix) {
    float angle = twopi/repetitions;
    float a = atan(p.y, p.x) + angle/2.;
    float r = length(p);
    a = mod(a,angle) - (angle/2.)*fix;
    p = vec2(cos(a), sin(a))*r;
    return p;
}

float Dist(vec2 P, vec2 P0, vec2 P1) {
    vec2 v = P1 - P0;
    vec2 w = P - P0;
    float c1 = dot(w, v);
    float c2 = dot(v, v);
    if (c1 <= 0.) return length(P-P0);
    float b = c1 / c2;
    vec2 Pb = P0 + b*v;
    return length(P-Pb);
}

vec2 sph(vec3 ro, vec3 rd, vec3 pos, float radius) {
    vec3 oc = pos - ro;
    float l = dot(rd, oc);
    float det = l*l - dot(oc, oc) + radius*radius;
    if (det < 0.0) return vec2(MAX_DISTANCE);
    float d = sqrt(det);
    return vec2(l - d, l + d);
}

vec3 background(vec3 r) {
    float x = atan(r.x, r.z);
    float y = pi*0.5-acos(r.y);
    vec3 col = bg*(1.+y);
    float t = iTime;
    float a = sin(r.x);
    float beam = sat(sin(10.*x+a*y*5.+t));
    beam *= sat(sin(7.*x+a*y*3.5-t));
    float beam2 = sat(sin(42.*x+a*y*21.-t));
    beam2 *= sat(sin(34.*x+a*y*17.+t));
    beam += beam2;
    col *= 1.+beam*.05;
    return col;
}

float remap(float a, float b, float c, float d, float t) {
    return ((t-a)/(b-a))*(d-c)+c;
}

de map(vec3 p, vec3 id) {
    float t = iTime*2.;
    float N = N3(id);
    de o;
    o.m = 0.;
    float x = (p.y+N*twopi)*1.+t;
    float r = 1.;
    float pump = cos(x+cos(x))+sin(2.*x)*.2+sin(4.*x)*.02;
    x = t + N*twopi;
    p.y -= (cos(x+cos(x))+sin(2.*x)*.2)*.6;
    p.xz *= 1. + pump*.2;
    float d1 = sdSphere(p, vec3(0., 0., 0.), r);
    float d2 = sdSphere(p, vec3(0., -.5, 0.), r);
    o.d = smax(d1, -d2, .1);
    o.m = 1.;
    if (p.y<.5) {
        float sway = sin(t+p.y+N*twopi)*S(.5, -3., p.y)*N*.3;
        p.x += sway*N;
        p.z += sway*(1.-N);
        vec3 mp = p;
        mp.xz = pModPolar(mp.xz, 6., 0.);
        float d3 = length(mp.xz-vec2(.2, .1))-remap(.5, -3.5, .1, .01, mp.y);
        if (d3<o.d) o.m = 2.;
        d3 += (sin(mp.y*10.)+sin(mp.y*23.))*.03;
        float d32 = length(mp.xz-vec2(.2, .1))-remap(.5, -3.5, .1, .04, mp.y)*.5;
        d3 = min(d3, d32);
        o.d = smin(o.d, d3, .5);
        if (p.y<.2) {
            vec3 op = p;
            op.xz = pModPolar(op.xz, 13., 1.);
            float d4 = length(op.xz-vec2(.85, .0))-remap(.5, -3., .04, .0, op.y);
            if (d4<o.d) o.m = 3.;
            o.d = smin(o.d, d4, .15);
        }
    }
    o.pump = pump;
    o.uv = p;
    o.d *= .8;
    return o;
}

vec3 calcNormal(de o) {
    vec3 eps = vec3(0.01, 0.0, 0.0);
    vec3 nor = vec3(
        map(o.pos+eps.xyy, o.id).d - map(o.pos-eps.xyy, o.id).d,
        map(o.pos+eps.yxy, o.id).d - map(o.pos-eps.yxy, o.id).d,
        map(o.pos+eps.yyx, o.id).d - map(o.pos-eps.yyx, o.id).d);
    return normalize(nor);
}

de CastRay(ray r) {
    float d = 0.;
    vec3 p;
    rc q;
    float t = iTime;
    vec3 grid = vec3(6., 30., 6.);
    de o, s;
    s.d = MAX_DISTANCE;
    float dC = MAX_DISTANCE;

    for (float i=0.; i<MAX_STEPS; i++) {
        p = r.o + r.d*d;
        p.y -= t;
        p.x += t;
        q = Repeat(p, grid);
        vec3 rC = ((2.*step(0., r.d)-1.)*q.h-q.p)/r.d;
        dC = min(min(rC.x, rC.y), rC.z)+.01;
        float N = N3(q.id);
        q.p += (N31(N)-.5)*grid*vec3(.5, .7, .5);
        if (Dist(q.p.xz, r.d.xz, vec2(0.))<1.1)
            s = map(q.p, q.id);
        else
            s.d = dC;
        if (s.d<HIT_DISTANCE || d>MAX_DISTANCE) break;
        d += min(s.d, dC);
    }

    if (s.d<HIT_DISTANCE) {
        o.m = s.m;
        o.d = d;
        o.id = q.id;
        o.uv = s.uv;
        o.pump = s.pump;
        o.pos = q.p;
    } else {
        o.m = 0.;
        o.d = d;
    }
    return o;
}

float VolTex(vec3 uv, vec3 p, float scale, float pump) {
    p.y *= scale;
    float s2 = 5.*p.x/twopi;
    s2 = fract(s2);
    vec2 ep = vec2(s2-.5, p.y-.6);
    float ed = length(ep);
    float e = B(.35, .45, .05, ed);
    float s = SIN(s2*twopi*15.);
    s = s*s; s = s*s;
    s *= S(1.4, -.3, uv.y-cos(s2*twopi)*.2+.3)*S(-.6, -.3, uv.y);
    float t = iTime*5.;
    float mask = SIN(p.x*twopi*2. + t);
    s *= mask*mask*2.;
    return s+e*pump*2.;
}

vec4 JellyTex(vec3 p) {
    vec3 s = vec3(atan(p.x, p.z), length(p.xz), p.y);
    float b = .75+sin(s.x*6.)*.25;
    b = mix(1., b, s.y*s.y);
    p.x += sin(s.z*10.)*.1;
    float b2 = cos(s.x*26.) - s.z-.7;
    b2 = S(.1, .6, b2);
    return vec4(b+b2);
}

vec3 render(vec2 uv, ray camRay, float depth) {
    bg = background(cam.ray.d);
    vec3 col = bg;
    de o = CastRay(camRay);
    vec3 L = up;
    if (o.m>0.) {
        vec3 n = calcNormal(o);
        float lambert = sat(dot(n, L));
        vec3 R = reflect(camRay.d, n);
        float fresnel = sat(1.+dot(camRay.d, n));
        vec3 ref = background(R);
        float fade = 0.;
        if (o.m==1.) {
            float density = 0.;
            for (float i=0.; i<VOLUME_STEPS; i++) {
                float sd = sph(o.uv, camRay.d, vec3(0.), .8+i*.015).x;
                if (sd!=MAX_DISTANCE) {
                    vec2 intersect = o.uv.xz+camRay.d.xz*sd;
                    vec3 uvv = vec3(atan(intersect.x, intersect.y), length(intersect.xy), o.uv.z);
                    density += VolTex(o.uv, uvv, 1.4+i*.03, o.pump);
                }
            }
            vec4 volTex = vec4(accent, density/VOLUME_STEPS);
            vec3 dif = JellyTex(o.uv).rgb;
            dif *= max(.2, lambert);
            col = mix(col, volTex.rgb, volTex.a);
            col = mix(col, vec3(dif), .25);
            col += fresnel*ref*sat(dot(up, n));
            fade = max(fade, S(.0, 1., fresnel));
        } else if (o.m==2.) {
            vec3 dif = accent;
            col = mix(bg, dif, fresnel);
            col *= mix(.6, 1., S(0., -1.5, o.uv.y));
            float prop = o.pump+.25;
            prop *= prop*prop;
            col += pow(1.-fresnel, 20.)*dif*prop;
            fade = fresnel;
        } else if (o.m==3.) {
            vec3 dif = accent;
            float d = S(100., 13., o.d);
            col = mix(bg, dif, pow(1.-fresnel, 5.)*d);
        }
        fade = max(fade, S(0., 100., o.d));
        col = mix(col, bg, fade);
    } else {
        col = bg;
    }
    return col;
}

void main() {
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    float t = iTime*.04;
    vec2 uv = fragCoord.xy / iResolution.xy;
    uv -= .5;
    uv.y *= iResolution.y/iResolution.x;
    vec2 m = iMouse.xy/iResolution.xy;
    if (m.x<0.05 || m.x>.95) {
        m = vec2(t*.25, SIN(t*pi)*.5+.5);
    }
    accent = mix(accentColor1, accentColor2, SIN(t*15.456));
    bg = mix(secondColor1, secondColor2, SIN(t*7.345231));
    float turn = (.1-m.x)*twopi;
    float s = sin(turn);
    float c = cos(turn);
    mat3 rotX = mat3(c, 0., s, 0., 1., 0., s, 0., -c);
    float camDist = -.1;
    vec3 lookAt = vec3(0., -1., 0.);
    vec3 camPos = vec3(0., INVERTMOUSE*camDist*cos((m.y)*pi), camDist)*rotX;
    CameraSetup(uv, camPos+lookAt, lookAt, 1.);
    vec3 col = render(uv, cam.ray, 0.);
    col = pow(col, vec3(mix(1.5, 2.6, SIN(t+pi))));
    float d = 1.-dot(uv, uv);
    col *= (d*d*d)+.1;
    outColor = vec4(col, 1.0);
}
