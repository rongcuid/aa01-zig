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

////// Methods

pub fn init(window: *c.SDL_Window) !@This() {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const instance = try vk.Instance.init(window);
    // Enumerate and selct physical devices
    const physDevices = try enumeratePhysicalDevices(instance.vkInstance, fba.allocator());
    defer physDevices.deinit();
    for (physDevices.items) |p| {
        printPhysicalDeviceInfo(p);
    }
    const physDevice = selectPhysicalDevice(physDevices.items);
    std.log.info("Selected physical device: 0x{x}", .{@ptrToInt(physDevice)});
    // Create logical device
    const gqIndex = try getGraphicsQueueFamilyIndex(physDevice);
    const device = try vk.Device.init(physDevice, gqIndex, instance.portability);
    var queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device.device, gqIndex, 0, &queue);
    return @This(){
        .instance = instance,
        .physicalDevice = physDevice,
        .device = device,
        .graphicsQueueFamilyIndex = gqIndex,
        .graphicsQueue = queue,
    };
}
pub fn deinit(self: *@This())void {
    std.log.debug("VulkanContext.deinit()", .{});
    self.device.deinit();
    self.instance.deinit();
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
