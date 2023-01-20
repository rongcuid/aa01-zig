const c = @import("c.zig");
const std = @import("std");

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

pub const Instance = struct {
    vkInstance: c.VkInstance,
    vkDebugMessenger: c.VkDebugUtilsMessengerEXT,
    portability: bool,

    pub fn init(window: *c.SDL_Window) !Instance {
        var n_exts: c_uint = undefined;
        var extensions: [16]?[*:0]const u8 = undefined;
        if (c.SDL_Vulkan_GetInstanceExtensions(window, &n_exts, &extensions) != c.SDL_TRUE) {
            @panic("Failed to get required extensions");
        }
        // This is the actual required extensions
        var actual_exts = try std.BoundedArray(?[*:0]const u8, 16).init(0);
        try actual_exts.appendSlice(extensions[0..n_exts]);
        try actual_exts.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        // TODO: check if validation layer is available
        var layers = try std.BoundedArray([*:0]const u8, 16).init(0);
        try layers.append("VK_LAYER_KHRONOS_validation");
        // Debug callback
        const debugCI = zeroInit(c.VkDebugUtilsMessengerCreateInfoEXT, .{
            .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = &debugCallback,
        });
        // Create instance
        const appInfo = zeroInit(c.VkApplicationInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "Arcland Air 01",
            .applicationVersion = c.VK_MAKE_VERSION(0, 1, 0),
            .pEngineName = "Arcland Engine",
            .engineVersion = c.VK_MAKE_VERSION(0, 1, 0),
            .apiVersion = c.VK_API_VERSION_1_3,
        });
        var instanceCI = zeroInit(c.VkInstanceCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = &debugCI,
            .pApplicationInfo = &appInfo,
            .enabledExtensionCount = @intCast(c_uint, actual_exts.len),
            .ppEnabledExtensionNames = &actual_exts.buffer,
            .enabledLayerCount = @intCast(c_uint, layers.len),
            .ppEnabledLayerNames = &layers.buffer,
            .flags = 0,
        });
        var instance: c.VkInstance = undefined;
        const result = c.vkCreateInstance(&instanceCI, null, &instance);
        var portability = false;
        if (result == c.VK_SUCCESS) {} else if (result == c.VK_ERROR_INCOMPATIBLE_DRIVER) {
            std.log.info("Failed to create Vulkan instance, trying again with portability subset. This is normal on Mac OS", .{});
            portability = true;
            // Try again with portability
            try actual_exts.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
            instanceCI.enabledExtensionCount = @intCast(c_uint, actual_exts.len);
            instanceCI.ppEnabledExtensionNames = &actual_exts.buffer;
            instanceCI.flags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
            check(c.vkCreateInstance(&instanceCI, null, &instance), "Failed to create VkInstance with portability subset");
        } else {
            check(result, "Failed to create VkInstance");
        }
        var debugMessenger: c.VkDebugUtilsMessengerEXT = null;
        check(
            PfnI("vkCreateDebugUtilsMessengerEXT").get(instance)(instance, &debugCI, null, &debugMessenger),
            "Failed to create VkDebugUtilsMessengerEXT",
        );
        return Instance{
            .vkInstance = instance,
            .vkDebugMessenger = debugMessenger,
            .portability = portability,
        };
    }

    pub fn deinit(self: *@This()) void {
        std.log.debug("Instance.deinit()", .{});
        if (self.vkDebugMessenger) |m| {
            self.pfn("vkDestroyDebugUtilsMessengerEXT")(
                self.vkInstance,
                m,
                null,
            );
        }
        self.vkDebugMessenger = undefined;
        c.vkDestroyInstance(self.vkInstance, null);
        self.vkInstance = undefined;
    }

    export fn debugCallback(
        severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
        msgType: c.VkDebugUtilsMessageTypeFlagsEXT,
        callbackData: ?*const c.VkDebugUtilsMessengerCallbackDataEXT,
        userData: ?*anyopaque,
    ) u32 {
        _ = userData;
        var msg = std.ArrayList(u8).init(std.heap.c_allocator);
        defer msg.deinit();
        if (msgType & c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT != 0) {
            msg.writer().print("GENERAL -- ", .{}) catch @panic("Debug messenger out of memory");
        } else if (msgType & c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT != 0) {
            msg.writer().print("VALIDATION -- ", .{}) catch @panic("Debug messenger out of memory");
        } else if (msgType & c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT != 0) {
            msg.writer().print("PERFORMANCE -- ", .{}) catch @panic("Debug messenger out of memory");
        } else if (msgType & c.VK_DEBUG_UTILS_MESSAGE_TYPE_DEVICE_ADDRESS_BINDING_BIT_EXT != 0) {
            msg.writer().print("ADDRESS BINDING -- ", .{}) catch @panic("Debug messenger out of memory");
        }
        const dat = callbackData orelse return c.VK_FALSE;
        // ID
        msg.writer().print("[{s}]", .{dat.pMessageIdName}) catch @panic("Debug messenger out of memory");
        // Message
        msg.writer().print(" {s}", .{dat.pMessage}) catch @panic("Debug messenger out of memory");
        if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT != 0) {
            std.log.err("{s}", .{msg.items});
        } else if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT != 0) {
            std.log.warn("{s}", .{msg.items});
        } else if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT != 0) {
            std.log.info("{s}", .{msg.items});
        } else if (severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT != 0) {
            std.log.debug("{s}", .{msg.items});
        }
        return c.VK_FALSE;
    }

    pub fn pfn(self: *const Instance, comptime name: [*:0]const u8) @TypeOf(PfnI(name).get(self.vkInstance)) {
        return PfnI(name).get(self.vkInstance);
    }
};

/// Load a PFN from an instance.
/// FIXME: currently assumes only one instance!
pub fn PfnI(comptime pfn: [*:0]const u8) type {
    const pfn_typename = "PFN_" ++ pfn;
    const T = @field(c, pfn_typename);
    const P = @typeInfo(T).Optional.child;
    return struct {
        var ptr: T = null;
        /// Return an instance level pfn
        pub fn get(instance: c.VkInstance) P {
            return ptr orelse {
                std.log.debug("Loading [{s}]", .{pfn_typename});
                ptr = @ptrCast(
                    T,
                    c.vkGetInstanceProcAddr(instance, pfn),
                );
                return ptr orelse @panic("Pfn not found");
            };
        }
    };
}
/// Load a PFN from an instance.
/// FIXME: currently assumes only one device!
pub fn PfnD(comptime pfn: [*:0]const u8) type {
    const pfn_typename = "PFN_" ++ pfn;
    const T = @field(c, pfn_typename);
    const P = @typeInfo(T).Optional.child;
    return struct {
        var ptr: T = null;
        /// Return an device level pfn
        pub fn get(device: c.VkDevice) P {
            return ptr orelse {
                std.log.debug("Loading [{s}]", .{pfn_typename});
                ptr = @ptrCast(
                    T,
                    c.vkGetDeviceProcAddr(device, pfn),
                );
                return ptr orelse @panic("Pfn not found");
            };
        }
    };
}
