#include "vulkan_utils.h"
#include <android/log.h>
#include <stdexcept>

#define LOG_TAG "VulkanUtils"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

Vec3 vec3Sub(const Vec3& a, const Vec3& b) {
    return Vec3(a.x - b.x, a.y - b.y, a.z - b.z);
}

Vec3 vec3Cross(const Vec3& a, const Vec3& b) {
    return Vec3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    );
}

Vec3 vec3Normalize(const Vec3& v) {
    float len = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
    if (len < 1e-8f) return Vec3(0, 0, 0);
    float inv = 1.0f / len;
    return Vec3(v.x * inv, v.y * inv, v.z * inv);
}

float vec3Dot(const Vec3& a, const Vec3& b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

Mat4 mat4Multiply(const Mat4& a, const Mat4& b) {
    Mat4 result;
    for (int col = 0; col < 4; col++) {
        for (int row = 0; row < 4; row++) {
            float sum = 0.0f;
            for (int k = 0; k < 4; k++) {
                sum += a.m[k * 4 + row] * b.m[col * 4 + k];
            }
            result.m[col * 4 + row] = sum;
        }
    }
    return result;
}

Mat4 mat4LookAt(const Vec3& eye, const Vec3& center, const Vec3& up) {
    Vec3 f = vec3Normalize(vec3Sub(center, eye));
    Vec3 s = vec3Normalize(vec3Cross(f, up));
    Vec3 u = vec3Cross(s, f);

    Mat4 result = Mat4::identity();
    result(0, 0) = s.x;
    result(0, 1) = s.y;
    result(0, 2) = s.z;
    result(1, 0) = u.x;
    result(1, 1) = u.y;
    result(1, 2) = u.z;
    result(2, 0) = -f.x;
    result(2, 1) = -f.y;
    result(2, 2) = -f.z;
    result(0, 3) = -vec3Dot(s, eye);
    result(1, 3) = -vec3Dot(u, eye);
    result(2, 3) = vec3Dot(f, eye);

    return result;
}

Mat4 mat4Perspective(float fovRadians, float aspect, float nearZ, float farZ) {
    float tanHalfFov = tanf(fovRadians * 0.5f);

    Mat4 result;
    result(0, 0) = 1.0f / (aspect * tanHalfFov);
    result(1, 1) = -1.0f / tanHalfFov;  // Vulkan Y is flipped
    result(2, 2) = farZ / (nearZ - farZ);
    result(2, 3) = (nearZ * farZ) / (nearZ - farZ);
    result(3, 2) = -1.0f;

    return result;
}

std::vector<uint32_t> loadShaderFromAsset(AAssetManager* assetManager, const char* filename) {
    if (assetManager == nullptr) {
        LOGE("AssetManager is null, cannot load shader: %s", filename);
        return {};
    }

    AAsset* asset = AAssetManager_open(assetManager, filename, AASSET_MODE_BUFFER);
    if (asset == nullptr) {
        LOGE("Failed to open shader asset: %s", filename);
        return {};
    }

    size_t size = AAsset_getLength(asset);
    if (size == 0 || (size % 4) != 0) {
        LOGE("Invalid SPIR-V file size for %s: %zu", filename, size);
        AAsset_close(asset);
        return {};
    }

    std::vector<uint32_t> code(size / 4);
    AAsset_read(asset, code.data(), size);
    AAsset_close(asset);

    LOGI("Loaded shader %s (%zu bytes)", filename, size);
    return code;
}

VkShaderModule createShaderModule(VkDevice device, const std::vector<uint32_t>& code) {
    if (code.empty()) {
        LOGE("Cannot create shader module from empty code");
        return VK_NULL_HANDLE;
    }

    VkShaderModuleCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = code.size() * sizeof(uint32_t);
    createInfo.pCode = code.data();

    VkShaderModule shaderModule;
    VkResult result = vkCreateShaderModule(device, &createInfo, nullptr, &shaderModule);
    if (result != VK_SUCCESS) {
        LOGE("Failed to create shader module: %d", result);
        return VK_NULL_HANDLE;
    }

    return shaderModule;
}

uint32_t findMemoryType(VkPhysicalDevice physicalDevice, uint32_t typeFilter,
                        VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties);

    for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) &&
            (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }

    LOGE("Failed to find suitable memory type!");
    return 0;
}

BufferAndMemory createBuffer(VkDevice device, VkPhysicalDevice physicalDevice,
                             VkDeviceSize size, VkBufferUsageFlags usage,
                             VkMemoryPropertyFlags memoryProperties) {
    BufferAndMemory result{};

    VkBufferCreateInfo bufferInfo{};
    bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferInfo.size = size;
    bufferInfo.usage = usage;
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    VkResult vkResult = vkCreateBuffer(device, &bufferInfo, nullptr, &result.buffer);
    if (vkResult != VK_SUCCESS) {
        LOGE("Failed to create buffer: %d", vkResult);
        return result;
    }

    VkMemoryRequirements memRequirements;
    vkGetBufferMemoryRequirements(device, result.buffer, &memRequirements);

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memRequirements.size;
    allocInfo.memoryTypeIndex = findMemoryType(physicalDevice, memRequirements.memoryTypeBits, memoryProperties);

    vkResult = vkAllocateMemory(device, &allocInfo, nullptr, &result.memory);
    if (vkResult != VK_SUCCESS) {
        LOGE("Failed to allocate buffer memory: %d", vkResult);
        vkDestroyBuffer(device, result.buffer, nullptr);
        result.buffer = VK_NULL_HANDLE;
        return result;
    }

    vkBindBufferMemory(device, result.buffer, result.memory, 0);
    return result;
}
