#include "vulkan_engine.h"
#include <android/log.h>
#include <cstring>
#include <cmath>
#include <algorithm>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_NO_STDIO
#include "stb_image.h"

#define LOG_TAG "VulkanEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

VulkanEngine::~VulkanEngine() {
    if (!mInitialized) return;
    vkDeviceWaitIdle(mDevice);

    for (uint32_t i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
        vkDestroySemaphore(mDevice, mImageAvailableSemaphores[i], nullptr);
        vkDestroySemaphore(mDevice, mRenderFinishedSemaphores[i], nullptr);
        vkDestroyFence(mDevice, mInFlightFences[i], nullptr);
    }
    for (int i = 0; i < SHADER_COUNT; i++)
        if (mPipelines[i] != VK_NULL_HANDLE) vkDestroyPipeline(mDevice, mPipelines[i], nullptr);
    if (mPipelineLayout != VK_NULL_HANDLE) vkDestroyPipelineLayout(mDevice, mPipelineLayout, nullptr);
    if (mFxaaPipeline != VK_NULL_HANDLE) vkDestroyPipeline(mDevice, mFxaaPipeline, nullptr);
    cleanupFluidResources();
    cleanupHistoryBuffer();
    if (mOffscreenRenderPass != VK_NULL_HANDLE) vkDestroyRenderPass(mDevice, mOffscreenRenderPass, nullptr);
    if (mDescriptorPool != VK_NULL_HANDLE) vkDestroyDescriptorPool(mDevice, mDescriptorPool, nullptr);
    if (mDescriptorSetLayout != VK_NULL_HANDLE) vkDestroyDescriptorSetLayout(mDevice, mDescriptorSetLayout, nullptr);
    if (mTextureSampler != VK_NULL_HANDLE) vkDestroySampler(mDevice, mTextureSampler, nullptr);
    for (int i = 0; i < MAX_TEXTURES; i++) {
        if (mTextures[i].imageView != VK_NULL_HANDLE) vkDestroyImageView(mDevice, mTextures[i].imageView, nullptr);
        if (mTextures[i].image != VK_NULL_HANDLE) vkDestroyImage(mDevice, mTextures[i].image, nullptr);
        if (mTextures[i].memory != VK_NULL_HANDLE) vkFreeMemory(mDevice, mTextures[i].memory, nullptr);
    }
    cleanupSwapchain();
    if (mCommandPool != VK_NULL_HANDLE) vkDestroyCommandPool(mDevice, mCommandPool, nullptr);
    if (mRenderPass != VK_NULL_HANDLE) vkDestroyRenderPass(mDevice, mRenderPass, nullptr);
    if (mDevice != VK_NULL_HANDLE) vkDestroyDevice(mDevice, nullptr);
    if (mSurface != VK_NULL_HANDLE) vkDestroySurfaceKHR(mInstance, mSurface, nullptr);
    if (mInstance != VK_NULL_HANDLE) vkDestroyInstance(mInstance, nullptr);
    mInitialized = false;
}

bool VulkanEngine::init(ANativeWindow* window, AAssetManager* assetManager) {
    mWindow = window;
    mAssetManager = assetManager;
    if (!createInstance()) return false;
    if (!createSurface()) return false;
    if (!pickPhysicalDevice()) return false;
    if (!createLogicalDevice()) return false;
    if (!createSwapchain()) return false;
    if (!createRenderPass()) return false;
    if (!createFramebuffers()) return false;
    if (!createCommandPool()) return false;
    if (!createCommandBuffers()) return false;
    if (!createSyncObjects()) return false;
    if (!createTextures()) return false;
    if (!createOffscreenRenderPass()) return false;
    if (!createHistoryBuffer()) return false;
    if (!createGraphicsPipeline()) return false;
    if (!createFluidResources()) LOGI("Fluid resources creation failed (non-fatal, fluid shader will be skipped)");
    mStartTime = std::chrono::high_resolution_clock::now();
    mPaused = false;
    mInitialized = true;
    LOGI("Vulkan engine fully initialized");
    return true;
}

bool VulkanEngine::reinitSurface(ANativeWindow* window) {
    if (!mInitialized) return false;
    vkDeviceWaitIdle(mDevice);
    cleanupSwapchain();
    if (mSurface != VK_NULL_HANDLE) { vkDestroySurfaceKHR(mInstance, mSurface, nullptr); mSurface = VK_NULL_HANDLE; }
    mWindow = window;
    if (!createSurface()) return false;
    if (!createSwapchain()) return false;
    if (!createFramebuffers()) return false;
    mPaused = false;
    LOGI("Surface reinitialized for new window");
    return true;
}

void VulkanEngine::pause() {
    if (!mInitialized) return;
    mPaused = true;
    vkDeviceWaitIdle(mDevice);
}

void VulkanEngine::cleanupSurface() {
    if (!mInitialized) return;
    vkDeviceWaitIdle(mDevice);
    cleanupSwapchain();
    if (mSurface != VK_NULL_HANDLE) { vkDestroySurfaceKHR(mInstance, mSurface, nullptr); mSurface = VK_NULL_HANDLE; }
    mPaused = true;
}

bool VulkanEngine::createInstance() {
    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Sparks";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "SparksEngine";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_1;
    const char* extensions[] = { VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_ANDROID_SURFACE_EXTENSION_NAME };
    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = 2;
    createInfo.ppEnabledExtensionNames = extensions;
    if (vkCreateInstance(&createInfo, nullptr, &mInstance) != VK_SUCCESS) { LOGE("Failed to create Vulkan instance"); return false; }
    LOGI("Vulkan instance created");
    return true;
}

bool VulkanEngine::createSurface() {
    VkAndroidSurfaceCreateInfoKHR createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR;
    createInfo.window = mWindow;
    if (vkCreateAndroidSurfaceKHR(mInstance, &createInfo, nullptr, &mSurface) != VK_SUCCESS) { LOGE("Failed to create surface"); return false; }
    return true;
}

bool VulkanEngine::pickPhysicalDevice() {
    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(mInstance, &deviceCount, nullptr);
    if (deviceCount == 0) { LOGE("No Vulkan devices"); return false; }
    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(mInstance, &deviceCount, devices.data());
    for (const auto& device : devices) {
        uint32_t qfCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &qfCount, nullptr);
        std::vector<VkQueueFamilyProperties> qfProps(qfCount);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &qfCount, qfProps.data());
        for (uint32_t i = 0; i < qfCount; i++) {
            VkBool32 present = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(device, i, mSurface, &present);
            if ((qfProps[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && present) {
                mPhysicalDevice = device; mQueueFamilyIndex = i;
                VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(device, &props);
                LOGI("Selected GPU: %s", props.deviceName);
                return true;
            }
        }
    }
    LOGE("No suitable device"); return false;
}

bool VulkanEngine::createLogicalDevice() {
    float queuePriority = 1.0f;
    VkDeviceQueueCreateInfo queueCI{}; queueCI.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCI.queueFamilyIndex = mQueueFamilyIndex; queueCI.queueCount = 1; queueCI.pQueuePriorities = &queuePriority;
    const char* ext[] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
    VkDeviceCreateInfo ci{}; ci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    ci.queueCreateInfoCount = 1; ci.pQueueCreateInfos = &queueCI;
    ci.enabledExtensionCount = 1; ci.ppEnabledExtensionNames = ext;
    if (vkCreateDevice(mPhysicalDevice, &ci, nullptr, &mDevice) != VK_SUCCESS) { LOGE("Failed to create device"); return false; }
    vkGetDeviceQueue(mDevice, mQueueFamilyIndex, 0, &mQueue);
    return true;
}

bool VulkanEngine::createSwapchain() {
    VkSurfaceCapabilitiesKHR caps;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(mPhysicalDevice, mSurface, &caps);
    if (caps.currentExtent.width != UINT32_MAX) mSwapchainExtent = caps.currentExtent;
    else {
        mSwapchainExtent.width = std::max(caps.minImageExtent.width, std::min(caps.maxImageExtent.width, (uint32_t)ANativeWindow_getWidth(mWindow)));
        mSwapchainExtent.height = std::max(caps.minImageExtent.height, std::min(caps.maxImageExtent.height, (uint32_t)ANativeWindow_getHeight(mWindow)));
    }
    mCurrentTransform = caps.currentTransform;
    uint32_t imageCount = 2;
    if (imageCount < caps.minImageCount) imageCount = caps.minImageCount;
    if (caps.maxImageCount > 0 && imageCount > caps.maxImageCount) imageCount = caps.maxImageCount;
    uint32_t fmtCount = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(mPhysicalDevice, mSurface, &fmtCount, nullptr);
    std::vector<VkSurfaceFormatKHR> formats(fmtCount);
    vkGetPhysicalDeviceSurfaceFormatsKHR(mPhysicalDevice, mSurface, &fmtCount, formats.data());
    mSwapchainFormat = formats[0].format; VkColorSpaceKHR colorSpace = formats[0].colorSpace;
    for (auto& f : formats) if (f.format == VK_FORMAT_R8G8B8A8_UNORM) { mSwapchainFormat = f.format; colorSpace = f.colorSpace; break; }
    VkSwapchainCreateInfoKHR ci{}; ci.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    ci.surface = mSurface; ci.minImageCount = imageCount; ci.imageFormat = mSwapchainFormat;
    ci.imageColorSpace = colorSpace; ci.imageExtent = mSwapchainExtent; ci.imageArrayLayers = 1;
    ci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    ci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    ci.preTransform = caps.currentTransform; ci.compositeAlpha = VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
    ci.presentMode = VK_PRESENT_MODE_FIFO_KHR; ci.clipped = VK_TRUE;
    if (vkCreateSwapchainKHR(mDevice, &ci, nullptr, &mSwapchain) != VK_SUCCESS) { LOGE("Failed to create swapchain"); return false; }
    vkGetSwapchainImagesKHR(mDevice, mSwapchain, &imageCount, nullptr);
    mSwapchainImages.resize(imageCount);
    vkGetSwapchainImagesKHR(mDevice, mSwapchain, &imageCount, mSwapchainImages.data());
    mSwapchainImageViews.resize(imageCount);
    for (uint32_t i = 0; i < imageCount; i++) {
        VkImageViewCreateInfo vi{}; vi.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        vi.image = mSwapchainImages[i]; vi.viewType = VK_IMAGE_VIEW_TYPE_2D; vi.format = mSwapchainFormat;
        vi.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT; vi.subresourceRange.levelCount = 1; vi.subresourceRange.layerCount = 1;
        if (vkCreateImageView(mDevice, &vi, nullptr, &mSwapchainImageViews[i]) != VK_SUCCESS) return false;
    }
    LOGI("Swapchain created: %ux%u", mSwapchainExtent.width, mSwapchainExtent.height);
    return true;
}

