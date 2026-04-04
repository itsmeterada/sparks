#include "particle_system.h"
#include <android/log.h>
#include <cstring>

#define LOG_TAG "ParticleSystem"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

bool ParticleSystem::init(VkDevice device, VkPhysicalDevice physicalDevice,
                          VkCommandPool commandPool, VkQueue queue,
                          VkRenderPass renderPass, uint32_t width, uint32_t height,
                          AAssetManager* assetManager) {
    mDevice = device;
    mPhysicalDevice = physicalDevice;

    mSimParams.maxParticles = MAX_PARTICLES;
    mSimParams.gravity = -9.8f;
    mSimParams.damping = 0.985f;
    mSimParams.baseLifetime = 2.0f;
    mSimParams.lifetimeVariance = 0.8f;
    mSimParams.sparkBrightness = 1.5f;
    mSimParams.frameNumber = 0;
    mSimParams.emitCount = 0;

    if (!createParticleBuffer(device, physicalDevice, commandPool, queue)) return false;
    if (!createUniformBuffer(device, physicalDevice)) return false;
    if (!createDescriptors(device)) return false;
    if (!createComputePipeline(device, assetManager)) return false;
    if (!createGraphicsPipeline(device, renderPass, width, height, assetManager)) return false;

    LOGI("ParticleSystem initialized with %u max particles", MAX_PARTICLES);
    return true;
}

void ParticleSystem::cleanup(VkDevice device) {
    vkDeviceWaitIdle(device);

    if (mComputePipeline != VK_NULL_HANDLE) vkDestroyPipeline(device, mComputePipeline, nullptr);
    if (mComputePipelineLayout != VK_NULL_HANDLE) vkDestroyPipelineLayout(device, mComputePipelineLayout, nullptr);
    if (mGraphicsPipeline != VK_NULL_HANDLE) vkDestroyPipeline(device, mGraphicsPipeline, nullptr);
    if (mGraphicsPipelineLayout != VK_NULL_HANDLE) vkDestroyPipelineLayout(device, mGraphicsPipelineLayout, nullptr);
    if (mDescriptorPool != VK_NULL_HANDLE) vkDestroyDescriptorPool(device, mDescriptorPool, nullptr);
    if (mDescriptorSetLayout != VK_NULL_HANDLE) vkDestroyDescriptorSetLayout(device, mDescriptorSetLayout, nullptr);

    if (mUniformBuffer != VK_NULL_HANDLE) {
        if (mUniformMapped != nullptr) {
            vkUnmapMemory(device, mUniformMemory);
            mUniformMapped = nullptr;
        }
        vkDestroyBuffer(device, mUniformBuffer, nullptr);
        vkFreeMemory(device, mUniformMemory, nullptr);
    }

    if (mParticleBuffer != VK_NULL_HANDLE) {
        vkDestroyBuffer(device, mParticleBuffer, nullptr);
        vkFreeMemory(device, mParticleMemory, nullptr);
    }
}

