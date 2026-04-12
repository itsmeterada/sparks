#version 450

// Chrome Metaball - Ported from Shadertoy
// https://www.shadertoy.com/view/7dtSDf
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

// ============================================================
// Common
// ============================================================

#define S(x, y, z) smoothstep(x, y, z)
#define animTime (mod(iTime, 11.))
#define A(v1,v2,t1,t2) mix(v1,v2,S(t1,t2,animTime))

float invLerp(float a, float b, float x) {
    x = clamp(x, a, b);
    return (x - a) / (b - a);
}

const float PI = 3.14159;
const float TAU = PI * 2.0;
const float DEG2RAD = PI / 180.;

float saturate_f(float x) { return clamp(x, 0.0, 1.0); }
vec3 saturate_v3(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }
vec4 saturate_v4(vec4 x) { return clamp(x, vec4(0.0), vec4(1.0)); }

mat2 rot2D(float angle) {
    float ca = cos(angle), sa = sin(angle);
    return mat2(ca, -sa, sa, ca);
}

mat3 lookAtMatrix(vec3 lookAtDirection) {
    vec3 ww = normalize(lookAtDirection);
    vec3 uu = cross(ww, vec3(0.0, 1.0, 0.0));
    vec3 vv = cross(uu, ww);
    return mat3(uu, vv, -ww);
}

vec4 linearTosRGB(vec4 linearRGB) {
    bvec4 cutoff = lessThan(linearRGB, vec4(0.0031308));
    vec4 higher = vec4(1.055)*pow(linearRGB, vec4(1.0/2.4)) - vec4(0.055);
    vec4 lower = linearRGB * vec4(12.92);
    return mix(higher, lower, cutoff);
}

vec4 ACESFilm(vec4 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return saturate_v4((x*(a*x+b))/(x*(c*x+d)+e));
}

