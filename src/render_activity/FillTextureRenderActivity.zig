//! A simple, debug renderer that just draws a texture

const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

device: c.VkDevice,
texture: c.VkImageView,

vert: c.VkShaderModule,
frag: c.VkShaderModule,
cache: c.VkPipelineCache,
pipeline: c.VkPipeline,
pipeline_layout: c.VkPipelineLayout,
descriptor_set_layout: [setLayoutCIs.len]c.VkDescriptorSetLayout,

pub fn init(
    device: c.VkDevice,
    cache: c.VkPipelineCache,
    shader_manager: *vk.ShaderManager,
) !@This() {
    const vert = try shader_manager.loadDefault(
        "shaders/textured_surface.vert",
        vk.ShaderManager.ShaderKind.vertex,
    );
    const frag = try shader_manager.loadDefault(
        "shaders/textured_surface.frag",
        vk.ShaderManager.ShaderKind.fragment,
    );
    const p = try createPipeline(device, cache, vert, frag);
    return @This(){
        .device = device,
        .texture = null,
        .vert = vert,
        .frag = frag,
        .cache = cache,
        .pipeline = p.pipeline,
        .pipeline_layout = p.pipeline_layout,
        .descriptor_set_layout = p.descriptor_layout,
    };
}

pub fn deinit(self: *@This()) void {
    for (self.descriptor_set_layout) |dsl| {
        c.vkDestroyDescriptorSetLayout(self.device, dsl, null);
    }
    c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
    c.vkDestroyPipeline(self.device, self.pipeline, null);
}

fn createPipeline(
    device: c.VkDevice,
    cache: c.VkPipelineCache,
    vert: c.VkShaderModule,
    frag: c.VkShaderModule,
) !struct {
    pipeline: c.VkPipeline,
    pipeline_layout: c.VkPipelineLayout,
    descriptor_layout: [setLayoutCIs.len]c.VkDescriptorSetLayout,
} {
    // Rendering
    const color: c.VkFormat = c.VK_FORMAT_R8G8B8A8_UNORM;
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
    for (setLayoutCIs) |ci, i| {
        vk.check(
            c.vkCreateDescriptorSetLayout(device, &ci, null, &setLayouts[i]),
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
        c.vkCreatePipelineLayout(device, &layoutCI, null, &layout),
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
        c.vkCreateGraphicsPipelines(device, cache, 1, &pipelineCI, null, &pipeline),
        "Failed to create pipeline",
    );
    return .{
        .pipeline = pipeline,
        .pipeline_layout = layout,
        .descriptor_layout = setLayouts,
    };
}

/// Binds a texture to this renderer
pub fn bindTexture(self: *@This(), texture: c.VkImageView) !void {
    self.texture = texture;
}

pub fn render(
    self: *@This(),
    cmd: c.VkCommandBuffer,
    out_image: c.VkImage,
    out_view: c.VkImageView,
    out_layout: c.VkImageLayout,
    out_area: c.VkRect2D,
) !void {
    const color_att_info = zeroInit(c.VkRenderingAttachmentInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO_KHR,
        .imageView = out_view,
        .imageLayout = c.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL_KHR,
        // .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        // .clearValue = c.VkClearValue{
        //     .color = c.VkClearColorValue{ .float32 = .{ 1.0, 1.0, 1.0, 1.0 } },
        // },
    });
    const rendering_info = zeroInit(c.VkRenderingInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO_KHR,
        .renderArea = out_area,
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_att_info,
    });

    // Start
    try begin_cmd(cmd);
    try self.begin_transition(cmd, out_image);
    vk.PfnD(.vkCmdBeginRenderingKHR).on(self.device)(cmd, &rendering_info);
    vk.PfnD(.vkCmdEndRenderingKHR).on(self.device)(cmd);
    try self.end_transition(cmd, out_image, out_layout);
    try end_cmd(cmd);
}

fn begin_cmd(cmd: c.VkCommandBuffer) !void {
    const begin_info = zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    vk.check(
        c.vkBeginCommandBuffer(cmd, &begin_info),
        "Failed to begin command buffer",
    );
}

fn begin_transition(
    self: *@This(),
    cmd: c.VkCommandBuffer,
    image: c.VkImage,
) !void {
    const image_barrier = zeroInit(c.VkImageMemoryBarrier2KHR, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2_KHR,
        .srcStageMask = c.VK_PIPELINE_STAGE_2_NONE_KHR,
        .dstStageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
        .dstAccessMask = c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT_KHR,
        .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = c.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL_KHR,
        .image = image,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    const dependency = zeroInit(c.VkDependencyInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO_KHR,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &image_barrier,
    });
    vk.PfnD(.vkCmdPipelineBarrier2KHR).on(self.device)(
        cmd,
        &dependency,
    );
}

fn end_transition(
    self: *@This(),
    cmd: c.VkCommandBuffer,
    image: c.VkImage,
    out_layout: c.VkImageLayout,
) !void {
    if (out_layout == c.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL_KHR) {
        return;
    }
    const image_barrier = zeroInit(c.VkImageMemoryBarrier2KHR, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2_KHR,
        .srcStageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
        .srcAccessMask = c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT_KHR,
        .oldLayout = c.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL_KHR,
        .newLayout = out_layout,
        .image = image,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    const dependency = zeroInit(c.VkDependencyInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO_KHR,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &image_barrier,
    });
    vk.PfnD(.vkCmdPipelineBarrier2KHR).on(self.device)(cmd, &dependency);
}

fn end_cmd(cmd: c.VkCommandBuffer) !void {
    vk.check(
        c.vkEndCommandBuffer(cmd),
        "Failed to end command buffer",
    );
}

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

const Vertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
};

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
        .bindingCount = 0,
        .pBindings = null,
    }),
    zeroInit(c.VkDescriptorSetLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = @intCast(u32, bindings.len),
        .pBindings = &bindings,
    }),
};
