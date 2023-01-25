const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");

const zeroInit = std.mem.zeroInit;

const TextureMap = std.StringHashMap(*Texture);

allocator: std.mem.Allocator,
device: c.VkDevice,
vma: c.VmaAllocator,

/// Owns this
pool: c.VkCommandPool,
textures: TextureMap,
sharing_mode: c.VkSharingMode,
/// All queue family indices shared, including the transfer
sharing_qfi: std.ArrayList(u32),

pub fn init(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vma: c.VmaAllocator,
    transfer_qfi: u32,
    sharing_qfi: []const u32,
) !@This() {
    const textures = TextureMap.init(allocator);
    // Command pool on transfer queue
    var pool: c.VkCommandPool = undefined;
    const poolCI = zeroInit(c.VkCommandPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = transfer_qfi,
    });
    vk.check(
        c.vkCreateCommandPool(device, &poolCI, null, &pool),
        "Failed to create command pool",
    );
    const sharing_mode: c.VkSharingMode = if (sharing_qfi.len != 0)
        c.VK_SHARING_MODE_CONCURRENT
    else
        c.VK_SHARING_MODE_EXCLUSIVE;
    var qfi = try std.ArrayList(u32).initCapacity(allocator, 1 + sharing_qfi.len);
    qfi.appendAssumeCapacity(transfer_qfi);
    qfi.appendSliceAssumeCapacity(sharing_qfi);

    return @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
        .pool = pool,
        .textures = textures,
        .sharing_mode = sharing_mode,
        .sharing_qfi = qfi,
    };
}

pub fn deinit(self: *@This()) void {
    std.log.debug("TextureManager.deinit()", .{});
    var iter = self.textures.valueIterator();
    while (iter.next()) |texture| {
        texture.*.destroy();
    }
    c.vkDestroyCommandPool(self.device, self.pool, null);
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
        .sharingMode = self.sharing_mode,
        .queueFamilyIndexCount = @intCast(u32, self.sharing_qfi.items.len),
        .pQueueFamilyIndices = self.sharing_qfi.items.ptr,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
    });
    var texture = try Texture.create(self.allocator, self.vma, &imageCI);
    try self.loadNow(
        queue,
        @ptrCast([*]const u8, surface_rgba.*.pixels)[0..n_bytes],
        c.VK_FORMAT_R8G8B8A8_UINT,
        c.VK_FORMAT_R8G8B8A8_UINT,
    );
    try self.textures.put(path, texture);
    return texture;
}

/// Load the texture into device right now
pub fn loadNow(
    self: *@This(),
    // texture: *Texture,
    queue: c.VkQueue,
    data: []const u8,
    src_format: c.VkFormat,
    dst_format: c.VkFormat,
) !void {
    const stagingCI = zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .size = data.len,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    });
    const stagingAllocCI = zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_AUTO,
        .flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        .requiredFlags = c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    });
    var staging: c.VkBuffer = undefined;
    var stagingAlloc: c.VmaAllocation = undefined;
    var stagingAI: c.VmaAllocationInfo = undefined;
    vk.check(
        c.vmaCreateBuffer(self.vma, &stagingCI, &stagingAllocCI, &staging, &stagingAlloc, &stagingAI),
        "Failed to create transfer buffer",
    );
    _ = queue;
    _ = src_format;
    _ = dst_format;
    c.vmaDestroyBuffer(self.vma, staging, stagingAlloc);
}

////// Texture

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
};
