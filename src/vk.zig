const c = @import("c.zig");
const std = @import("std");

pub const Instance = @import("vk/Instance.zig");
pub const Device = @import("vk/Device.zig");
pub const Swapchain = @import("vk/Swapchain.zig");

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

/// Load a PFN from an instance.
/// FIXME: currently assumes only one instance!
pub fn PfnI(comptime pfn: @TypeOf(.enum_literal)) type {
    const pfn_name = @tagName(pfn);
    const pfn_typename = "PFN_" ++ pfn_name;
    const T = @field(c, pfn_typename);
    const P = @typeInfo(T).Optional.child;
    return struct {
        var use_instance: c.VkInstance = null;
        var ptr: T = null;
        /// Return an instance level pfn
        pub fn on(instance: c.VkInstance) P {
            return ptr orelse {
                std.log.debug("Loading [{s}]", .{pfn_name});
                if (use_instance == null) {
                    use_instance = instance;
                } else if (instance != use_instance) {
                    @panic("Multiple instances!");
                }
                ptr = @ptrCast(
                    T,
                    c.vkGetInstanceProcAddr(instance, pfn_name),
                );
                return ptr orelse @panic("Pfn not found");
            };
        }
    };
}
/// Load a PFN from an instance.
/// FIXME: currently assumes only one device!
pub fn PfnD(comptime pfn: @TypeOf(.enum_literal)) type {
    const pfn_name = @tagName(pfn);
    const pfn_typename = "PFN_" ++ pfn_name;
    const T = @field(c, pfn_typename);
    const P = @typeInfo(T).Optional.child;
    return struct {
        var ptr: T = null;
        /// Return an device level pfn
        pub fn on(device: c.VkDevice) P {
            return ptr orelse {
                std.log.debug("Loading [{s}]", .{pfn_typename});
                ptr = @ptrCast(
                    T,
                    c.vkGetDeviceProcAddr(device, pfn_name),
                );
                return ptr orelse @panic("Pfn not found");
            };
        }
    };
}