bool VulkanEngine::createRenderPass() {
    VkAttachmentDescription att{}; att.format = mSwapchainFormat; att.samples = VK_SAMPLE_COUNT_1_BIT;
    att.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE; att.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    att.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE; att.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED; att.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    VkAttachmentReference ref{}; ref.attachment = 0; ref.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    VkSubpassDescription sub{}; sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    sub.colorAttachmentCount = 1; sub.pColorAttachments = &ref;
    VkSubpassDependency dep{}; dep.srcSubpass = VK_SUBPASS_EXTERNAL; dep.dstSubpass = 0;
    dep.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    VkRenderPassCreateInfo ci{}; ci.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    ci.attachmentCount = 1; ci.pAttachments = &att; ci.subpassCount = 1; ci.pSubpasses = &sub;
    ci.dependencyCount = 1; ci.pDependencies = &dep;
    return vkCreateRenderPass(mDevice, &ci, nullptr, &mRenderPass) == VK_SUCCESS;
}

bool VulkanEngine::createFramebuffers() {
    mFramebuffers.resize(mSwapchainImageViews.size());
    for (size_t i = 0; i < mSwapchainImageViews.size(); i++) {
        VkFramebufferCreateInfo ci{}; ci.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        ci.renderPass = mRenderPass; ci.attachmentCount = 1; ci.pAttachments = &mSwapchainImageViews[i];
        ci.width = mSwapchainExtent.width; ci.height = mSwapchainExtent.height; ci.layers = 1;
        if (vkCreateFramebuffer(mDevice, &ci, nullptr, &mFramebuffers[i]) != VK_SUCCESS) return false;
    }
    return true;
}

bool VulkanEngine::createCommandPool() {
    VkCommandPoolCreateInfo ci{}; ci.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    ci.queueFamilyIndex = mQueueFamilyIndex; ci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    return vkCreateCommandPool(mDevice, &ci, nullptr, &mCommandPool) == VK_SUCCESS;
}

bool VulkanEngine::createCommandBuffers() {
    mCommandBuffers.resize(MAX_FRAMES_IN_FLIGHT);
    VkCommandBufferAllocateInfo ai{}; ai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    ai.commandPool = mCommandPool; ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; ai.commandBufferCount = MAX_FRAMES_IN_FLIGHT;
    return vkAllocateCommandBuffers(mDevice, &ai, mCommandBuffers.data()) == VK_SUCCESS;
}

bool VulkanEngine::createSyncObjects() {
    mImageAvailableSemaphores.resize(MAX_FRAMES_IN_FLIGHT);
    mRenderFinishedSemaphores.resize(MAX_FRAMES_IN_FLIGHT);
    mInFlightFences.resize(MAX_FRAMES_IN_FLIGHT);
    VkSemaphoreCreateInfo si{}; si.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    VkFenceCreateInfo fi{}; fi.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO; fi.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    for (uint32_t i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
        if (vkCreateSemaphore(mDevice, &si, nullptr, &mImageAvailableSemaphores[i]) != VK_SUCCESS ||
            vkCreateSemaphore(mDevice, &si, nullptr, &mRenderFinishedSemaphores[i]) != VK_SUCCESS ||
            vkCreateFence(mDevice, &fi, nullptr, &mInFlightFences[i]) != VK_SUCCESS) return false;
    }
    return true;
}

