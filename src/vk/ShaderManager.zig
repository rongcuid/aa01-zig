//! Shader resource manager

const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");

const zeroInit = std.mem.zeroInit;

const ShaderMap = std.StringHashMap(c.VkShaderModule);

allocator: std.mem.Allocator,

device: c.VkDevice,

compiler: c.shaderc_compiler_t,
shaders: ShaderMap,

pub const ShaderKind = enum {
    vertex,
    fragment,
    compute,
    pub fn toShadercKind(self: ShaderKind) c.shaderc_shader_kind {
        return switch (self) {
            .vertex => c.shaderc_glsl_vertex_shader,
            .fragment => c.shaderc_glsl_fragment_shader,
            .compute => c.shaderc_glsl_compute_shader,
        };
    }
};

pub fn init(allocator: std.mem.Allocator, device: c.VkDevice) !@This() {
    const compiler = c.shaderc_compiler_initialize();
    if (compiler == null) {
        @panic("Failed to initialize shaderc");
    }
    const shaders = ShaderMap.init(allocator);
    return @This(){
        .allocator = allocator,
        .device = device,
        .compiler = compiler,
        .shaders = shaders,
    };
}

pub fn deinit(self: *@This()) void {
    var iter = self.shaders.valueIterator();
    while (iter.next()) |pShader| {
        c.vkDestroyShaderModule(self.device, pShader.*, null);
    }
    self.shaders.deinit();
    c.shaderc_compiler_release(self.compiler);
}

pub fn loadDefault(self: *@This(), path: [:0]const u8, kind: ShaderKind) !c.VkShaderModule {
    if (self.shaders.get(path)) |shader| {
        return shader;
    }
    const src = try std.fs.cwd().readFileAlloc(self.allocator, path, std.math.maxInt(usize));
    // Compile
    const options = c.shaderc_compile_options_initialize();
    defer c.shaderc_compile_options_release(options);
    if (options == null) {
        @panic("Failed to initialize options");
    }
    c.shaderc_compile_options_set_warnings_as_errors(options);
    const result = c.shaderc_compile_into_spv(
        self.compiler,
        src.ptr,
        src.len,
        kind.toShadercKind(),
        path,
        "main",
        options,
    );
    defer c.shaderc_result_release(result);
    if (result == null) {
        @panic("Failed to allocate for compilation");
    }
    const status = c.shaderc_result_get_compilation_status(result);
    if (status != c.shaderc_compilation_status_success) {
        const msg = c.shaderc_result_get_error_message(result);
        std.log.err("Shaderc error: {s}", .{msg});
        @panic("Shader compile failed");
    }
    const spv = c.shaderc_result_get_bytes(result);
    // Create shader module
    const ci = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = c.shaderc_result_get_length(result),
        .pCode = @ptrCast([*]const u32, @alignCast(@alignOf(u32), spv)),
    };
    var shader: c.VkShaderModule = undefined;
    vk.check(
        c.vkCreateShaderModule(self.device, &ci, null, &shader),
        "Failed to create shader module",
    );
    // Store and return
    try self.shaders.put(path, shader);
    return shader;
}
