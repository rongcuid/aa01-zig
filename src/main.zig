const c = @import("c.zig");
const render = @import("renderer.zig");
const assert = @import("std").debug.assert;

pub fn main() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    var r = try render.Renderer.init();
    defer r.drop();

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }

        _ = c.SDL_RenderClear(r.renderer);
        _ = c.SDL_RenderCopy(r.renderer, r.texture, null, null);
        c.SDL_RenderPresent(r.renderer);

        c.SDL_Delay(17);
    }
}