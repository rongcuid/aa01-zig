//! Simple Nuklear GUI rendering. This uses nuklear-provided font baking and default fonts, intended for debugging only.

const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

const Pipeline = @import("nk/NuklearPipeline.zig");

const MAX_VERTS = 1024;
const MAX_INDEX = 1024;
const MAX_TEXTURES = 128;

allocator: std.mem.Allocator,
device: c.VkDevice,
vma: c.VmaAllocator,
/// Owns
context: c.nk_context,
/// Owns
atlas: c.nk_font_atlas,
/// Owns
atlas_texture: *vk.Texture,
/// Owns
atlas_view: c.VkImageView,
/// Owns
pipeline: Pipeline,
convert_cfg: c.nk_convert_config,
/// References `self.atlas_texture`
tex_null: c.nk_draw_null_texture,
/// Owns
cmds: c.nk_buffer,
/// Owns
verts: c.nk_buffer,
vertsBuffer: vk.Buffer,
/// Owns
idx: c.nk_buffer,
idxBuffer: vk.Buffer,
// Owns.
descriptor_pool: c.VkDescriptorPool,
// Owns. Clears every Frame
descriptor_sets: DescriptorSetMap,
// Owns.
sampler: c.VkSampler,

const DescriptorSetMap = std.AutoHashMap(c.VkImageView, c.VkDescriptorSet);

pub fn init(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vma: c.VmaAllocator,
    cache: c.VkPipelineCache,
    texture_manager: *vk.TextureManager,
    shader_manager: *vk.ShaderManager,
) !@This() {
    var img_width: c_int = 1024;
    var img_height: c_int = 1024;
    var atlas: c.nk_font_atlas = undefined;
    c.nk_font_atlas_init_default(&atlas);
    c.nk_font_atlas_begin(&atlas);
    const font = c.nk_font_atlas_add_default(&atlas, 16, null);
    const img = @ptrCast(
        [*]const u8,
        c.nk_font_atlas_bake(&atlas, &img_width, &img_height, c.NK_FONT_ATLAS_RGBA32),
    );
    // Create the texture on device
    const atlas_texture = try texture_manager.loadPixels(
        img[0..@intCast(usize, img_width * img_height * 4)],
        @intCast(u32, img_width),
        @intCast(u32, img_height),
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        c.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL_KHR,
    );
    var atlas_view = try atlas_texture.createDefaultView();
    // Finish atlas
    var tex_null: c.nk_draw_null_texture = undefined;
    c.nk_font_atlas_end(&atlas, c.nk_handle_ptr(atlas_view), &tex_null);
    // Create context
    var context: c.nk_context = undefined;
    if (c.nk_init_default(&context, &font.*.handle) == 0) {
        @panic("Failed to initialize Nuklear");
    }
    const convert_cfg = c.nk_convert_config{
        .shape_AA = c.NK_ANTI_ALIASING_ON,
        .line_AA = c.NK_ANTI_ALIASING_ON,
        .vertex_layout = &VertexLayout,
        .vertex_size = @sizeOf(Pipeline.Vertex),
        .vertex_alignment = @alignOf(Pipeline.Vertex),
        .circle_segment_count = 22,
        .curve_segment_count = 22,
        .arc_segment_count = 22,
        .global_alpha = 1.0,
        .tex_null = tex_null,
    };
    // Nuklear command buffer on CPU
    var cmds: c.nk_buffer = undefined;
    c.nk_buffer_init_default(&cmds);
    // Vert and index buffer on device
    const vertSize = MAX_VERTS * @sizeOf(Pipeline.Vertex);
    const vertsBuffer = try vk.Buffer.initExclusiveSequentialMapped(vma, vertSize, c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    const idxSize = MAX_INDEX * @sizeOf(c_short);
    const idxBuffer = try vk.Buffer.initExclusiveSequentialMapped(vma, idxSize, c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    var verts: c.nk_buffer = undefined;
    c.nk_buffer_init_fixed(&verts, vertsBuffer.allocInfo.pMappedData, vertSize);
    var idx: c.nk_buffer = undefined;
    c.nk_buffer_init_fixed(&idx, idxBuffer.allocInfo.pMappedData, idxSize);

    // Build pipeline
    const pipeline = try Pipeline.init(device, cache, shader_manager);
    // Descriptors
    var descriptor_pool: c.VkDescriptorPool = undefined;
    const poolSizes = [_]c.VkDescriptorPoolSize{
        .{
            .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = MAX_TEXTURES,
        },
    };
    const poolCI = zeroInit(c.VkDescriptorPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1,
        .poolSizeCount = @intCast(u32, poolSizes.len),
        .pPoolSizes = &poolSizes,
    });
    vk.check(
        c.vkCreateDescriptorPool(device, &poolCI, null, &descriptor_pool),
        "Failed to create descriptor pool",
    );
    const descriptor_sets = DescriptorSetMap.init(allocator);
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
        c.vkCreateSampler(device, &samplerCI, null, &sampler),
        "Failed to create sampler",
    );
    return @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
        .context = context,
        .atlas = atlas,
        .atlas_texture = atlas_texture,
        .atlas_view = atlas_view,
        .pipeline = pipeline,
        .convert_cfg = convert_cfg,
        .tex_null = tex_null,
        .cmds = cmds,
        .verts = verts,
        .vertsBuffer = vertsBuffer,
        .idx = idx,
        .idxBuffer = idxBuffer,
        .descriptor_pool = descriptor_pool,
        .descriptor_sets = descriptor_sets,
        .sampler = sampler,
    };
}

