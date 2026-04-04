#version 450

layout(location = 0) in vec4 fragColor;
layout(location = 0) out vec4 outColor;

void main() {
    // Soft circle using point coordinate
    vec2 coord = gl_PointCoord - vec2(0.5);
    float d = length(coord) * 2.0;

    // Radial falloff for soft glow
    float alpha = smoothstep(1.0, 0.3, d);

    // Discard fully transparent fragments
    if (alpha * fragColor.a < 0.001) {
        discard;
    }

    outColor = vec4(fragColor.rgb, fragColor.a * alpha);
}