bool VulkanEngine::loadTexture(const char* assetPath, int index) {
    auto raw = loadRawAsset(mAssetManager, assetPath);
    if (raw.empty()) { LOGE("Failed to load %s", assetPath); return false; }
    int w, h, ch;
    stbi_uc* pixels = stbi_load_from_memory(raw.data(), (int)raw.size(), &w, &h, &ch, 4);
    if (!pixels) { LOGE("Failed to decode %s", assetPath); return false; }
    LOGI("Texture %d loaded: %dx%d from %s", index, w, h, assetPath);
    VkDeviceSize imageSize = w * h * 4;

    auto staging = createBuffer(mDevice, mPhysicalDevice, imageSize,
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    void* data; vkMapMemory(mDevice, staging.memory, 0, imageSize, 0, &data);
    memcpy(data, pixels, imageSize); vkUnmapMemory(mDevice, staging.memory);
    stbi_image_free(pixels);

    VkImageCreateInfo ii{}; ii.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO; ii.imageType = VK_IMAGE_TYPE_2D;
    ii.extent = {(uint32_t)w, (uint32_t)h, 1}; ii.mipLevels = 1; ii.arrayLayers = 1;
    ii.format = VK_FORMAT_R8G8B8A8_UNORM; ii.tiling = VK_IMAGE_TILING_OPTIMAL;
    ii.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    ii.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    ii.samples = VK_SAMPLE_COUNT_1_BIT;
    if (vkCreateImage(mDevice, &ii, nullptr, &mTextures[index].image) != VK_SUCCESS) return false;

    VkMemoryRequirements memReqs; vkGetImageMemoryRequirements(mDevice, mTextures[index].image, &memReqs);
    VkMemoryAllocateInfo ai{}; ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ai.allocationSize = memReqs.size;
    ai.memoryTypeIndex = findMemoryType(mPhysicalDevice, memReqs.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (vkAllocateMemory(mDevice, &ai, nullptr, &mTextures[index].memory) != VK_SUCCESS) return false;
    vkBindImageMemory(mDevice, mTextures[index].image, mTextures[index].memory, 0);

    // One-shot command buffer for upload
    VkCommandBufferAllocateInfo cmdAI{}; cmdAI.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAI.commandPool = mCommandPool; cmdAI.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cmdAI.commandBufferCount = 1;
    VkCommandBuffer cmd; vkAllocateCommandBuffers(mDevice, &cmdAI, &cmd);
    VkCommandBufferBeginInfo bi{}; bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &bi);

    VkImageMemoryBarrier barrier{}; barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = mTextures[index].image;
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    VkBufferImageCopy region{}; region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    region.imageExtent = {(uint32_t)w, (uint32_t)h, 1};
    vkCmdCopyBufferToImage(cmd, staging.buffer, mTextures[index].image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    vkEndCommandBuffer(cmd);
    VkSubmitInfo si{}; si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO; si.commandBufferCount = 1; si.pCommandBuffers = &cmd;
    vkQueueSubmit(mQueue, 1, &si, VK_NULL_HANDLE); vkQueueWaitIdle(mQueue);
    vkFreeCommandBuffers(mDevice, mCommandPool, 1, &cmd);
    vkDestroyBuffer(mDevice, staging.buffer, nullptr); vkFreeMemory(mDevice, staging.memory, nullptr);

    // Image view
    VkImageViewCreateInfo vi{}; vi.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    vi.image = mTextures[index].image; vi.viewType = VK_IMAGE_VIEW_TYPE_2D;
    vi.format = VK_FORMAT_R8G8B8A8_UNORM;
    vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    return vkCreateImageView(mDevice, &vi, nullptr, &mTextures[index].imageView) == VK_SUCCESS;
}

bool VulkanEngine::loadTexture3D(const char* assetPath, int index, uint32_t w, uint32_t h, uint32_t d) {
    auto raw = loadRawAsset(mAssetManager, assetPath);
    VkDeviceSize expected = w * h * d;
    if (raw.size() != expected) { LOGE("3D texture %s: expected %u bytes, got %zu", assetPath, (unsigned)expected, raw.size()); return false; }
    LOGI("3D texture %d loaded: %ux%ux%u from %s", index, w, h, d, assetPath);

    // Expand R8 to RGBA8 for upload
    VkDeviceSize imageSize = expected * 4;
    std::vector<uint8_t> rgba(imageSize);
    for (size_t i = 0; i < expected; i++) {
        rgba[i * 4 + 0] = raw[i];
        rgba[i * 4 + 1] = raw[i];
        rgba[i * 4 + 2] = raw[i];
        rgba[i * 4 + 3] = 255;
    }

    auto staging = createBuffer(mDevice, mPhysicalDevice, imageSize,
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    void* data; vkMapMemory(mDevice, staging.memory, 0, imageSize, 0, &data);
    memcpy(data, rgba.data(), imageSize); vkUnmapMemory(mDevice, staging.memory);

    VkImageCreateInfo ii{}; ii.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ii.imageType = VK_IMAGE_TYPE_3D;
    ii.extent = {w, h, d}; ii.mipLevels = 1; ii.arrayLayers = 1;
    ii.format = VK_FORMAT_R8G8B8A8_UNORM; ii.tiling = VK_IMAGE_TILING_OPTIMAL;
    ii.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    ii.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    ii.samples = VK_SAMPLE_COUNT_1_BIT;
    if (vkCreateImage(mDevice, &ii, nullptr, &mTextures[index].image) != VK_SUCCESS) return false;

    VkMemoryRequirements memReqs; vkGetImageMemoryRequirements(mDevice, mTextures[index].image, &memReqs);
    VkMemoryAllocateInfo ai{}; ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ai.allocationSize = memReqs.size;
    ai.memoryTypeIndex = findMemoryType(mPhysicalDevice, memReqs.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (vkAllocateMemory(mDevice, &ai, nullptr, &mTextures[index].memory) != VK_SUCCESS) return false;
    vkBindImageMemory(mDevice, mTextures[index].image, mTextures[index].memory, 0);

    VkCommandBufferAllocateInfo cmdAI{}; cmdAI.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAI.commandPool = mCommandPool; cmdAI.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cmdAI.commandBufferCount = 1;
    VkCommandBuffer cmd; vkAllocateCommandBuffers(mDevice, &cmdAI, &cmd);
    VkCommandBufferBeginInfo bi{}; bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &bi);

    VkImageMemoryBarrier barrier{}; barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = mTextures[index].image;
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    VkBufferImageCopy region{}; region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    region.imageExtent = {w, h, d};
    vkCmdCopyBufferToImage(cmd, staging.buffer, mTextures[index].image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    vkEndCommandBuffer(cmd);
    VkSubmitInfo si{}; si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO; si.commandBufferCount = 1; si.pCommandBuffers = &cmd;
    vkQueueSubmit(mQueue, 1, &si, VK_NULL_HANDLE); vkQueueWaitIdle(mQueue);
    vkFreeCommandBuffers(mDevice, mCommandPool, 1, &cmd);
    vkDestroyBuffer(mDevice, staging.buffer, nullptr); vkFreeMemory(mDevice, staging.memory, nullptr);

    VkImageViewCreateInfo vi{}; vi.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    vi.image = mTextures[index].image; vi.viewType = VK_IMAGE_VIEW_TYPE_3D;
    vi.format = VK_FORMAT_R8G8B8A8_UNORM;
    vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    return vkCreateImageView(mDevice, &vi, nullptr, &mTextures[index].imageView) == VK_SUCCESS;
}

bool VulkanEngine::createTextures() {
    // Load all textures
    if (!loadTexture("textures/stars.jpg", 0)) return false;
    if (!loadTexture("textures/rgba_noise_medium.png", 1)) return false;
    if (!loadTexture("textures/rgba_noise_large.png", 2)) return false; // iChannel1: 1024x1024 for texelFetch dithering
    if (!loadTexture3D("textures/grey_noise_3d.bin", 3, 32, 32, 32)) return false;
    if (!loadTexture("textures/organic2.png", 4)) return false;

    // Sampler
    VkSamplerCreateInfo si{}; si.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    si.magFilter = VK_FILTER_LINEAR; si.minFilter = VK_FILTER_LINEAR;
    si.addressModeU = si.addressModeV = si.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
    si.maxLod = 1.0f;
    if (vkCreateSampler(mDevice, &si, nullptr, &mTextureSampler) != VK_SUCCESS) return false;

    // Descriptor set layout: 3 combined image samplers
    VkDescriptorSetLayoutBinding bindings[MAX_TEX_BINDINGS]{};
    for (int i = 0; i < MAX_TEX_BINDINGS; i++) {
        bindings[i].binding = i;
        bindings[i].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        bindings[i].descriptorCount = 1;
        bindings[i].stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
    }
    VkDescriptorSetLayoutCreateInfo li{}; li.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    li.bindingCount = MAX_TEX_BINDINGS; li.pBindings = bindings;
    if (vkCreateDescriptorSetLayout(mDevice, &li, nullptr, &mDescriptorSetLayout) != VK_SUCCESS) return false;

    // Descriptor pool (2 sets, 6 combined image samplers total)
    VkDescriptorPoolSize poolSize{}; poolSize.type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    poolSize.descriptorCount = MAX_TEX_BINDINGS * 4;
    VkDescriptorPoolCreateInfo pi{}; pi.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    pi.poolSizeCount = 1; pi.pPoolSizes = &poolSize; pi.maxSets = 4;
    if (vkCreateDescriptorPool(mDevice, &pi, nullptr, &mDescriptorPool) != VK_SUCCESS) return false;

    // Allocate 2 descriptor sets
    VkDescriptorSetLayout layouts[4] = {mDescriptorSetLayout, mDescriptorSetLayout, mDescriptorSetLayout, mDescriptorSetLayout};
    VkDescriptorSetAllocateInfo dsai{}; dsai.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    dsai.descriptorPool = mDescriptorPool; dsai.descriptorSetCount = 4; dsai.pSetLayouts = layouts;
    if (vkAllocateDescriptorSets(mDevice, &dsai, mDescriptorSets) != VK_SUCCESS) return false;

    // Update descriptor set 0 (starship): all bindings → stars texture
    {
        VkDescriptorImageInfo imgInfo{}; imgInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        imgInfo.imageView = mTextures[0].imageView; imgInfo.sampler = mTextureSampler;
        VkWriteDescriptorSet writes[MAX_TEX_BINDINGS]{};
        for (int i = 0; i < MAX_TEX_BINDINGS; i++) {
            writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = mDescriptorSets[0];
            writes[i].dstBinding = i; writes[i].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
            writes[i].descriptorCount = 1; writes[i].pImageInfo = &imgInfo;
        }
        vkUpdateDescriptorSets(mDevice, MAX_TEX_BINDINGS, writes, 0, nullptr);
    }
    // Update descriptor set 1 (clouds): binding 0=noise_med, 1=noise_small, 2=noise_gray
    {
        VkDescriptorImageInfo imgInfos[MAX_TEX_BINDINGS]{};
        for (int i = 0; i < MAX_TEX_BINDINGS; i++) {
            imgInfos[i].imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            imgInfos[i].imageView = mTextures[1 + i].imageView; // textures 1,2,3
            imgInfos[i].sampler = mTextureSampler;
        }
        VkWriteDescriptorSet writes[MAX_TEX_BINDINGS]{};
        for (int i = 0; i < MAX_TEX_BINDINGS; i++) {
            writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = mDescriptorSets[1];
            writes[i].dstBinding = i; writes[i].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
            writes[i].descriptorCount = 1; writes[i].pImageInfo = &imgInfos[i];
        }
        vkUpdateDescriptorSets(mDevice, MAX_TEX_BINDINGS, writes, 0, nullptr);
    }

    // Update descriptor set 3 (grid): all bindings → organic2 texture
    {
        VkDescriptorImageInfo imgInfo{}; imgInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        imgInfo.imageView = mTextures[4].imageView; imgInfo.sampler = mTextureSampler;
        VkWriteDescriptorSet writes[MAX_TEX_BINDINGS]{};
        for (int i = 0; i < MAX_TEX_BINDINGS; i++) {
            writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = mDescriptorSets[3];
            writes[i].dstBinding = i; writes[i].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
            writes[i].descriptorCount = 1; writes[i].pImageInfo = &imgInfo;
        }
        vkUpdateDescriptorSets(mDevice, MAX_TEX_BINDINGS, writes, 0, nullptr);
    }

    LOGI("All textures and descriptor sets created");
    return true;
}

bool VulkanEngine::createGraphicsPipeline() {
    auto vertCode = loadShaderFromAsset(mAssetManager, "shaders/fullscreen.vert.spv");
    const char* fragNames[SHADER_COUNT] = {
        "shaders/sparks.frag.spv", "shaders/cosmic.frag.spv",
        "shaders/starship.frag.spv", "shaders/clouds.frag.spv",
        "shaders/seascape.frag.spv", "shaders/rainforest.frag.spv",
        "shaders/plasma.frag.spv", "shaders/grid.frag.spv",
        "shaders/interstellar.frag.spv", "shaders/mandelbulb.frag.spv",
        "shaders/cyberspace.frag.spv", "shaders/tunnel.frag.spv",
        "shaders/primitives.frag.spv", "shaders/fractal.frag.spv",
        "shaders/palette.frag.spv", "shaders/octgrams.frag.spv",
        "shaders/voxellines.frag.spv", "shaders/mandelbulb2.frag.spv",
        "shaders/protean.frag.spv", "shaders/rocaille.frag.spv",
        "shaders/hudrings.frag.spv", "shaders/flighthud.frag.spv",
        "shaders/metalball.frag.spv", "shaders/heart.frag.spv",
        "shaders/jellyfish.frag.spv", "shaders/hypertunnel.frag.spv"
    };
    std::vector<uint32_t> fragCodes[SHADER_COUNT];
    VkShaderModule fragModules[SHADER_COUNT]{};

    if (vertCode.empty()) { LOGE("Failed to load vertex shader"); return false; }
    for (int i = 0; i < SHADER_COUNT; i++) {
        fragCodes[i] = loadShaderFromAsset(mAssetManager, fragNames[i]);
        if (fragCodes[i].empty()) { LOGE("Failed to load %s", fragNames[i]); return false; }
    }

    VkShaderModule vertModule = createShaderModule(mDevice, vertCode);
    for (int i = 0; i < SHADER_COUNT; i++) fragModules[i] = createShaderModule(mDevice, fragCodes[i]);

    // Pipeline layout
    VkPushConstantRange pcRange{}; pcRange.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
    pcRange.size = sizeof(PushConstants);
    VkPipelineLayoutCreateInfo pli{}; pli.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pli.setLayoutCount = 1; pli.pSetLayouts = &mDescriptorSetLayout;
    pli.pushConstantRangeCount = 1; pli.pPushConstantRanges = &pcRange;
    if (vkCreatePipelineLayout(mDevice, &pli, nullptr, &mPipelineLayout) != VK_SUCCESS) return false;

    // Common pipeline state
    VkPipelineVertexInputStateCreateInfo vertexInput{}; vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    VkPipelineInputAssemblyStateCreateInfo inputAsm{}; inputAsm.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    inputAsm.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkViewport vp{}; vp.width = (float)mSwapchainExtent.width; vp.height = (float)mSwapchainExtent.height; vp.maxDepth = 1.0f;
    VkRect2D sc{}; sc.extent = mSwapchainExtent;
    VkPipelineViewportStateCreateInfo vpState{}; vpState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    vpState.viewportCount = 1; vpState.pViewports = &vp; vpState.scissorCount = 1; vpState.pScissors = &sc;
    VkPipelineRasterizationStateCreateInfo rast{}; rast.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rast.polygonMode = VK_POLYGON_MODE_FILL; rast.lineWidth = 1.0f; rast.cullMode = VK_CULL_MODE_NONE;
    VkPipelineMultisampleStateCreateInfo ms{}; ms.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineColorBlendAttachmentState cba{}; cba.colorWriteMask = 0xF;
    VkPipelineColorBlendStateCreateInfo cb{}; cb.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    cb.attachmentCount = 1; cb.pAttachments = &cba;
    VkDynamicState dynStates[] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
    VkPipelineDynamicStateCreateInfo dynState{}; dynState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynState.dynamicStateCount = 2; dynState.pDynamicStates = dynStates;

    VkGraphicsPipelineCreateInfo pci{}; pci.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pci.stageCount = 2; pci.pVertexInputState = &vertexInput; pci.pInputAssemblyState = &inputAsm;
    pci.pViewportState = &vpState; pci.pRasterizationState = &rast; pci.pMultisampleState = &ms;
    pci.pColorBlendState = &cb; pci.pDynamicState = &dynState;
    pci.layout = mPipelineLayout; pci.renderPass = mRenderPass; pci.subpass = 0;

    for (int i = 0; i < SHADER_COUNT; i++) {
        VkPipelineShaderStageCreateInfo stages[2]{};
        stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT; stages[0].module = vertModule; stages[0].pName = "main";
        stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT; stages[1].module = fragModules[i]; stages[1].pName = "main";
        pci.pStages = stages;
        if (vkCreateGraphicsPipelines(mDevice, VK_NULL_HANDLE, 1, &pci, nullptr, &mPipelines[i]) != VK_SUCCESS) {
            LOGE("Failed to create pipeline %d (%s), skipping", i, fragNames[i]);
            mPipelines[i] = VK_NULL_HANDLE;
        }
    }

    // FXAA post-process pipeline (uses main render pass for swapchain output)
    auto fxaaCode = loadShaderFromAsset(mAssetManager, "shaders/fxaa.frag.spv");
    if (!fxaaCode.empty()) {
        VkShaderModule fxaaModule = createShaderModule(mDevice, fxaaCode);
        if (fxaaModule != VK_NULL_HANDLE) {
            VkPipelineShaderStageCreateInfo fxaaStages[2]{};
            fxaaStages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
            fxaaStages[0].stage = VK_SHADER_STAGE_VERTEX_BIT; fxaaStages[0].module = vertModule; fxaaStages[0].pName = "main";
            fxaaStages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
            fxaaStages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT; fxaaStages[1].module = fxaaModule; fxaaStages[1].pName = "main";
            pci.pStages = fxaaStages;
            vkCreateGraphicsPipelines(mDevice, VK_NULL_HANDLE, 1, &pci, nullptr, &mFxaaPipeline);
            vkDestroyShaderModule(mDevice, fxaaModule, nullptr);
            LOGI("FXAA pipeline created");
        }
    }

    vkDestroyShaderModule(mDevice, vertModule, nullptr);
    for (int i = 0; i < SHADER_COUNT; i++) vkDestroyShaderModule(mDevice, fragModules[i], nullptr);
    LOGI("All %d graphics pipelines created", SHADER_COUNT);
    return true;
}

bool VulkanEngine::createOffscreenRenderPass() {
    VkAttachmentDescription att{}; att.format = mSwapchainFormat; att.samples = VK_SAMPLE_COUNT_1_BIT;
    att.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE; att.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    att.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE; att.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    att.finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    VkAttachmentReference ref{}; ref.attachment = 0; ref.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    VkSubpassDescription sub{}; sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    sub.colorAttachmentCount = 1; sub.pColorAttachments = &ref;
    VkSubpassDependency dep{}; dep.srcSubpass = VK_SUBPASS_EXTERNAL; dep.dstSubpass = 0;
    dep.srcStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    dep.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
    dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    VkRenderPassCreateInfo ci{}; ci.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    ci.attachmentCount = 1; ci.pAttachments = &att; ci.subpassCount = 1; ci.pSubpasses = &sub;
    ci.dependencyCount = 1; ci.pDependencies = &dep;
    return vkCreateRenderPass(mDevice, &ci, nullptr, &mOffscreenRenderPass) == VK_SUCCESS;
}

bool VulkanEngine::createHistoryBuffer() {
    uint32_t w = mSwapchainExtent.width;
    uint32_t h = mSwapchainExtent.height;

    VkImageCreateInfo ii{}; ii.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ii.imageType = VK_IMAGE_TYPE_2D; ii.extent = {w, h, 1};
    ii.mipLevels = 1; ii.arrayLayers = 1;
    ii.format = mSwapchainFormat; ii.tiling = VK_IMAGE_TILING_OPTIMAL;
    ii.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    ii.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    ii.samples = VK_SAMPLE_COUNT_1_BIT;
    if (vkCreateImage(mDevice, &ii, nullptr, &mHistoryImage) != VK_SUCCESS) return false;

    VkMemoryRequirements memReqs;
    vkGetImageMemoryRequirements(mDevice, mHistoryImage, &memReqs);
    VkMemoryAllocateInfo ai{}; ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ai.allocationSize = memReqs.size;
    ai.memoryTypeIndex = findMemoryType(mPhysicalDevice, memReqs.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (vkAllocateMemory(mDevice, &ai, nullptr, &mHistoryMemory) != VK_SUCCESS) return false;
    vkBindImageMemory(mDevice, mHistoryImage, mHistoryMemory, 0);

    VkImageViewCreateInfo vi{}; vi.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    vi.image = mHistoryImage; vi.viewType = VK_IMAGE_VIEW_TYPE_2D;
    vi.format = mSwapchainFormat;
    vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    if (vkCreateImageView(mDevice, &vi, nullptr, &mHistoryView) != VK_SUCCESS) return false;

    // Transition to SHADER_READ_ONLY so it's ready to be sampled
    VkCommandBufferAllocateInfo cmdAI{}; cmdAI.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAI.commandPool = mCommandPool; cmdAI.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cmdAI.commandBufferCount = 1;
    VkCommandBuffer cmd; vkAllocateCommandBuffers(mDevice, &cmdAI, &cmd);
    VkCommandBufferBeginInfo bi{}; bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &bi);
    VkImageMemoryBarrier barrier{}; barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = mHistoryImage;
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                         0, 0, nullptr, 0, nullptr, 1, &barrier);
    vkEndCommandBuffer(cmd);
    VkSubmitInfo si{}; si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO; si.commandBufferCount = 1; si.pCommandBuffers = &cmd;
    vkQueueSubmit(mQueue, 1, &si, VK_NULL_HANDLE); vkQueueWaitIdle(mQueue);
    vkFreeCommandBuffers(mDevice, mCommandPool, 1, &cmd);

    // Update descriptor set 2 with history buffer
    VkDescriptorImageInfo imgInfo{};
    imgInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    imgInfo.imageView = mHistoryView;
    imgInfo.sampler = mTextureSampler;
    VkWriteDescriptorSet writes[MAX_TEX_BINDINGS]{};
    for (int i = 0; i < MAX_TEX_BINDINGS; i++) {
        writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[i].dstSet = mDescriptorSets[2];
        writes[i].dstBinding = i;
        writes[i].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        writes[i].descriptorCount = 1;
        writes[i].pImageInfo = &imgInfo; // all bindings point to history
    }
    vkUpdateDescriptorSets(mDevice, MAX_TEX_BINDINGS, writes, 0, nullptr);

    // Create framebuffer for offscreen rendering
    if (mOffscreenRenderPass != VK_NULL_HANDLE) {
        VkFramebufferCreateInfo fbci{}; fbci.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        fbci.renderPass = mOffscreenRenderPass; fbci.attachmentCount = 1; fbci.pAttachments = &mHistoryView;
        fbci.width = w; fbci.height = h; fbci.layers = 1;
        if (vkCreateFramebuffer(mDevice, &fbci, nullptr, &mHistoryFramebuffer) != VK_SUCCESS) return false;
    }

    mFrameCount = 0;
    LOGI("History buffer created: %ux%u", w, h);
    return true;
}

void VulkanEngine::cleanupHistoryBuffer() {
    if (mHistoryFramebuffer != VK_NULL_HANDLE) { vkDestroyFramebuffer(mDevice, mHistoryFramebuffer, nullptr); mHistoryFramebuffer = VK_NULL_HANDLE; }
    if (mHistoryView != VK_NULL_HANDLE) { vkDestroyImageView(mDevice, mHistoryView, nullptr); mHistoryView = VK_NULL_HANDLE; }
    if (mHistoryImage != VK_NULL_HANDLE) { vkDestroyImage(mDevice, mHistoryImage, nullptr); mHistoryImage = VK_NULL_HANDLE; }
    if (mHistoryMemory != VK_NULL_HANDLE) { vkFreeMemory(mDevice, mHistoryMemory, nullptr); mHistoryMemory = VK_NULL_HANDLE; }
}

// --- Multi-pass (fluid) infrastructure -------------------------------------

bool VulkanEngine::createOffscreenTarget(OffscreenTarget& target, uint32_t w, uint32_t h,
                                         VkFormat format, bool pingPong, bool withMipmaps,
                                         VkRenderPass renderPassForFramebuffer) {
    target.width = w; target.height = h; target.format = format;
    target.pingPong = pingPong; target.mipLevels = 1;
    if (withMipmaps) {
        uint32_t mn = std::min(w, h);
        while (mn > 1) { target.mipLevels++; mn >>= 1; }
    }
    const int count = pingPong ? 2 : 1;
    const VkImageUsageFlags usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT |
                                    VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;

    for (int i = 0; i < count; i++) {
        VkImageCreateInfo ii{}; ii.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        ii.imageType = VK_IMAGE_TYPE_2D; ii.extent = {w, h, 1};
        ii.mipLevels = target.mipLevels; ii.arrayLayers = 1;
        ii.format = format; ii.tiling = VK_IMAGE_TILING_OPTIMAL;
        ii.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        ii.usage = usage; ii.samples = VK_SAMPLE_COUNT_1_BIT;
        if (vkCreateImage(mDevice, &ii, nullptr, &target.image[i]) != VK_SUCCESS) return false;

        VkMemoryRequirements memReqs; vkGetImageMemoryRequirements(mDevice, target.image[i], &memReqs);
        VkMemoryAllocateInfo ai{}; ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        ai.allocationSize = memReqs.size;
        ai.memoryTypeIndex = findMemoryType(mPhysicalDevice, memReqs.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        if (vkAllocateMemory(mDevice, &ai, nullptr, &target.memory[i]) != VK_SUCCESS) return false;
        vkBindImageMemory(mDevice, target.image[i], target.memory[i], 0);

        // all-mips view (sampling)
        VkImageViewCreateInfo vi{}; vi.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        vi.image = target.image[i]; vi.viewType = VK_IMAGE_VIEW_TYPE_2D; vi.format = format;
        vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, target.mipLevels, 0, 1};
        if (vkCreateImageView(mDevice, &vi, nullptr, &target.viewAll[i]) != VK_SUCCESS) return false;

        // mip-0 view (framebuffer attachment)
        VkImageViewCreateInfo vi0{}; vi0.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        vi0.image = target.image[i]; vi0.viewType = VK_IMAGE_VIEW_TYPE_2D; vi0.format = format;
        vi0.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        if (vkCreateImageView(mDevice, &vi0, nullptr, &target.viewMip0[i]) != VK_SUCCESS) return false;

        if (renderPassForFramebuffer != VK_NULL_HANDLE) {
            VkFramebufferCreateInfo fbci{}; fbci.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
            fbci.renderPass = renderPassForFramebuffer;
            fbci.attachmentCount = 1; fbci.pAttachments = &target.viewMip0[i];
            fbci.width = w; fbci.height = h; fbci.layers = 1;
            if (vkCreateFramebuffer(mDevice, &fbci, nullptr, &target.framebuffer[i]) != VK_SUCCESS) return false;
        }
    }

    // Initial transition: UNDEFINED -> SHADER_READ_ONLY_OPTIMAL (all mips)
    VkCommandBufferAllocateInfo cmdAI{}; cmdAI.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAI.commandPool = mCommandPool; cmdAI.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cmdAI.commandBufferCount = 1;
    VkCommandBuffer cmd; vkAllocateCommandBuffers(mDevice, &cmdAI, &cmd);
    VkCommandBufferBeginInfo bi{}; bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &bi);
    for (int i = 0; i < count; i++) {
        VkImageMemoryBarrier b{}; b.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        b.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        b.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        b.image = target.image[i];
        b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, target.mipLevels, 0, 1};
        b.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                             0, 0, nullptr, 0, nullptr, 1, &b);
    }
    vkEndCommandBuffer(cmd);
    VkSubmitInfo si{}; si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1; si.pCommandBuffers = &cmd;
    vkQueueSubmit(mQueue, 1, &si, VK_NULL_HANDLE); vkQueueWaitIdle(mQueue);
    vkFreeCommandBuffers(mDevice, mCommandPool, 1, &cmd);

    target.srcIdx = 0;
    LOGI("OffscreenTarget created: %ux%u, fmt=%d, pingPong=%d, mips=%u",
         w, h, (int)format, (int)pingPong, target.mipLevels);
    return true;
}