pub fn deinit(self: *@This()) void {
    c.nk_buffer_free(&self.cmds);
    c.nk_buffer_free(&self.verts);
    c.nk_buffer_free(&self.idx);
    self.vertsBuffer.deinit();
    self.idxBuffer.deinit();
    c.nk_font_atlas_clear(&self.atlas);
    c.nk_free(&self.context);
    vk.check(c.vkDeviceWaitIdle(self.device), "Failed to wait device idle");
    self.descriptor_sets.deinit();
    c.vkDestroyDescriptorPool(self.device, self.descriptor_pool, null);
    c.vkDestroySampler(self.device, self.sampler, null);
    self.atlas_texture.destroy();
    self.pipeline.deinit();
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
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
    });
    const rendering_info = zeroInit(c.VkRenderingInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO_KHR,
        .renderArea = out_area,
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_att_info,
    });
    try self.beginTransition(cmd, out_image);
    vk.PfnD(.vkCmdBeginRenderingKHR).on(self.device)(cmd, &rendering_info);
    try self.drawNuklear(cmd);
    try setDynamicState(cmd, out_area);
    vk.PfnD(.vkCmdEndRenderingKHR).on(self.device)(cmd);
    try self.endTransition(cmd, out_image, out_layout);
}

fn beginTransition(
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

fn drawNuklear(self: *@This(), cmd: c.VkCommandBuffer) !void {
    // Clear all descriptors
    self.descriptor_sets.clearRetainingCapacity();
    vk.check(
        c.vkResetDescriptorPool(self.device, self.descriptor_pool, 0),
        "Failed to reset descriptor pool",
    );
    // Convert draw commands
    if (c.nk_convert(&self.context, &self.cmds, &self.verts, &self.idx, &self.convert_cfg) != c.NK_CONVERT_SUCCESS) {
        @panic("Failed to convert nk_commands");
    }
    // Draw commands
    var nk_cmd = c.nk__draw_begin(&self.context, &self.cmds);
    var index_offset: u32 = 0;
    while (nk_cmd != null) : (nk_cmd = c.nk__draw_next(nk_cmd, &self.cmds, &self.context)) {
        if (nk_cmd.*.elem_count == 0) continue;
        const pTexture = @ptrCast(*c.VkImageView, @alignCast(@alignOf(c.VkImageView), nk_cmd.*.texture.ptr));
        // Bind texture descriptor set
        const ds = try self.getDescriptorSet(pTexture.*);
        c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline.layout, 0, 1, &ds, 0, null);
        // Set scissor
        // TODO: scaling
        const scissor = c.VkRect2D{
            .offset = .{
                .x = @floatToInt(i32, std.math.max(nk_cmd.*.clip_rect.x, 0.0)),
                .y = @floatToInt(i32, std.math.max(nk_cmd.*.clip_rect.y, 0.0)),
            },
            .extent = .{
                .width = @floatToInt(u32, nk_cmd.*.clip_rect.w),
                .height = @floatToInt(u32, nk_cmd.*.clip_rect.h),
            },
        };
        c.vkCmdSetScissor(cmd, 0, 1, &scissor);
        // Draw
        c.vkCmdDrawIndexed(cmd, nk_cmd.*.elem_count, 1, index_offset, 0, 0);
        index_offset += nk_cmd.*.elem_count;
    }
    // Finish recording, reset Nuklear state
    c.nk_clear(&self.context);
}

