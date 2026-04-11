#pragma once

#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>
#include <android/native_window.h>
#include <android/asset_manager.h>
#include <vector>
#include <chrono>

#include "vulkan_utils.h"

static constexpr uint32_t MAX_FRAMES_IN_FLIGHT = 2;
static constexpr int SHADER_COUNT = 21;
static constexpr int MAX_TEXTURES = 5;
static constexpr int MAX_TEX_BINDINGS = 3;

struct PushConstants {
    float iResolutionX;
    float iResolutionY;
    float iTime;
    int32_t preRotate; // 0=identity, 1=rotate90, 2=rotate180, 3=rotate270
    float iMouseX;
    float iMouseY;
    float iMouseZ;
    float iMouseW;
    int32_t mode; // 0=normal, 1=parallax
    int32_t iFrame;
};

struct TextureResource {
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView imageView = VK_NULL_HANDLE;
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
    void toggleMode();
    void toggleHalfRes();
    void onTouch(float x, float y, int action);

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
    bool createTextures();
    bool loadTexture(const char* assetPath, int index);
    bool loadTexture3D(const char* assetPath, int index, uint32_t w, uint32_t h, uint32_t d);
    bool createHistoryBuffer();
    bool createOffscreenRenderPass();
    void cleanupHistoryBuffer();
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

    // Textures: 0=stars, 1=rgba_noise_medium, 2=rgba_noise_small, 3=gray_noise_small
    TextureResource mTextures[MAX_TEXTURES] = {};
    VkSampler mTextureSampler = VK_NULL_HANDLE;
    VkDescriptorSetLayout mDescriptorSetLayout = VK_NULL_HANDLE;
    VkDescriptorPool mDescriptorPool = VK_NULL_HANDLE;
    // Descriptor sets: 0=starship, 1=clouds/plasma, 2=history buffer, 3=grid(organic2)
    VkDescriptorSet mDescriptorSets[4] = {};

    // History buffer for temporal reprojection / FXAA intermediate
    VkImage mHistoryImage = VK_NULL_HANDLE;
    VkDeviceMemory mHistoryMemory = VK_NULL_HANDLE;
    VkImageView mHistoryView = VK_NULL_HANDLE;
    VkRenderPass mOffscreenRenderPass = VK_NULL_HANDLE;
    VkFramebuffer mHistoryFramebuffer = VK_NULL_HANDLE;
    VkPipeline mFxaaPipeline = VK_NULL_HANDLE;
    int32_t mFrameCount = 0;

    VkCommandPool mCommandPool = VK_NULL_HANDLE;
    std::vector<VkCommandBuffer> mCommandBuffers;

    std::vector<VkSemaphore> mImageAvailableSemaphores;
    std::vector<VkSemaphore> mRenderFinishedSemaphores;
    std::vector<VkFence> mInFlightFences;
    uint32_t mCurrentFrame = 0;

    std::chrono::high_resolution_clock::time_point mStartTime;

    // Mouse state (Shadertoy convention, relative/trackpad style)
    float mMouseX = 0.0f, mMouseY = 0.0f; // virtual mouse pos (pixel coords)
    float mMouseZ = 0.0f, mMouseW = 0.0f; // click pos (positive z=pressed, negative z=released)
    bool mMousePressed = false;
    int mMode = 0; // 0=normal, 1=shader feature
    bool mHalfRes = false;
    bool mMouseInitialized = false;
    float mTouchStartX = 0.0f, mTouchStartY = 0.0f; // touch-down position
    float mVirtualStartX = 0.0f, mVirtualStartY = 0.0f; // virtual pos at touch-down

    bool mNeedsResize = false;
    bool mInitialized = false;
    bool mPaused = false;
};
