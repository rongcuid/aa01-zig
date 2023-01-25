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
queue: c.VkQueue,
transfer_qfi: u32,
graphics_qfi: u32,

pub fn init(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vma: c.VmaAllocator,
    queue: c.VkQueue,
    transfer_qfi: u32,
    graphics_qfi: u32,
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

    return @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
        .pool = pool,
        .textures = textures,
        .queue = queue,
        .transfer_qfi = transfer_qfi,
        .graphics_qfi = graphics_qfi,
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
    path: [:0]const u8,
    usage: c.VkImageUsageFlags,
    layout: c.VkImageLayout,
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
    try self.loadNow(texture, surface_rgba, layout);
    try self.textures.put(path, texture);
    return texture;
}

/// Load the texture into device right now
pub fn loadNow(
    self: *@This(),
    texture: *Texture,
    surface: *c.SDL_Surface,
    dst_layout: c.VkImageLayout,
) !void {
    const n_bytes = @intCast(usize, surface.*.w * surface.*.h * surface.*.format.*.BytesPerPixel);
    const stagingCI = zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .size = n_bytes,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    });
    const stagingAllocCI = zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_AUTO,
        .flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        .requiredFlags = c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
    });
    var staging: c.VkBuffer = undefined;
    var stagingAlloc: c.VmaAllocation = undefined;
    var stagingAI: c.VmaAllocationInfo = undefined;
    vk.check(
        c.vmaCreateBuffer(self.vma, &stagingCI, &stagingAllocCI, &staging, &stagingAlloc, &stagingAI),
        "Failed to create transfer buffer",
    );
    defer c.vmaDestroyBuffer(self.vma, staging, stagingAlloc);
    // Copy image into transfer buffer
    @memcpy(@ptrCast([*]u8, stagingAI.pMappedData), @ptrCast([*]const u8, surface.*.pixels), n_bytes);
    // Allocate command buffer for transfer
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
    defer c.vkFreeCommandBuffers(self.device, self.pool, 1, &cmd);
    // Prepare transfer
    const beginInfo = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    };
    const region = zeroInit(c.VkBufferImageCopy, .{
        .imageSubresource = c.VkImageSubresourceLayers{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageExtent = c.VkExtent3D{
            .width = @intCast(u32, surface.*.w),
            .height = @intCast(u32, surface.*.h),
            .depth = 1,
        },
    });
    vk.check(c.vkBeginCommandBuffer(cmd, &beginInfo), "Failed to begin recording");
    self.recordUploadTransitionIn(cmd, texture);
    c.vkCmdCopyBufferToImage(
        cmd,
        staging,
        texture.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &region,
    );
    self.recordUploadTransitionOut(cmd, texture, dst_layout);
    vk.check(c.vkEndCommandBuffer(cmd), "Failed to end recording");
    const cmdInfo = zeroInit(c.VkCommandBufferSubmitInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO_KHR,
        .commandBuffer = cmd,
    });
    const submit = zeroInit(c.VkSubmitInfo2KHR, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2_KHR,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmdInfo,
    });
    vk.check(
        vk.PfnD(.vkQueueSubmit2KHR).on(self.device)(self.queue, 1, &submit, null),
        "Failed to submit queue",
    );
    vk.check(c.vkQueueWaitIdle(self.queue), "Failed to wait queue idle");
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

fn recordUploadTransitionIn(self: *const @This(), cmd: c.VkCommandBuffer, texture: *const Texture) void {
    self.recordLayoutTransition(
        cmd,
        texture,
        c.VK_PIPELINE_STAGE_2_NONE_KHR,
        0,
        c.VK_PIPELINE_STAGE_2_TRANSFER_BIT_KHR,
        c.VK_ACCESS_2_TRANSFER_WRITE_BIT_KHR,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        0,
        0,
    );
}

fn recordUploadTransitionOut(self: *const @This(), cmd: c.VkCommandBuffer, texture: *const Texture, dst_layout: c.VkImageLayout) void {
    self.recordLayoutTransition(
        cmd,
        texture,
        c.VK_PIPELINE_STAGE_2_TRANSFER_BIT_KHR,
        c.VK_ACCESS_2_TRANSFER_WRITE_BIT_KHR,
        c.VK_PIPELINE_STAGE_2_NONE,
        0,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        dst_layout,
        0,
        0,
    );
}

fn recordLayoutTransition(
    self: *const @This(),
    cmd: c.VkCommandBuffer,
    texture: *const Texture,
    srcStageMask: c.VkPipelineStageFlags2KHR,
    srcAccessMask: c.VkAccessFlags2KHR,
    dstStageMask: c.VkPipelineStageFlags2KHR,
    dstAccessMask: c.VkAccessFlags2KHR,
    oldLayout: c.VkImageLayout,
    newLayout: c.VkImageLayout,
    srcQueueFamilyIndex: u32,
    dstQueueFamilyIndex: u32,
) void {
    const barrier = c.VkImageMemoryBarrier2KHR{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2_KHR,
        .pNext = null,
        // Top of pipe, no access
        .srcStageMask = srcStageMask,
        .srcAccessMask = srcAccessMask,
        // Transfer stage write
        .dstStageMask = dstStageMask,
        .dstAccessMask = dstAccessMask,
        // Change to transfer layout
        .oldLayout = oldLayout,
        .newLayout = newLayout,
        .srcQueueFamilyIndex = srcQueueFamilyIndex,
        .dstQueueFamilyIndex = dstQueueFamilyIndex,
        .image = texture.image,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    const depInfo = zeroInit(c.VkDependencyInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO_KHR,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &barrier,
    });
    vk.PfnD(.vkCmdPipelineBarrier2KHR).on(self.device)(cmd, &depInfo);
}
