#pragma once

#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>
#include <android/native_window.h>
#include <android/asset_manager.h>
#include <vector>
#include <chrono>

#include "vulkan_utils.h"

static constexpr uint32_t MAX_FRAMES_IN_FLIGHT = 2;

struct PushConstants {
    float iResolutionX;
    float iResolutionY;
    float iTime;
};

class VulkanEngine {
public:
    VulkanEngine() = default;
    ~VulkanEngine();

    bool init(ANativeWindow* window, AAssetManager* assetManager);
    void render();
    void onResize(uint32_t width, uint32_t height);

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
    std::vector<VkImage> mSwapchainImages;
    std::vector<VkImageView> mSwapchainImageViews;

    VkRenderPass mRenderPass = VK_NULL_HANDLE;
    std::vector<VkFramebuffer> mFramebuffers;
    VkPipelineLayout mPipelineLayout = VK_NULL_HANDLE;
    VkPipeline mGraphicsPipeline = VK_NULL_HANDLE;

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
};
