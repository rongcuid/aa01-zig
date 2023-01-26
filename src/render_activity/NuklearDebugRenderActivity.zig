//! Simple Nuklear GUI rendering. This uses nuklear-provided font baking and default fonts, intended for debugging only.

const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

const Pipeline = @import("nk/NuklearPipeline.zig");

allocator: std.mem.Allocator,
device: c.VkDevice,
vma: c.VmaAllocator,
pipeline: Pipeline,
atlas_texture: vk.Texture,

pub fn init(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vma: c.VmaAllocator,
) !@This() {
    const img_width = 1024;
    const img_height = 1024;
    var atlas: c.nk_font_atlas = undefined;
    c.nk_font_atlas_init_default(&atlas);
    c.nk_font_atlas_begin(&atlas);
    c.nk_font_atlas_add_default(&atlas, 16, null);
    const img = @ptrCast(
        [*]const u8,
        c.nk_font_atlas_bake(&atlas, &img_width, &img_height, c.NK_FONT_ATLAS_RGBA32),
    );
    // Create device texture
    var atlas_texture = try vk.Texture.createDefault(
        allocator,
        device,
        vma,
        img_width,
        img_height,
        c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
    );
    const surface = c.SDL_CreateRGBSurfaceFrom(
        img,
        img_width,
        img_height,
        1,
        4 * img_width,
        0x000000FF,
        0x0000FF00,
        0x00FF0000,
        0xFF000000,
    );
    defer c.SDL_FreeSurface(surface);
    var atlas_view: c.VkImageView = undefined;
    // Finish atlas
    c.nk_font_atlas_end(&atlas, c.nk_handle_ptr(atlas_view), 0);
    return @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
    };
}

pub fn deinit(self: *@This()) void {
    _ = self;
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
