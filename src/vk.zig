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

/// Load a PFN from an instance.
/// FIXME: currently assumes only one instance!
pub fn PfnInstance(comptime pfn: [*:0]const u8) type {
    const pfn_typename = "PFN_" ++ pfn;
    const T = @field(c, pfn_typename);
    const P = @typeInfo(T).Optional.child;
    return struct {
        var ptr: T = null;
        pub fn get(instance: c.VkInstance) !P {
            return ptr orelse {
                std.log.debug("Loading [{s}]", .{pfn_typename});
                ptr = @ptrCast(
                    T,
                    c.vkGetInstanceProcAddr(instance, pfn),
                );
                return ptr orelse return error.PfnNotFound;
            };
        }
    };
}
