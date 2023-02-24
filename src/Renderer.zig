const c = @import("c.zig");
const std = @import("std");
const zeroInit = @import("std").mem.zeroInit;
const assert = @import("std").debug.assert;
const vk = @import("vk.zig");

const VulkanContext = @import("VulkanContext.zig");
const NuklearDebugRenderActivity = @import("render_activity/NuklearDebugRenderActivity.zig");

var alloc = std.heap.c_allocator;

const Self = @This();
const NDRAFrameData = NuklearDebugRenderActivity.FrameData;
const NDRAFrameList = std.ArrayList(NDRAFrameData);

window: *c.SDL_Window,
context: *VulkanContext,
ndra: NuklearDebugRenderActivity,
ndra_frames: NDRAFrameList,
zig_texture: *vk.Texture,

pub fn init() !Self {
    const window = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 1280, 720, c.SDL_WINDOW_VULKAN) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    var context = try VulkanContext.create(std.heap.c_allocator, window);

    // Zig logo
    const zig_texture = try context.texture_manager.loadFileCached(
        "src/zig.bmp",
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );
    // Debug background
    var ndra = try NuklearDebugRenderActivity.init(context);
    var ndra_frames = try NDRAFrameList.initCapacity(std.heap.c_allocator, context.swapchain.total_frames);
    for (0..context.swapchain.total_frames) |_| {
        ndra_frames.appendAssumeCapacity(try NDRAFrameData.init(alloc, context));
    }

    // Return
    return Self{
        .window = window,
        .context = context,
        .ndra = ndra,
        .ndra_frames = ndra_frames,
        .zig_texture = zig_texture,
    };
}
pub fn deinit(self: *Self) void {
    for (self.ndra_frames.items) |*f| {
        f.deinit();
    }
    self.ndra_frames.deinit();
    self.ndra.deinit();
    self.context.destroy();
    c.SDL_DestroyWindow(self.window);
    self.window = undefined;
}

pub fn render(self: *Self) !void {
    // Acquire swapchain image
    const acquired = try self.context.swapchain.acquire();
    const ndra_frame = &self.ndra_frames.items[acquired.number];
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
        c.vkAllocateCommandBuffers.?(self.context.device, &allocInfo, &cmd),
        "Failed to allocate command buffer",
    );
    const area = zeroInit(c.VkRect2D, .{
        .extent = self.context.swapchain.extent,
    });
    try begin_cmd(cmd);
    // Run renderers
    // A test window
    self.drawTestWindow();
    try self.ndra.render(ndra_frame, cmd, acquired.image, acquired.view, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, area);
    // End
    try end_cmd(cmd);
    // Submit and present
    try self.submit(&acquired, &[_]c.VkCommandBuffer{cmd});
    const resize = try self.context.swapchain.present(self.context.graphicsQueue);
    // TODO: resize swapchain
    _ = resize;
}

fn beginRender(self: *Self, acquired: *const vk.Swapchain.Frame) !void {
    vk.check(
        c.vkWaitForFences.?(self.context.device, 1, &acquired.fence, 1, c.UINT64_MAX),
        "Failed to wait for fences",
    );
    vk.check(
        c.vkResetFences.?(self.context.device, 1, &acquired.fence),
        "Failed to reset fences",
    );
    vk.check(
        c.vkResetCommandPool.?(self.context.device, acquired.pool, 0),
        "Failed to reset command pool",
    );
}

fn begin_cmd(cmd: c.VkCommandBuffer) !void {
    const begin_info = zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    vk.check(
        c.vkBeginCommandBuffer.?(cmd, &begin_info),
        "Failed to begin command buffer",
    );
}

fn end_cmd(cmd: c.VkCommandBuffer) !void {
    vk.check(
        c.vkEndCommandBuffer.?(cmd),
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
        c.vkQueueSubmit2KHR.?(self.context.graphicsQueue, 1, &submit_info, acquired.fence),
        "Failed to submit present queue",
    );
}

fn drawTestWindow(self: *@This()) void {
    if (self.ndra.begin(
        "Hello, world",
        .{ .x = 50, .y = 50, .w = 640, .h = 360 },
        c.NK_WINDOW_BORDER |
            c.NK_WINDOW_MOVABLE |
            c.NK_WINDOW_SCALABLE |
            c.NK_WINDOW_MINIMIZABLE |
            c.NK_WINDOW_TITLE,
    )) {
        c.nk_layout_row_static(&self.ndra.nk_context, 30, 80, 1);
        if (c.nk_button_label(&self.ndra.nk_context, "button") == 1) {
            std.debug.print("button pressed\n", .{});
        }
    }
    self.ndra.end();
}
