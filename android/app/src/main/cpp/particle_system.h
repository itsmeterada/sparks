#pragma once

#include <vulkan/vulkan.h>
#include <android/asset_manager.h>
#include "vulkan_utils.h"

static constexpr uint32_t MAX_PARTICLES = 262144;

struct Particle {
    float position[4];  // xyz + size(w)
    float velocity[4];  // xyz + lifetime(w)
    float color[4];     // rgba
};

struct SimParams {
    float deltaTime;
    float emitterX, emitterY, emitterZ;
    uint32_t emitCount;
    uint32_t maxParticles;
    float gravity;
    float damping;
    float baseLifetime;
    float lifetimeVariance;
    float sparkBrightness;
    uint32_t frameNumber;
};

struct PushConstants {
    float viewProjection[16];
    float sparkBrightness;
    float screenHeight;
    float padding[2];
};

class ParticleSystem {
public:
    ParticleSystem() = default;
    ~ParticleSystem() = default;

    bool init(VkDevice device, VkPhysicalDevice physicalDevice,
              VkCommandPool commandPool, VkQueue queue,
              VkRenderPass renderPass, uint32_t width, uint32_t height,
              AAssetManager* assetManager);

    void cleanup(VkDevice device);

    void recordCompute(VkCommandBuffer cmd);
    void recordRender(VkCommandBuffer cmd, const Mat4& viewProj, float screenHeight);

    void updateSimParams(VkDevice device, float deltaTime, bool touching,
                         float emitterX, float emitterY, float emitterZ);

    void recreateGraphicsPipeline(VkDevice device, VkRenderPass renderPass,
                                  uint32_t width, uint32_t height,
                                  AAssetManager* assetManager);

private:
    bool createParticleBuffer(VkDevice device, VkPhysicalDevice physicalDevice,
                              VkCommandPool commandPool, VkQueue queue);
    bool createUniformBuffer(VkDevice device, VkPhysicalDevice physicalDevice);
    bool createDescriptors(VkDevice device);
    bool createComputePipeline(VkDevice device, AAssetManager* assetManager);
    bool createGraphicsPipeline(VkDevice device, VkRenderPass renderPass,
                                uint32_t width, uint32_t height,
                                AAssetManager* assetManager);

    VkDevice mDevice = VK_NULL_HANDLE;
    VkPhysicalDevice mPhysicalDevice = VK_NULL_HANDLE;

    // Particle storage buffer (used as both SSBO and vertex buffer)
    VkBuffer mParticleBuffer = VK_NULL_HANDLE;
    VkDeviceMemory mParticleMemory = VK_NULL_HANDLE;

    // SimParams uniform buffer
    VkBuffer mUniformBuffer = VK_NULL_HANDLE;
    VkDeviceMemory mUniformMemory = VK_NULL_HANDLE;
    void* mUniformMapped = nullptr;

    // Descriptors
    VkDescriptorSetLayout mDescriptorSetLayout = VK_NULL_HANDLE;
    VkDescriptorPool mDescriptorPool = VK_NULL_HANDLE;
    VkDescriptorSet mDescriptorSet = VK_NULL_HANDLE;

    // Compute pipeline
    VkPipelineLayout mComputePipelineLayout = VK_NULL_HANDLE;
    VkPipeline mComputePipeline = VK_NULL_HANDLE;

    // Graphics pipeline
    VkPipelineLayout mGraphicsPipelineLayout = VK_NULL_HANDLE;
    VkPipeline mGraphicsPipeline = VK_NULL_HANDLE;

    SimParams mSimParams{};
};
