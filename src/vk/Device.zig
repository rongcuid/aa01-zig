//! This struct is movable. Do not take a pointer!

const c = @import("../c.zig");
const std = @import("std");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

/// Logical device
vkDevice: c.VkDevice,

pub fn init(
    phys: c.VkPhysicalDevice,
    graphicsQueueFamilyIndex: u32,
    portability: bool,
) !@This() {
    const priority: f32 = 1.0;
    const queueCI = zeroInit(c.VkDeviceQueueCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = graphicsQueueFamilyIndex,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    });
    var features = zeroInit(c.VkPhysicalDeviceFeatures, .{});
    var extensions = try std.BoundedArray([*:0]const u8, 16).init(0);
    try extensions.append(c.VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    if (portability) {
        try extensions.append("VK_KHR_portability_subset");
    }
    const layers = [1][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
    const deviceCI = zeroInit(c.VkDeviceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queueCI,
        .queueCreateInfoCount = 1,
        .pEnabledFeatures = &features,
        .enabledExtensionCount = @intCast(u32, extensions.len),
        .ppEnabledExtensionNames = &extensions.buffer,
        .enabledLayerCount = layers.len,
        .ppEnabledLayerNames = &layers,
    });
    var device: c.VkDevice = undefined;
    vk.check(c.vkCreateDevice(phys, &deviceCI, null, &device), "Failed to create VkDevice");
    return @This() {
        .vkDevice = device,
    };
}

pub fn deinit(self: *@This()) void {
    std.log.debug("Device.deinit()", .{});
    c.vkDestroyDevice(self.vkDevice, null);
    self.vkDevice = undefined;
}
