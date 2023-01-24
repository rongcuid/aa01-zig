const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");

const zeroInit = std.mem.zeroInit;

const TextureMap = std.StringHashMap(c.VkImage);

allocator: std.mem.Allocator,
device: c.VkDevice,
vma: c.VmaAllocator,

pub fn init(allocator: std.mem.Allocator, device: c.VkDevice, vma: c.VmaAllocator) !@This() {
    return @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
    };
}

pub fn deinit(self: *@This()) void {
    std.log.debug("TextureManager.deinit()");
    _ = self;
}

/// Load a default R8G8B8A8 image
pub fn loadDefault(self: *@This(), path: [:0]const u8) !c.VkImage {
    std.log.info("Loading image `{s}`", .{path});
    _ = self;
    const surface = c.IMG_Load(path);
    if (surface == null) {
        std.log.err("{s}", .{c.SDL_GetError()});
        @panic("Failed to load image");
    }
    defer c.SDL_FreeSurface(surface);
    const format = c.SDL_AllocFormat(c.SDL_PIXELFORMAT_RGBA8888);
    const surface_rgba = c.SDL_ConvertSurface(surface, format, 0);
    if (surface_rgba == null) {
        std.log.err("{s}", .{c.SDL_GetError()});
        @panic("Failed to load image");
    }
    defer c.SDL_FreeSurface(surface_rgba);

    // vk.check(c.vmaCreateImage())
}
