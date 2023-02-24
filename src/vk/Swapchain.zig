//! This struct is movable. Do not take a pointer!

const c = @import("../c.zig");
const std = @import("std");
const vk = @import("../vk.zig");
const vkz = @import("vkz");

const print = std.debug.print;
const zeroInit = std.mem.zeroInit;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

/// Owns
vkSurface: c.VkSurfaceKHR,
/// References
vkSwapchain: c.VkSwapchainKHR,
/// References
vkDevice: c.VkDevice,

extent: c.VkExtent2D,

total_frames: u32,
current_frame: u32,
images: std.ArrayList(c.VkImage),
views: std.ArrayList(c.VkImageView),
acquisition_semaphores: std.ArrayList(c.VkSemaphore),
render_complete_semaphores: std.ArrayList(c.VkSemaphore),
fences: std.ArrayList(c.VkFence),
pools: std.ArrayList(c.VkCommandPool),

const Self = @This();
pub const Frame = struct {
    number: u32,
    resize: bool,
    image: c.VkImage,
    view: c.VkImageView,
    semaphore_acq: c.VkSemaphore,
    semaphore_comp: c.VkSemaphore,
    fence: c.VkFence,
    pool: c.VkCommandPool,
};

pub fn init(
    allocator: Allocator,
    phys: c.VkPhysicalDevice,
    device: c.VkDevice,
    graphicsQueueFamilyIndex: u32,
    surface: c.VkSurfaceKHR,
    width: u32,
    height: u32,
) !Self {
    const swapchain = try createSwapchain(
        allocator,
        phys,
        device,
        surface,
        graphicsQueueFamilyIndex,
        @intCast(u32, width),
        @intCast(u32, height),
        null,
    );
    std.log.debug("Created VkSwapchainKHR [0x{x}]", .{@ptrToInt(swapchain)});
    const extent = c.VkExtent2D{
        .width = width,
        .height = height,
    };
    var imageCount: u32 = undefined;
    vk.check(
        c.vkGetSwapchainImagesKHR(device, swapchain, &imageCount, null),
        "Failed to get number of swapchain images",
    );
    var images = try std.ArrayList(c.VkImage).initCapacity(allocator, imageCount);
    images.appendNTimesAssumeCapacity(undefined, imageCount);
    vk.check(
        c.vkGetSwapchainImagesKHR(device, swapchain, &imageCount, images.items.ptr),
        "Failed to get swapchain images",
    );
    const formats = try getFormats(allocator, phys, surface);
    var views = try std.ArrayList(c.VkImageView).initCapacity(allocator, imageCount);
    var img_acq_semaphores = try std.ArrayList(c.VkSemaphore).initCapacity(allocator, imageCount);
    var render_semaphores = try std.ArrayList(c.VkSemaphore).initCapacity(allocator, imageCount);
    var fences = try std.ArrayList(c.VkFence).initCapacity(allocator, imageCount);
    var pools = try std.ArrayList(c.VkCommandPool).initCapacity(allocator, imageCount);
    for (images.items) |img| {
        views.appendAssumeCapacity(try createImageView(
            device,
            img,
            formats.items[0].format,
        ));
        img_acq_semaphores.appendAssumeCapacity(try createSemaphore(device));
        render_semaphores.appendAssumeCapacity(try createSemaphore(device));
        fences.appendAssumeCapacity(try createFence(device));
        pools.appendAssumeCapacity(try createCommandPool(device, graphicsQueueFamilyIndex));
    }
    return Self{
        .vkDevice = device,
        .vkSurface = surface,
        .vkSwapchain = swapchain,
        .extent = extent,
        .total_frames = imageCount,
        .current_frame = 0,
        .images = images,
        .views = views,
        .acquisition_semaphores = img_acq_semaphores,
        .render_complete_semaphores = render_semaphores,
        .fences = fences,
        .pools = pools,
    };
}

pub fn deinit(self: *Self) void {
    std.log.debug("Swapchain.deinit()", .{});
    std.log.debug("Destroying VkImageView", .{});
    for (self.pools.items) |p| {
        c.vkDestroyCommandPool(self.vkDevice, p, null);
    }
    for (self.fences.items) |f| {
        c.vkDestroyFence(self.vkDevice, f, null);
    }
    for (self.acquisition_semaphores.items) |s| {
        c.vkDestroySemaphore(self.vkDevice, s, null);
    }
    for (self.render_complete_semaphores.items) |s| {
        c.vkDestroySemaphore(self.vkDevice, s, null);
    }
    for (self.views.items) |v| {
        c.vkDestroyImageView(self.vkDevice, v, null);
    }
    self.views.deinit();
    std.log.debug("Destroying VkSwapchainKHR [0x{x}]", .{@ptrToInt(self.vkSwapchain)});
    c.vkDestroySwapchainKHR(self.vkDevice, self.vkSwapchain, null);
    self.vkSwapchain = undefined;
}