void VulkanEngine::destroyOffscreenTarget(OffscreenTarget& target) {
    const int count = target.pingPong ? 2 : 1;
    for (int i = 0; i < count; i++) {
        if (target.framebuffer[i] != VK_NULL_HANDLE) { vkDestroyFramebuffer(mDevice, target.framebuffer[i], nullptr); target.framebuffer[i] = VK_NULL_HANDLE; }
        if (target.viewMip0[i] != VK_NULL_HANDLE) { vkDestroyImageView(mDevice, target.viewMip0[i], nullptr); target.viewMip0[i] = VK_NULL_HANDLE; }
        if (target.viewAll[i] != VK_NULL_HANDLE) { vkDestroyImageView(mDevice, target.viewAll[i], nullptr); target.viewAll[i] = VK_NULL_HANDLE; }
        if (target.image[i] != VK_NULL_HANDLE) { vkDestroyImage(mDevice, target.image[i], nullptr); target.image[i] = VK_NULL_HANDLE; }
        if (target.memory[i] != VK_NULL_HANDLE) { vkFreeMemory(mDevice, target.memory[i], nullptr); target.memory[i] = VK_NULL_HANDLE; }
    }
}

// Generates the mipmap chain for target.image[idx] via successive blits.
// Precondition: entire image in SHADER_READ_ONLY_OPTIMAL.
// Postcondition: entire image in SHADER_READ_ONLY_OPTIMAL with mip chain populated.
void VulkanEngine::recordGenerateMipmaps(VkCommandBuffer cmd, OffscreenTarget& target, int idx) {
    if (target.mipLevels <= 1) return;
    VkImage img = target.image[idx];

    // mips 1..N-1: SHADER_READ_ONLY -> TRANSFER_DST
    {
        VkImageMemoryBarrier b{}; b.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        b.oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        b.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        b.image = img;
        b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 1, target.mipLevels - 1, 0, 1};
        b.srcAccessMask = VK_ACCESS_SHADER_READ_BIT; b.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                             0, 0, nullptr, 0, nullptr, 1, &b);
    }
    // mip 0: SHADER_READ_ONLY -> TRANSFER_SRC
    {
        VkImageMemoryBarrier b{}; b.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        b.oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        b.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        b.image = img;
        b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        b.srcAccessMask = VK_ACCESS_SHADER_READ_BIT; b.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                             0, 0, nullptr, 0, nullptr, 1, &b);
    }

    int32_t mipW = (int32_t)target.width;
    int32_t mipH = (int32_t)target.height;
    for (uint32_t i = 1; i < target.mipLevels; i++) {
        int32_t nextW = std::max(1, mipW >> 1);
        int32_t nextH = std::max(1, mipH >> 1);

        VkImageBlit blit{};
        blit.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, i - 1, 0, 1};
        blit.srcOffsets[1] = {mipW, mipH, 1};
        blit.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, i, 0, 1};
        blit.dstOffsets[1] = {nextW, nextH, 1};
        vkCmdBlitImage(cmd, img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                       img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);

        if (i + 1 < target.mipLevels) {
            // this mip becomes source for next iteration
            VkImageMemoryBarrier b{}; b.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            b.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            b.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
            b.image = img;
            b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, i, 1, 0, 1};
            b.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; b.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
            vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                                 0, 0, nullptr, 0, nullptr, 1, &b);
        }
        mipW = nextW; mipH = nextH;
    }

    // Final: all mips -> SHADER_READ_ONLY_OPTIMAL
    VkImageMemoryBarrier finals[2]{};
    finals[0].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    finals[0].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    finals[0].newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    finals[0].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; finals[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    finals[0].image = img;
    finals[0].subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, target.mipLevels - 1, 0, 1};
    finals[0].srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT; finals[0].dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    finals[1].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    finals[1].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    finals[1].newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    finals[1].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; finals[1].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    finals[1].image = img;
    finals[1].subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, target.mipLevels - 1, 1, 0, 1};
    finals[1].srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; finals[1].dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                         0, 0, nullptr, 0, nullptr, 2, finals);
}

