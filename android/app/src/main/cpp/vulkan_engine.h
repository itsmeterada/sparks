#pragma once

#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>
#include <android/native_window.h>
#include <android/asset_manager.h>
#include <vector>
#include <chrono>

#include "vulkan_utils.h"

static constexpr uint32_t MAX_FRAMES_IN_FLIGHT = 2;
static constexpr int SHADER_COUNT = 3;

struct PushConstants {
    float iResolutionX;
    float iResolutionY;
    float iTime;
    int32_t preRotate; // 0=identity, 1=rotate90, 2=rotate180, 3=rotate270
};

class VulkanEngine {
public:
    VulkanEngine() = default;
    ~VulkanEngine();

    bool init(ANativeWindow* window, AAssetManager* assetManager);
    bool reinitSurface(ANativeWindow* window);
    void pause();
    void cleanupSurface();
    void render();
    void onResize(uint32_t width, uint32_t height);
    void toggleShader();

    bool isInitialized() const { return mInitialized; }

private:
    bool createInstance();
    bool createSurface();
    bool pickPhysicalDevice();
    bool createLogicalDevice();
    bool createSwapchain();
    bool createRenderPass();
    bool createFramebuffers();
    bool createCommandPool();
    bool createCommandBuffers();
    bool createSyncObjects();
    bool createGraphicsPipeline();
    bool createTexture();
    void cleanupSwapchain();
    void recreateSwapchain();

    ANativeWindow* mWindow = nullptr;
    AAssetManager* mAssetManager = nullptr;

    VkInstance mInstance = VK_NULL_HANDLE;
    VkSurfaceKHR mSurface = VK_NULL_HANDLE;
    VkPhysicalDevice mPhysicalDevice = VK_NULL_HANDLE;
    VkDevice mDevice = VK_NULL_HANDLE;
    VkQueue mQueue = VK_NULL_HANDLE;
    uint32_t mQueueFamilyIndex = 0;

    VkSwapchainKHR mSwapchain = VK_NULL_HANDLE;
    VkFormat mSwapchainFormat = VK_FORMAT_R8G8B8A8_UNORM;
    VkExtent2D mSwapchainExtent{};
    VkSurfaceTransformFlagBitsKHR mCurrentTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
    std::vector<VkImage> mSwapchainImages;
    std::vector<VkImageView> mSwapchainImageViews;

    VkRenderPass mRenderPass = VK_NULL_HANDLE;
    std::vector<VkFramebuffer> mFramebuffers;
    VkPipelineLayout mPipelineLayout = VK_NULL_HANDLE;
    VkPipeline mPipelines[SHADER_COUNT] = {};
    int mCurrentShader = 0;

    // Texture for starship shader
    VkImage mTextureImage = VK_NULL_HANDLE;
    VkDeviceMemory mTextureMemory = VK_NULL_HANDLE;
    VkImageView mTextureImageView = VK_NULL_HANDLE;
    VkSampler mTextureSampler = VK_NULL_HANDLE;
    VkDescriptorSetLayout mDescriptorSetLayout = VK_NULL_HANDLE;
    VkDescriptorPool mDescriptorPool = VK_NULL_HANDLE;
    VkDescriptorSet mDescriptorSet = VK_NULL_HANDLE;

    VkCommandPool mCommandPool = VK_NULL_HANDLE;
    std::vector<VkCommandBuffer> mCommandBuffers;

    std::vector<VkSemaphore> mImageAvailableSemaphores;
    std::vector<VkSemaphore> mRenderFinishedSemaphores;
    std::vector<VkFence> mInFlightFences;
    uint32_t mCurrentFrame = 0;

    // Timing
    std::chrono::high_resolution_clock::time_point mStartTime;

    bool mNeedsResize = false;
    bool mInitialized = false;
    bool mPaused = false;
};
