const c = @import("c.zig");
const renderer = @import("renderer.zig");
const assert = @import("std").debug.assert;

pub fn main() !void {
    try renderer.initializeSDL();
    defer renderer.quitSDL();

    var r = try renderer.Renderer.init();
    defer r.deinit();

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