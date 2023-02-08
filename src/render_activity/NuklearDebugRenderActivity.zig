//! Simple Nuklear GUI rendering. This uses nuklear-provided font baking and default fonts, intended for debugging only.

const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

const Pipeline = @import("nk/NuklearPipeline.zig");

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
    c.nk_font_atlas_end(&atlas, c.nk_handle_ptr(atlas_view), 0);
    // Create context
    var context: c.nk_context = undefined;
    if (c.nk_init_default(&context, &font.*.handle) == 0) {
        @panic("Failed to initialize Nuklear");
    }
    // Build pipeline
    const pipeline = try Pipeline.init(device, cache, shader_manager);
    return @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
        .context = context,
        .atlas = atlas,
        .atlas_texture = atlas_texture,
        .atlas_view = atlas_view,
        .pipeline = pipeline,
    };
}

pub fn deinit(self: *@This()) void {
    c.nk_font_atlas_clear(&self.atlas);
    c.nk_free(&self.context);
    vk.check(c.vkDeviceWaitIdle(self.device), "Failed to wait device idle");
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
    _ = self;
    _ = cmd;
    _ = out_image;
    _ = out_view;
    _ = out_layout;
    _ = out_area;
}
