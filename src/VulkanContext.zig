const c = @import("c.zig");
const std = @import("std");
const vk = @import("vk.zig");

const zeroInit = std.mem.zeroInit;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

////// Fields
/// Vulkan instance
instance: vk.Instance,
physicalDevice: c.VkPhysicalDevice,

device: vk.Device,
graphicsQueueFamilyIndex: u32,
/// Graphics queue. Currently, assume that graphics queue can present
graphicsQueue: c.VkQueue,

surface: c.VkSurfaceKHR,
swapchain: vk.Swapchain,

commandPool: c.VkCommandPool,

////// Methods

pub fn init(alloc: Allocator, window: *c.SDL_Window) !@This() {
    const instance = try vk.Instance.init(window);
    // Enumerate and selct physical devices
    const physDevice = try instance.selectPhysicalDevice();
    std.log.info("Selected physical device: 0x{x}", .{@ptrToInt(physDevice)});
    // Create logical device
    const gqIndex = try getGraphicsQueueFamilyIndex(physDevice);
    const device = try vk.Device.init(physDevice, gqIndex, instance.portability);
    var queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device.vkDevice, gqIndex, 0, &queue);
    // Command pool
    const commandPool = try createCommandPool(device.vkDevice, gqIndex);
    // Surface and Swapchain
    const surface = try getSurface(window, instance.vkInstance);
    var width: i32 = undefined;
    var height: i32 = undefined;
    c.SDL_GetWindowSize(window, &width, &height);
    const swapchain = try vk.Swapchain.init(
        alloc,
        physDevice,
        device.vkDevice,
        gqIndex,
        surface,
        @intCast(u32, width),
        @intCast(u32, height),
    );
    return @This(){
        .instance = instance,
        .physicalDevice = physDevice,
        .device = device,
        .graphicsQueueFamilyIndex = gqIndex,
        .graphicsQueue = queue,
        .surface = surface,
        .swapchain = swapchain,
        .commandPool = commandPool,
    };
}
pub fn deinit(self: *@This()) void {
    std.log.debug("VulkanContext.deinit()", .{});
    self.swapchain.deinit();
    c.vkDestroySurfaceKHR(self.instance.vkInstance, self.surface, null);
    self.surface = undefined;
    c.vkDestroyCommandPool(self.device.vkDevice, self.commandPool, null);
    self.device.deinit();
    self.instance.deinit();
}

////// Queue family

fn getGraphicsQueueFamilyIndex(phys: c.VkPhysicalDevice) !u32 {
    var count: u32 = undefined;
    c.vkGetPhysicalDeviceQueueFamilyProperties(phys, &count, null);
    var props = try std.BoundedArray(c.VkQueueFamilyProperties, 16).init(count);
    c.vkGetPhysicalDeviceQueueFamilyProperties(phys, &count, &props.buffer);
    for (props.buffer) |p, i| {
        if (p.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            return @intCast(u32, i);
        }
    }
    return error.NoGraphicsQueue;
}

////// Command pool

fn createCommandPool(device: c.VkDevice, queueFamilyIndex: u32) !c.VkCommandPool {
    const ci = zeroInit(c.VkCommandPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = queueFamilyIndex,
    });
    var commandPool: c.VkCommandPool = undefined;
    vk.check(
        c.vkCreateCommandPool(device, &ci, null, &commandPool),
        "Failed to create command pool",
    );
    return commandPool;
}

////// Surface

fn getSurface(window: *c.SDL_Window, instance: c.VkInstance) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    if (c.SDL_Vulkan_CreateSurface(
        window,
        instance,
        &surface,
    ) != c.SDL_TRUE) {
        @panic("Failed to create Vulkan surface");
    }
    return surface;
}