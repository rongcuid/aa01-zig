const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");

const zeroInit = std.mem.zeroInit;

allocator: std.mem.Allocator,

device: c.VkDevice,
vma: c.VmaAllocator,
image: c.VkImage,
alloc: c.VmaAllocation,
pub fn createDefault(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vma: c.VmaAllocator,
    width: u32,
    height: u32,
    usage: c.VkImageUsageFlags,
) !*@This() {
    const ci = zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = c.VK_FORMAT_R8G8B8A8_UINT,
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
    p.* = @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
        .image = image,
        .alloc = alloc,
    };
    return p;
}
pub fn destroy(self: *@This()) void {
    c.vmaDestroyImage(self.vma, self.image, self.alloc);
    self.allocator.destroy(self);
}