float smin(float a, float b, float k) {
    float h = clamp(0.5+0.5*(b-a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0-h);
}

struct Hit {
    int id;
    float d;
};

struct TraceResult {
    int id;
    float d;
    vec3 ro;
    vec3 rd;
};

Hit hmin(Hit a, Hit b) { if (a.d < b.d) return a; return b; }
Hit hsmin(Hit a, Hit b, float k) {
    Hit h = hmin(a, b);
    h.d = smin(a.d, b.d, k);
    return h;
}

struct Light {
    vec3 direction;
    vec3 ambient;
    vec3 color;
};

struct Surface {
    int materialId;
    float dist;
    vec3 p;
    vec3 n;
    float ao;
    vec3 rd;
};

struct Material {
    vec3 albedo;
    float metallic;
    float roughness;
    vec3 emissive;
    float ao;
};

float sdSphere(vec3 p, float r) {
    return length(p) - r;
}

struct Camera {
    vec3 position;
    vec3 direction;
};

Camera createOrbitCamera(vec2 uv, vec2 mouse, vec2 resolution, float fov, vec3 target, float height, float distanceToTarget) {
    vec2 r = mouse;
    float halfFov = fov * 0.5;
    float zoom = cos(halfFov) / sin(halfFov);
    vec3 position = target + vec3(0, height, 0) + vec3(sin(r.x), 0.0, cos(r.x)) * distanceToTarget;
    vec3 direction = normalize(vec3(uv, -zoom));
    direction.yz = rot2D(-r.y) * direction.yz;
    direction = lookAtMatrix(target - position) * direction;
    return Camera(position, direction);
}

// PBR
vec3 F_Schlick_full(float HoV, vec3 f0, vec3 f90) {
    return f0 + (f90 - f0) * pow(1.0 - HoV, 5.0);
}
vec3 F_Schlick(float HoV, vec3 f0) {
    return F_Schlick_full(HoV, f0, vec3(1.0));
}
float D_GGX(float NoH, float a) {
    float a2 = a * a;
    float f = (NoH * a2 - NoH) * NoH + 1.0;
    return a2 / (PI * f * f);
}
float V_SmithGGXCorrelated(float NoV, float NoL, float a) {
    float a2 = a * a;
    float GGL = NoL * sqrt(NoV*NoV * (1.0 - a2) + a2);
    float GGV = NoV * sqrt(NoL*NoL * (1.0 - a2) + a2);
    return 0.5 / (GGL + GGV);
}

vec3 BRDF(Light l, Surface surf, Material mat) {
    vec3 V = -surf.rd;
    vec3 N = surf.n;
    vec3 L = l.direction;
    vec3 H = normalize(V + L);
    float NoV = max(dot(N, V), 0.0);
    float NoL = max(dot(N, L), 0.0);
    float NoH = max(dot(N, H), 0.0);
    float HoV = max(dot(H, V), 0.0);
    vec3 albedo = mat.albedo;
    float roughness = mat.roughness;
    float a = roughness * roughness;
    float metallic = mat.metallic;
    vec3 dielectricSpecular = vec3(0.04);
    vec3 black = vec3(0);
    vec3 F0 = mix(dielectricSpecular, albedo, metallic);
    vec3 F = F_Schlick(HoV, F0);
    float D = D_GGX(NoH, a);
    float Vis = V_SmithGGXCorrelated(NoV, NoL, a);
    vec3 specular = F * (Vis * D);
    vec3 kD = vec3(1.0) - F;
    vec3 c_diff = mix(albedo * (1.0 - dielectricSpecular), black, metallic);
    vec3 diffuse = kD * (c_diff / PI);
    vec3 fakeGI = l.ambient * mat.albedo;
    vec3 emissive = mat.emissive;
    vec3 directLight = l.color * NoL * (diffuse + specular);
    return fakeGI + emissive + directLight;
}

// ============================================================
// Scene
// ============================================================

#define NUM_REFLECTIONS 5
const float SURF_HIT = 0.01;
const float farPlane = 20.0;
const int maxSteps = 128;

Hit ground(vec3 p) {
    return Hit(0, -(length(p-vec3(0, 198.8, 0)) - 200.));
}

Hit metaBall(vec3 p) {
    vec3 q = p;
    q.y += A(cos(animTime * PI) * 1.0 + 1.7, 0.0, 0.0, 4.0);
    if (animTime > 10.0) {
        float t = animTime - 10.0;
        q.y += -2.5 * t + 0.5 * 10.0 * t*t;
    }
    q.xz *= rot2D(q.y);
    vec3 scale = A(vec3(1), vec3(0.5, 1.0, 0.5), 10., 11.);
    q *= scale;
    float r = 1.0;
    r = A(r, 0.2, 10., 10.5);
    float amp = 0.1;
    amp = A(amp, sin(animTime * 30.0) * .05 + 0.1, 8.0, 10.);
    amp = A(amp, 1., 10., 10.5);
    r += amp * sin(q.x * 8.0 + animTime * 5.0) * sin(q.y * 8.0) * sin(q.z * 8.0);
    float sphere = sdSphere(q, r);
    float definition = A(0.7, 0.3, 10., 10.5);
    sphere *= definition;
    return Hit(1, sphere);
}

Hit ballGround(vec3 p) {
    float blend = A(0.5, 0.0, 0.0, 8.0);
    blend = A(blend, 0.5, 10.0, 11.0);
    return hsmin(metaBall(p), ground(p), blend);
}

Hit map(vec3 p) {
    return ballGround(p);
}

vec3 mapNormal(vec3 p, float surfHit) {
    vec2 e = vec2(0.01, 0.0);
    float d = map(p).d;
    return normalize(vec3(
        d - map(p - e.xyy).d,
        d - map(p - e.yxy).d,
        d - map(p - e.yyx).d
    ));
}

TraceResult trace(vec3 ro, vec3 rd, float maxDistance, int mSteps) {
    float d = 0.0;
    float closestD = maxDistance;
    Hit closest = Hit(-1, maxDistance);
    for (int i=0; i < mSteps && d < maxDistance; i++) {
        vec3 p = ro + rd * d;
        Hit h = map(p);
        if (h.d < closest.d) {
            closest = h;
            closestD = d;
        }
        if (h.d <= SURF_HIT) return TraceResult(closest.id, d, ro, rd);
        d += h.d;
    }
    if (d >= maxDistance) return TraceResult(-1, maxDistance, ro, rd);
    return TraceResult(-2, closestD, ro, rd);
}

Surface getSurf(TraceResult tr) {
    vec3 p = tr.ro + tr.rd * tr.d;
    vec3 n = mapNormal(p, SURF_HIT);
    return Surface(tr.id, tr.d, p, n, 0.0, tr.rd);
}

TraceResult traceReflection(Surface s, float maxDistance, int mSteps) {
    vec3 ro = s.p + s.n * SURF_HIT * 2.0;
    vec3 rd = reflect(s.rd, s.n);
    float d = SURF_HIT * 2.0;
    for (int i=0; i < mSteps && d < maxDistance; i++) {
        vec3 p = ro + rd * d;
        Hit h = map(p);
        if (h.d < SURF_HIT) return TraceResult(h.id, d, ro, rd);
        d += h.d;
    }
    return TraceResult(-1, maxDistance, ro, rd);
}

Material matFromSurface(Surface s) {
    Material m;
    m.albedo = vec3(0.0);
    m.emissive = vec3(0.0);
    m.roughness = 1.0;
    m.metallic = 0.0;
    m.ao = s.ao;
    if (s.materialId == -1) {
        m.albedo = vec3(0.01);
        m.roughness = 0.85;
    } else if (s.materialId == 0) {
        m.albedo = vec3(0.01);
        m.roughness = 0.0;
    } else if (s.materialId == 1) {
        m.albedo = vec3(0.1);
        m.roughness = 0.1;
        m.metallic = 1.0;
    } else {
        m.emissive = vec3(1, 0, 1);
    }
    return m;
}

vec3 calculateLights(Surface s, Material m) {
    Light l0;
    l0.direction = normalize(vec3(1, 1, 0));
    l0.ambient = vec3(0.01);
    l0.color = vec3(3.0);
    Light l1;
    l1.direction = normalize(vec3(-1, 1, 0));
    l1.ambient = vec3(0.01);
    l1.color = vec3(3.0);
    return max(BRDF(l0, s, m), vec3(0)) + max(BRDF(l1, s, m), vec3(0));
}

struct LightingResult {
    Material mat;
    vec3 color;
};

LightingResult surfaceLighting(inout Surface s) {
    if (s.materialId == -1) {
        s.p.y += 1.1;
        vec3 n = normalize(s.p);
        Surface floorS = Surface(0, s.dist, s.p, vec3(0,1,0), s.ao, s.rd);
        Material floorM = matFromSurface(s);
        vec3 floorColor = calculateLights(floorS, floorM);
        float floorBlend = S(-.2, 1.2, n.y);
        Material m = matFromSurface(s);
        s.n = n;
        m.roughness = 1.0;
        vec3 color = mix(floorColor, vec3(0), floorBlend);
        return LightingResult(m, color);
    } else if (s.materialId == 0) {
        Material m = matFromSurface(s);
        vec3 floorColor = calculateLights(s, m);
        return LightingResult(m, floorColor);
    } else if (s.materialId == 1) {
        Surface floorS = Surface(0, s.dist, s.p, s.n, s.ao, s.rd);
        Material floorM = matFromSurface(floorS);
        vec3 floorColor = calculateLights(floorS, floorM);
        Material m = matFromSurface(s);
        vec3 ballColor = calculateLights(s, m);
        float blend = S(-1.1, -0.9, s.p.y);
        vec3 color = mix(floorColor, ballColor, blend);
        m.metallic = mix(floorM.metallic, m.metallic, blend);
        m.roughness = mix(floorM.roughness, m.roughness, blend);
        return LightingResult(m, color);
    } else {
        Material m = matFromSurface(s);
        vec3 color = calculateLights(s, m);
        return LightingResult(m, color);
    }
}

vec3 lighting(Surface s) {
    LightingResult current = surfaceLighting(s);
    vec3 color = current.color;
    float extinction = 1.0;
    for (int i = 0; i < NUM_REFLECTIONS; i++) {
        TraceResult rh = traceReflection(s, farPlane, maxSteps);
        s = getSurf(rh);
        float refAmount = (1.0 - current.mat.roughness);
        extinction *= refAmount;
        current = surfaceLighting(s);
        color += extinction * saturate_v3(current.color) * 0.6;
    }
    return color;
}

void main()
{
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;
    vec2 uv = fragCoord / iResolution.xy;
    vec2 screen = uv * 2.0 - 1.0;
    screen.x *= iResolution.x / iResolution.y;

    float xCam = A(0.0, -0.2, 0.0, 3.0);
    xCam = A(xCam, -0.65, 0.0, 9.0);
    xCam = A(xCam, -0.95, 8.5, 10.0);
    xCam = A(xCam, -1.0, 10.0, 11.0);

    float yCam = A(-0.25, -0.08, 0.3, 1.0);
    yCam = A(yCam, -0.3, 0.5, 2.5);
    yCam = A(yCam, -0.08, 0.5, 3.0);
    yCam = A(yCam, -0.06, 4.0, 10.0);
    yCam = A(yCam, 0.15, 10.0, 10.5);
    yCam = A(yCam, -0.25, 10.0, 11.0);

    float camDist = A(1.5, 5.5, 0.0, 2.0);
    camDist = A(camDist, 3.5, 0.0, 3.0);
    camDist = A(camDist, 4.0, 3.0, 5.0);
    camDist = A(camDist, 4.5, 4.0, 7.0);
    camDist = A(camDist, 3.5, 7.0, 10.0);
    camDist = A(camDist, 2.0, 9.5, 10.5);
    camDist = A(camDist, 2.5, 10.0, 11.);

    Camera cam = createOrbitCamera(
        screen,
        vec2(xCam, yCam) * PI,
        iResolution.xy,
        60.0 * DEG2RAD,
        vec3(0, 0.5, 0),
        0.0,
        camDist
    );

    vec3 ro = cam.position;
    vec3 rd = cam.direction;

    TraceResult tr = trace(ro, rd, farPlane, maxSteps);
    Surface s = getSurf(tr);

    vec4 col = vec4(lighting(s), 1.0);
    col = ACESFilm(col);
    col = linearTosRGB(col);
    outColor = col;
}
