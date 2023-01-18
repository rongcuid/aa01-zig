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
// swapchainImages: c.VkImage,
// swapchainViews: c.VkImageView,

pub fn init(context: *const VulkanContext, window: *c.SDL_Window) !@This() {
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
    return @This(){
        .context = context,
        .surface = surface,
        .swapchain = swapchain,
    };
}

pub fn deinit(self: *@This()) void {
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
    const swapchainCI = zeroInit(c.VkSwapchainCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = 3,
        .imageFormat = c.VK_FORMAT_B8G8R8A8_SRGB,
        .imageColorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
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
    });
    var swapchain: c.VkSwapchainKHR = undefined;
    vk.check(
        c.vkCreateSwapchainKHR(context.device, &swapchainCI, null, &swapchain),
        "Failed to create VkSwapchainKHR",
    );
    return swapchain;
}
