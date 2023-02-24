const c = @import("c.zig");
const std = @import("std");
const vk = @import("vk.zig");

const zeroInit = std.mem.zeroInit;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

////// Fields
allocator: Allocator,
/// Vulkan instance
instance: *vk.Instance,
physicalDevice: c.VkPhysicalDevice,

device: c.VkDevice,
graphicsQueueFamilyIndex: u32,
/// Graphics queue. Currently, assume that graphics queue can present
graphicsQueue: c.VkQueue,
pipeline_cache: c.VkPipelineCache,

vma: c.VmaAllocator,

surface: c.VkSurfaceKHR,
swapchain: vk.Swapchain,

shader_manager: *vk.ShaderManager,
texture_manager: *vk.TextureManager,

////// Methods

pub fn create(alloc: Allocator, window: *c.SDL_Window) !*@This() {
    const instance = try vk.Instance.create(alloc, window);
    // Enumerate and selct physical devices
    const physDevice = try instance.selectPhysicalDevice();
    std.log.info("Selected physical device: 0x{x}", .{@ptrToInt(physDevice)});
    // Create logical device
    const gqIndex = try getGraphicsQueueFamilyIndex(physDevice);
    const device = try vk.device.create_default_graphics(physDevice, gqIndex);
    var queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device, gqIndex, 0, &queue);
    // Pipeline cache
    var pipeline_cache: c.VkPipelineCache = undefined;
    const pipelineCacheCI = c.VkPipelineCacheCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .initialDataSize = 0,
        .pInitialData = null,
    };
    vk.check(
        c.vkCreatePipelineCache(device, &pipelineCacheCI, null, &pipeline_cache),
        "Failed to create pipeline cache",
    );
    // VMA
    const vkFuncs = zeroInit(c.VmaVulkanFunctions, .{
        .vkGetInstanceProcAddr = &c.vkGetInstanceProcAddr,
        .vkGetDeviceProcAddr = &c.vkGetDeviceProcAddr,
    });
    const vmaCI = zeroInit(c.VmaAllocatorCreateInfo, .{
        .physicalDevice = physDevice,
        .device = device,
        .instance = instance.vkInstance,
        .pVulkanFunctions = &vkFuncs,
    });
    var vma: c.VmaAllocator = undefined;
    vk.check(
        c.vmaCreateAllocator(&vmaCI, &vma),
        "Failed to create VMA allocator",
    );
    // Surface and Swapchain
    const surface = try getSurface(window, instance.vkInstance);
    var width: i32 = undefined;
    var height: i32 = undefined;
    c.SDL_GetWindowSize(window, &width, &height);
    const swapchain = try vk.Swapchain.init(
        alloc,
        physDevice,
        device,
        gqIndex,
        surface,
        @intCast(u32, width),
        @intCast(u32, height),
    );
    const shader_manager = try vk.ShaderManager.create(alloc, device);
    const texture_manager = try vk.TextureManager.create(alloc, device, vma, queue, gqIndex, gqIndex);
    var result = try alloc.create(@This());
    result.* = @This(){
        .allocator = alloc,
        .instance = instance,
        .physicalDevice = physDevice,
        .device = device,
        .pipeline_cache = pipeline_cache,
        .vma = vma,
        .graphicsQueueFamilyIndex = gqIndex,
        .graphicsQueue = queue,
        .surface = surface,
        .swapchain = swapchain,
        .shader_manager = shader_manager,
        .texture_manager = texture_manager,
    };
    return result;
}
pub fn destroy(self: *@This()) void {
    std.log.debug("VulkanContext.deinit()", .{});
    vk.check(c.vkDeviceWaitIdle(self.device), "Failed to wait device idle");
    self.shader_manager.destroy();
    self.texture_manager.destroy();
    self.swapchain.deinit();
    c.vkDestroySurfaceKHR(self.instance.vkInstance, self.surface, null);
    self.surface = undefined;
    c.vmaDestroyAllocator(self.vma);
    self.vma = undefined;
    c.vkDestroyPipelineCache(self.device, self.pipeline_cache, null);
    self.pipeline_cache = undefined;
    c.vkDestroyDevice(self.device, null);
    self.instance.destroy();
    self.allocator.destroy(self);
}

////// Queue family

fn getGraphicsQueueFamilyIndex(phys: c.VkPhysicalDevice) !u32 {
    var count: u32 = undefined;
    c.vkGetPhysicalDeviceQueueFamilyProperties(phys, &count, null);
    var props = try std.BoundedArray(c.VkQueueFamilyProperties, 16).init(count);
    c.vkGetPhysicalDeviceQueueFamilyProperties(phys, &count, &props.buffer);
    for (props.buffer, 0..) |p, i| {
        if (p.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            return @intCast(u32, i);
        }
    }
    return error.NoGraphicsQueue;
}

////// Command pool

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
