//! This struct is movable. Do not take a pointer!

const c = @import("../c.zig");
const std = @import("std");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

pub fn create_default_graphics(
    phys: c.VkPhysicalDevice,
    graphicsQueueFamilyIndex: u32,
) !c.VkDevice {
    const portability = checkPortability(phys);
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
    return device;
}

fn checkPortability(phys: c.VkPhysicalDevice) bool {
    var exts: [128]c.VkExtensionProperties = undefined;
    var count: u32 = undefined;
    vk.check(
        c.vkEnumerateDeviceExtensionProperties(phys, null, &count, &exts),
        "Failed to enumerate device extension properties count",
    );
    for (exts[0..count]) |ext| {
        if (std.cstr.cmp(
            @ptrCast([*:0]const u8, &ext.extensionName),
            "VK_KHR_portability_subset",
        ) == 0) {
            return true;
        }
    }
    return false;
}
