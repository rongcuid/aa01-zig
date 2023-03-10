//! This struct is immovable!

const c = @import("../c.zig");
const std = @import("std");
const vk = @import("../vk.zig");

const zeroInit = std.mem.zeroInit;

allocator: std.mem.Allocator,
/// Owns
vkInstance: c.VkInstance,
/// Owns
vkDebugMessenger: c.VkDebugUtilsMessengerEXT,

/// Creates a Vulkan instance. Enables portability enumeration, all validation, and all messages.
///
/// Currently requires a SDL2 window due to SDL API.
/// With SDL greater than 2.26.2, `window` can be NULL. Therefore, this argument will be deprecated.
pub fn create(alloc: std.mem.Allocator, window: *c.SDL_Window) !*@This() {
    var n_exts: c_uint = undefined;
    var extensions: [16]?[*:0]const u8 = undefined;
    if (c.SDL_Vulkan_GetInstanceExtensions(window, &n_exts, &extensions) != c.SDL_TRUE) {
        @panic("Failed to get required extensions");
    }
    // This is the actual required extensions
    var actual_exts = try std.BoundedArray(?[*:0]const u8, 16).init(0);
    try actual_exts.appendSlice(extensions[0..n_exts]);
    try actual_exts.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    try actual_exts.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    // TODO: check if validation layer is available
    var layers = try std.BoundedArray([*:0]const u8, 16).init(0);
    try layers.append("VK_LAYER_KHRONOS_validation");
    try layers.append("VK_LAYER_KHRONOS_synchronization2");
    // Debug callback
    const debugCI = zeroInit(c.VkDebugUtilsMessengerCreateInfoEXT, .{
        .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = &debugCallback,
    });
    // Create instance
    const appInfo = zeroInit(c.VkApplicationInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Arcland Air 01",
        .applicationVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "Arcland Engine",
        .engineVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .apiVersion = c.VK_API_VERSION_1_2,
    });
    var instanceCI = zeroInit(c.VkInstanceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = &debugCI,
        .pApplicationInfo = &appInfo,
        .enabledExtensionCount = @intCast(c_uint, actual_exts.len),
        .ppEnabledExtensionNames = &actual_exts.buffer,
        .enabledLayerCount = @intCast(c_uint, layers.len),
        .ppEnabledLayerNames = &layers.buffer,
        .flags = 0,
    });
    instanceCI.flags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    // Create instance
    var instance: c.VkInstance = undefined;
    vk.check(
        c.vkCreateInstance.?(&instanceCI, null, &instance),
        "Failed to create VkInstance",
    );
    // Load procedure pointers
    c.volkLoadInstance(instance);
    // Create debug messenger
    var debugMessenger: c.VkDebugUtilsMessengerEXT = null;
    vk.check(
        c.vkCreateDebugUtilsMessengerEXT.?(instance, &debugCI, null, &debugMessenger),
        "Failed to create VkDebugUtilsMessengerEXT",
    );
    var p = try alloc.create(@This());
    p.* = @This(){
        .allocator = alloc,
        .vkInstance = instance,
        .vkDebugMessenger = debugMessenger,
    };
    return p;
}

pub fn destroy(self: *@This()) void {
    std.log.debug("Instance.destroy()", .{});
    if (self.vkDebugMessenger) |m| {
        c.vkDestroyDebugUtilsMessengerEXT.?(
            self.vkInstance,
            m,
            null,
        );
    }
    self.vkDebugMessenger = undefined;
    c.vkDestroyInstance.?(self.vkInstance, null);
    self.vkInstance = undefined;
    self.allocator.destroy(self);
}

