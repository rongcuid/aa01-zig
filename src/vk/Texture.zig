const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");

const zeroInit = std.mem.zeroInit;

allocator: std.mem.Allocator,
vma: c.VmaAllocator,
image: c.VkImage,
alloc: c.VmaAllocation,
pub fn create(
    allocator: std.mem.Allocator,
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
