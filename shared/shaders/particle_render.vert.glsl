#version 450

layout(location = 0) in vec4 inPosition;  // xyz + size(w)
layout(location = 1) in vec4 inVelocity;  // xyz + lifetime(w)
layout(location = 2) in vec4 inColor;     // rgba

layout(location = 0) out vec4 fragColor;

layout(push_constant) uniform PushConstants {
    mat4 viewProjection;
    float sparkBrightness;
    float screenHeight;
};

void main() {
    // Skip dead particles
    if (inVelocity.w <= 0.0) {
        gl_Position = vec4(0.0, 0.0, -2.0, 1.0); // behind camera
        gl_PointSize = 0.0;
        fragColor = vec4(0.0);
        return;
    }

    vec4 clipPos = viewProjection * vec4(inPosition.xyz, 1.0);
    gl_Position = clipPos;

    // Point size attenuated by distance
    float dist = max(clipPos.w, 0.1);
    gl_PointSize = inPosition.w * (screenHeight * 0.1) / dist;
    gl_PointSize = clamp(gl_PointSize, 1.0, 64.0);

    fragColor = vec4(inColor.rgb * sparkBrightness, inColor.a);
}
