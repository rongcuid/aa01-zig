//! This struct is movable. Do not take a pointer!

const c = @import("../c.zig");
const std = @import("std");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

allocator: std.mem.Allocator,
/// Logical device
vkDevice: c.VkDevice,

pub fn create(
    alloc: std.mem.Allocator,
    phys: c.VkPhysicalDevice,
    graphicsQueueFamilyIndex: u32,
    portability: bool,
) !*@This() {
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
    try extensions.append(c.VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME);
    try extensions.append(c.VK_KHR_SYNCHRONIZATION_2_EXTENSION_NAME);
    if (portability) {
        try extensions.append("VK_KHR_portability_subset");
    }
    const layers = [_][*:0]const u8{
        "VK_LAYER_KHRONOS_validation",
        "VK_LAYER_KHRONOS_synchronization2",
    };
    var sync2 = c.VkPhysicalDeviceSynchronization2FeaturesKHR{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR,
        .pNext = null,
        .synchronization2 = c.VK_TRUE,
    };
    const dynamic = c.VkPhysicalDeviceDynamicRenderingFeaturesKHR{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR,
        .pNext = &sync2,
        .dynamicRendering = c.VK_TRUE,
    };
    const deviceCI = zeroInit(c.VkDeviceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &dynamic,
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
    var p = try alloc.create(@This());
    p.* = @This(){
        .allocator = alloc,
        .vkDevice = device,
    };
    return p;
}

pub fn destroy(self: *@This()) void {
    std.log.debug("Device.destroy()", .{});
    c.vkDestroyDevice(self.vkDevice, null);
    self.vkDevice = undefined;
    self.allocator.destroy(self);
}