bool ParticleSystem::createParticleBuffer(VkDevice device, VkPhysicalDevice physicalDevice,
                                          VkCommandPool commandPool, VkQueue queue) {
    VkDeviceSize bufferSize = sizeof(Particle) * MAX_PARTICLES;

    // Create staging buffer
    BufferAndMemory staging = createBuffer(device, physicalDevice, bufferSize,
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (staging.buffer == VK_NULL_HANDLE) return false;

    // Zero out staging buffer
    void* data;
    vkMapMemory(device, staging.memory, 0, bufferSize, 0, &data);
    memset(data, 0, static_cast<size_t>(bufferSize));
    vkUnmapMemory(device, staging.memory);

    // Create device-local particle buffer
    BufferAndMemory particleBuf = createBuffer(device, physicalDevice, bufferSize,
        VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (particleBuf.buffer == VK_NULL_HANDLE) {
        vkDestroyBuffer(device, staging.buffer, nullptr);
        vkFreeMemory(device, staging.memory, nullptr);
        return false;
    }

    mParticleBuffer = particleBuf.buffer;
    mParticleMemory = particleBuf.memory;

    // Copy staging to device
    VkCommandBufferAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.commandPool = commandPool;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = 1;

    VkCommandBuffer cmd;
    vkAllocateCommandBuffers(device, &allocInfo, &cmd);

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &beginInfo);

    VkBufferCopy copyRegion{};
    copyRegion.size = bufferSize;
    vkCmdCopyBuffer(cmd, staging.buffer, mParticleBuffer, 1, &copyRegion);

    vkEndCommandBuffer(cmd);

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmd;

    vkQueueSubmit(queue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(queue);

    vkFreeCommandBuffers(device, commandPool, 1, &cmd);
    vkDestroyBuffer(device, staging.buffer, nullptr);
    vkFreeMemory(device, staging.memory, nullptr);

    LOGI("Particle buffer created: %zu bytes", static_cast<size_t>(bufferSize));
    return true;
}

bool ParticleSystem::createUniformBuffer(VkDevice device, VkPhysicalDevice physicalDevice) {
    VkDeviceSize bufferSize = sizeof(SimParams);

    BufferAndMemory uniformBuf = createBuffer(device, physicalDevice, bufferSize,
        VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (uniformBuf.buffer == VK_NULL_HANDLE) return false;

    mUniformBuffer = uniformBuf.buffer;
    mUniformMemory = uniformBuf.memory;

    vkMapMemory(device, mUniformMemory, 0, bufferSize, 0, &mUniformMapped);
    memcpy(mUniformMapped, &mSimParams, sizeof(SimParams));

    return true;
}

bool ParticleSystem::createDescriptors(VkDevice device) {
    // Descriptor set layout: binding 0 = SSBO, binding 1 = UBO
    VkDescriptorSetLayoutBinding bindings[2]{};

    bindings[0].binding = 0;
    bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    bindings[0].descriptorCount = 1;
    bindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT | VK_SHADER_STAGE_VERTEX_BIT;

    bindings[1].binding = 1;
    bindings[1].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    bindings[1].descriptorCount = 1;
    bindings[1].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 2;
    layoutInfo.pBindings = bindings;

    if (vkCreateDescriptorSetLayout(device, &layoutInfo, nullptr, &mDescriptorSetLayout) != VK_SUCCESS) {
        LOGE("Failed to create descriptor set layout");
        return false;
    }

    // Descriptor pool
    VkDescriptorPoolSize poolSizes[2]{};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    poolSizes[0].descriptorCount = 1;
    poolSizes[1].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    poolSizes[1].descriptorCount = 1;

    VkDescriptorPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.maxSets = 1;
    poolInfo.poolSizeCount = 2;
    poolInfo.pPoolSizes = poolSizes;

    if (vkCreateDescriptorPool(device, &poolInfo, nullptr, &mDescriptorPool) != VK_SUCCESS) {
        LOGE("Failed to create descriptor pool");
        return false;
    }

    // Allocate descriptor set
    VkDescriptorSetAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    allocInfo.descriptorPool = mDescriptorPool;
    allocInfo.descriptorSetCount = 1;
    allocInfo.pSetLayouts = &mDescriptorSetLayout;

    if (vkAllocateDescriptorSets(device, &allocInfo, &mDescriptorSet) != VK_SUCCESS) {
        LOGE("Failed to allocate descriptor set");
        return false;
    }

    // Update descriptor set
    VkDescriptorBufferInfo ssboInfo{};
    ssboInfo.buffer = mParticleBuffer;
    ssboInfo.offset = 0;
    ssboInfo.range = sizeof(Particle) * MAX_PARTICLES;

    VkDescriptorBufferInfo uboInfo{};
    uboInfo.buffer = mUniformBuffer;
    uboInfo.offset = 0;
    uboInfo.range = sizeof(SimParams);

    VkWriteDescriptorSet writes[2]{};

    writes[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[0].dstSet = mDescriptorSet;
    writes[0].dstBinding = 0;
    writes[0].descriptorCount = 1;
    writes[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    writes[0].pBufferInfo = &ssboInfo;

    writes[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[1].dstSet = mDescriptorSet;
    writes[1].dstBinding = 1;
    writes[1].descriptorCount = 1;
    writes[1].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    writes[1].pBufferInfo = &uboInfo;

    vkUpdateDescriptorSets(device, 2, writes, 0, nullptr);

    return true;
}

bool ParticleSystem::createComputePipeline(VkDevice device, AAssetManager* assetManager) {
    auto compCode = loadShaderFromAsset(assetManager, "shaders/particle_sim.comp.spv");
    if (compCode.empty()) {
        LOGE("Failed to load compute shader");
        return false;
    }

    VkShaderModule compModule = createShaderModule(device, compCode);
    if (compModule == VK_NULL_HANDLE) return false;

    // Pipeline layout
    VkPipelineLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    layoutInfo.setLayoutCount = 1;
    layoutInfo.pSetLayouts = &mDescriptorSetLayout;

    if (vkCreatePipelineLayout(device, &layoutInfo, nullptr, &mComputePipelineLayout) != VK_SUCCESS) {
        LOGE("Failed to create compute pipeline layout");
        vkDestroyShaderModule(device, compModule, nullptr);
        return false;
    }

    VkComputePipelineCreateInfo pipelineInfo{};
    pipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipelineInfo.stage.module = compModule;
    pipelineInfo.stage.pName = "main";
    pipelineInfo.layout = mComputePipelineLayout;

    VkResult result = vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &mComputePipeline);
    vkDestroyShaderModule(device, compModule, nullptr);

    if (result != VK_SUCCESS) {
        LOGE("Failed to create compute pipeline: %d", result);
        return false;
    }

    LOGI("Compute pipeline created");
    return true;
}

bool ParticleSystem::createGraphicsPipeline(VkDevice device, VkRenderPass renderPass,
                                            uint32_t width, uint32_t height,
                                            AAssetManager* assetManager) {
    auto vertCode = loadShaderFromAsset(assetManager, "shaders/particle_render.vert.spv");
    auto fragCode = loadShaderFromAsset(assetManager, "shaders/particle_render.frag.spv");
    if (vertCode.empty() || fragCode.empty()) {
        LOGE("Failed to load graphics shaders");
        return false;
    }

    VkShaderModule vertModule = createShaderModule(device, vertCode);
    VkShaderModule fragModule = createShaderModule(device, fragCode);
    if (vertModule == VK_NULL_HANDLE || fragModule == VK_NULL_HANDLE) {
        if (vertModule != VK_NULL_HANDLE) vkDestroyShaderModule(device, vertModule, nullptr);
        if (fragModule != VK_NULL_HANDLE) vkDestroyShaderModule(device, fragModule, nullptr);
        return false;
    }

    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = vertModule;
    stages[0].pName = "main";
    stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = fragModule;
    stages[1].pName = "main";

    // Vertex input: stride=48 bytes, 3 vec4 attributes
    VkVertexInputBindingDescription bindingDesc{};
    bindingDesc.binding = 0;
    bindingDesc.stride = sizeof(Particle); // 48 bytes
    bindingDesc.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;

    VkVertexInputAttributeDescription attrDescs[3]{};
    // position (location 0)
    attrDescs[0].location = 0;
    attrDescs[0].binding = 0;
    attrDescs[0].format = VK_FORMAT_R32G32B32A32_SFLOAT;
    attrDescs[0].offset = offsetof(Particle, position);
    // velocity (location 1)
    attrDescs[1].location = 1;
    attrDescs[1].binding = 0;
    attrDescs[1].format = VK_FORMAT_R32G32B32A32_SFLOAT;
    attrDescs[1].offset = offsetof(Particle, velocity);
    // color (location 2)
    attrDescs[2].location = 2;
    attrDescs[2].binding = 0;
    attrDescs[2].format = VK_FORMAT_R32G32B32A32_SFLOAT;
    attrDescs[2].offset = offsetof(Particle, color);

    VkPipelineVertexInputStateCreateInfo vertexInputInfo{};
    vertexInputInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vertexInputInfo.vertexBindingDescriptionCount = 1;
    vertexInputInfo.pVertexBindingDescriptions = &bindingDesc;
    vertexInputInfo.vertexAttributeDescriptionCount = 3;
    vertexInputInfo.pVertexAttributeDescriptions = attrDescs;

    VkPipelineInputAssemblyStateCreateInfo inputAssembly{};
    inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
    inputAssembly.primitiveRestartEnable = VK_FALSE;

    VkViewport viewport{};
    viewport.x = 0.0f;
    viewport.y = 0.0f;
    viewport.width = static_cast<float>(width);
    viewport.height = static_cast<float>(height);
    viewport.minDepth = 0.0f;
    viewport.maxDepth = 1.0f;

    VkRect2D scissor{};
    scissor.offset = {0, 0};
    scissor.extent = {width, height};

    VkPipelineViewportStateCreateInfo viewportState{};
    viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewportState.viewportCount = 1;
    viewportState.pViewports = &viewport;
    viewportState.scissorCount = 1;
    viewportState.pScissors = &scissor;

    VkPipelineRasterizationStateCreateInfo rasterizer{};
    rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterizer.depthClampEnable = VK_FALSE;
    rasterizer.rasterizerDiscardEnable = VK_FALSE;
    rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
    rasterizer.lineWidth = 1.0f;
    rasterizer.cullMode = VK_CULL_MODE_NONE;
    rasterizer.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rasterizer.depthBiasEnable = VK_FALSE;

    VkPipelineMultisampleStateCreateInfo multisampling{};
    multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    multisampling.sampleShadingEnable = VK_FALSE;

    // Additive blending: src=ONE, dst=ONE
    VkPipelineColorBlendAttachmentState blendAttachment{};
    blendAttachment.blendEnable = VK_TRUE;
    blendAttachment.srcColorBlendFactor = VK_BLEND_FACTOR_ONE;
    blendAttachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE;
    blendAttachment.colorBlendOp = VK_BLEND_OP_ADD;
    blendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    blendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    blendAttachment.alphaBlendOp = VK_BLEND_OP_ADD;
    blendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                                     VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;

    VkPipelineColorBlendStateCreateInfo colorBlending{};
    colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    colorBlending.logicOpEnable = VK_FALSE;
    colorBlending.attachmentCount = 1;
    colorBlending.pAttachments = &blendAttachment;

    VkPipelineDepthStencilStateCreateInfo depthStencil{};
    depthStencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    depthStencil.depthTestEnable = VK_FALSE;
    depthStencil.depthWriteEnable = VK_FALSE;
    depthStencil.stencilTestEnable = VK_FALSE;

    // Push constants for viewProjection mat4 + sparkBrightness + screenHeight
    VkPushConstantRange pushConstantRange{};
    pushConstantRange.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
    pushConstantRange.offset = 0;
    pushConstantRange.size = sizeof(PushConstants);

    VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 1;
    pipelineLayoutInfo.pSetLayouts = &mDescriptorSetLayout;
    pipelineLayoutInfo.pushConstantRangeCount = 1;
    pipelineLayoutInfo.pPushConstantRanges = &pushConstantRange;

    if (vkCreatePipelineLayout(device, &pipelineLayoutInfo, nullptr, &mGraphicsPipelineLayout) != VK_SUCCESS) {
        LOGE("Failed to create graphics pipeline layout");
        vkDestroyShaderModule(device, vertModule, nullptr);
        vkDestroyShaderModule(device, fragModule, nullptr);
        return false;
    }

    VkGraphicsPipelineCreateInfo pipelineInfo{};
    pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pipelineInfo.stageCount = 2;
    pipelineInfo.pStages = stages;
    pipelineInfo.pVertexInputState = &vertexInputInfo;
    pipelineInfo.pInputAssemblyState = &inputAssembly;
    pipelineInfo.pViewportState = &viewportState;
    pipelineInfo.pRasterizationState = &rasterizer;
    pipelineInfo.pMultisampleState = &multisampling;
    pipelineInfo.pDepthStencilState = &depthStencil;
    pipelineInfo.pColorBlendState = &colorBlending;
    pipelineInfo.pDynamicState = nullptr;
    pipelineInfo.layout = mGraphicsPipelineLayout;
    pipelineInfo.renderPass = renderPass;
    pipelineInfo.subpass = 0;

    VkResult result = vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &mGraphicsPipeline);

    vkDestroyShaderModule(device, vertModule, nullptr);
    vkDestroyShaderModule(device, fragModule, nullptr);

    if (result != VK_SUCCESS) {
        LOGE("Failed to create graphics pipeline: %d", result);
        return false;
    }

    LOGI("Graphics pipeline created (%ux%u)", width, height);
    return true;
}

void ParticleSystem::recreateGraphicsPipeline(VkDevice device, VkRenderPass renderPass,
                                              uint32_t width, uint32_t height,
                                              AAssetManager* assetManager) {
    vkDeviceWaitIdle(device);
    if (mGraphicsPipeline != VK_NULL_HANDLE) {
        vkDestroyPipeline(device, mGraphicsPipeline, nullptr);
        mGraphicsPipeline = VK_NULL_HANDLE;
    }
    if (mGraphicsPipelineLayout != VK_NULL_HANDLE) {
        vkDestroyPipelineLayout(device, mGraphicsPipelineLayout, nullptr);
        mGraphicsPipelineLayout = VK_NULL_HANDLE;
    }
    createGraphicsPipeline(device, renderPass, width, height, assetManager);
}

void ParticleSystem::recordCompute(VkCommandBuffer cmd) {
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, mComputePipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, mComputePipelineLayout,
                            0, 1, &mDescriptorSet, 0, nullptr);

    uint32_t groupCount = (MAX_PARTICLES + 255) / 256;
    vkCmdDispatch(cmd, groupCount, 1, 1);
}

void ParticleSystem::recordRender(VkCommandBuffer cmd, const Mat4& viewProj, float screenHeight) {
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mGraphicsPipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, mGraphicsPipelineLayout,
                            0, 1, &mDescriptorSet, 0, nullptr);

    PushConstants pc{};
    memcpy(pc.viewProjection, viewProj.m, sizeof(float) * 16);
    pc.sparkBrightness = mSimParams.sparkBrightness;
    pc.screenHeight = screenHeight;

    vkCmdPushConstants(cmd, mGraphicsPipelineLayout,
                       VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                       0, sizeof(PushConstants), &pc);

    VkDeviceSize offset = 0;
    vkCmdBindVertexBuffers(cmd, 0, 1, &mParticleBuffer, &offset);
    vkCmdDraw(cmd, MAX_PARTICLES, 1, 0, 0);
}

void ParticleSystem::updateSimParams(VkDevice device, float deltaTime, bool touching,
                                     float emitterX, float emitterY, float emitterZ) {
    mSimParams.deltaTime = deltaTime;
    mSimParams.emitterX = emitterX;
    mSimParams.emitterY = emitterY;
    mSimParams.emitterZ = emitterZ;
    mSimParams.emitCount = touching ? 4096 : 0;
    mSimParams.frameNumber++;

    if (mUniformMapped != nullptr) {
        memcpy(mUniformMapped, &mSimParams, sizeof(SimParams));
    }
}
