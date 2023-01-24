pub usingnamespace @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_vulkan.h");
    @cInclude("SDL2/SDL_image.h");
    @cDefine("VMA_STATIC_VULKAN_FUNCTIONS", "0");
    @cDefine("VMA_DYNAMIC_VULKAN_FUNCTIONS", "1");
    @cInclude("vulkan/vulkan.h");
    @cInclude("shaderc/shaderc.h");
    @cInclude("vk_mem_alloc.h");
    @cInclude("nuklear.h");
});
