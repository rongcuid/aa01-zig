const c = @import("c.zig");
const std = @import("std");
// const vk = @import("vk.zig");
const vk = @import("vulkan");

const zeroInit = std.mem.zeroInit;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

////// Fields
/// Vulkan instance
instance: c.VkInstance,
/// Debug messenger object
debugMessenger: c.VkDebugUtilsMessengerEXT,
physicalDevice: c.VkPhysicalDevice,
/// Logical device
device: c.VkDevice,
graphicsQueueFamilyIndex: u32,
/// Graphics queue. Currently, assume that graphics queue can present
graphicsQueue: c.VkQueue,

////// Methods

pub fn init(window: *c.SDL_Window) !@This() {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var n_exts: c_uint = undefined;
    var extensions: [16]?[*:0]const u8 = undefined;
    if (c.SDL_Vulkan_GetInstanceExtensions(window, &n_exts, &extensions) != c.SDL_TRUE) {
        @panic("Failed to get required extensions");
    }
    // Create instance
    const inst_debug = try createVkInstance(extensions[0..n_exts]);
    // Enumerate and selct physical devices
    const physDevices = try enumeratePhysicalDevices(inst_debug[0], fba.allocator());
    defer physDevices.deinit();
    for (physDevices.items) |p| {
        printPhysicalDeviceInfo(p);
    }
    const physDevice = selectPhysicalDevice(physDevices.items);
    std.log.info("Selected physical device: 0x{x}", .{@ptrToInt(physDevice)});
    // Create logical device
    const gqIndex = try getGraphicsQueueFamilyIndex(physDevice);
    const device = try createDevice(physDevice, gqIndex, inst_debug[2]);
    var queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device, gqIndex, 0, &queue);
    return @This(){
        .instance = inst_debug[0],
        .debugMessenger = inst_debug[1],
        .physicalDevice = physDevice,
        .device = device,
        .graphicsQueueFamilyIndex = gqIndex,
        .graphicsQueue = queue,
    };
}

////// Instance

/// TODO: refactor return types
fn createVkInstance(exts: []?[*:0]const u8) !struct { c.VkInstance, c.VkDebugUtilsMessengerEXT, bool } {
    // This is the actual required extensions
    var actual_exts = try std.BoundedArray(?[*:0]const u8, 16).init(0);
    try actual_exts.appendSlice(exts);
    try actual_exts.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    // TODO: check if validation layer is available
    var layers = try std.BoundedArray([*:0]const u8, 16).init(0);
    try layers.append("VK_LAYER_KHRONOS_validation");
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
        .apiVersion = c.VK_API_VERSION_1_3,
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
    var instance: c.VkInstance = undefined;
    const result = c.vkCreateInstance(&instanceCI, null, &instance);
    var portability = false;
    if (result == c.VK_SUCCESS) {} else if (result == c.VK_ERROR_INCOMPATIBLE_DRIVER) {
        std.log.info("Failed to create Vulkan instance, trying again with portability subset. This is normal on Mac OS", .{});
        portability = true;
        // Try again with portability
        try actual_exts.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        instanceCI.enabledExtensionCount = @intCast(c_uint, actual_exts.len);
        instanceCI.ppEnabledExtensionNames = &actual_exts.buffer;
        instanceCI.flags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
        vk.check(c.vkCreateInstance(&instanceCI, null, &instance), "Failed to create VkInstance with portability subset");
    } else {
        vk.check(result, "Failed to create VkInstance");
    }
    var debugMessenger: c.VkDebugUtilsMessengerEXT = null;
    if (try vk.Pfn(c.PFN_vkCreateDebugUtilsMessengerEXT).get(instance)) |f| {
        vk.check(
            f(instance, &debugCI, null, &debugMessenger),
            "Failed to create VkDebugUtilsMessengerEXT",
        );
    }

    // const vkCreateDebugUtilsMessengerEXT = @ptrCast(
    //     c.PFN_vkCreateDebugUtilsMessengerEXT,
    //     c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"),
    // );
    // if (vkCreateDebugUtilsMessengerEXT) |f| {
    //     vk.check(f(instance, &debugCI, null, &debugMessenger), "Failed to create VkDebugUtilsMessengerEXT");
    // }
    return .{ instance, debugMessenger, portability };
}

pub fn deinit(self: *@This()) void {
    std.log.debug("VulkanContext.deinit()", .{});
    c.vkDestroyDevice(self.device, null);
    self.device = undefined;
    const vkDestroyDebugUtilsMessengerEXT = @ptrCast(
        c.PFN_vkDestroyDebugUtilsMessengerEXT,
        c.vkGetInstanceProcAddr(self.instance, "vkDestroyDebugUtilsMessengerEXT"),
    );
    if (vkDestroyDebugUtilsMessengerEXT) |f| {
        if (self.debugMessenger) |m| {
            f(self.instance, m, null);
        }
    }
    self.debugMessenger = undefined;
    c.vkDestroyInstance(self.instance, null);
    self.instance = undefined;
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
    } else if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT != 0) {
        std.log.warn("{s}", .{msg.items});
    } else if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT != 0) {
        std.log.info("{s}", .{msg.items});
    } else if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT != 0) {
        std.log.debug("{s}", .{msg.items});
    }
    return c.VK_FALSE;
}

////// Physical devices

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
    std.log.info("Device: [{s}] ({s})", .{ props.deviceName, physicalDeviceTypeName(&props) });
}

/// Currently, just pick the first device
fn selectPhysicalDevice(phys: []c.VkPhysicalDevice) c.VkPhysicalDevice {
    if (phys.len == 0) {
        @panic("No physical device");
    }
    return phys.ptr[0];
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

////// Logical device
fn createDevice(
    phys: c.VkPhysicalDevice,
    graphicsQueueFamilyIndex: u32,
    portability: bool,
) !c.VkDevice {
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
    return device;
}
