#include "vulkan_engine.h"
#include <android/log.h>
#include <cstring>
#include <algorithm>

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

    if (mGraphicsPipeline != VK_NULL_HANDLE) vkDestroyPipeline(mDevice, mGraphicsPipeline, nullptr);
    if (mGraphicsPipeline2 != VK_NULL_HANDLE) vkDestroyPipeline(mDevice, mGraphicsPipeline2, nullptr);
    if (mPipelineLayout != VK_NULL_HANDLE) vkDestroyPipelineLayout(mDevice, mPipelineLayout, nullptr);

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
    if (!createGraphicsPipeline()) return false;

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

    // Destroy old surface
    if (mSurface != VK_NULL_HANDLE) {
        vkDestroySurfaceKHR(mInstance, mSurface, nullptr);
        mSurface = VK_NULL_HANDLE;
    }

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

    if (mSurface != VK_NULL_HANDLE) {
        vkDestroySurfaceKHR(mInstance, mSurface, nullptr);
        mSurface = VK_NULL_HANDLE;
    }

    mPaused = true;
    LOGI("Surface cleaned up (engine kept alive)");
}

bool VulkanEngine::createInstance() {
    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Sparks";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "SparksEngine";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_1;

    const char* extensions[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_ANDROID_SURFACE_EXTENSION_NAME
    };

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = 2;
    createInfo.ppEnabledExtensionNames = extensions;

    VkResult result = vkCreateInstance(&createInfo, nullptr, &mInstance);
    if (result != VK_SUCCESS) {
        LOGE("Failed to create Vulkan instance: %d", result);
        return false;
    }

    LOGI("Vulkan instance created");
    return true;
}

bool VulkanEngine::createSurface() {
    VkAndroidSurfaceCreateInfoKHR createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR;
    createInfo.window = mWindow;

    VkResult result = vkCreateAndroidSurfaceKHR(mInstance, &createInfo, nullptr, &mSurface);
    if (result != VK_SUCCESS) {
        LOGE("Failed to create Android surface: %d", result);
        return false;
    }

    LOGI("Android surface created");
    return true;
}

bool VulkanEngine::pickPhysicalDevice() {
    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(mInstance, &deviceCount, nullptr);
    if (deviceCount == 0) {
        LOGE("No Vulkan physical devices found");
        return false;
    }

    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(mInstance, &deviceCount, devices.data());

    for (const auto& device : devices) {
        uint32_t queueFamilyCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nullptr);
        std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.data());

        for (uint32_t i = 0; i < queueFamilyCount; i++) {
            bool hasGraphics = (queueFamilies[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0;

            VkBool32 presentSupport = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(device, i, mSurface, &presentSupport);

            if (hasGraphics && presentSupport) {
                mPhysicalDevice = device;
                mQueueFamilyIndex = i;

                VkPhysicalDeviceProperties props;
                vkGetPhysicalDeviceProperties(device, &props);
                LOGI("Selected GPU: %s (queue family %u)", props.deviceName, i);
                return true;
            }
        }
    }

    LOGE("No suitable physical device found");
    return false;
}

bool VulkanEngine::createLogicalDevice() {
    float queuePriority = 1.0f;

    VkDeviceQueueCreateInfo queueCreateInfo{};
    queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfo.queueFamilyIndex = mQueueFamilyIndex;
    queueCreateInfo.queueCount = 1;
    queueCreateInfo.pQueuePriorities = &queuePriority;

    const char* deviceExtensions[] = {
        VK_KHR_SWAPCHAIN_EXTENSION_NAME
    };

    VkDeviceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    createInfo.queueCreateInfoCount = 1;
    createInfo.pQueueCreateInfos = &queueCreateInfo;
    createInfo.enabledExtensionCount = 1;
    createInfo.ppEnabledExtensionNames = deviceExtensions;

    VkResult result = vkCreateDevice(mPhysicalDevice, &createInfo, nullptr, &mDevice);
    if (result != VK_SUCCESS) {
        LOGE("Failed to create logical device: %d", result);
        return false;
    }

    vkGetDeviceQueue(mDevice, mQueueFamilyIndex, 0, &mQueue);
    LOGI("Logical device created");
    return true;
}

