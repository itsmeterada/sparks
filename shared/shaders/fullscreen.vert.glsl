#version 450

layout(location = 0) out vec2 fragCoord;

// Fullscreen triangle - no vertex buffer needed
// Vertices: (-1,-1), (3,-1), (-1,3) cover the entire screen
void main() {
    vec2 pos = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);
    // Convert to pixel coordinates (will be scaled by iResolution in fragment shader)
    fragCoord = pos;
}
