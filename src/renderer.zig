const c = @import("c.zig");
const std = @import("std");
const zeroInit = @import("std").mem.zeroInit;
const assert = @import("std").debug.assert;

var alloc = std.heap.c_allocator;

pub fn initializeSDL() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
}

pub fn quitSDL() void {
    c.SDL_Quit();
}

pub const VulkanContext = struct {
    /// Vulkan instance
    instance: c.VkInstance,
    // /// Logical device
    // device: c.VkDevice,
    // /// Present queue. Currently, only this one queue
    // presentQueue: c.VkQueue,x
    pub fn init(window: *c.SDL_Window) !VulkanContext {
        var n_exts: c_uint = undefined;
        var extensions: [16]?[*:0]const u8 = undefined;
        if (c.SDL_Vulkan_GetInstanceExtensions(window, &n_exts, &extensions) != c.SDL_TRUE) {
            @panic("Failed to get required extensions");
        }
        const instance = try createVkInstance(extensions[0..n_exts]);
        return VulkanContext{
            .instance = instance,
            // .device = null,
        };
    }
};

fn createVkInstance(exts: []?[*:0]const u8) !c.VkInstance {
    const appInfo = zeroInit(c.VkApplicationInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "Arcland Air 01",
        .applicationVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "Arcland Engine",
        .engineVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .apiVersion = c.VK_API_VERSION_1_3,
    });
    const instanceCI = zeroInit(c.VkInstanceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .pApplicationInfo = &appInfo,
        .enabledExtensionCount = @intCast(c_uint, exts.len),
        .ppEnabledExtensionNames = exts.ptr,
        .flags = 0,
    });
    var instance: c.VkInstance = undefined;
    const result = c.vkCreateInstance(&instanceCI, null, &instance);
    if (result != c.VK_SUCCESS) {
        @panic("Failed to create VkInstance");
    }
    return instance;
}

pub const Renderer = struct {
    window: *c.SDL_Window,
    context: VulkanContext,
    pub fn init() !Renderer {
        const window = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 300, 73, c.SDL_WINDOW_VULKAN) orelse
            {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const context = try VulkanContext.init(window);
        return Renderer{
            .window = window,
            .context = context,
        };
    }
    pub fn deinit(self: *Renderer) void {
        c.SDL_DestroyWindow(self.window);
        self.window = undefined;
    }
};