bool VulkanEngine::createSwapchain() {
    VkSurfaceCapabilitiesKHR capabilities;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(mPhysicalDevice, mSurface, &capabilities);

    if (capabilities.currentExtent.width != UINT32_MAX) {
        mSwapchainExtent = capabilities.currentExtent;
    } else {
        mSwapchainExtent.width = ANativeWindow_getWidth(mWindow);
        mSwapchainExtent.height = ANativeWindow_getHeight(mWindow);
        mSwapchainExtent.width = std::max(capabilities.minImageExtent.width,
                                          std::min(capabilities.maxImageExtent.width, mSwapchainExtent.width));
        mSwapchainExtent.height = std::max(capabilities.minImageExtent.height,
                                           std::min(capabilities.maxImageExtent.height, mSwapchainExtent.height));
    }

    // Track the current surface transform so we can derive the real display
    // orientation when passing iResolution to the shader.
    mCurrentTransform = capabilities.currentTransform;

    uint32_t imageCount = 2;
    if (imageCount < capabilities.minImageCount) imageCount = capabilities.minImageCount;
    if (capabilities.maxImageCount > 0 && imageCount > capabilities.maxImageCount) {
        imageCount = capabilities.maxImageCount;
    }

    uint32_t formatCount = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(mPhysicalDevice, mSurface, &formatCount, nullptr);
    std::vector<VkSurfaceFormatKHR> formats(formatCount);
    vkGetPhysicalDeviceSurfaceFormatsKHR(mPhysicalDevice, mSurface, &formatCount, formats.data());

    mSwapchainFormat = formats[0].format;
    VkColorSpaceKHR colorSpace = formats[0].colorSpace;
    for (const auto& fmt : formats) {
        if (fmt.format == VK_FORMAT_R8G8B8A8_UNORM) {
            mSwapchainFormat = fmt.format;
            colorSpace = fmt.colorSpace;
            break;
        }
    }

    VkSwapchainCreateInfoKHR createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    createInfo.surface = mSurface;
    createInfo.minImageCount = imageCount;
    createInfo.imageFormat = mSwapchainFormat;
    createInfo.imageColorSpace = colorSpace;
    createInfo.imageExtent = mSwapchainExtent;
    createInfo.imageArrayLayers = 1;
    createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    createInfo.preTransform = capabilities.currentTransform;
    createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
    createInfo.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    createInfo.clipped = VK_TRUE;

    VkResult result = vkCreateSwapchainKHR(mDevice, &createInfo, nullptr, &mSwapchain);
    if (result != VK_SUCCESS) {
        LOGE("Failed to create swapchain: %d", result);
        return false;
    }

    vkGetSwapchainImagesKHR(mDevice, mSwapchain, &imageCount, nullptr);
    mSwapchainImages.resize(imageCount);
    vkGetSwapchainImagesKHR(mDevice, mSwapchain, &imageCount, mSwapchainImages.data());

    mSwapchainImageViews.resize(imageCount);
    for (uint32_t i = 0; i < imageCount; i++) {
        VkImageViewCreateInfo viewInfo{};
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        viewInfo.image = mSwapchainImages[i];
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = mSwapchainFormat;
        viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        viewInfo.subresourceRange.levelCount = 1;
        viewInfo.subresourceRange.layerCount = 1;

        if (vkCreateImageView(mDevice, &viewInfo, nullptr, &mSwapchainImageViews[i]) != VK_SUCCESS) {
            LOGE("Failed to create image view %u", i);
            return false;
        }
    }

    LOGI("Swapchain created: %ux%u, %u images", mSwapchainExtent.width, mSwapchainExtent.height, imageCount);
    return true;
}

