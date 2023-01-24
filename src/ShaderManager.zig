//! Shader resource manager

const std = @import("std");
const c = @import("c.zig");
const vk = @import("vk.zig");

const zeroInit = std.mem.zeroInit;

const ShaderMap = std.StringHashMap(c.VkShaderModule);

allocator: std.mem.Allocator,

device: c.VkDevice,

compiler: c.shaderc_compiler_t,
shaders: ShaderMap,

pub fn init(allocator: std.mem.Allocator, device: c.VkDevice) !@This() {
    const compiler = c.shaderc_compiler_initialize();
    if (compiler == null) {
        @panic("Failed to initialize shaderc");
    }
    const shaders = ShaderMap.init(allocator);
    return @This() {
        .allocator = allocator,
        .device = device,
        .compiler = compiler,
        .shaders = shaders,
    };
}

pub fn deinit(self: *@This()) void {
    for (self.shaders.valueIterator()) |shader| {
        c.vkDestroyShaderModule(self.device, shader, null);
    }
    self.shaders.deinit();
    c.shaderc_compiler_release(self.compiler);
}

pub fn load(self: *@This(), path: [:0]const u8) !c.VkShaderModule {
    if (self.shaders.get(path)) |shader| {
        return shader;
    }
    return null;
}