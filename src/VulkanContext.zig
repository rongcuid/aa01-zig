const c = @import("c.zig");
const std = @import("std");
const vk = @import("vk.zig");

const print = std.debug.print;
const zeroInit = std.mem.zeroInit;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

/// Vulkan instance
instance: c.VkInstance,
// /// Logical device
// device: c.VkDevice,
// /// Present queue. Currently, only this one queue
// presentQueue: c.VkQueue,x
pub fn init(window: *c.SDL_Window) !@This() {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var n_exts: c_uint = undefined;
    var extensions: [16]?[*:0]const u8 = undefined;
    if (c.SDL_Vulkan_GetInstanceExtensions(window, &n_exts, &extensions) != c.SDL_TRUE) {
        @panic("Failed to get required extensions");
    }
    const instance = try createVkInstance(extensions[0..n_exts]);
    const physDevices = try enumeratePhysicalDevices(instance, fba.allocator());
    for (physDevices.items) |p| {
        printPhysicalDeviceInfo(p);
    }

    return @This(){
        .instance = instance,
        // .device = null,
    };
}

fn createVkInstance(exts: []?[*:0]const u8) !c.VkInstance {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    // This is the actual required extensions
    var actual_exts = try std.ArrayList(?[*:0]const u8).initCapacity(fba.allocator(), 16);
    defer actual_exts.deinit();
    actual_exts.appendSliceAssumeCapacity(exts);
    //
    const appInfo = zeroInit(c.VkApplicationInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "Arcland Air 01",
        .applicationVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "Arcland Engine",
        .engineVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .apiVersion = c.VK_API_VERSION_1_3,
    });
    var instanceCI = zeroInit(c.VkInstanceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .pApplicationInfo = &appInfo,
        .enabledExtensionCount = @intCast(c_uint, actual_exts.items.len),
        .ppEnabledExtensionNames = actual_exts.items.ptr,
        .flags = 0,
    });
    var instance: c.VkInstance = undefined;
    const result = c.vkCreateInstance(&instanceCI, null, &instance);
    if (result == c.VK_SUCCESS) {
        return instance;
    } else if (result == c.VK_ERROR_INCOMPATIBLE_DRIVER) {
        // Try again with portability
        try actual_exts.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        instanceCI.enabledExtensionCount = @intCast(c_uint, actual_exts.items.len);
        instanceCI.ppEnabledExtensionNames = actual_exts.items.ptr;
        instanceCI.flags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
        vk.check(c.vkCreateInstance(&instanceCI, null, &instance), "Failed to create VkInstance with portability subset");
    } else {
        vk.check(result, "Failed to create VkInstance");
    }
    return instance;
}

fn enumeratePhysicalDevices(instance: c.VkInstance, alloc: Allocator) !std.ArrayList(c.VkPhysicalDevice) {
    var count: u32 = undefined;
    vk.check(c.vkEnumeratePhysicalDevices(instance, &count, null), "Failed to enumerate number of physical devices");
    var phys = std.ArrayList(c.VkPhysicalDevice).init(alloc);
    try phys.appendNTimes(undefined, count);
    vk.check(c.vkEnumeratePhysicalDevices(instance, &count, phys.items.ptr), "Failed to enumerate physical devices");
    return phys;
}

fn getPhysicalDeviceProperties(phys: c.VkPhysicalDevice) c.VkPhysicalDeviceProperties {
    var props: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(phys, &props);
    return props;
}

fn physicalDeviceTypeName(props: *const c.VkPhysicalDeviceProperties) []const u8 {
    return switch (props.deviceType) {
        c.VK_PHYSICAL_DEVICE_TYPE_OTHER => "Other",
        c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "Integrated",
        c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "Discrete",
        c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "Virtual",
        c.VK_PHYSICAL_DEVICE_TYPE_CPU => "CPU",
        else => unreachable,
    };
}

fn printPhysicalDeviceInfo(phys: c.VkPhysicalDevice) void {
    const props = getPhysicalDeviceProperties(phys);
    print("Device: [{s}] ({s})\n", .{props.deviceName, physicalDeviceTypeName(&props)});
}