const c = @import("c.zig");
const std = @import("std");
const zeroInit = @import("std").mem.zeroInit;
const assert = @import("std").debug.assert;
const vk = @import("vk.zig");

const VulkanContext = @import("VulkanContext.zig");
const ClearScreenRenderActivity = @import("render_activity/ClearScreenRenderActivity.zig");
const FillTextureRenderActivity = @import("render_activity/FillTextureRenderActivity.zig");

var alloc = std.heap.c_allocator;

const Self = @This();

window: *c.SDL_Window,
context: VulkanContext,
csra: ClearScreenRenderActivity,
ftra: FillTextureRenderActivity,
zig_texture: *vk.TextureManager.Texture,
zig_texture_view: c.VkImageView,

pub fn init() !Self {
    const window = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 300, 73, c.SDL_WINDOW_VULKAN) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    var context = try VulkanContext.init(std.heap.c_allocator, window);
    const zig_texture = try context.texture_manager.loadDefault(
        "src/zig.bmp",
        c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );
    var zig_texture_view: c.VkImageView = undefined;
    const viewCI = zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = zig_texture.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = c.VK_FORMAT_R8G8B8A8_UINT,
        .components = c.VkComponentMapping{
            .r = c.VK_COMPONENT_SWIZZLE_R,
            .g = c.VK_COMPONENT_SWIZZLE_G,
            .b = c.VK_COMPONENT_SWIZZLE_B,
            .a = c.VK_COMPONENT_SWIZZLE_A,
        },
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    vk.check(
        c.vkCreateImageView(context.device, &viewCI, null, &zig_texture_view),
        "Failed to create image view",
    );
    const csra = try ClearScreenRenderActivity.init(
        context.device,
        c.VkClearValue{
            .color = c.VkClearColorValue{ .float32 = .{ 0.1, 0.2, 0.3, 1.0 } },
        },
    );
    var ftra = try FillTextureRenderActivity.init(
        context.device,
        context.pipeline_cache,
        &context.shader_manager,
    );
    try ftra.bindTexture(zig_texture_view);
    return Self{
        .window = window,
        .context = context,
        .csra = csra,
        .ftra = ftra,
        .zig_texture = zig_texture,
        .zig_texture_view = zig_texture_view,
    };
}
pub fn deinit(self: *Self) void {
    c.vkDestroyImageView(self.context.device, self.zig_texture_view, null);
    self.ftra.deinit();
    self.csra.deinit();
    self.context.deinit();
    c.SDL_DestroyWindow(self.window);
    self.window = undefined;
}

pub fn render(self: *Self) !void {
    // Acquire swapchain image
    const acquired = try self.context.swapchain.acquire();
    // Prepare structures
    try self.beginRender(&acquired);
    var cmds: [2]c.VkCommandBuffer = undefined;
    const allocInfo = zeroInit(c.VkCommandBufferAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = acquired.pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(u32, cmds.len),
    });
    vk.check(
        c.vkAllocateCommandBuffers(self.context.device, &allocInfo, &cmds),
        "Failed to allocate command buffer",
    );
    const area = zeroInit(c.VkRect2D, .{
        .extent = self.context.swapchain.extent,
    });
    // Run renderers
    try self.csra.render(cmds[0], acquired.image, acquired.view, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, area);
    try self.ftra.render(cmds[1], acquired.image, acquired.view, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, area);
    // Submit and present
    try self.submit(&acquired, &cmds);
    const resize = try self.context.swapchain.present(self.context.graphicsQueue);
    // TODO: resize swapchain
    _ = resize;
}

fn beginRender(self: *Self, acquired: *const vk.Swapchain.Frame) !void {
    vk.check(
        c.vkWaitForFences(self.context.device, 1, &acquired.fence, 1, c.UINT64_MAX),
        "Failed to wait for fences",
    );
    vk.check(
        c.vkResetFences(self.context.device, 1, &acquired.fence),
        "Failed to reset fences",
    );
    vk.check(
        c.vkResetCommandPool(self.context.device, acquired.pool, 0),
        "Failed to reset command pool",
    );
}

fn submit(self: *Self, acquired: *const vk.Swapchain.Frame, cmds: []c.VkCommandBuffer) !void {
    // Submit
    var cmd_info = try std.BoundedArray(c.VkCommandBufferSubmitInfoKHR, 128).init(0);
    for (cmds) |cmd| {
        cmd_info.appendAssumeCapacity(zeroInit(c.VkCommandBufferSubmitInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO_KHR,
            .commandBuffer = cmd,
        }));
    }

    const wait_semaphore_info = zeroInit(c.VkSemaphoreSubmitInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO_KHR,
        .semaphore = acquired.semaphore_acq,
        .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
    });
    const signal_info = zeroInit(c.VkSemaphoreSubmitInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO_KHR,
        .semaphore = acquired.semaphore_comp,
        .stageMask = c.VK_PIPELINE_STAGE_2_NONE_KHR,
    });
    const submit_info = zeroInit(c.VkSubmitInfo2KHR, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2_KHR,
        .waitSemaphoreInfoCount = 1,
        .pWaitSemaphoreInfos = &wait_semaphore_info,
        .commandBufferInfoCount = @intCast(u32, cmd_info.len),
        .pCommandBufferInfos = &cmd_info.buffer,
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &signal_info,
    });
    vk.check(
        vk.PfnD(.vkQueueSubmit2KHR).on(self.context.device)(self.context.graphicsQueue, 1, &submit_info, acquired.fence),
        "Failed to submit present queue",
    );
}
