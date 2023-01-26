const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");

const zeroInit = std.mem.zeroInit;

allocator: std.mem.Allocator,

device: c.VkDevice,
vma: c.VmaAllocator,
image: c.VkImage,
alloc: c.VmaAllocation,
pub fn create(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vma: c.VmaAllocator,
    pImageCI: *const c.VkImageCreateInfo,
) !*@This() {
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
    var p = try allocator.create(@This());
    p.* = @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
        .image = image,
        .alloc = alloc,
    };
    return p;
}
pub fn destroy(self: *@This()) void {
    c.vmaDestroyImage(self.vma, self.image, self.alloc);
    self.allocator.destroy(self);
}

/// Load the texture into device right now
pub fn load(
    self: *@This(),
    /// An initialized command buffer. Will be ended by this call.
    cmd: c.VkCommandBuffer,
    /// Queue to transfer data with
    queue: c.VkQueue,
    /// Queue family index of the transfer queue
    transfer_qfi: u32,
    /// Queue family index of the graphics queue. Ownership will be transferred here
    graphics_qfi: u32,
    /// Source data
    surface: *c.SDL_Surface,
    /// Destination image layout
    dst_layout: c.VkImageLayout,
) !void {
    // Create staging buffer
    var staging: c.VkBuffer = undefined;
    var stagingAlloc: c.VmaAllocation = undefined;
    var stagingAI: c.VmaAllocationInfo = undefined;
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
    vk.check(
        c.vmaCreateBuffer(self.vma, &stagingCI, &stagingAllocCI, &staging, &stagingAlloc, &stagingAI),
        "Failed to create transfer buffer",
    );
    defer c.vmaDestroyBuffer(self.vma, staging, stagingAlloc);

    // Copy image into transfer buffer
    @memcpy(@ptrCast([*]u8, stagingAI.pMappedData), @ptrCast([*]const u8, surface.*.pixels), n_bytes);
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
    // Begin recording
    vk.check(c.vkBeginCommandBuffer(cmd, &beginInfo), "Failed to begin recording");
    self.recordUploadTransitionIn(cmd, transfer_qfi, graphics_qfi);
    c.vkCmdCopyBufferToImage(
        cmd,
        staging,
        self.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &region,
    );
    self.recordUploadTransitionOut(cmd, dst_layout, transfer_qfi, graphics_qfi);
    vk.check(c.vkEndCommandBuffer(cmd), "Failed to end recording");
    // Submit to queue
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
        vk.PfnD(.vkQueueSubmit2KHR).on(self.device)(queue, 1, &submit, null),
        "Failed to submit queue",
    );
    vk.check(c.vkQueueWaitIdle(queue), "Failed to wait queue idle");
}

fn recordUploadTransitionIn(
    self: *const @This(),
    cmd: c.VkCommandBuffer,
    transfer_qfi: u32,
    graphics_qfi: u32,
) void {
    self.recordLayoutTransition(
        cmd,
        c.VK_PIPELINE_STAGE_2_NONE_KHR,
        0,
        c.VK_PIPELINE_STAGE_2_TRANSFER_BIT_KHR,
        c.VK_ACCESS_2_TRANSFER_WRITE_BIT_KHR,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        transfer_qfi,
        graphics_qfi,
    );
}

fn recordUploadTransitionOut(
    self: *const @This(),
    cmd: c.VkCommandBuffer,
    dst_layout: c.VkImageLayout,
    transfer_qfi: u32,
    graphics_qfi: u32,
) void {
    self.recordLayoutTransition(
        cmd,
        c.VK_PIPELINE_STAGE_2_TRANSFER_BIT_KHR,
        c.VK_ACCESS_2_TRANSFER_WRITE_BIT_KHR,
        c.VK_PIPELINE_STAGE_2_NONE,
        0,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        dst_layout,
        transfer_qfi,
        graphics_qfi,
    );
}

fn recordLayoutTransition(
    self: *const @This(),
    cmd: c.VkCommandBuffer,
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
        .image = self.image,
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