bool VulkanEngine::createRenderPass() {
    VkAttachmentDescription colorAttachment{};
    colorAttachment.format = mSwapchainFormat;
    colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
    colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE; // Fullscreen shader overwrites every pixel
    colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

    VkAttachmentReference colorRef{};
    colorRef.attachment = 0;
    colorRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkSubpassDescription subpass{};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorRef;

    VkSubpassDependency dependency{};
    dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;
    dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.srcAccessMask = 0;
    dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

    VkRenderPassCreateInfo renderPassInfo{};
    renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    renderPassInfo.attachmentCount = 1;
    renderPassInfo.pAttachments = &colorAttachment;
    renderPassInfo.subpassCount = 1;
    renderPassInfo.pSubpasses = &subpass;
    renderPassInfo.dependencyCount = 1;
    renderPassInfo.pDependencies = &dependency;

    if (vkCreateRenderPass(mDevice, &renderPassInfo, nullptr, &mRenderPass) != VK_SUCCESS) {
        LOGE("Failed to create render pass");
        return false;
    }

    return true;
}

bool VulkanEngine::createFramebuffers() {
    mFramebuffers.resize(mSwapchainImageViews.size());

    for (size_t i = 0; i < mSwapchainImageViews.size(); i++) {
        VkFramebufferCreateInfo fbInfo{};
        fbInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        fbInfo.renderPass = mRenderPass;
        fbInfo.attachmentCount = 1;
        fbInfo.pAttachments = &mSwapchainImageViews[i];
        fbInfo.width = mSwapchainExtent.width;
        fbInfo.height = mSwapchainExtent.height;
        fbInfo.layers = 1;

        if (vkCreateFramebuffer(mDevice, &fbInfo, nullptr, &mFramebuffers[i]) != VK_SUCCESS) {
            LOGE("Failed to create framebuffer %zu", i);
            return false;
        }
    }

    return true;
}

bool VulkanEngine::createCommandPool() {
    VkCommandPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.queueFamilyIndex = mQueueFamilyIndex;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;

    if (vkCreateCommandPool(mDevice, &poolInfo, nullptr, &mCommandPool) != VK_SUCCESS) {
        LOGE("Failed to create command pool");
        return false;
    }

    return true;
}

bool VulkanEngine::createCommandBuffers() {
    mCommandBuffers.resize(MAX_FRAMES_IN_FLIGHT);

    VkCommandBufferAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.commandPool = mCommandPool;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = MAX_FRAMES_IN_FLIGHT;

    if (vkAllocateCommandBuffers(mDevice, &allocInfo, mCommandBuffers.data()) != VK_SUCCESS) {
        LOGE("Failed to allocate command buffers");
        return false;
    }

    return true;
}

bool VulkanEngine::createSyncObjects() {
    mImageAvailableSemaphores.resize(MAX_FRAMES_IN_FLIGHT);
    mRenderFinishedSemaphores.resize(MAX_FRAMES_IN_FLIGHT);
    mInFlightFences.resize(MAX_FRAMES_IN_FLIGHT);

    VkSemaphoreCreateInfo semInfo{};
    semInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;

    for (uint32_t i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
        if (vkCreateSemaphore(mDevice, &semInfo, nullptr, &mImageAvailableSemaphores[i]) != VK_SUCCESS ||
            vkCreateSemaphore(mDevice, &semInfo, nullptr, &mRenderFinishedSemaphores[i]) != VK_SUCCESS ||
            vkCreateFence(mDevice, &fenceInfo, nullptr, &mInFlightFences[i]) != VK_SUCCESS) {
            LOGE("Failed to create sync objects for frame %u", i);
            return false;
        }
    }

    return true;
}

