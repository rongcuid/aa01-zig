const c = @import("c.zig");
const std = @import("std");
const vk = @import("vk.zig");
const VulkanContext = @import("VulkanContext.zig");
const Swapchain = @import("Swapchain.zig");

const print = std.debug.print;
const zeroInit = std.mem.zeroInit;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Self = @This();

instance: c.VkInstance,
device: c.VkDevice,
surface: c.VkSurfaceKHR,
swapchain: Swapchain,

pub fn init(
    allocator: Allocator,
    context: *const VulkanContext,
    window: *c.SDL_Window,
) !Self {
    var surface: c.VkSurfaceKHR = undefined;
    if (c.SDL_Vulkan_CreateSurface(
        window,
        context.instance.vkInstance,
        &surface,
    ) != c.SDL_TRUE) {
        @panic("Failed to create Vulkan surface");
    }
    var width: i32 = undefined;
    var height: i32 = undefined;
    c.SDL_GetWindowSize(window, &width, &height);
    const swapchain = try Swapchain.init(
        allocator,
        context.physicalDevice,
        context.device.device,
        context.graphicsQueueFamilyIndex,
        surface,
        @intCast(u32, width),
        @intCast(u32, height),
    );

    return Self{
        .instance = context.instance.vkInstance,
        .device = context.device.device,
        .surface = surface,
        .swapchain = swapchain,
    };
}

pub fn deinit(self: *Self) void {
    std.log.debug("VulkanOutput.deinit()", .{});
    self.swapchain.deinit();
    c.vkDestroySurfaceKHR(self.instance, self.surface, null);
    self.surface = undefined;
    self.device = undefined;
    self.instance = undefined;
}
