pub usingnamespace @cImport({
    @cInclude("volk.h");
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_vulkan.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("shaderc/shaderc.h");
    // @cDefine("VMA_STATIC_VULKAN_FUNCTIONS", "0");
    // @cDefine("VMA_DYNAMIC_VULKAN_FUNCTIONS", "1");
    @cInclude("vk_mem_alloc.h");
    @cInclude("nuklear.h");
});
