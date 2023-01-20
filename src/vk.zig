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

pub fn PfnInstance(comptime pfn: []const u8) type {
    const pfn_typename = "PFN_" ++ pfn;
    const T = @field(c, pfn_typename);
    const P = @typeInfo(T).Optional.child;
    return struct {
        pub fn get(instance: c.VkInstance) !P {
            std.log.debug("PFN: {s}", .{pfn_typename});
            const p = @ptrCast(
                T,
                c.vkGetInstanceProcAddr(instance, pfn.ptr),
            );
            return p orelse return error.PfnNotLoaded;
        }
    };
}
