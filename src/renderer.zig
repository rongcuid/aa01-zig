const c = @import("c.zig");
const std = @import("std");
const zeroInit = @import("std").mem.zeroInit;
const assert = @import("std").debug.assert;
const VulkanContext = @import("VulkanContext.zig");

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
        self.context.deinit();
        c.SDL_DestroyWindow(self.window);
        self.window = undefined;
    }
};
