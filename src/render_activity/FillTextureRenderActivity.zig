//! A simple, debug renderer that just draws a texture

const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

device: c.VkDevice,
texture: c.VkImageView,

pipeline: c.VkPipeline,

pub fn init(
    device: c.VkDevice,
) !@This() {
    return @This(){
        .device = device,
        .texture = c.VK_NULL_HANDLE,
    };
}

pub fn deinit(self: *@This()) void {
    c.vkDestroyPipeline(self.device, self.pipeline, null);
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
    _ = self;
    _ = cmd;
    _ = out_image;
    _ = out_view;
    _ = out_layout;
    _ = out_area;
}