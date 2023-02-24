const std = @import("std");
const c = @import("../../c.zig");
const vk = @import("../../vk.zig");
const zeroInit = std.mem.zeroInit;

device: c.VkDevice,
/// Owns
pipeline: c.VkPipeline,
/// Owns
layout: c.VkPipelineLayout,
/// Owns
descriptor_set_layouts: [setLayoutCIs.len]c.VkDescriptorSetLayout,
/// Owns
sampler: c.VkSampler,
/// Owns
vert: c.VkShaderModule,
/// Owns
frag: c.VkShaderModule,

pub fn init(
    device: c.VkDevice,
    cache: c.VkPipelineCache,
    shader_manager: *vk.ShaderManager,
) !@This() {
    const vert = try shader_manager.loadDefault(
        "shaders/nuklear.vert",
        vk.ShaderManager.ShaderKind.vertex,
    );
    const frag = try shader_manager.loadDefault(
        "shaders/nuklear.frag",
        vk.ShaderManager.ShaderKind.fragment,
    );
    // Rendering
    const color: c.VkFormat = c.VK_FORMAT_B8G8R8A8_SRGB;
    const renderingCI = zeroInit(c.VkPipelineRenderingCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &color,
    });
    // Shader stages
    var stages = [_]c.VkPipelineShaderStageCreateInfo{
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert,
            .pName = "main",
            .pSpecializationInfo = null,
        },
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag,
            .pName = "main",
            .pSpecializationInfo = null,
        },
    };
    // Descriptor sets
    var setLayouts: [setLayoutCIs.len]c.VkDescriptorSetLayout = undefined;
    for (setLayoutCIs, 0..) |ci, i| {
        vk.check(
            c.vkCreateDescriptorSetLayout.?(device, &ci, null, &setLayouts[i]),
            "Failed to create descriptor set layout",
        );
    }
    // Layout
    var layout: c.VkPipelineLayout = undefined;
    const layoutCI = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = @intCast(u32, setLayouts.len),
        .pSetLayouts = &setLayouts,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };
    vk.check(
        c.vkCreatePipelineLayout.?(device, &layoutCI, null, &layout),
        "Failed to create pipeline layout",
    );
    // Pipeline
    var pipeline: c.VkPipeline = undefined;
    const pipelineCI = zeroInit(c.VkGraphicsPipelineCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = &renderingCI,
        .stageCount = stages.len,
        .pStages = &stages,
        .pVertexInputState = &vertexInputStateCI,
        .pInputAssemblyState = &inputAssemblyStateCI,
        .pTessellationState = null,
        .pViewportState = &viewportStateCI,
        .pRasterizationState = &rasterizationStateCI,
        .pMultisampleState = null,
        .pDepthStencilState = null,
        .pColorBlendState = &colorBlendStateCI,
        .pDynamicState = &dynamicStateCI,
        .layout = layout,
        .renderPass = null,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = 0,
    });
    vk.check(
        c.vkCreateGraphicsPipelines.?(device, cache, 1, &pipelineCI, null, &pipeline),
        "Failed to create pipeline",
    );
    // Sampler
    var sampler: c.VkSampler = undefined;
    const samplerCI = zeroInit(c.VkSamplerCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = c.VK_FILTER_NEAREST,
        .minFilter = c.VK_FILTER_NEAREST,
        .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_NEAREST,
        .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .minLod = 0,
        .maxLod = 1,
    });
    vk.check(
        c.vkCreateSampler.?(device, &samplerCI, null, &sampler),
        "Failed to create sampler",
    );
    return @This(){
        .device = device,
        .vert = vert,
        .frag = frag,
        .pipeline = pipeline,
        .layout = layout,
        .descriptor_set_layouts = setLayouts,
        .sampler = sampler,
    };
}

pub fn deinit(self: *@This()) void {
    c.vkDestroySampler.?(self.device, self.sampler, null);
    for (self.descriptor_set_layouts) |dsl| {
        c.vkDestroyDescriptorSetLayout.?(self.device, dsl, null);
    }
    c.vkDestroyPipelineLayout.?(self.device, self.layout, null);
    c.vkDestroyPipeline.?(self.device, self.pipeline, null);
}

// Constants

pub const Vertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
};

/// The `Vertex` struct
const vertexBindingDescriptions = [_]c.VkVertexInputBindingDescription{
    .{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
    },
};
/// Fields of `Vertex` struct
const vertexInputAttributeDescriptions = [_]c.VkVertexInputAttributeDescription{
    .{
        .location = 0,
        .binding = 0,
        .format = c.VK_FORMAT_R32G32_SFLOAT,
        .offset = @offsetOf(Vertex, "position"),
    },
    .{
        .location = 1,
        .binding = 0,
        .format = c.VK_FORMAT_R32G32_SFLOAT,
        .offset = @offsetOf(Vertex, "uv"),
    },
    .{
        .location = 2,
        .binding = 0,
        .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
        .offset = @offsetOf(Vertex, "color"),
    },
};

const vertexInputStateCI = c.VkPipelineVertexInputStateCreateInfo{
    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    .pNext = null,
    .flags = 0,
    .vertexBindingDescriptionCount = @intCast(u32, vertexBindingDescriptions.len),
    .pVertexBindingDescriptions = &vertexBindingDescriptions,
    .vertexAttributeDescriptionCount = @intCast(u32, vertexInputAttributeDescriptions.len),
    .pVertexAttributeDescriptions = &vertexInputAttributeDescriptions,
};

const inputAssemblyStateCI = c.VkPipelineInputAssemblyStateCreateInfo{
    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    .pNext = null,
    .flags = 0,
    .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    .primitiveRestartEnable = c.VK_FALSE,
};

const viewportStateCI = zeroInit(c.VkPipelineViewportStateCreateInfo, .{
    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    .viewportCount = 1,
    .pViewports = null,
    .scissorCount = 1,
    .pScissors = null,
});

const rasterizationStateCI = zeroInit(c.VkPipelineRasterizationStateCreateInfo, .{
    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    .polygonMode = c.VK_POLYGON_MODE_FILL,
    .cullMode = c.VK_CULL_MODE_NONE,
    .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
    .lineWidth = 1.0,
});

const colorBlendStateCI = zeroInit(c.VkPipelineColorBlendStateCreateInfo, .{
    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    .attachmentCount = 1,
    .pAttachments = &c.VkPipelineColorBlendAttachmentState{
        .blendEnable = 1,
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT |
            c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT |
            c.VK_COLOR_COMPONENT_A_BIT,
    },
});

const dynamicStates = [_]c.VkDynamicState{
    c.VK_DYNAMIC_STATE_VIEWPORT,
    c.VK_DYNAMIC_STATE_SCISSOR,
};

const dynamicStateCI = zeroInit(c.VkPipelineDynamicStateCreateInfo, .{
    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    .dynamicStateCount = @intCast(u32, dynamicStates.len),
    .pDynamicStates = &dynamicStates,
});

const bindings = [_]c.VkDescriptorSetLayoutBinding{.{
    .binding = 0,
    .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    .descriptorCount = 1,
    .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    .pImmutableSamplers = null,
}};
const setLayoutCIs = [_]c.VkDescriptorSetLayoutCreateInfo{
    zeroInit(c.VkDescriptorSetLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = @intCast(u32, bindings.len),
        .pBindings = &bindings,
    }),
};