bool VulkanEngine::createFluidResources() {
    // Use display dimensions (not swapchain extent which may be rotated)
    // so the simulation runs in display orientation, matching OpenGL behavior.
    uint32_t w = (uint32_t)ANativeWindow_getWidth(mWindow);
    uint32_t h = (uint32_t)ANativeWindow_getHeight(mWindow);

    // 1. RGBA16F render pass (finalLayout = SHADER_READ_ONLY_OPTIMAL)
    {
        VkAttachmentDescription att{}; att.format = VK_FORMAT_R16G16B16A16_SFLOAT;
        att.samples = VK_SAMPLE_COUNT_1_BIT;
        att.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE; att.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
        att.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE; att.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        att.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        att.finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        VkAttachmentReference ref{}; ref.attachment = 0; ref.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        VkSubpassDescription sub{}; sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
        sub.colorAttachmentCount = 1; sub.pColorAttachments = &ref;
        VkSubpassDependency dep{}; dep.srcSubpass = VK_SUBPASS_EXTERNAL; dep.dstSubpass = 0;
        dep.srcStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
        dep.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dep.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
        dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        VkRenderPassCreateInfo ci{}; ci.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
        ci.attachmentCount = 1; ci.pAttachments = &att; ci.subpassCount = 1; ci.pSubpasses = &sub;
        ci.dependencyCount = 1; ci.pDependencies = &dep;
        if (vkCreateRenderPass(mDevice, &ci, nullptr, &mFluid.renderPass) != VK_SUCCESS) {
            LOGE("Failed to create fluid render pass"); return false;
        }
    }

    // 2. Sampler with mipmap support (maxLod high enough for 11 levels)
    {
        VkSamplerCreateInfo si{}; si.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        si.magFilter = VK_FILTER_LINEAR; si.minFilter = VK_FILTER_LINEAR;
        si.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
        si.addressModeU = si.addressModeV = si.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        si.maxLod = 16.0f;
        if (vkCreateSampler(mDevice, &si, nullptr, &mFluid.sampler) != VK_SUCCESS) return false;
    }

    // 3. Descriptor set layout (4 combined image samplers for iChannel0-3)
    {
        VkDescriptorSetLayoutBinding bindings[FLUID_TEX_BINDINGS]{};
        for (int i = 0; i < FLUID_TEX_BINDINGS; i++) {
            bindings[i].binding = i;
            bindings[i].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
            bindings[i].descriptorCount = 1;
            bindings[i].stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
        }
        VkDescriptorSetLayoutCreateInfo li{}; li.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        li.bindingCount = FLUID_TEX_BINDINGS; li.pBindings = bindings;
        if (vkCreateDescriptorSetLayout(mDevice, &li, nullptr, &mFluid.descLayout) != VK_SUCCESS) return false;
    }

    // 4. Pipeline layout
    {
        VkPushConstantRange pcRange{}; pcRange.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
        pcRange.size = sizeof(PushConstants);
        VkPipelineLayoutCreateInfo pli{}; pli.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        pli.setLayoutCount = 1; pli.pSetLayouts = &mFluid.descLayout;
        pli.pushConstantRangeCount = 1; pli.pPushConstantRanges = &pcRange;
        if (vkCreatePipelineLayout(mDevice, &pli, nullptr, &mFluid.pipelineLayout) != VK_SUCCESS) return false;
    }

    // 5. Descriptor pool + sets
    {
        const uint32_t totalSets = FLUID_PASS_COUNT * MAX_FRAMES_IN_FLIGHT;
        VkDescriptorPoolSize poolSize{}; poolSize.type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        poolSize.descriptorCount = FLUID_TEX_BINDINGS * totalSets;
        VkDescriptorPoolCreateInfo pi{}; pi.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        pi.poolSizeCount = 1; pi.pPoolSizes = &poolSize; pi.maxSets = totalSets;
        if (vkCreateDescriptorPool(mDevice, &pi, nullptr, &mFluid.descPool) != VK_SUCCESS) return false;

        VkDescriptorSetLayout layouts[FLUID_PASS_COUNT * MAX_FRAMES_IN_FLIGHT];
        for (uint32_t i = 0; i < totalSets; i++) layouts[i] = mFluid.descLayout;
        VkDescriptorSetAllocateInfo dsai{}; dsai.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        dsai.descriptorPool = mFluid.descPool; dsai.descriptorSetCount = totalSets; dsai.pSetLayouts = layouts;
        if (vkAllocateDescriptorSets(mDevice, &dsai, mFluid.descSets) != VK_SUCCESS) return false;
    }

    // 6. Offscreen targets
    if (!createOffscreenTarget(mFluid.velocity, w, h, VK_FORMAT_R16G16B16A16_SFLOAT, true, true, mFluid.renderPass)) return false;
    if (!createOffscreenTarget(mFluid.pressure, w, h, VK_FORMAT_R16G16B16A16_SFLOAT, true, true, mFluid.renderPass)) return false;
    if (!createOffscreenTarget(mFluid.turbulence, w, h, VK_FORMAT_R16G16B16A16_SFLOAT, false, true, mFluid.renderPass)) return false;
    if (!createOffscreenTarget(mFluid.confinement, w, h, VK_FORMAT_R16G16B16A16_SFLOAT, false, false, mFluid.renderPass)) return false;

    // 7. Pipelines (reuse vertex shader, load 5 fragment shaders)
    auto vertCode = loadShaderFromAsset(mAssetManager, "shaders/fullscreen.vert.spv");
    if (vertCode.empty()) { LOGE("Failed to load vertex shader for fluid"); return false; }
    VkShaderModule vertModule = createShaderModule(mDevice, vertCode);

    const char* fragNames[FLUID_PASS_COUNT] = {
        "shaders/fluid_a.frag.spv", "shaders/fluid_b.frag.spv",
        "shaders/fluid_c.frag.spv", "shaders/fluid_d.frag.spv",
        "shaders/fluid_image.frag.spv"
    };

    // Common pipeline state
    VkPipelineVertexInputStateCreateInfo vertexInput{}; vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    VkPipelineInputAssemblyStateCreateInfo inputAsm{}; inputAsm.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    inputAsm.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkViewport vp{}; vp.width = (float)w; vp.height = (float)h; vp.maxDepth = 1.0f;
    VkRect2D sc{}; sc.extent = mSwapchainExtent;
    VkPipelineViewportStateCreateInfo vpState{}; vpState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    vpState.viewportCount = 1; vpState.pViewports = &vp; vpState.scissorCount = 1; vpState.pScissors = &sc;
    VkPipelineRasterizationStateCreateInfo rast{}; rast.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rast.polygonMode = VK_POLYGON_MODE_FILL; rast.lineWidth = 1.0f; rast.cullMode = VK_CULL_MODE_NONE;
    VkPipelineMultisampleStateCreateInfo ms{}; ms.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineColorBlendAttachmentState cba{}; cba.colorWriteMask = 0xF;
    VkPipelineColorBlendStateCreateInfo cb{}; cb.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    cb.attachmentCount = 1; cb.pAttachments = &cba;
    VkDynamicState dynStates[] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
    VkPipelineDynamicStateCreateInfo dynState{}; dynState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynState.dynamicStateCount = 2; dynState.pDynamicStates = dynStates;

    VkGraphicsPipelineCreateInfo pci{}; pci.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pci.stageCount = 2; pci.pVertexInputState = &vertexInput; pci.pInputAssemblyState = &inputAsm;
    pci.pViewportState = &vpState; pci.pRasterizationState = &rast; pci.pMultisampleState = &ms;
    pci.pColorBlendState = &cb; pci.pDynamicState = &dynState;
    pci.layout = mFluid.pipelineLayout; pci.subpass = 0;

    for (int i = 0; i < FLUID_PASS_COUNT; i++) {
        auto fragCode = loadShaderFromAsset(mAssetManager, fragNames[i]);
        if (fragCode.empty()) { LOGE("Failed to load %s", fragNames[i]); vkDestroyShaderModule(mDevice, vertModule, nullptr); return false; }
        VkShaderModule fragModule = createShaderModule(mDevice, fragCode);

        VkPipelineShaderStageCreateInfo stages[2]{};
        stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT; stages[0].module = vertModule; stages[0].pName = "main";
        stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT; stages[1].module = fragModule; stages[1].pName = "main";
        pci.pStages = stages;

        // buffer passes A-D use fluid renderPass (RGBA16F); image pass uses main renderPass (swapchain)
        pci.renderPass = (i < 4) ? mFluid.renderPass : mRenderPass;

        VkPipeline* target = (i < 4) ? &mFluid.bufferPipelines[i] : &mFluid.imagePipeline;
        if (vkCreateGraphicsPipelines(mDevice, VK_NULL_HANDLE, 1, &pci, nullptr, target) != VK_SUCCESS) {
            LOGE("Failed to create fluid pipeline %d", i);
            vkDestroyShaderModule(mDevice, fragModule, nullptr);
            vkDestroyShaderModule(mDevice, vertModule, nullptr);
            return false;
        }
        vkDestroyShaderModule(mDevice, fragModule, nullptr);
    }
    vkDestroyShaderModule(mDevice, vertModule, nullptr);

    mFluid.initialized = true;
    LOGI("Fluid resources created: %ux%u, vel mips=%u", w, h, mFluid.velocity.mipLevels);
    return true;
}

