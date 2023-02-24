const c = @import("c.zig");
const std = @import("std");

pub const Instance = @import("vk/Instance.zig");
pub const device = @import("vk/device.zig");
pub const Swapchain = @import("vk/Swapchain.zig");
pub const ShaderManager = @import("vk/ShaderManager.zig");
pub const TextureManager = @import("vk/TextureManager.zig");
pub const Texture = @import("vk/Texture.zig");

const zeroInit = std.mem.zeroInit;

pub fn check(result: c.VkResult, message: []const u8) void {
    if (result != c.VK_SUCCESS) {
        const msg = std.fmt.allocPrint(
            std.heap.c_allocator,
            "{s}: {any}",
            .{ message, result },
            // .{message, @intToEnum(c.VkResult, result)}
        ) catch unreachable;
        defer std.heap.c_allocator.free(msg);
        @panic(msg);
    }
}

pub const Buffer = struct {
    vma: c.VmaAllocator,
    buffer: c.VkBuffer,
    alloc: c.VmaAllocation,
    allocInfo: c.VmaAllocationInfo,

    pub fn initExclusiveSequentialMapped(
        vma: c.VmaAllocator,
        size: usize,
        usage: c.VkBufferUsageFlags,
    ) !Buffer {
        var alloc: c.VmaAllocation = undefined;
        var buffer: c.VkBuffer = undefined;
        var allocInfo: c.VmaAllocationInfo = undefined;
        const ci = zeroInit(c.VkBufferCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = @intCast(c.VkDeviceSize, size),
            .usage = usage,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        });
        const ai = zeroInit(c.VmaAllocationCreateInfo, .{
            .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT | c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .requiredFlags = c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        });
        check(
            c.vmaCreateBuffer(vma, &ci, &ai, &buffer, &alloc, &allocInfo),
            "Failed to create buffer",
        );
        return .{
            .vma = vma,
            .buffer = buffer,
            .alloc = alloc,
            .allocInfo = allocInfo,
        };
    }

    pub fn deinit(self: *Buffer) void {
        c.vmaDestroyBuffer(self.vma, self.buffer, self.alloc);
    }
};
