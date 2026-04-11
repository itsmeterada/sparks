#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float2 iResolution;
    float iTime;
    float _pad;
    float4 iMouse;
    int mode;
    int iFrame;
};

#endif
