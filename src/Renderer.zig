const c = @import("c.zig");
const std = @import("std");
const zeroInit = @import("std").mem.zeroInit;
const assert = @import("std").debug.assert;

const VulkanContext = @import("VulkanContext.zig");
const VulkanOutput = @import("VulkanOutput.zig");

var alloc = std.heap.c_allocator;

const Self = @This();

window: *c.SDL_Window,
context: VulkanContext,
output: VulkanOutput,
pub fn init() !Self {
    const window = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 300, 73, c.SDL_WINDOW_VULKAN) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    const context = try VulkanContext.init(window);
    const output = try VulkanOutput.init(
        std.heap.c_allocator,
        context.instance.vkInstance,
        context.physicalDevice,
        context.device,
        context.graphicsQueueFamilyIndex,
        window,
    );
    return Self{
        .window = window,
        .context = context,
        .output = output,
    };
}
pub fn deinit(self: *Self) void {
    self.output.deinit();
    self.context.deinit();
    c.SDL_DestroyWindow(self.window);
    self.window = undefined;
}