export fn debugCallback(
    severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    msgType: c.VkDebugUtilsMessageTypeFlagsEXT,
    callbackData: ?*const c.VkDebugUtilsMessengerCallbackDataEXT,
    userData: ?*anyopaque,
) u32 {
    _ = userData;
    var msg = std.ArrayList(u8).init(std.heap.c_allocator);
    defer msg.deinit();
    if (msgType & c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT != 0) {
        msg.writer().print("GENERAL -- ", .{}) catch @panic("Debug messenger out of memory");
    } else if (msgType & c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT != 0) {
        msg.writer().print("VALIDATION -- ", .{}) catch @panic("Debug messenger out of memory");
    } else if (msgType & c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT != 0) {
        msg.writer().print("PERFORMANCE -- ", .{}) catch @panic("Debug messenger out of memory");
    } else if (msgType & c.VK_DEBUG_UTILS_MESSAGE_TYPE_DEVICE_ADDRESS_BINDING_BIT_EXT != 0) {
        msg.writer().print("ADDRESS BINDING -- ", .{}) catch @panic("Debug messenger out of memory");
    }
    const dat = callbackData orelse return c.VK_FALSE;
    // ID
    msg.writer().print("[{s}]", .{dat.pMessageIdName}) catch @panic("Debug messenger out of memory");
    // Message
    msg.writer().print(" {s}", .{dat.pMessage}) catch @panic("Debug messenger out of memory");
    if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT != 0) {
        std.log.err("{s}", .{msg.items});
        @panic("Validation error");
    } else if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT != 0) {
        std.log.warn("{s}", .{msg.items});
    } else if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT != 0) {
        std.log.info("{s}", .{msg.items});
    } else if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT != 0) {
        std.log.debug("{s}", .{msg.items});
    }
    return c.VK_FALSE;
}

/// Select the first physical device that fulfills requirements
pub fn selectPhysicalDevice(self: *const @This()) !c.VkPhysicalDevice {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const physDevs = try enumeratePhysicalDevices(fba.allocator(), self.vkInstance);
    for (physDevs.items) |p| {
        // Properties
        var props = zeroInit(c.VkPhysicalDeviceProperties2, .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
            .pNext = null,
        });
        c.vkGetPhysicalDeviceProperties2.?(p, &props);
        if (props.properties.apiVersion < c.VK_API_VERSION_1_2) {
            std.log.info("[{s}] does not support Vulkan 1.2", .{props.properties.deviceName});
            continue;
        } else {
            std.log.info("[{s}] supports Vulkan 1.2", .{props.properties.deviceName});
        }
        // Features
        var sync2 = zeroInit(c.VkPhysicalDeviceSynchronization2FeaturesKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR,
        });
        var dynamic = zeroInit(c.VkPhysicalDeviceDynamicRenderingFeaturesKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR,
            .pNext = &sync2,
        });
        var features = zeroInit(c.VkPhysicalDeviceFeatures2, .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
            .pNext = &dynamic,
        });
        c.vkGetPhysicalDeviceFeatures2.?(p, &features);
        if (dynamic.dynamicRendering == 0) {
            std.log.info("[{s}] does not support dynamic rendering", .{props.properties.deviceName});
            continue;
        } else {
            std.log.info("[{s}] supports dynamic rendering", .{props.properties.deviceName});
        }
        if (sync2.synchronization2 == 0) {
            std.log.info("[{s}] does not support synchronization2", .{props.properties.deviceName});
        }
        return p;
    }
    return error.NoDeviceFound;
}

fn enumeratePhysicalDevices(alloc: std.mem.Allocator, instance: c.VkInstance) !std.ArrayList(c.VkPhysicalDevice) {
    var count: u32 = undefined;
    vk.check(
        c.vkEnumeratePhysicalDevices.?(instance, &count, null),
        "Failed to enumerate number of physical devices",
    );
    var phys = std.ArrayList(c.VkPhysicalDevice).init(alloc);
    try phys.appendNTimes(undefined, count);
    vk.check(
        c.vkEnumeratePhysicalDevices.?(instance, &count, phys.items.ptr),
        "Failed to enumerate physical devices",
    );
    return phys;
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
