#version 450

// another synthwave sunset thing - Ported from Shadertoy
// https://www.shadertoy.com/view/tsScRK
// Pseudo-tessellation (triangle) noise terrain under a synthwave sunset.
// Sound-texture sampling is disabled in the original by default, so the
// audio-visualizer path (textureMirror) is folded out here.

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

#define speed 10.
#define wave_thing

float jTime;

float amp(vec2 p) {
    return smoothstep(1., 8., abs(p.x));
}

float pow512(float a) {
    a *= a; // ^2
    a *= a; // ^4
    a *= a; // ^8
    a *= a; // ^16
    a *= a; // ^32
    a *= a; // ^64
    a *= a; // ^128
    a *= a; // ^256
    return a * a;
}
float pow1d5(float a) {
    return a * sqrt(a);
}
float hash21(vec2 co) {
    return fract(sin(dot(co.xy, vec2(1.9898, 7.233))) * 45758.5433);
}
float hash(vec2 uv) {
    float a = amp(uv);
#ifdef wave_thing
    float w = a > 0. ? (1. - .4 * pow512(.51 + .49 * sin((.02 * (uv.y + .5 * uv.x) - jTime) * 2.))) : 0.;
#else
    float w = 1.;
#endif
    return a > 0. ? a * pow1d5(hash21(uv)) * w : 0.;
}

// With sound sampling disabled the a1/a2/a3 edge attenuations are always 1.
float edgeMin(float dx, vec2 da, vec2 db) {
    return min(min((1. - dx) * db.y, da.x), da.y);
}

vec2 trinoise(vec2 uv) {
    const float sq = sqrt(3. / 2.);
    uv.x *= sq;
    uv.y -= .5 * uv.x;
    vec2 d = fract(uv);
    uv -= d;

    bool c = dot(d, vec2(1)) > 1.;

    vec2 dd = 1. - d;
    vec2 da = c ? dd : d, db = c ? d : dd;

    float nn = hash(uv + float(c));
    float n2 = hash(uv + vec2(1, 0));
    float n3 = hash(uv + vec2(0, 1));

    float nmid = mix(n2, n3, d.y);
    float ns = mix(nn, c ? n2 : n3, da.y);
    float dx = da.x / db.y;
    return vec2(mix(ns, nmid, dx), edgeMin(dx, da, db));
}

vec2 map(vec3 p) {
    vec2 n = trinoise(p.xz);
    return vec2(p.y - 2. * n.x, n.y);
}

vec3 grad(vec3 p) {
    const vec2 e = vec2(.005, 0);
    float a = map(p).x;
    return vec3(map(p + e.xyy).x - a,
                map(p + e.yxy).x - a,
                map(p + e.yyx).x - a) / e.x;
}

vec2 intersect(vec3 ro, vec3 rd) {
    float d = 0., h = 0.;
    for (int i = 0; i < 500; i++) { // look nice with 50 iterations
        vec3 p = ro + d * rd;
        vec2 s = map(p);
        h = s.x;
        d += h * .5;
        if (abs(h) < .003 * d)
            return vec2(d, s.y);
        if (d > 150. || p.y > 2.) break;
    }
    return vec2(-1);
}

void addsun(vec3 rd, vec3 ld, inout vec3 col) {
    float sun = smoothstep(.21, .2, distance(rd, ld));

    if (sun > 0.) {
        float yd = (rd.y - ld.y);
        float a = sin(3.1 * exp(-(yd) * 14.));
        sun *= smoothstep(-.8, 0., a);
        col = mix(col, vec3(1., .8, .4) * .75, sun);
    }
}

float starnoise(vec3 rd) {
    float c = 0.;
    vec3 p = normalize(rd) * 300.;
    for (float i = 0.; i < 4.; i++) {
        vec3 q = fract(p) - .5;
        vec3 id = floor(p);
        float c2 = smoothstep(.5, 0., length(q));
        c2 *= step(hash21(id.xz / id.y), .06 - i * i * 0.005);
        c += c2;
        p = p * .6 + .5 * p * mat3(3. / 5., 0, 4. / 5., 0, 1, 0, -4. / 5., 0, 3. / 5.);
    }
    c *= c;
    float g = dot(sin(rd * 10.512), cos(rd.yzx * 10.512));
    c *= smoothstep(-3.14, -.9, g) * .5 + .5 * smoothstep(-.3, 1., g);
    return c * c;
}

vec3 gsky(vec3 rd, vec3 ld, bool mask) {
    float haze = exp2(-5. * (abs(rd.y) - .2 * dot(rd, ld)));
    float st = mask ? (starnoise(rd)) * (1. - min(haze, 1.)) : 0.;
    vec3 back = vec3(.4, .1, .7);
    vec3 col = clamp(mix(back, vec3(.7, .1, .4), haze) + st, 0., 1.);
    if (mask) addsun(rd, ld, col);
    return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    const float AA = 1.;
    const float iTimeDelta = 1. / 60.;
    vec2 uv = (2. * fragCoord - iResolution.xy) / iResolution.y;

    const float shutter_speed = .25; // for motion blur
    float dt = fract(hash21(AA * fragCoord) + iTime) * shutter_speed;
    jTime = mod(iTime - dt * iTimeDelta, 4000.);
    vec3 ro = vec3(0., 1, (-20000. + jTime * speed));

    vec3 rd = normalize(vec3(uv, 4. / 3.));

    vec2 i = intersect(ro, rd);
    float d = i.x;

    vec3 ld = normalize(vec3(0, .125 + .05 * sin(.1 * jTime), 1));

    vec3 fog = d > 0. ? exp2(-d * vec3(.14, .1, .28)) : vec3(0.);
    vec3 sky = gsky(rd, ld, d < 0.);

    vec3 p = ro + d * rd;
    vec3 n = normalize(grad(p));

    float diff = dot(n, ld) + .1 * n.y;
    vec3 col = vec3(.1, .11, .18) * diff;

    vec3 rfd = reflect(rd, n);
    vec3 rfcol = gsky(rfd, ld, true);

    col = mix(col, rfcol, .05 + .95 * pow(max(1. + dot(rd, n), 0.), 5.));
    col = mix(col, vec3(.8, .1, .92), smoothstep(.05, .0, i.y));
    col = mix(sky, col, fog);
    // no gamma for that old cg look
    fragColor = vec4(clamp(col, 0., 1.), 1.);
}

void main() {
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    vec4 o;
    mainImage(o, fragCoord);
    outColor = vec4(o.rgb, 1.0);
}
