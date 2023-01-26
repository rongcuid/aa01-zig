const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");

const zeroInit = std.mem.zeroInit;

const TextureMap = std.StringHashMap(*vk.Texture);

allocator: std.mem.Allocator,
device: c.VkDevice,
vma: c.VmaAllocator,

/// Owns this
pool: c.VkCommandPool,
textures: TextureMap,
queue: c.VkQueue,
transfer_qfi: u32,
graphics_qfi: u32,

pub fn create(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vma: c.VmaAllocator,
    queue: c.VkQueue,
    transfer_qfi: u32,
    graphics_qfi: u32,
) !*@This() {
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

    var p = try allocator.create(@This());
    p.* = @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
        .pool = pool,
        .textures = textures,
        .queue = queue,
        .transfer_qfi = transfer_qfi,
        .graphics_qfi = graphics_qfi,
    };
    return p;
}

pub fn destroy(self: *@This()) void {
    std.log.debug("TextureManager.destroy()", .{});
    var iter = self.textures.valueIterator();
    while (iter.next()) |texture| {
        texture.*.destroy();
    }
    c.vkDestroyCommandPool(self.device, self.pool, null);
    self.allocator.destroy(self);
}

/// Load a default R8G8B8A8 image
pub fn loadFileRgbaUint(
    self: *@This(),
    path: [:0]const u8,
    usage: c.VkImageUsageFlags,
    layout: c.VkImageLayout,
) !*vk.Texture {
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

    var texture = try vk.Texture.createDefault(
        self.allocator,
        self.device,
        self.vma,
        @intCast(u32, surface_rgba.*.w),
        @intCast(u32, surface_rgba.*.h),
        usage,
    );
    var cmd: c.VkCommandBuffer = undefined;
    const cmdAI = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = self.pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    vk.check(
        c.vkAllocateCommandBuffers(self.device, &cmdAI, &cmd),
        "Failed to allocate command buffer",
    );
    try texture.load(
        cmd,
        self.queue,
        self.transfer_qfi,
        self.graphics_qfi,
        surface_rgba,
        layout,
    );
    try self.textures.put(path, texture);
    return texture;
}
