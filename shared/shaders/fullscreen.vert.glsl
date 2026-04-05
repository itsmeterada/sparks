#version 450

layout(location = 0) out vec2 vUV;

layout(push_constant) uniform PushConstants {
    vec2 iResolution;
    float iTime;
    int preRotate; // 0=identity, 1=rotate90, 2=rotate180, 3=rotate270
    vec4 iMouse;
    int mode;
};

void main() {
    vec2 pos = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);

    // Rotate UV to compensate for Vulkan preTransform.
    // The framebuffer may be rotated relative to the display;
    // we remap UVs so the fragment shader sees display-oriented coordinates.
    vec2 uv = pos;
    if (preRotate == 1) {        // ROTATE_90
        uv = vec2(pos.y, 1.0 - pos.x);
    } else if (preRotate == 2) { // ROTATE_180
        uv = vec2(1.0 - pos.x, 1.0 - pos.y);
    } else if (preRotate == 3) { // ROTATE_270
        uv = vec2(1.0 - pos.y, pos.x);
    }

    vUV = uv;
}
