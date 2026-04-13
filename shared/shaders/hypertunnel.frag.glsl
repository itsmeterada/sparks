#version 450

// Hyper Tunnel - Ported from Shadertoy
// https://www.shadertoy.com/view/4t2cR1
// From "Sailing Beyond" demoscene (CC BY-NC-SA 3.0)

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

#define FAR 1e3
#define INFINITY 1e32
#define FOV 70.0
#define PI 3.14159265

float hash12(vec2 p) {
    float h = dot(p, vec2(127.1, 311.7));
    return fract(sin(h)*43758.5453123);
}

float noise_3(in vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 fm = f - 1.0;
    vec3 u = 1.0 + fm*fm*fm*fm*fm;

    vec2 ii = i.xy + i.z * vec2(5.0);
    float a = hash12(ii + vec2(0.0, 0.0));
    float b = hash12(ii + vec2(1.0, 0.0));
    float c = hash12(ii + vec2(0.0, 1.0));
    float d = hash12(ii + vec2(1.0, 1.0));
    float v1 = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);

    ii += vec2(5.0);
    a = hash12(ii + vec2(0.0, 0.0));
    b = hash12(ii + vec2(1.0, 0.0));
    c = hash12(ii + vec2(0.0, 1.0));
    d = hash12(ii + vec2(1.0, 1.0));
    float v2 = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);

    return max(mix(v1, v2, u.z), 0.0);
}

float fbm(vec3 x) {
    float r = 0.0;
    float w = 1.0, s = 1.0;
    for (int i = 0; i < 4; i++) {
        w *= 0.25;
        s *= 3.0;
        r += w * noise_3(s * x);
    }
    return r;
}

float yC(float x) {
    return cos(x * -0.134) * 1.0 * sin(x * 0.13) * 15.0 + fbm(vec3(x * 0.1, 0.0, 0.0) * 55.4);
}

struct geometry {
    float dist;
    vec3 hit;
    int iterations;
};

float fCylinderInf(vec3 p, float r) {
    return length(p.xz) - r;
}

geometry mapScene(vec3 p) {
    p.x -= yC(p.y * 0.1) * 3.0;
    p.z += yC(p.y * 0.01) * 4.0;

    float n = pow(abs(fbm(p * 0.06)) * 12.0, 1.3);
    float s = fbm(p * 0.01 + vec3(0.0, iTime * 0.14, 0.0)) * 128.0;

    geometry obj;
    obj.hit = vec3(0.0);
    obj.iterations = 0;
    obj.dist = max(0.0, -fCylinderInf(p, s + 18.0 - n));

    p.x -= sin(p.y * 0.02) * 34.0 + cos(p.z * 0.01) * 62.0;
    obj.dist = max(obj.dist, -fCylinderInf(p, s + 28.0 + n * 2.0));

    return obj;
}

const int MAX_ITERATIONS = 100;

geometry trace(vec3 o, vec3 d) {
    float t_min = 10.0;
    float t_max = FAR;
    float omega = 1.3;
    float t = t_min;
    float candidate_error = INFINITY;
    float candidate_t = t_min;
    float previousRadius = 0.0;
    float stepLength = 0.0;
    float pixelRadius = 1.0 / 1000.0;

    geometry mp = mapScene(o);
    float functionSign = mp.dist < 0.0 ? -1.0 : 1.0;

    for (int i = 0; i < MAX_ITERATIONS; ++i) {
        mp = mapScene(d * t + o);
        mp.iterations = i;

        float signedRadius = functionSign * mp.dist;
        float radius = abs(signedRadius);
        bool sorFail = omega > 1.0 && (radius + previousRadius) < stepLength;

        if (sorFail) {
            stepLength -= omega * stepLength;
            omega = 1.0;
        } else {
            stepLength = signedRadius * omega;
        }
        previousRadius = radius;
        float error = radius / t;

        if (!sorFail && error < candidate_error) {
            candidate_t = t;
            candidate_error = error;
        }

        if ((!sorFail && error < pixelRadius) || t > t_max) break;

        t += stepLength * 0.5;
    }

    mp.dist = candidate_t;
    if (t > t_max || candidate_error > pixelRadius) mp.dist = INFINITY;
    return mp;
}

void main() {
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    vec2 ouv = fragCoord / iResolution;
    vec2 uv = ouv - 0.5;
    uv *= tan(radians(FOV) / 2.0) * 4.0;

    float T = iTime;
    vec3 vuv = normalize(vec3(cos(T), sin(T * 0.11), sin(T * 0.41)));
    vec3 ro = vec3(0.0, 30.0 + iTime * 100.0, -0.1);
    ro.x += yC(ro.y * 0.1) * 3.0;
    ro.z -= yC(ro.y * 0.01) * 4.0;

    vec3 vrp = vec3(0.0, 50.0 + iTime * 100.0, 2.0);
    vrp.x += yC(vrp.y * 0.1) * 3.0;
    vrp.z -= yC(vrp.y * 0.01) * 4.0;

    vec3 vpn = normalize(vrp - ro);
    vec3 u = normalize(cross(vuv, vpn));
    vec3 v = cross(vpn, u);
    vec3 vcv = ro + vpn;
    vec3 scrCoord = vcv + uv.x * u * iResolution.x / iResolution.y + uv.y * v;
    vec3 rd = normalize(scrCoord - ro);
    vec3 oro = ro;

    vec3 sceneColor = vec3(0.0);
    geometry tr = trace(ro, rd);
    tr.hit = ro + rd * tr.dist;

    vec3 col = vec3(1.0, 0.5, 0.4) * fbm(tr.hit.xzy * 0.01) * 20.0;
    col.b *= fbm(tr.hit * 0.01) * 10.0;

    sceneColor += min(0.8, float(tr.iterations) / 90.0) * col + col * 0.03;
    sceneColor *= 1.0 + 0.9 * (abs(fbm(tr.hit * 0.002 + 3.0) * 10.0) * fbm(vec3(0.0, 0.0, iTime * 0.05) * 2.0));
    sceneColor *= 0.6;

    vec3 steamColor1 = vec3(0.0, 0.4, 0.5);
    vec3 rro = oro;
    ro = tr.hit;

    float distC = tr.dist, f = 0.0;
    for (float i = 0.0; i < 24.0; i++) {
        rro = ro - rd * distC;
        f += fbm(rro * vec3(0.1, 0.1, 0.1) * 0.3) * 0.1;
        distC -= 3.0;
        if (distC < 3.0) break;
    }

    sceneColor += steamColor1 * pow(abs(f * 1.5), 3.0) * 4.0;

    vec4 fragColor = vec4(clamp(sceneColor * (1.0 - length(uv) / 2.0), 0.0, 1.0), 1.0);
    fragColor = pow(abs(fragColor / tr.dist * 130.0), vec4(0.8));
    outColor = fragColor;
}
