const c = @import("c.zig");
const Renderer = @import("Renderer.zig");
const assert = @import("std").debug.assert;

pub fn main() !void {
    try initializeSDL();
    defer quitSDL();

    var r = try Renderer.init();
    defer r.deinit();
    r.render();
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
        c.SDL_Delay(17);
    }
}

fn initializeSDL() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
}

fn quitSDL() void {
    c.SDL_Quit();
}