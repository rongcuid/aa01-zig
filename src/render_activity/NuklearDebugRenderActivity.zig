//! Simple Nuklear GUI rendering. This uses nuklear-provided font baking and default fonts, intended for debugging only.

const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

const VulkanContext = @import("../VulkanContext.zig");

const Frame = @import("ndra/Frame.zig");
const Pipeline = @import("ndra/Pipeline.zig");

context: *VulkanContext,
/// Owns
nk_context: c.nk_context,
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
frames: Frames,

/// Owns.
sampler: c.VkSampler,

const Frames = std.ArrayList(Frame);

pub fn init(
    allocator: std.mem.Allocator,
    context: *VulkanContext,
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
    const atlas_texture = try context.texture_manager.loadPixels(
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
    var nk_context: c.nk_context = undefined;
    if (c.nk_init_default(&nk_context, &font.*.handle) == 0) {
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

    // Build pipeline
    const pipeline = try Pipeline.init(context.device, context.pipeline_cache, context.shader_manager);
    // Frame list
    const frames = Frames.init(allocator);

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
        c.vkCreateSampler(context.device, &samplerCI, null, &sampler),
        "Failed to create sampler",
    );
    return @This(){
        .context = context,
        .nk_context = nk_context,
        .atlas = atlas,
        .atlas_texture = atlas_texture,
        .atlas_view = atlas_view,
        .pipeline = pipeline,
        .convert_cfg = convert_cfg,
        .tex_null = tex_null,
        .cmds = cmds,
        .frames = frames,
        .sampler = sampler,
    };
}

pub fn deinit(self: *@This()) void {
    vk.check(c.vkDeviceWaitIdle(self.device), "Failed to wait device idle");
    c.nk_buffer_free(&self.cmds);
    c.nk_buffer_free(&self.verts);
    c.nk_buffer_free(&self.idx);
    self.vertsBuffer.deinit();
    self.idxBuffer.deinit();
    c.nk_font_atlas_clear(&self.atlas);
    c.nk_free(&self.context);
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
    vk.PfnD(.vkCmdBeginRenderingKHR).on(self.context.device)(cmd, &rendering_info);
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline.pipeline);
    try setDynamicState(cmd, out_area);
    try self.drawNuklear(cmd);
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
    vk.PfnD(.vkCmdPipelineBarrier2KHR).on(self.context.device)(
        cmd,
        &dependency,
    );
}

fn drawNuklear(self: *@This(), cmd: c.VkCommandBuffer) !void {
    // TODO: clear descriptor pool
    c.nk_buffer_clear(&self.cmds);
    c.nk_buffer_clear(&self.verts);
    c.nk_buffer_clear(&self.idx);
    // Convert draw commands
    if (c.nk_convert(&self.context, &self.cmds, &self.verts, &self.idx, &self.convert_cfg) != c.NK_CONVERT_SUCCESS) {
        @panic("Failed to convert nk_commands");
    }
    // Bind vertex and index buffers
    const vOffsets: u64 = 0;
    c.vkCmdBindVertexBuffers(cmd, 0, 1, &self.vertsBuffer.buffer, &vOffsets);
    c.vkCmdBindIndexBuffer(cmd, self.idxBuffer.buffer, 0, c.VK_INDEX_TYPE_UINT16);
    // Draw commands
    var nk_cmd = c.nk__draw_begin(&self.context, &self.cmds);
    var index_offset: u32 = 0;
    while (nk_cmd != null) : (nk_cmd = c.nk__draw_next(nk_cmd, &self.cmds, &self.context)) {
        if (nk_cmd.*.elem_count == 0) continue;
        const texture = @ptrCast(c.VkImageView, nk_cmd.*.texture.ptr);
        // Bind texture descriptor set
        const ds = try self.getDescriptorSet(texture);
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
