#pragma once

#include <vulkan/vulkan.h>
#include <android/asset_manager.h>
#include <vector>
#include <array>
#include <cmath>
#include <cstring>

// Simple 4x4 matrix (column-major, matching Vulkan/GLSL conventions)
struct Mat4 {
    float m[16];

    Mat4() { memset(m, 0, sizeof(m)); }

    static Mat4 identity() {
        Mat4 result;
        result.m[0] = 1.0f;
        result.m[5] = 1.0f;
        result.m[10] = 1.0f;
        result.m[15] = 1.0f;
        return result;
    }

    float& operator()(int row, int col) { return m[col * 4 + row]; }
    const float& operator()(int row, int col) const { return m[col * 4 + row]; }
};

struct Vec3 {
    float x, y, z;
    Vec3() : x(0), y(0), z(0) {}
    Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}
};

Vec3 vec3Sub(const Vec3& a, const Vec3& b);
Vec3 vec3Cross(const Vec3& a, const Vec3& b);
Vec3 vec3Normalize(const Vec3& v);
float vec3Dot(const Vec3& a, const Vec3& b);

Mat4 mat4Multiply(const Mat4& a, const Mat4& b);
Mat4 mat4LookAt(const Vec3& eye, const Vec3& center, const Vec3& up);
Mat4 mat4Perspective(float fovRadians, float aspect, float nearZ, float farZ);

struct BufferAndMemory {
    VkBuffer buffer;
    VkDeviceMemory memory;
};

std::vector<uint32_t> loadShaderFromAsset(AAssetManager* assetManager, const char* filename);
VkShaderModule createShaderModule(VkDevice device, const std::vector<uint32_t>& code);
uint32_t findMemoryType(VkPhysicalDevice physicalDevice, uint32_t typeFilter, VkMemoryPropertyFlags properties);
BufferAndMemory createBuffer(VkDevice device, VkPhysicalDevice physicalDevice,
                             VkDeviceSize size, VkBufferUsageFlags usage,
                             VkMemoryPropertyFlags memoryProperties);
