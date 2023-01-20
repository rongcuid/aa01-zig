const c = @import("c.zig");
const std = @import("std");

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

pub fn Pfn(comptime T: type) type {
    return struct {
        pub fn get(instance: c.VkInstance) !T {
            const name = @typeName(T);
            if (std.mem.eql(u8, name[0..4], "PFN_")) {
                return error.InvalidPfnType;
            }
            const ptr = c.vkGetInstanceProcAddr(instance, name[4..]);
            if (ptr == null) {
                return error.PfnNotFound;
            } else {
                return @ptrCast(T, ptr);
            }
        }
    };
}