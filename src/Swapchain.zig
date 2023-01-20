const c = @import("c.zig");
const std = @import("std");
const vk = @import("vk.zig");
const VulkanContext = @import("VulkanContext.zig");

const print = std.debug.print;
const zeroInit = std.mem.zeroInit;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

device: c.VkDevice,
surface: c.VkSurfaceKHR,
swapchain: c.VkSwapchainKHR,
current_frame: usize,
images: std.ArrayList(c.VkImage),
views: std.ArrayList(c.VkImageView),

const Self = @This();

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
    for (images.items) |img| {
        const ci = zeroInit(c.VkImageViewCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = img,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = formats.items[0].format,
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
        views.appendAssumeCapacity(view);
    }
    return Self{
        .device = device,
        .surface = surface,
        .swapchain = swapchain,
        .current_frame = 0,
        .images = images,
        .views = views,
    };
}

pub fn deinit(self: *Self) void {
    std.log.debug("Swapchain.deinit()", .{});
    std.log.debug("Destroying VkImageView", .{});
    for (self.views.items) |v| {
        c.vkDestroyImageView(self.device, v, null);
    }
    self.views.deinit();
    std.log.debug("Destroying VkSwapchainKHR [0x{x}]", .{@ptrToInt(self.swapchain)});
    c.vkDestroySwapchainKHR(self.device, self.swapchain, null);
    self.swapchain = undefined;
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

pub fn acquire(self: *@This()) !usize {
    c.vkAcquireNextImageKHR(
        self.device,
        self.swapchain,
        c.UINT64_MAX,
    );
}
