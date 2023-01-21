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
        context.device.vkDevice,
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
    self.context.deinit();
    c.SDL_DestroyWindow(self.window);
    self.window = undefined;
}

pub fn render(self: *Self) void {
    vk.check(
        c.vkResetCommandPool(
            self.context.device.vkDevice,
            self.context.commandPool,
            c.VK_COMMAND_POOL_RESET_RELEASE_RESOURCES_BIT,
        ),
        "Failed to reset command pool",
    );
    const allocInfo = zeroInit(c.VkCommandBufferAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.context.commandPool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });
    var cmd: c.VkCommandBuffer = undefined;
    vk.check(
        c.vkAllocateCommandBuffers(self.context.device.vkDevice, &allocInfo, &cmd),
        "Failed to allocate command buffer",
    );
    const acquired = try self.context.swapchain.acquire();
    const image = self.context.swapchain.images.items[acquired.frame];
    const view = self.context.swapchain.views.items[acquired.frame];
    const fence = self.context.swapchain.fences.items[acquired.frame];
    const ias = self.context.swapchain.acquisition_semaphores.items[acquired.frame];
    const rcs = self.context.swapchain.render_complete_semaphores.items[acquired.frame];
    const area = zeroInit(c.VkRect2D, .{
        .extent = self.context.swapchain.extent,
    });
    try self.csra.render(cmd, image, view, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, area);
    // Submit
    vk.check(
        c.vkWaitForFences(self.context.device.vkDevice, 1, &fence, 1, c.UINT64_MAX),
        "Failed to wait for fences",
    );
    vk.check(
        c.vkResetFences(self.context.device.vkDevice, 1, &fence),
        "Failed to reset fences",
    );
    const dst: c.VkPipelineStageFlags = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    const submit_info = zeroInit(c.VkSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &ias,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &rcs,
        .pWaitDstStageMask = &dst,
    });
    vk.check(
        c.vkQueueSubmit(self.context.graphicsQueue, 1, &submit_info, fence),
        "Failed to submit present queue",
    );
    const resize = try self.context.swapchain.present(self.context.graphicsQueue);
    _ = resize;
}