bool VulkanEngine::createGraphicsPipeline() {
    auto vertCode = loadShaderFromAsset(mAssetManager, "shaders/fullscreen.vert.spv");
    auto fragCode1 = loadShaderFromAsset(mAssetManager, "shaders/sparks.frag.spv");
    auto fragCode2 = loadShaderFromAsset(mAssetManager, "shaders/cosmic.frag.spv");
    if (vertCode.empty() || fragCode1.empty() || fragCode2.empty()) {
        LOGE("Failed to load shaders");
        return false;
    }

    VkShaderModule vertModule = createShaderModule(mDevice, vertCode);
    VkShaderModule fragModule1 = createShaderModule(mDevice, fragCode1);
    VkShaderModule fragModule2 = createShaderModule(mDevice, fragCode2);
    if (vertModule == VK_NULL_HANDLE || fragModule1 == VK_NULL_HANDLE || fragModule2 == VK_NULL_HANDLE) {
        LOGE("Failed to create shader modules");
        return false;
    }

    // No vertex input - fullscreen triangle generated in vertex shader
    VkPipelineVertexInputStateCreateInfo vertexInputInfo{};
    vertexInputInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

    VkPipelineInputAssemblyStateCreateInfo inputAssembly{};
    inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    VkViewport viewport{};
    viewport.width = static_cast<float>(mSwapchainExtent.width);
    viewport.height = static_cast<float>(mSwapchainExtent.height);
    viewport.maxDepth = 1.0f;

    VkRect2D scissor{};
    scissor.extent = mSwapchainExtent;

    VkPipelineViewportStateCreateInfo viewportState{};
    viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewportState.viewportCount = 1;
    viewportState.pViewports = &viewport;
    viewportState.scissorCount = 1;
    viewportState.pScissors = &scissor;

    VkPipelineRasterizationStateCreateInfo rasterizer{};
    rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
    rasterizer.lineWidth = 1.0f;
    rasterizer.cullMode = VK_CULL_MODE_NONE;

    VkPipelineMultisampleStateCreateInfo multisampling{};
    multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineColorBlendAttachmentState colorBlendAttachment{};
    colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                                          VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;

    VkPipelineColorBlendStateCreateInfo colorBlending{};
    colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    colorBlending.attachmentCount = 1;
    colorBlending.pAttachments = &colorBlendAttachment;

    // Push constants: iResolution (vec2) + iTime (float) + preRotate (int) = 16 bytes
    VkPushConstantRange pushConstantRange{};
    pushConstantRange.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
    pushConstantRange.offset = 0;
    pushConstantRange.size = sizeof(PushConstants);

    VkPipelineLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    layoutInfo.pushConstantRangeCount = 1;
    layoutInfo.pPushConstantRanges = &pushConstantRange;

    if (vkCreatePipelineLayout(mDevice, &layoutInfo, nullptr, &mPipelineLayout) != VK_SUCCESS) {
        LOGE("Failed to create pipeline layout");
        return false;
    }

    // Dynamic viewport and scissor for resize
    VkDynamicState dynamicStates[] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
    VkPipelineDynamicStateCreateInfo dynamicState{};
    dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamicState.dynamicStateCount = 2;
    dynamicState.pDynamicStates = dynamicStates;

    // Shared pipeline create info
    VkGraphicsPipelineCreateInfo pipelineInfo{};
    pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pipelineInfo.stageCount = 2;
    pipelineInfo.pVertexInputState = &vertexInputInfo;
    pipelineInfo.pInputAssemblyState = &inputAssembly;
    pipelineInfo.pViewportState = &viewportState;
    pipelineInfo.pRasterizationState = &rasterizer;
    pipelineInfo.pMultisampleState = &multisampling;
    pipelineInfo.pColorBlendState = &colorBlending;
    pipelineInfo.pDynamicState = &dynamicState;
    pipelineInfo.layout = mPipelineLayout;
    pipelineInfo.renderPass = mRenderPass;
    pipelineInfo.subpass = 0;

    // Pipeline 1: sparks
    VkPipelineShaderStageCreateInfo stages1[2]{};
    stages1[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages1[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages1[0].module = vertModule;
    stages1[0].pName = "main";
    stages1[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages1[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages1[1].module = fragModule1;
    stages1[1].pName = "main";

    pipelineInfo.pStages = stages1;
    VkResult result = vkCreateGraphicsPipelines(mDevice, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &mGraphicsPipeline);
    if (result != VK_SUCCESS) {
        LOGE("Failed to create graphics pipeline 1: %d", result);
        vkDestroyShaderModule(mDevice, vertModule, nullptr);
        vkDestroyShaderModule(mDevice, fragModule1, nullptr);
        vkDestroyShaderModule(mDevice, fragModule2, nullptr);
        return false;
    }

    // Pipeline 2: cosmic
    VkPipelineShaderStageCreateInfo stages2[2]{};
    stages2[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages2[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages2[0].module = vertModule;
    stages2[0].pName = "main";
    stages2[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages2[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages2[1].module = fragModule2;
    stages2[1].pName = "main";

    pipelineInfo.pStages = stages2;
    result = vkCreateGraphicsPipelines(mDevice, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &mGraphicsPipeline2);

    vkDestroyShaderModule(mDevice, vertModule, nullptr);
    vkDestroyShaderModule(mDevice, fragModule1, nullptr);
    vkDestroyShaderModule(mDevice, fragModule2, nullptr);

    if (result != VK_SUCCESS) {
        LOGE("Failed to create graphics pipeline 2: %d", result);
        return false;
    }

    LOGI("Both graphics pipelines created");
    return true;
}

void VulkanEngine::cleanupSwapchain() {
    for (auto fb : mFramebuffers) {
        vkDestroyFramebuffer(mDevice, fb, nullptr);
    }
    mFramebuffers.clear();

    for (auto iv : mSwapchainImageViews) {
        vkDestroyImageView(mDevice, iv, nullptr);
    }
    mSwapchainImageViews.clear();

    if (mSwapchain != VK_NULL_HANDLE) {
        vkDestroySwapchainKHR(mDevice, mSwapchain, nullptr);
        mSwapchain = VK_NULL_HANDLE;
    }
}

void VulkanEngine::recreateSwapchain() {
    vkDeviceWaitIdle(mDevice);
    cleanupSwapchain();
    createSwapchain();
    createFramebuffers();
    // Pipeline uses dynamic viewport/scissor, no need to recreate
}

void VulkanEngine::render() {
    if (!mInitialized || mPaused) return;

    if (mNeedsResize) {
        mNeedsResize = false;
        recreateSwapchain();
    }

    // Calculate elapsed time
    auto now = std::chrono::high_resolution_clock::now();
    float iTime = std::chrono::duration<float>(now - mStartTime).count();

    // Wait for this frame's fence
    vkWaitForFences(mDevice, 1, &mInFlightFences[mCurrentFrame], VK_TRUE, UINT64_MAX);

    uint32_t imageIndex;
    VkResult acquireResult = vkAcquireNextImageKHR(mDevice, mSwapchain, UINT64_MAX,
                                                    mImageAvailableSemaphores[mCurrentFrame],
                                                    VK_NULL_HANDLE, &imageIndex);

    if (acquireResult == VK_ERROR_OUT_OF_DATE_KHR || acquireResult == VK_SUBOPTIMAL_KHR) {
        // Don't recreate here — wait for surfaceChanged to provide stable dimensions.
        // Just skip this frame.
        return;
    }
    if (acquireResult != VK_SUCCESS) {
        LOGE("Failed to acquire swapchain image: %d", acquireResult);
        return;
    }

    vkResetFences(mDevice, 1, &mInFlightFences[mCurrentFrame]);

    VkCommandBuffer cmd = mCommandBuffers[mCurrentFrame];
    vkResetCommandBuffer(cmd, 0);

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &beginInfo);

    // Begin render pass
    VkRenderPassBeginInfo rpBegin{};
    rpBegin.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpBegin.renderPass = mRenderPass;
    rpBegin.framebuffer = mFramebuffers[imageIndex];
    rpBegin.renderArea.extent = mSwapchainExtent;
    VkClearValue clearColor{};
    clearColor.color = {{0.0f, 0.0f, 0.0f, 1.0f}};
    rpBegin.clearValueCount = 1;
    rpBegin.pClearValues = &clearColor;

    vkCmdBeginRenderPass(cmd, &rpBegin, VK_SUBPASS_CONTENTS_INLINE);

    VkPipeline activePipeline = (mCurrentShader == 0) ? mGraphicsPipeline : mGraphicsPipeline2;
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, activePipeline);

    // Set dynamic viewport and scissor
    VkViewport viewport{};
    viewport.width = static_cast<float>(mSwapchainExtent.width);
    viewport.height = static_cast<float>(mSwapchainExtent.height);
    viewport.maxDepth = 1.0f;
    vkCmdSetViewport(cmd, 0, 1, &viewport);

    VkRect2D scissor{};
    scissor.extent = mSwapchainExtent;
    vkCmdSetScissor(cmd, 0, 1, &scissor);

    // Push constants: iResolution + iTime + preRotate
    // iResolution = actual display dimensions from ANativeWindow.
    // preRotate tells the vertex shader how to rotate UVs to compensate for
    // the Vulkan surface preTransform (framebuffer may be rotated vs display).
    PushConstants pc{};
    pc.iResolutionX = static_cast<float>(ANativeWindow_getWidth(mWindow));
    pc.iResolutionY = static_cast<float>(ANativeWindow_getHeight(mWindow));
    pc.iTime = iTime;

    switch (mCurrentTransform) {
        case VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR:  pc.preRotate = 1; break;
        case VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR: pc.preRotate = 2; break;
        case VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR: pc.preRotate = 3; break;
        default:                                       pc.preRotate = 0; break;
    }

    vkCmdPushConstants(cmd, mPipelineLayout, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                       0, sizeof(PushConstants), &pc);

    // Draw fullscreen triangle (3 vertices, no vertex buffer)
    vkCmdDraw(cmd, 3, 1, 0, 0);

    vkCmdEndRenderPass(cmd);
    vkEndCommandBuffer(cmd);

    // Submit
    VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.waitSemaphoreCount = 1;
    submitInfo.pWaitSemaphores = &mImageAvailableSemaphores[mCurrentFrame];
    submitInfo.pWaitDstStageMask = &waitStage;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmd;
    submitInfo.signalSemaphoreCount = 1;
    submitInfo.pSignalSemaphores = &mRenderFinishedSemaphores[mCurrentFrame];

    if (vkQueueSubmit(mQueue, 1, &submitInfo, mInFlightFences[mCurrentFrame]) != VK_SUCCESS) {
        LOGE("Failed to submit draw command buffer");
        return;
    }

    // Present
    VkPresentInfoKHR presentInfo{};
    presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    presentInfo.waitSemaphoreCount = 1;
    presentInfo.pWaitSemaphores = &mRenderFinishedSemaphores[mCurrentFrame];
    presentInfo.swapchainCount = 1;
    presentInfo.pSwapchains = &mSwapchain;
    presentInfo.pImageIndices = &imageIndex;

    VkResult presentResult = vkQueuePresentKHR(mQueue, &presentInfo);
    if (presentResult == VK_ERROR_OUT_OF_DATE_KHR) {
        // Swapchain is stale. surfaceChanged will trigger a proper resize.
        mNeedsResize = true;
    }

    mCurrentFrame = (mCurrentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
}

void VulkanEngine::onResize(uint32_t width, uint32_t height) {
    if (width == 0 || height == 0) return;
    mNeedsResize = true;
}

void VulkanEngine::toggleShader() {
    mCurrentShader = (mCurrentShader + 1) % 2;
    LOGI("Switched to shader %d", mCurrentShader);
}