void VulkanEngine::cleanupFluidResources() {
    if (!mFluid.initialized) return;
    for (int i = 0; i < 4; i++) {
        if (mFluid.bufferPipelines[i] != VK_NULL_HANDLE) { vkDestroyPipeline(mDevice, mFluid.bufferPipelines[i], nullptr); mFluid.bufferPipelines[i] = VK_NULL_HANDLE; }
    }
    if (mFluid.imagePipeline != VK_NULL_HANDLE) { vkDestroyPipeline(mDevice, mFluid.imagePipeline, nullptr); mFluid.imagePipeline = VK_NULL_HANDLE; }
    destroyOffscreenTarget(mFluid.velocity);
    destroyOffscreenTarget(mFluid.pressure);
    destroyOffscreenTarget(mFluid.turbulence);
    destroyOffscreenTarget(mFluid.confinement);
    if (mFluid.descPool != VK_NULL_HANDLE) { vkDestroyDescriptorPool(mDevice, mFluid.descPool, nullptr); mFluid.descPool = VK_NULL_HANDLE; }
    if (mFluid.pipelineLayout != VK_NULL_HANDLE) { vkDestroyPipelineLayout(mDevice, mFluid.pipelineLayout, nullptr); mFluid.pipelineLayout = VK_NULL_HANDLE; }
    if (mFluid.descLayout != VK_NULL_HANDLE) { vkDestroyDescriptorSetLayout(mDevice, mFluid.descLayout, nullptr); mFluid.descLayout = VK_NULL_HANDLE; }
    if (mFluid.sampler != VK_NULL_HANDLE) { vkDestroySampler(mDevice, mFluid.sampler, nullptr); mFluid.sampler = VK_NULL_HANDLE; }
    if (mFluid.renderPass != VK_NULL_HANDLE) { vkDestroyRenderPass(mDevice, mFluid.renderPass, nullptr); mFluid.renderPass = VK_NULL_HANDLE; }
    mFluid.initialized = false;
}

