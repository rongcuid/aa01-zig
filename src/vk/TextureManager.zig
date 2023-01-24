const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");

const zeroInit = std.mem.zeroInit;

const TextureMap = std.StringHashMap(*Texture);

allocator: std.mem.Allocator,
device: c.VkDevice,
vma: c.VmaAllocator,

textures: TextureMap,

pub const Texture = struct {
    allocator: std.mem.Allocator,
    vma: c.VmaAllocator,
    image: c.VkImage,
    alloc: c.VmaAllocation,
    pub fn create(
        allocator: std.mem.Allocator,
        vma: c.VmaAllocator,
        pImageCI: *const c.VkImageCreateInfo,
    ) !*Texture {
        const allocCI = zeroInit(c.VmaAllocationCreateInfo, .{
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        });
        var image: c.VkImage = undefined;
        var alloc: c.VmaAllocation = undefined;
        vk.check(
            c.vmaCreateImage(vma, pImageCI, &allocCI, &image, &alloc, null),
            "Failed to create image",
        );
        var p = try allocator.create(Texture);
        p.* = Texture{
            .allocator = allocator,
            .vma = vma,
            .image = image,
            .alloc = alloc,
        };
        return p;
    }
    pub fn destroy(self: *Texture) void {
        c.vmaDestroyImage(self.vma, self.image, self.alloc);
        self.allocator.destroy(self);
    }
    /// Load the texture into device right now
    pub fn loadNow(
        self: *Texture,
        queue: c.VkQueue,
        data: []const u8,
        src_format: c.VkFormat,
        dst_format: c.VkFormat,
    ) !void {
        _ = self;
        _ = queue;
        _ = data;
        _ = src_format;
        _ = dst_format;
    }
};

pub fn init(allocator: std.mem.Allocator, device: c.VkDevice, vma: c.VmaAllocator) !@This() {
    const textures = TextureMap.init(allocator);
    return @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
        .textures = textures,
    };
}

pub fn deinit(self: *@This()) void {
    std.log.debug("TextureManager.deinit()", .{});
    var iter = self.textures.valueIterator();
    while (iter.next()) |texture| {
        texture.*.destroy();
    }
}

/// Load a default R8G8B8A8 image
pub fn loadDefault(
    self: *@This(),
    queue: c.VkQueue,
    path: [:0]const u8,
    usage: c.VkImageUsageFlags,
) !*Texture {
    if (self.textures.get(path)) |texture| {
        return texture;
    }
    std.log.info("Loading image `{s}`", .{path});
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
    const n_bytes = @intCast(usize, surface_rgba.*.w * surface_rgba.*.h * format.*.BytesPerPixel);

    const imageCI = zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = c.VK_FORMAT_R8G8B8A8_UINT,
        .extent = c.VkExtent3D{
            .width = @intCast(u32, surface_rgba.*.w),
            .height = @intCast(u32, surface_rgba.*.h),
            .depth = 1,
        },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = usage | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
    });
    var texture = try Texture.create(self.allocator, self.vma, &imageCI);
    try texture.loadNow(
        queue,
        @ptrCast([*]const u8, surface_rgba.*.pixels)[0..n_bytes],
        c.VK_FORMAT_R8G8B8A8_UINT,
        c.VK_FORMAT_R8G8B8A8_UINT,
    );
    try self.textures.put(path, texture);
    return texture;
}
