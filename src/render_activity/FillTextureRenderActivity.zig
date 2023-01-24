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
    shader_manager: *vk.ShaderManager,
) !@This() {
    const vert = try shader_manager.loadDefault("shaders/textured_surface.vert", vk.ShaderManager.ShaderKind.vertex);
    const frag = try shader_manager.loadDefault("shaders/textured_surface.frag", vk.ShaderManager.ShaderKind.fragment);
    _ = vert;
    _ = frag;
    return @This(){
        .device = device,
        .texture = null,
        .pipeline = null,
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