void VulkanEngine::renderFluid(VkCommandBuffer cmd, uint32_t imageIndex, const PushConstants& pc) {
    VkClearValue clear{}; clear.color = {{0,0,0,0}};

    // Offscreen targets are at display dimensions (not swapchain extent).
    uint32_t dispW = mFluid.velocity.width;
    uint32_t dispH = mFluid.velocity.height;

    // Buffer passes: display-sized viewport, preRotate=0, iResolution=display
    VkViewport bufVp{}; bufVp.width = (float)dispW; bufVp.height = (float)dispH; bufVp.maxDepth = 1.0f;
    VkRect2D bufSc{}; bufSc.extent = {dispW, dispH};
    VkExtent2D bufExtent = {dispW, dispH};

    PushConstants bufferPc = pc;
    bufferPc.iResolutionX = (float)dispW;
    bufferPc.iResolutionY = (float)dispH;
    bufferPc.preRotate = 0;

    // Image pass: swapchain-sized viewport, display iResolution, normal preRotate
    VkViewport imgVp{}; imgVp.width = (float)mSwapchainExtent.width; imgVp.height = (float)mSwapchainExtent.height; imgVp.maxDepth = 1.0f;
    VkRect2D imgSc{}; imgSc.extent = mSwapchainExtent;

    // Helper: update a per-frame descriptor set's 4 channels
    auto updateDescSet = [&](int passIdx, VkImageView ch0, VkImageView ch1, VkImageView ch2, VkImageView ch3) {
        int dsIdx = passIdx * MAX_FRAMES_IN_FLIGHT + mCurrentFrame;
        VkImageView channels[FLUID_TEX_BINDINGS] = {ch0, ch1, ch2, ch3};
        VkDescriptorImageInfo infos[FLUID_TEX_BINDINGS]{};
        VkWriteDescriptorSet writes[FLUID_TEX_BINDINGS]{};
        for (int i = 0; i < FLUID_TEX_BINDINGS; i++) {
            infos[i].imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            infos[i].imageView = channels[i] ? channels[i] : mTextures[0].imageView;
            infos[i].sampler = mFluid.sampler;
            writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[i].dstSet = mFluid.descSets[dsIdx];
            writes[i].dstBinding = i;
            writes[i].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
            writes[i].descriptorCount = 1;
            writes[i].pImageInfo = &infos[i];
        }
        vkUpdateDescriptorSets(mDevice, FLUID_TEX_BINDINGS, writes, 0, nullptr);
    };

    // Helper: record one buffer pass (render to RGBA16F offscreen target)
    auto recordBufferPass = [&](int passIdx, OffscreenTarget& target, int targetIdx) {
        int dsIdx = passIdx * MAX_FRAMES_IN_FLIGHT + mCurrentFrame;
        VkRenderPassBeginInfo rpbi{}; rpbi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        rpbi.renderPass = mFluid.renderPass;
        rpbi.framebuffer = target.framebuffer[targetIdx];
        rpbi.renderArea.extent = bufExtent;
        rpbi.clearValueCount = 1; rpbi.pClearValues = &clear;
        vkCmdBeginRenderPass(cmd, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mFluid.bufferPipelines[passIdx]);
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mFluid.pipelineLayout, 0, 1, &mFluid.descSets[dsIdx], 0, nullptr);
        vkCmdSetViewport(cmd, 0, 1, &bufVp);
        vkCmdSetScissor(cmd, 0, 1, &bufSc);
        vkCmdPushConstants(cmd, mFluid.pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(bufferPc), &bufferPc);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(cmd);
    };

    int velSrc = mFluid.velocity.srcIdx;
    int velDst = 1 - velSrc;
    int prsSrc = mFluid.pressure.srcIdx;
    int prsDst = 1 - prsSrc;

    // Pass A: velocity
    updateDescSet(0,
        mFluid.velocity.viewAll[velSrc],
        mFluid.pressure.viewAll[prsSrc],
        mFluid.confinement.viewAll[0],
        mFluid.turbulence.viewAll[0]);
    recordBufferPass(0, mFluid.velocity, velDst);
    recordGenerateMipmaps(cmd, mFluid.velocity, velDst);

    // Pass B: turbulence
    updateDescSet(1,
        mFluid.velocity.viewAll[velDst],
        mTextures[0].imageView,
        mTextures[0].imageView,
        mTextures[0].imageView);
    recordBufferPass(1, mFluid.turbulence, 0);
    recordGenerateMipmaps(cmd, mFluid.turbulence, 0);

    // Pass C: confinement
    updateDescSet(2,
        mFluid.turbulence.viewAll[0],
        mTextures[0].imageView,
        mTextures[0].imageView,
        mTextures[0].imageView);
    recordBufferPass(2, mFluid.confinement, 0);

    // Pass D: pressure
    updateDescSet(3,
        mFluid.velocity.viewAll[velDst],
        mFluid.pressure.viewAll[prsSrc],
        mTextures[0].imageView,
        mTextures[0].imageView);
    recordBufferPass(3, mFluid.pressure, prsDst);
    recordGenerateMipmaps(cmd, mFluid.pressure, prsDst);

    // Image pass: render to swapchain
    updateDescSet(4,
        mFluid.velocity.viewAll[velDst],
        mFluid.pressure.viewAll[prsDst],
        mFluid.turbulence.viewAll[0],
        mFluid.confinement.viewAll[0]);
    {
        VkRenderPassBeginInfo rpbi{}; rpbi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        rpbi.renderPass = mRenderPass;
        rpbi.framebuffer = mFramebuffers[imageIndex];
        rpbi.renderArea.extent = mSwapchainExtent;
        rpbi.clearValueCount = 1; rpbi.pClearValues = &clear;
        vkCmdBeginRenderPass(cmd, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mFluid.imagePipeline);
        int imgDsIdx = 4 * MAX_FRAMES_IN_FLIGHT + mCurrentFrame;
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mFluid.pipelineLayout, 0, 1, &mFluid.descSets[imgDsIdx], 0, nullptr);
        vkCmdSetViewport(cmd, 0, 1, &imgVp);
        vkCmdSetScissor(cmd, 0, 1, &imgSc);
        vkCmdPushConstants(cmd, mFluid.pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(pc), &pc);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(cmd);
    }

    // Swap ping-pong targets
    mFluid.velocity.srcIdx = velDst;
    mFluid.pressure.srcIdx = prsDst;
}

void VulkanEngine::cleanupSwapchain() {
    for (auto fb : mFramebuffers) vkDestroyFramebuffer(mDevice, fb, nullptr);
    mFramebuffers.clear();
    for (auto iv : mSwapchainImageViews) vkDestroyImageView(mDevice, iv, nullptr);
    mSwapchainImageViews.clear();
    if (mSwapchain != VK_NULL_HANDLE) { vkDestroySwapchainKHR(mDevice, mSwapchain, nullptr); mSwapchain = VK_NULL_HANDLE; }
}

void VulkanEngine::recreateSwapchain() {
    vkDeviceWaitIdle(mDevice);
    cleanupFluidResources();
    cleanupHistoryBuffer();
    cleanupSwapchain();
    createSwapchain();
    createFramebuffers();
    createHistoryBuffer();
    if (!createFluidResources()) LOGI("Fluid resources recreation failed (non-fatal)");
}

