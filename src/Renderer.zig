const c = @import("c.zig");
const std = @import("std");
const zeroInit = @import("std").mem.zeroInit;
const assert = @import("std").debug.assert;
const vk = @import("vk.zig");

const VulkanContext = @import("VulkanContext.zig");

var alloc = std.heap.c_allocator;

const Self = @This();

window: *c.SDL_Window,
context: VulkanContext,
pub fn init() !Self {
    const window = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 300, 73, c.SDL_WINDOW_VULKAN) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    const context = try VulkanContext.init(std.heap.c_allocator, window);
    return Self{
        .window = window,
        .context = context,
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
}
