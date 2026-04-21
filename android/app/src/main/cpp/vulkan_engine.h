#pragma once

#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>
#include <android/native_window.h>
#include <android/asset_manager.h>
#include <vector>
#include <chrono>

#include "vulkan_utils.h"
#include "benchmark_engine.h"

static constexpr uint32_t MAX_FRAMES_IN_FLIGHT = 2;
static constexpr int SHADER_COUNT = 28;       // mPipelines slots (index 26 = fluid placeholder, kept VK_NULL_HANDLE)
static constexpr int MAX_TEXTURES = 6;
static constexpr int MAX_TEX_BINDINGS = 3;

// Multi-pass (fluid) infrastructure
static constexpr int FLUID_PASS_COUNT = 5; // buffer_a, b, c, d, image
static constexpr int FLUID_TEX_BINDINGS = 4; // iChannel0-3
static constexpr int FLUID_SHADER_INDEX = 26;
static constexpr int TOTAL_SHADER_COUNT = 28;

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

// Offscreen render target supporting ping-pong and mipmaps.
// When pingPong=true, image[0]/image[1] alternate as src/dst each frame.
// When pingPong=false, only image[0] is used.
// Format is typically RGBA16F for fluid simulation buffers.
struct OffscreenTarget {
    VkImage image[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE};
    VkDeviceMemory memory[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE};
    VkImageView viewAll[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE};  // all mips, for sampling
    VkImageView viewMip0[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE}; // mip 0 only, for framebuffer
    VkFramebuffer framebuffer[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE};
    uint32_t width = 0, height = 0;
    uint32_t mipLevels = 1;
    VkFormat format = VK_FORMAT_R16G16B16A16_SFLOAT;
    bool pingPong = false;
    int srcIdx = 0; // index holding current content; dst = 1 - srcIdx when pingPong
};

struct FluidResources {
    OffscreenTarget velocity;     // pingPong, mipmap
    OffscreenTarget pressure;     // pingPong, mipmap
    OffscreenTarget turbulence;   // single, mipmap
    OffscreenTarget confinement;  // single, no mipmap
    VkRenderPass renderPass = VK_NULL_HANDLE;
    VkDescriptorSetLayout descLayout = VK_NULL_HANDLE;
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    VkDescriptorPool descPool = VK_NULL_HANDLE;
    VkDescriptorSet descSets[FLUID_PASS_COUNT * MAX_FRAMES_IN_FLIGHT] = {};
    VkPipeline bufferPipelines[4] = {}; // buffer_a, b, c, d
    VkPipeline imagePipeline = VK_NULL_HANDLE;
    VkSampler sampler = VK_NULL_HANDLE;
    bool initialized = false;
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
    void prevShader();
    void toggleMode();
    void toggleHalfRes();
    void onTouch(float x, float y, int action);

    bool isInitialized() const { return mInitialized; }

    // Benchmark control (called from UI thread)
    void startBenchmark(bench::Mode mode);
    void abortBenchmark();
    bool isBenchmarkRunning() const { return mBenchmark.isRunning(); }
    bool isBenchmarkDone() const { return mBenchmark.isDone(); }
    std::string getBenchmarkStatus() const { return mBenchmark.statusText(); }
    std::string getBenchmarkReportJson(const std::string& osVersion,
                                       const std::string& model,
                                       const std::string& thermalStart,
                                       const std::string& thermalEnd,
                                       const std::string& timestamp) const;
    void finishBenchmarkAndRestore();
    int currentShaderIndex() const { return mCurrentShader; }

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

    // Multi-pass (fluid) helpers
    bool createOffscreenTarget(OffscreenTarget& target, uint32_t w, uint32_t h,
                               VkFormat format, bool pingPong, bool withMipmaps,
                               VkRenderPass renderPassForFramebuffer);
    void destroyOffscreenTarget(OffscreenTarget& target);
    void recordGenerateMipmaps(VkCommandBuffer cmd, OffscreenTarget& target, int idx);

    bool createFluidResources();
    void cleanupFluidResources();
    void renderFluid(VkCommandBuffer cmd, uint32_t imageIndex, const PushConstants& pc);
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
    // Descriptor sets: 0=starship, 1=clouds/plasma, 2=history buffer, 3=grid(organic2), 4=furball(noise_small)
    VkDescriptorSet mDescriptorSets[5] = {};

    // Fluid multi-pass resources
    FluidResources mFluid;

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

    // Benchmark state
    mutable bench::BenchmarkEngine mBenchmark;
    int mPreBenchShader = 0;
    int mPreBenchMode = 0;
};
