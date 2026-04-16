#version 450

// Fur Ball - Ported from Shadertoy "fur ball"
// Original Author: Simon Green (@simesgreen) v1.1, 2013
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

layout(set = 0, binding = 0) uniform sampler2D iChannel0; // noise (density)
layout(set = 0, binding = 1) uniform sampler2D iChannel1; // noise (color)

const float uvScale = 1.0;
const float colorUvScale = 0.1;
const float furDepth = 0.2;
const int furLayers = 64;
const float rayStep = furDepth * 2.0 / float(furLayers);
const float furThreshold = 0.4;
const float shininess = 50.0;

bool intersectSphere(vec3 ro, vec3 rd, float r, out float t) {
    float b = dot(-ro, rd);
    float det = b*b - dot(ro, ro) + r*r;
    if (det < 0.0) return false;
    det = sqrt(det);
    t = b - det;
    return t > 0.0;
}

vec3 rotateX(vec3 p, float a) {
    float sa = sin(a);
    float ca = cos(a);
    return vec3(p.x, ca*p.y - sa*p.z, sa*p.y + ca*p.z);
}

vec3 rotateY(vec3 p, float a) {
    float sa = sin(a);
    float ca = cos(a);
    return vec3(ca*p.x + sa*p.z, p.y, -sa*p.x + ca*p.z);
}

vec2 cartesianToSpherical(vec3 p) {
    float r = length(p);
    float t = (r - (1.0 - furDepth)) / furDepth;
    p = rotateX(p.zyx, -cos(iTime * 1.5) * t * t * 0.4).zyx;
    p /= r;
    vec2 uv = vec2(atan(p.y, p.x), acos(p.z));
    uv.y -= t * t * 0.1;
    return uv;
}

float furDensity(vec3 pos, out vec2 uv) {
    uv = cartesianToSpherical(pos.xzy);
    // iChannel0 sampled with Y-flip to mimic the original setup
    // (Shadertoy version supplies Y-flipped texture as iChannel0).
    vec4 tex = textureLod(iChannel0, vec2(uv.x, -uv.y) * uvScale, 0.0);
    float density = smoothstep(furThreshold, 1.0, tex.x);
    float r = length(pos);
    float t = (r - (1.0 - furDepth)) / furDepth;
    float len = tex.y;
    density *= smoothstep(len, len - 0.2, t);
    return density;
}

vec3 furNormal(vec3 pos, float density) {
    float eps = 0.01;
    vec3 n;
    vec2 uv;
    n.x = furDensity(vec3(pos.x + eps, pos.y, pos.z), uv) - density;
    n.y = furDensity(vec3(pos.x, pos.y + eps, pos.z), uv) - density;
    n.z = furDensity(vec3(pos.x, pos.y, pos.z + eps), uv) - density;
    return normalize(n);
}

vec3 furShade(vec3 pos, vec2 uv, vec3 ro, float density) {
    const vec3 L = vec3(0, 1, 0);
    vec3 V = normalize(ro - pos);
    vec3 H = normalize(V + L);

    vec3 N = -furNormal(pos, density);
    float diff = max(0.0, dot(N, L) * 0.5 + 0.5);
    float spec = pow(max(0.0, dot(N, H)), shininess);

    vec3 color = textureLod(iChannel1, uv * colorUvScale, 0.0).xyz;

    float r = length(pos);
    float t = (r - (1.0 - furDepth)) / furDepth;
    t = clamp(t, 0.0, 1.0);
    float i = t * 0.5 + 0.5;

    return color * diff * i + vec3(spec * i);
}

vec4 scene(vec3 ro, vec3 rd) {
    vec3 p = vec3(0.0);
    const float r = 1.0;
    float t;
    bool hit = intersectSphere(ro - p, rd, r, t);

    vec4 c = vec4(0.0);
    if (hit) {
        vec3 pos = ro + rd * t;
        for (int i = 0; i < furLayers; i++) {
            vec4 sampleCol;
            vec2 uv;
            sampleCol.a = furDensity(pos, uv);
            if (sampleCol.a > 0.0) {
                sampleCol.rgb = furShade(pos, uv, ro, sampleCol.a);
                sampleCol.rgb *= sampleCol.a;
                c = c + sampleCol * (1.0 - c.a);
                if (c.a > 0.95) break;
            }
            pos += rd * rayStep;
        }
    }
    return c;
}

void main() {
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    vec2 uv = fragCoord / iResolution;
    uv = uv * 2.0 - 1.0;
    uv.x *= iResolution.x / iResolution.y;

    vec3 ro = vec3(0.0, 0.0, 2.5);
    vec3 rd = normalize(vec3(uv, -2.0));

    vec2 mouse = iMouse.xy / iResolution;
    float roty = 0.0;
    float rotx = 0.0;
    if (iMouse.z > 0.0) {
        rotx = (mouse.y - 0.5) * 3.0;
        roty = -(mouse.x - 0.5) * 6.0;
    } else {
        roty = sin(iTime * 1.5);
    }

    ro = rotateX(ro, rotx);
    ro = rotateY(ro, roty);
    rd = rotateX(rd, rotx);
    rd = rotateY(rd, roty);

    outColor = scene(ro, rd);
}
