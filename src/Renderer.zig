const c = @import("c.zig");
const std = @import("std");
const zeroInit = @import("std").mem.zeroInit;
const assert = @import("std").debug.assert;
const vk = @import("vk.zig");

const VulkanContext = @import("VulkanContext.zig");
const ClearScreenRenderActivity = @import("render_activity/ClearScreenRenderActivity.zig");
const FillTextureRenderActivity = @import("render_activity/FillTextureRenderActivity.zig");
const NuklearDebugRenderActivity = @import("render_activity/NuklearDebugRenderActivity.zig");

var alloc = std.heap.c_allocator;

const Self = @This();

window: *c.SDL_Window,
context: VulkanContext,
ftra: FillTextureRenderActivity,
ndra: NuklearDebugRenderActivity,
zig_texture: *vk.Texture,

pub fn init() !Self {
    const window = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 1280, 720, c.SDL_WINDOW_VULKAN) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    var context = try VulkanContext.init(std.heap.c_allocator, window);
    const zig_texture = try context.texture_manager.loadFileCached(
        "src/zig.bmp",
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );
    var ftra = try FillTextureRenderActivity.init(
        context.device,
        context.pipeline_cache,
        context.shader_manager,
    );
    // Debug background
    try ftra.bindTexture(try zig_texture.createDefaultView());
    var ndra = try NuklearDebugRenderActivity.init(
        alloc,
        context.device,
        context.vma,
        context.pipeline_cache,
        context.texture_manager,
        context.shader_manager,
    );
    // try ftra.bindTexture(ndra.atlas_view);

    // Return
    return Self{
        .window = window,
        .context = context,
        .ftra = ftra,
        .ndra = ndra,
        .zig_texture = zig_texture,
    };
}
pub fn deinit(self: *Self) void {
    self.ndra.deinit();
    self.ftra.deinit();
    self.context.deinit();
    c.SDL_DestroyWindow(self.window);
    self.window = undefined;
}

pub fn render(self: *Self) !void {
    // Acquire swapchain image
    const acquired = try self.context.swapchain.acquire();
    // Prepare structures
    try self.beginRender(&acquired);
    var cmd: c.VkCommandBuffer = undefined;
    const allocInfo = zeroInit(c.VkCommandBufferAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = acquired.pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });
    vk.check(
        c.vkAllocateCommandBuffers(self.context.device, &allocInfo, &cmd),
        "Failed to allocate command buffer",
    );
    const area = zeroInit(c.VkRect2D, .{
        .extent = self.context.swapchain.extent,
    });
    try begin_cmd(cmd);
    // Run renderers
    try self.ftra.render(cmd, acquired.image, acquired.view, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, area);
    try end_cmd(cmd);
    // Submit and present
    try self.submit(&acquired, &[_]c.VkCommandBuffer{cmd});
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

fn begin_cmd(cmd: c.VkCommandBuffer) !void {
    const begin_info = zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    vk.check(
        c.vkBeginCommandBuffer(cmd, &begin_info),
        "Failed to begin command buffer",
    );
}

fn end_cmd(cmd: c.VkCommandBuffer) !void {
    vk.check(
        c.vkEndCommandBuffer(cmd),
        "Failed to end command buffer",
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
