const c = @import("c.zig");
const assert = @import("std").debug.assert;

pub const Renderer = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    rw: *c.SDL_RWops,
    surface: *c.SDL_Surface,
    texture: *c.SDL_Texture,
    pub fn init() !Renderer {
        const window = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 300, 73, c.SDL_WINDOW_OPENGL) orelse
        {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const renderer = c.SDL_CreateRenderer(window, -1, 0) orelse {
            c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const zig_bmp = @embedFile("zig.bmp");
        const rw = c.SDL_RWFromConstMem(zig_bmp, zig_bmp.len) orelse {
            c.SDL_Log("Unable to get RWFromConstMem: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const zig_surface = c.SDL_LoadBMP_RW(rw, 0) orelse {
            c.SDL_Log("Unable to load bmp: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const zig_texture = c.SDL_CreateTextureFromSurface(renderer, zig_surface) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        return Renderer {
            .window = window,
            .renderer = renderer,
            .rw = rw,
            .surface = zig_surface,
            .texture = zig_texture,
        };
    }
    pub fn drop(self: *Renderer) void {
        c.SDL_DestroyTexture(self.texture);
        c.SDL_FreeSurface(self.surface);
        assert(c.SDL_RWclose(self.rw) == 0);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
    }
};