fn setDynamicState(
    cmd: c.VkCommandBuffer,
    out_area: c.VkRect2D,
) !void {
    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @intToFloat(f32, out_area.extent.width),
        .height = @intToFloat(f32, out_area.extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };
    c.vkCmdSetViewport(cmd, 0, 1, &viewport);
    c.vkCmdSetScissor(cmd, 0, 1, &out_area);
}

/// Binds a texture to this renderer
fn getDescriptorSet(self: *@This(), view: c.VkImageView) !c.VkDescriptorSet {
    if (self.descriptor_sets.get(view)) |ds| {
        return ds;
    }
    // Not cached, allocate new descriptor set
    var ds: c.VkDescriptorSet = undefined;
    const dsAI = zeroInit(c.VkDescriptorSetAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = self.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &self.pipeline.descriptor_set_layouts[0],
    });
    vk.check(
        c.vkAllocateDescriptorSets(self.device, &dsAI, &ds),
        "Failed to allocate descriptor set",
    );
    // Write image to descriptor
    const imageInfo = c.VkDescriptorImageInfo{
        .sampler = self.sampler,
        .imageView = view,
        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    };
    const write = zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = ds,
        .dstBinding = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &imageInfo,
    });
    c.vkUpdateDescriptorSets(self.device, 1, &write, 0, null);
    try self.descriptor_sets.put(view, ds);
    return ds;
}

fn endTransition(
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

/// Vertex layout for Nuklear
const VertexLayout = [_]c.nk_draw_vertex_layout_element{
    .{
        .attribute = c.NK_VERTEX_POSITION,
        .format = c.NK_FORMAT_FLOAT,
        .offset = @offsetOf(Pipeline.Vertex, "position"),
    },
    .{
        .attribute = c.NK_VERTEX_TEXCOORD,
        .format = c.NK_FORMAT_FLOAT,
        .offset = @offsetOf(Pipeline.Vertex, "uv"),
    },
    .{
        .attribute = c.NK_VERTEX_COLOR,
        .format = c.NK_FORMAT_R32G32B32A32_FLOAT,
        .offset = @offsetOf(Pipeline.Vertex, "color"),
    },
    // End
    .{
        .attribute = c.NK_VERTEX_ATTRIBUTE_COUNT,
        .format = c.NK_FORMAT_COUNT,
        .offset = 0,
    },
};

/// New window
pub fn begin(self: *@This(), title: [:0]const u8, bounds: c.struct_nk_rect, flags: c.nk_flags) bool {
    return c.nk_begin(&self.context, title, bounds, flags) == 1;
}

/// New window with separated title
pub fn begin_titled(self: *@This(), name: [:0]const u8, title: [:0]u8, bounds: c.nk_rect, flags: c.nk_flags) bool {
    return c.nk_begin_titled(&self.context, name, title, bounds, flags) == 1;
}

/// End window
pub fn end(self: *@This()) void {
    c.nk_end(&self.context);
}

/// Begin Nuklear input
pub fn input_begin(self: *@This()) void {
    c.nk_input_begin(&self.context);
}

/// Mouse movement
pub fn input_mouse(self: *@This(), x: i32, y: i32) void {
    c.nk_input_motion(&self.context, x, y);
}

/// Keyboard events
pub fn input_key(self: *@This(), key: c.nk_keys, down: bool) void {
    c.nk_input_key(&self.context, key, down);
}

/// Mouse button
pub fn input_button(self: *@This(), btn: c.nk_buttons, x: i32, y: i32, down: bool) void {
    c.nk_input_button(&self.context, btn, x, y, down);
}

/// Mouse scroll
pub fn input_scroll(self: *@This(), val: c.nk_vec2) void {
    c.nk_input_scroll(&self.context, val);
}

/// ASCII character
pub fn input_char(self: *@This(), ch: u8) void {
    c.nk_input_char(&self.context, ch);
}

/// Encoded Unicode rune
pub fn input_glyph(self: *@This(), g: c.nk_glyph) void {
    c.nk_input_glyph(&self.context, g);
}

/// Unicode rune
pub fn input_unicode(self: *@This(), r: c.nk_rune) void {
    c.nk_input_unicode(&self.context, r);
}

/// End Nuklear input
pub fn input_end(self: *@This()) void {
    c.nk_input_end(&self.context);
}
