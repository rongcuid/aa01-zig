const c = @import("c.zig");
const std = @import("std");
const vk = @import("vk.zig");
const VulkanContext = @import("VulkanContext.zig");

const print = std.debug.print;
const zeroInit = std.mem.zeroInit;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

context: *const VulkanContext,
surface: c.VkSurfaceKHR,
swapchain: c.VkSwapchainKHR,
swapchainImages: std.ArrayList(c.VkImage),
// swapchainViews: c.VkImageView,

pub fn init(context: *const VulkanContext, window: *c.SDL_Window, allocator: Allocator) !@This() {
    var surface: c.VkSurfaceKHR = undefined;
    if (c.SDL_Vulkan_CreateSurface(window, context.instance, &surface) != c.SDL_TRUE) {
        @panic("Failed to create Vulkan surface");
    }
    var width: i32 = undefined;
    var height: i32 = undefined;
    c.SDL_GetWindowSize(window, &width, &height);
    const swapchain = try createSwapchain(
        context,
        surface,
        @intCast(u32, width),
        @intCast(u32, height),
        null,
    );
    std.log.debug("Created VkSwapchainKHR [0x{x}]", .{@ptrToInt(swapchain)});
    // c.vkDestroySwapchainKHR(context.device, swapchain, null);
    // c.vkDestroySurfaceKHR(context.instance, surface, null);
    // _ = allocator;
    var imageCount: u32 = undefined;
    vk.check(
        c.vkGetSwapchainImagesKHR(context.device, swapchain, &imageCount, null),
        "Failed to get number of swapchain images",
    );
    var images = try std.ArrayList(c.VkImage).initCapacity(allocator, imageCount);
    images.appendNTimesAssumeCapacity(undefined, imageCount);
    vk.check(
        c.vkGetSwapchainImagesKHR(context.device, swapchain, &imageCount, images.items.ptr),
        "Failed to get swapchain images",
    );
    // for (images.items) |img| {
    //     const ci = zeroInit(c.VkImageViewCreateInfo, .{
    //         .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    //     });
    //     var view: c.VkImageView = undefined;
    //     vk.check(
    //         c.vkCreateImageView(context.device, &ci, null, &view),
    //         "Failed to create VkImageView",
    //     );
    // }
    return @This(){
        .context = context,
        .surface = surface,
        .swapchain = swapchain,
        .swapchainImages = images,
    };
}

pub fn deinit(self: *@This()) void {
    std.log.debug("VulkanOutput.deinit()", .{});
    std.log.debug("Destroying VkSwapchainKHR [0x{x}]", .{@ptrToInt(self.swapchain)});
    c.vkDestroySwapchainKHR(self.context.device, self.swapchain, null);
    self.swapchain = undefined;
    c.vkDestroySurfaceKHR(self.context.instance, self.surface, null);
    self.surface = undefined;
    self.context = undefined;
}

fn createSwapchain(
    context: *const VulkanContext,
    surface: c.VkSurfaceKHR,
    width: u32,
    height: u32,
    oldSwapchain: c.VkSwapchainKHR,
) !c.VkSwapchainKHR {
    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    vk.check(
        c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(context.physicalDevice, surface, &capabilities),
        "Failed to get physical device capabilities",
    );
    var formatCount: u32 = undefined;
    vk.check(
        c.vkGetPhysicalDeviceSurfaceFormatsKHR(context.physicalDevice, surface, &formatCount, null),
        "Failed to get number of surface formats",
    );
    var formats = try std.BoundedArray(c.VkSurfaceFormatKHR, 128).init(formatCount);
    vk.check(
        c.vkGetPhysicalDeviceSurfaceFormatsKHR(context.physicalDevice, surface, &formatCount, &formats.buffer),
        "Failed to get number of surface formats",
    );
    const swapchainCI = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .surface = surface,
        .minImageCount = 3,
        .imageFormat = formats.buffer[0].format,
        .imageColorSpace = formats.buffer[0].colorSpace,
        // TODO: clamp this
        .imageExtent = c.VkExtent2D{
            .width = width,
            .height = height,
        },
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 1,
        .pQueueFamilyIndices = &context.graphicsQueueFamilyIndex,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = c.VK_PRESENT_MODE_FIFO_KHR,
        .clipped = c.VK_TRUE,
        .oldSwapchain = oldSwapchain,
    };
    var swapchain: c.VkSwapchainKHR = undefined;
    vk.check(
        c.vkCreateSwapchainKHR(context.device, &swapchainCI, null, &swapchain),
        "Failed to create VkSwapchainKHR",
    );
    return swapchain;
}