void VulkanEngine::render() {
    if (!mInitialized || mPaused) return;
    if (mNeedsResize) { mNeedsResize = false; recreateSwapchain(); }

    auto now = std::chrono::high_resolution_clock::now();
    float iTime = std::chrono::duration<float>(now - mStartTime).count();

    vkWaitForFences(mDevice, 1, &mInFlightFences[mCurrentFrame], VK_TRUE, UINT64_MAX);
    uint32_t imageIndex;
    VkResult acq = vkAcquireNextImageKHR(mDevice, mSwapchain, UINT64_MAX,
        mImageAvailableSemaphores[mCurrentFrame], VK_NULL_HANDLE, &imageIndex);
    if (acq == VK_ERROR_OUT_OF_DATE_KHR || acq == VK_SUBOPTIMAL_KHR) return;
    if (acq != VK_SUCCESS) return;
    vkResetFences(mDevice, 1, &mInFlightFences[mCurrentFrame]);

    VkCommandBuffer cmd = mCommandBuffers[mCurrentFrame];
    vkResetCommandBuffer(cmd, 0);
    VkCommandBufferBeginInfo bi{}; bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &bi);

    // Prepare push constants early (needed by both passes)
    PushConstants pc{}; pc.iResolutionX = (float)ANativeWindow_getWidth(mWindow);
    pc.iResolutionY = (float)ANativeWindow_getHeight(mWindow); pc.iTime = iTime;
    pc.iMouseX = mMouseX; pc.iMouseY = mMouseY; pc.iMouseZ = mMouseZ; pc.iMouseW = mMouseW;
    pc.mode = mMode;
    pc.iFrame = mFrameCount;
    switch (mCurrentTransform) {
        case VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR: pc.preRotate = 1; break;
        case VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR: pc.preRotate = 2; break;
        case VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR: pc.preRotate = 3; break;
        default: pc.preRotate = 0; break;
    }

    // Fluid multi-pass path
    bool isFluid = (mCurrentShader == FLUID_SHADER_INDEX && mFluid.initialized);

    // Auto-skip null pipelines (e.g. GPU failed to compile a heavy shader)
    if (!isFluid && mPipelines[mCurrentShader] == VK_NULL_HANDLE) {
        for (int i = 0; i < SHADER_COUNT; i++) {
            mCurrentShader = (mCurrentShader + 1) % SHADER_COUNT;
            if (mPipelines[mCurrentShader] != VK_NULL_HANDLE) break;
        }
    }
    bool pipelineValid = isFluid || (mPipelines[mCurrentShader] != VK_NULL_HANDLE);

    VkClearValue clear{}; clear.color = {{0,0,0,1}};
    VkRenderPassBeginInfo rpbi{}; rpbi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpbi.renderPass = mRenderPass; rpbi.framebuffer = mFramebuffers[imageIndex];
    rpbi.renderArea.extent = mSwapchainExtent; rpbi.clearValueCount = 1; rpbi.pClearValues = &clear;
    // Mode flags
    bool doFxaa = (mCurrentShader == 9 && mMode == 1 && mFxaaPipeline != VK_NULL_HANDLE && mHistoryFramebuffer != VK_NULL_HANDLE);
    bool doHalfRes = (mHalfRes && mHistoryFramebuffer != VK_NULL_HANDLE);
    uint32_t halfW = mSwapchainExtent.width / 2;
    uint32_t halfH = mSwapchainExtent.height / 2;

    // For half-res, use half of display dimensions (preserves aspect ratio)
    PushConstants pcHalf = pc;
    if (doHalfRes) { pcHalf.iResolutionX = pc.iResolutionX / 2.0f; pcHalf.iResolutionY = pc.iResolutionY / 2.0f; }

    // Helper: get descriptor set index for current shader
    auto getDsIndex = [&]() -> int {
        if (mCurrentShader == 3 || mCurrentShader == 6 || mCurrentShader == 8 || mCurrentShader == 16) return 1;
        if (mCurrentShader == 5) return 2;
        if (mCurrentShader == 7) return 3;
        return 0;
    };

    if (!pipelineValid) {
        // Pipeline failed to compile — just clear to black so fences/present still work
        vkCmdBeginRenderPass(cmd, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdEndRenderPass(cmd);
    } else if (isFluid) {
        renderFluid(cmd, imageIndex, pc);
    } else if (doFxaa) {
        // 2-pass FXAA: render to offscreen, then FXAA to swapchain
        VkRenderPassBeginInfo offRpbi{}; offRpbi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        offRpbi.renderPass = mOffscreenRenderPass; offRpbi.framebuffer = mHistoryFramebuffer;
        offRpbi.renderArea.extent = mSwapchainExtent;
        VkClearValue offClear{}; offClear.color = {{0,0,0,1}};
        offRpbi.clearValueCount = 1; offRpbi.pClearValues = &offClear;
        vkCmdBeginRenderPass(cmd, &offRpbi, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mPipelines[mCurrentShader]);
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mPipelineLayout, 0, 1, &mDescriptorSets[getDsIndex()], 0, nullptr);
        VkViewport offVp{}; offVp.width = (float)mSwapchainExtent.width; offVp.height = (float)mSwapchainExtent.height; offVp.maxDepth = 1.0f;
        vkCmdSetViewport(cmd, 0, 1, &offVp);
        VkRect2D offSc{}; offSc.extent = mSwapchainExtent;
        vkCmdSetScissor(cmd, 0, 1, &offSc);
        vkCmdPushConstants(cmd, mPipelineLayout, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(pc), &pc);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(cmd);

        // Pass 2: FXAA
        vkCmdBeginRenderPass(cmd, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mFxaaPipeline);
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mPipelineLayout, 0, 1, &mDescriptorSets[2], 0, nullptr);
        VkViewport vp{}; vp.width = (float)mSwapchainExtent.width; vp.height = (float)mSwapchainExtent.height; vp.maxDepth = 1.0f;
        vkCmdSetViewport(cmd, 0, 1, &vp);
        VkRect2D sc{}; sc.extent = mSwapchainExtent;
        vkCmdSetScissor(cmd, 0, 1, &sc);
        vkCmdPushConstants(cmd, mPipelineLayout, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(pc), &pc);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(cmd);
    } else if (doHalfRes) {
        // Half-res: render to offscreen at half viewport, then blit upscaled to swapchain
        VkRenderPassBeginInfo offRpbi{}; offRpbi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        offRpbi.renderPass = mOffscreenRenderPass; offRpbi.framebuffer = mHistoryFramebuffer;
        offRpbi.renderArea.extent = mSwapchainExtent;
        VkClearValue offClear{}; offClear.color = {{0,0,0,1}};
        offRpbi.clearValueCount = 1; offRpbi.pClearValues = &offClear;
        vkCmdBeginRenderPass(cmd, &offRpbi, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mPipelines[mCurrentShader]);
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mPipelineLayout, 0, 1, &mDescriptorSets[getDsIndex()], 0, nullptr);
        VkViewport halfVp{}; halfVp.width = (float)halfW; halfVp.height = (float)halfH; halfVp.maxDepth = 1.0f;
        vkCmdSetViewport(cmd, 0, 1, &halfVp);
        VkRect2D halfSc{}; halfSc.extent = {halfW, halfH};
        vkCmdSetScissor(cmd, 0, 1, &halfSc);
        vkCmdPushConstants(cmd, mPipelineLayout, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(pcHalf), &pcHalf);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(cmd);
        // History buffer is now SHADER_READ_ONLY_OPTIMAL

        // Blit half-res region to full swapchain
        VkImageMemoryBarrier blitBarriers[2]{};
        // history: SHADER_READ_ONLY → TRANSFER_SRC
        blitBarriers[0].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        blitBarriers[0].oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        blitBarriers[0].newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        blitBarriers[0].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; blitBarriers[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        blitBarriers[0].image = mHistoryImage; blitBarriers[0].subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        blitBarriers[0].srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT; blitBarriers[0].dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        // swapchain: PRESENT_SRC → TRANSFER_DST
        blitBarriers[1].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        blitBarriers[1].oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        blitBarriers[1].newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        blitBarriers[1].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; blitBarriers[1].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        blitBarriers[1].image = mSwapchainImages[imageIndex]; blitBarriers[1].subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        blitBarriers[1].dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 2, blitBarriers);

        VkImageBlit blitRegion{};
        blitRegion.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        blitRegion.srcOffsets[0] = {0, 0, 0};
        blitRegion.srcOffsets[1] = {(int32_t)halfW, (int32_t)halfH, 1};
        blitRegion.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        blitRegion.dstOffsets[0] = {0, 0, 0};
        blitRegion.dstOffsets[1] = {(int32_t)mSwapchainExtent.width, (int32_t)mSwapchainExtent.height, 1};
        vkCmdBlitImage(cmd, mHistoryImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                       mSwapchainImages[imageIndex], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blitRegion, VK_FILTER_LINEAR);

        // Transition back
        blitBarriers[0].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        blitBarriers[0].newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        blitBarriers[0].srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT; blitBarriers[0].dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        blitBarriers[1].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        blitBarriers[1].newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        blitBarriers[1].srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; blitBarriers[1].dstAccessMask = 0;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
                             0, 0, nullptr, 0, nullptr, 2, blitBarriers);
    } else {
        // Normal: render directly to swapchain
        vkCmdBeginRenderPass(cmd, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mPipelines[mCurrentShader]);
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mPipelineLayout, 0, 1, &mDescriptorSets[getDsIndex()], 0, nullptr);
        VkViewport vp{}; vp.width = (float)mSwapchainExtent.width; vp.height = (float)mSwapchainExtent.height; vp.maxDepth = 1.0f;
        vkCmdSetViewport(cmd, 0, 1, &vp);
        VkRect2D sc{}; sc.extent = mSwapchainExtent;
        vkCmdSetScissor(cmd, 0, 1, &sc);
        vkCmdPushConstants(cmd, mPipelineLayout, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(pc), &pc);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(cmd);
    }

    // Copy swapchain to history buffer for temporal reprojection (rainforest + mode==1)
    if (mCurrentShader == 5 && mMode == 1 && mHistoryImage != VK_NULL_HANDLE) {
        // Transition swapchain: PRESENT_SRC → TRANSFER_SRC
        VkImageMemoryBarrier barriers[2]{};
        barriers[0].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barriers[0].oldLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        barriers[0].newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barriers[0].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barriers[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barriers[0].image = mSwapchainImages[imageIndex];
        barriers[0].subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        barriers[0].srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        barriers[0].dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        // Transition history: SHADER_READ_ONLY → TRANSFER_DST
        barriers[1].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barriers[1].oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barriers[1].newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barriers[1].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barriers[1].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barriers[1].image = mHistoryImage;
        barriers[1].subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        barriers[1].srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
        barriers[1].dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                             VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 2, barriers);

        // Copy
        VkImageCopy region{};
        region.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        region.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        region.extent = {mSwapchainExtent.width, mSwapchainExtent.height, 1};
        vkCmdCopyImage(cmd, mSwapchainImages[imageIndex], VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                       mHistoryImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

        // Transition back: swapchain → PRESENT_SRC, history → SHADER_READ_ONLY
        barriers[0].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barriers[0].newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        barriers[0].srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        barriers[0].dstAccessMask = 0;
        barriers[1].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barriers[1].newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barriers[1].srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barriers[1].dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT,
                             VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
                             0, 0, nullptr, 0, nullptr, 2, barriers);
    }

    vkEndCommandBuffer(cmd);

    VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo si{}; si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.waitSemaphoreCount = 1; si.pWaitSemaphores = &mImageAvailableSemaphores[mCurrentFrame];
    si.pWaitDstStageMask = &waitStage; si.commandBufferCount = 1; si.pCommandBuffers = &cmd;
    si.signalSemaphoreCount = 1; si.pSignalSemaphores = &mRenderFinishedSemaphores[mCurrentFrame];
    if (vkQueueSubmit(mQueue, 1, &si, mInFlightFences[mCurrentFrame]) != VK_SUCCESS) return;

    VkPresentInfoKHR pi{}; pi.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    pi.waitSemaphoreCount = 1; pi.pWaitSemaphores = &mRenderFinishedSemaphores[mCurrentFrame];
    pi.swapchainCount = 1; pi.pSwapchains = &mSwapchain; pi.pImageIndices = &imageIndex;
    if (vkQueuePresentKHR(mQueue, &pi) == VK_ERROR_OUT_OF_DATE_KHR) mNeedsResize = true;
    mCurrentFrame = (mCurrentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
    mFrameCount++;
}

void VulkanEngine::onResize(uint32_t w, uint32_t h) { if (w && h) mNeedsResize = true; }

void VulkanEngine::toggleShader() {
    for (int i = 0; i < TOTAL_SHADER_COUNT; i++) {
        mCurrentShader = (mCurrentShader + 1) % TOTAL_SHADER_COUNT;
        if (mCurrentShader == FLUID_SHADER_INDEX) {
            if (mFluid.initialized) break;
        } else {
            if (mPipelines[mCurrentShader] != VK_NULL_HANDLE) break;
        }
    }
    mFrameCount = 0;
    LOGI("Switched to shader %d%s", mCurrentShader, mCurrentShader == FLUID_SHADER_INDEX ? " (fluid)" : "");
}

void VulkanEngine::prevShader() {
    for (int i = 0; i < TOTAL_SHADER_COUNT; i++) {
        mCurrentShader = (mCurrentShader - 1 + TOTAL_SHADER_COUNT) % TOTAL_SHADER_COUNT;
        if (mCurrentShader == FLUID_SHADER_INDEX) {
            if (mFluid.initialized) break;
        } else {
            if (mPipelines[mCurrentShader] != VK_NULL_HANDLE) break;
        }
    }
    mFrameCount = 0;
    LOGI("Switched to shader %d%s", mCurrentShader, mCurrentShader == FLUID_SHADER_INDEX ? " (fluid)" : "");
}

void VulkanEngine::toggleMode() {
    mMode = (mMode + 1) % 2;
    mFrameCount = 0;
    LOGI("Switched to mode %d", mMode);
}

void VulkanEngine::toggleHalfRes() {
    mHalfRes = !mHalfRes;
    LOGI("Half-res: %s", mHalfRes ? "ON" : "OFF");
}

void VulkanEngine::onTouch(float x, float y, int action) {
    // x,y in pixel coordinates (Y flipped by caller for Shadertoy convention)

    // Fluid: absolute touch position (Shadertoy convention)
    if (mCurrentShader == FLUID_SHADER_INDEX) {
        if (action == 0) { // DOWN
            mMousePressed = true;
            mMouseX = x; mMouseY = y;
            mMouseZ = x; mMouseW = y;
        } else if (action == 1) { // MOVE
            if (mMousePressed) { mMouseX = x; mMouseY = y; }
        } else { // UP
            mMousePressed = false;
        }
        return;
    }

    // Other shaders: relative/trackpad style
    if (!mMouseInitialized) {
        mMouseX = (float)ANativeWindow_getWidth(mWindow) * 0.5f;
        mMouseY = (float)ANativeWindow_getHeight(mWindow) * 0.4f;
        mMouseInitialized = true;
    }

    if (action == 0) { // DOWN - record start positions for relative movement
        mMousePressed = true;
        mTouchStartX = x;
        mTouchStartY = y;
        mVirtualStartX = mMouseX;
        mVirtualStartY = mMouseY;
        mMouseZ = mMouseX; // positive z = button pressed
        mMouseW = mMouseY;
    } else if (action == 1) { // MOVE - apply delta from touch start
        if (mMousePressed) {
            mMouseX = mVirtualStartX + (x - mTouchStartX);
            mMouseY = mVirtualStartY + (y - mTouchStartY);
        }
    } else { // UP - keep z positive so shader holds position
        mMousePressed = false;
    }
}
