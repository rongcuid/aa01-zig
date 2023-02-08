const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");

const zeroInit = std.mem.zeroInit;

allocator: std.mem.Allocator,

device: c.VkDevice,
vma: c.VmaAllocator,

format: c.VkFormat,
image: c.VkImage,
alloc: c.VmaAllocation,

views: std.ArrayList(c.VkImageView),

pub fn createDefault(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vma: c.VmaAllocator,
    format: c.VkFormat,
    width: u32,
    height: u32,
    usage: c.VkImageUsageFlags,
) !*@This() {
    const ci = zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = c.VkExtent3D{ .width = width, .height = height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = usage | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
    });
    return create(allocator, device, vma, &ci);
}
pub fn create(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vma: c.VmaAllocator,
    pImageCI: *const c.VkImageCreateInfo,
) !*@This() {
    const allocCI = zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_AUTO,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    });
    var image: c.VkImage = undefined;
    var alloc: c.VmaAllocation = undefined;
    vk.check(
        c.vmaCreateImage(vma, pImageCI, &allocCI, &image, &alloc, null),
        "Failed to create image",
    );
    var p = try allocator.create(@This());
    const views = std.ArrayList(c.VkImageView).init(allocator);
    p.* = @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
        .format = pImageCI.*.format,
        .image = image,
        .alloc = alloc,
        .views = views,
    };
    return p;
}
pub fn destroy(self: *@This()) void {
    for (self.views.items) |v| {
        c.vkDestroyImageView(self.device, v, null);
    }
    self.views.deinit();
    c.vmaDestroyImage(self.vma, self.image, self.alloc);
    self.allocator.destroy(self);
}

/// Create a managed image view
pub fn createDefaultView(
    self: *@This(),
    format: c.VkFormat,
) !c.VkImageView {
    var view: c.VkImageView = undefined;
    const ci = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = self.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .components = .{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    vk.check(
        c.vkCreateImageView(self.device, &ci, null, &view),
        "Failed to create image view",
    );
    try self.views.append(view);
    return view;
}
