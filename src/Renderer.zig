const c = @import("c.zig");
const std = @import("std");
const zeroInit = @import("std").mem.zeroInit;
const assert = @import("std").debug.assert;
const vk = @import("vk.zig");

const VulkanContext = @import("VulkanContext.zig");
const ClearScreenRenderActivity = @import("render_activity/ClearScreenRenderActivity.zig");

var alloc = std.heap.c_allocator;

const Self = @This();

window: *c.SDL_Window,
context: VulkanContext,
csra: ClearScreenRenderActivity,

pub fn init() !Self {
    const window = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 300, 73, c.SDL_WINDOW_VULKAN) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    const context = try VulkanContext.init(std.heap.c_allocator, window);
    const csra = try ClearScreenRenderActivity.init(
        context.device,
        c.VkClearValue{
            .color = c.VkClearColorValue{ .float32 = .{ 0.1, 0.2, 0.3, 1.0 } },
        },
    );
    return Self{
        .window = window,
        .context = context,
        .csra = csra,
    };
}
pub fn deinit(self: *Self) void {
    self.csra.deinit();
    self.context.deinit();
    c.SDL_DestroyWindow(self.window);
    self.window = undefined;
}

pub fn render(self: *Self) void {
    // Acquire swapchain image
    const acquired = try self.context.swapchain.acquire();
    // Prepare structures
    try self.beginRender(&acquired);
    const allocInfo = zeroInit(c.VkCommandBufferAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = acquired.pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });
    var cmd: c.VkCommandBuffer = undefined;
    vk.check(
        c.vkAllocateCommandBuffers(self.context.device, &allocInfo, &cmd),
        "Failed to allocate command buffer",
    );
    const area = zeroInit(c.VkRect2D, .{
        .extent = self.context.swapchain.extent,
    });
    // Run renderers
    try self.csra.render(cmd, acquired.image, acquired.view, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, area);
    // Submit and present
    try self.submit(&acquired, cmd);
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

fn submit(self: *Self, acquired: *const vk.Swapchain.Frame, cmd: c.VkCommandBuffer) !void {
    // Submit
    const cmd_info = zeroInit(c.VkCommandBufferSubmitInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO_KHR,
        .commandBuffer = cmd,
    });
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
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &signal_info,
    });
    vk.check(
        vk.PfnD(.vkQueueSubmit2KHR).on(self.context.device)(self.context.graphicsQueue, 1, &submit_info, acquired.fence),
        "Failed to submit present queue",
    );
}