fn getFormats(allocator: Allocator, phys: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !std.ArrayList(c.VkSurfaceFormatKHR) {
    var count: u32 = undefined;
    vk.check(
        c.vkGetPhysicalDeviceSurfaceFormatsKHR(phys, surface, &count, null),
        "Failed to get number of surface formats",
    );
    var formats = try std.ArrayList(c.VkSurfaceFormatKHR).initCapacity(allocator, count);
    formats.appendNTimesAssumeCapacity(undefined, count);
    vk.check(
        c.vkGetPhysicalDeviceSurfaceFormatsKHR(phys, surface, &count, formats.items.ptr),
        "Failed to get number of surface formats",
    );
    return formats;
}

fn createSwapchain(
    allocator: Allocator,
    phys: c.VkPhysicalDevice,
    device: c.VkDevice,
    surface: c.VkSurfaceKHR,
    graphicsQueueFamilyIndex: u32,
    width: u32,
    height: u32,
    oldSwapchain: c.VkSwapchainKHR,
) !c.VkSwapchainKHR {
    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    vk.check(
        c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(phys, surface, &capabilities),
        "Failed to get physical device capabilities",
    );
    const formats = try getFormats(allocator, phys, surface);
    defer formats.deinit();
    const swapchainCI = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .surface = surface,
        .minImageCount = 3,
        .imageFormat = formats.items[0].format,
        .imageColorSpace = formats.items[0].colorSpace,
        // TODO: clamp this
        .imageExtent = c.VkExtent2D{
            .width = width,
            .height = height,
        },
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 1,
        .pQueueFamilyIndices = &graphicsQueueFamilyIndex,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = c.VK_PRESENT_MODE_FIFO_KHR,
        .clipped = c.VK_TRUE,
        .oldSwapchain = oldSwapchain,
    };
    var swapchain: c.VkSwapchainKHR = undefined;
    vk.check(
        c.vkCreateSwapchainKHR(device, &swapchainCI, null, &swapchain),
        "Failed to create VkSwapchainKHR",
    );
    return swapchain;
}

fn createImageView(
    device: c.VkDevice,
    image: c.VkImage,
    format: c.VkFormat,
) !c.VkImageView {
    const ci = zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .components = c.VkComponentMapping{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    var view: c.VkImageView = undefined;
    vk.check(
        c.vkCreateImageView(device, &ci, null, &view),
        "Failed to create VkImageView",
    );
    return view;
}

fn createSemaphore(device: c.VkDevice) !c.VkSemaphore {
    const ci = zeroInit(c.VkSemaphoreCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    });
    var semaphore: c.VkSemaphore = undefined;
    vk.check(
        c.vkCreateSemaphore(device, &ci, null, &semaphore),
        "Failed to create semaphore",
    );
    return semaphore;
}

fn createFence(device: c.VkDevice) !c.VkFence {
    const ci = zeroInit(c.VkFenceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    });
    var fence: c.VkFence = undefined;
    vk.check(
        c.vkCreateFence(device, &ci, null, &fence),
        "Failed to create fence",
    );
    return fence;
}

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

pub fn acquire(self: *@This()) !Frame {
    var frame: u32 = undefined;
    const err = c.vkAcquireNextImageKHR(
        self.vkDevice,
        self.vkSwapchain,
        c.UINT64_MAX,
        self.acquisition_semaphores.items[self.current_frame],
        null,
        &frame,
    );
    var resize = false;
    switch (err) {
        c.VK_SUCCESS => resize = false,
        c.VK_SUBOPTIMAL_KHR => resize = false,
        c.VK_ERROR_OUT_OF_DATE_KHR => resize = true,
        else => @panic("Failed to acquire swapchain image"),
    }
    self.current_frame = frame;
    return Frame{
        .number = frame,
        .resize = resize,
        .image = self.images.items[frame],
        .view = self.views.items[frame],
        .semaphore_acq = self.acquisition_semaphores.items[frame],
        .semaphore_comp = self.render_complete_semaphores.items[frame],
        .fence = self.fences.items[frame],
        .pool = self.pools.items[frame],
    };
}

pub fn present(self: *@This(), queue: c.VkQueue) !bool {
    var resize = false;
    const present_info = zeroInit(c.VkPresentInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &self.render_complete_semaphores.items[self.current_frame],
        .swapchainCount = 1,
        .pSwapchains = &self.vkSwapchain,
        .pImageIndices = &self.current_frame,
    });
    const err = c.vkQueuePresentKHR(queue, &present_info);
    switch (err) {
        c.VK_SUCCESS => {},
        c.VK_SUBOPTIMAL_KHR => resize = false,
        c.VK_ERROR_OUT_OF_DATE_KHR => resize = true,
        else => @panic("Failed to present image"),
    }
    self.current_frame = (self.current_frame + 1) % @intCast(u32, self.images.items.len);
    return resize;
}
