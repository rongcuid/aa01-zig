//! Simple Nuklear GUI rendering. This uses nuklear-provided font baking and default fonts, intended for debugging only.

const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

const Pipeline = @import("nk/NuklearPipeline.zig");

const MAX_VERTS = 1024;
const MAX_INDEX = 1024;

allocator: std.mem.Allocator,
device: c.VkDevice,
vma: c.VmaAllocator,
/// Owns
context: c.nk_context,
/// Owns
atlas: c.nk_font_atlas,
/// Owns
atlas_texture: *vk.Texture,
/// Owns
atlas_view: c.VkImageView,
/// Owns
pipeline: Pipeline,
convert_cfg: c.nk_convert_config,
/// References `self.atlas_texture`
tex_null: c.nk_draw_null_texture,
/// Owns
cmds: c.nk_buffer,
/// Owns
verts: c.nk_buffer,
vertsBuffer: vk.Buffer,
/// Owns
idx: c.nk_buffer,
idxBuffer: vk.Buffer,

pub fn init(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vma: c.VmaAllocator,
    cache: c.VkPipelineCache,
    texture_manager: *vk.TextureManager,
    shader_manager: *vk.ShaderManager,
) !@This() {
    var img_width: c_int = 1024;
    var img_height: c_int = 1024;
    var atlas: c.nk_font_atlas = undefined;
    c.nk_font_atlas_init_default(&atlas);
    c.nk_font_atlas_begin(&atlas);
    const font = c.nk_font_atlas_add_default(&atlas, 16, null);
    const img = @ptrCast(
        [*]const u8,
        c.nk_font_atlas_bake(&atlas, &img_width, &img_height, c.NK_FONT_ATLAS_RGBA32),
    );
    // Create the texture on device
    const atlas_texture = try texture_manager.loadPixels(
        img[0..@intCast(usize, img_width * img_height * 4)],
        @intCast(u32, img_width),
        @intCast(u32, img_height),
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        c.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL_KHR,
    );
    var atlas_view = try atlas_texture.createDefaultView();
    // Finish atlas
    var tex_null: c.nk_draw_null_texture = undefined;
    c.nk_font_atlas_end(&atlas, c.nk_handle_ptr(atlas_view), &tex_null);
    // Create context
    var context: c.nk_context = undefined;
    if (c.nk_init_default(&context, &font.*.handle) == 0) {
        @panic("Failed to initialize Nuklear");
    }
    const convert_cfg = c.nk_convert_config{
        .shape_AA = c.NK_ANTI_ALIASING_ON,
        .line_AA = c.NK_ANTI_ALIASING_ON,
        .vertex_layout = &VertexLayout,
        .vertex_size = @sizeOf(Pipeline.Vertex),
        .vertex_alignment = @alignOf(Pipeline.Vertex),
        .circle_segment_count = 22,
        .curve_segment_count = 22,
        .arc_segment_count = 22,
        .global_alpha = 1.0,
        .tex_null = tex_null,
    };
    // Nuklear command buffer on CPU
    var cmds: c.nk_buffer = undefined;
    c.nk_buffer_init_default(&cmds);
    // Vert and index buffer on device
    const vertSize = MAX_VERTS * @sizeOf(Pipeline.Vertex);
    const vertsBuffer = try vk.Buffer.initExclusiveSequentialMapped(vma, vertSize, c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    const idxSize = MAX_INDEX * @sizeOf(c_short);
    const idxBuffer = try vk.Buffer.initExclusiveSequentialMapped(vma, idxSize, c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    var verts: c.nk_buffer = undefined;
    c.nk_buffer_init_fixed(&verts, vertsBuffer.allocInfo.pMappedData, vertSize);
    var idx: c.nk_buffer = undefined;
    c.nk_buffer_init_fixed(&idx, idxBuffer.allocInfo.pMappedData, idxSize);

    // Build pipeline
    const pipeline = try Pipeline.init(device, cache, shader_manager);
    return @This(){
        .allocator = allocator,
        .device = device,
        .vma = vma,
        .context = context,
        .atlas = atlas,
        .atlas_texture = atlas_texture,
        .atlas_view = atlas_view,
        .pipeline = pipeline,
        .convert_cfg = convert_cfg,
        .tex_null = tex_null,
        .cmds = cmds,
        .verts = verts,
        .vertsBuffer = vertsBuffer,
        .idx = idx,
        .idxBuffer = idxBuffer,
    };
}

pub fn deinit(self: *@This()) void {
    c.nk_buffer_free(&self.cmds);
    c.nk_buffer_free(&self.verts);
    c.nk_buffer_free(&self.idx);
    self.vertsBuffer.deinit();
    self.idxBuffer.deinit();
    c.nk_font_atlas_clear(&self.atlas);
    c.nk_free(&self.context);
    vk.check(c.vkDeviceWaitIdle(self.device), "Failed to wait device idle");
    self.atlas_texture.destroy();
    self.pipeline.deinit();
}

pub fn render(
    self: *@This(),
    cmd: c.VkCommandBuffer,
    out_image: c.VkImage,
    out_view: c.VkImageView,
    out_layout: c.VkImageLayout,
    out_area: c.VkRect2D,
) !void {
    _ = self;
    _ = cmd;
    _ = out_image;
    _ = out_view;
    _ = out_layout;
    _ = out_area;
}

/// Vertex layout for Nuklear
const VertexLayout = [_]c.nk_draw_vertex_layout_element{
    .{
        .attribute = c.NK_VERTEX_POSITION,
        .format = c.NK_FORMAT_FLOAT,
        .offset = @offsetOf(Pipeline.Vertex, "position"),
    },
    .{
        .attribute = c.NK_VERTEX_TEXCOORD,
        .format = c.NK_FORMAT_FLOAT,
        .offset = @offsetOf(Pipeline.Vertex, "uv"),
    },
    .{
        .attribute = c.NK_VERTEX_COLOR,
        .format = c.NK_FORMAT_R32G32B32A32_FLOAT,
        .offset = @offsetOf(Pipeline.Vertex, "color"),
    },
    // End
    .{
        .attribute = c.NK_VERTEX_ATTRIBUTE_COUNT,
        .format = c.NK_FORMAT_COUNT,
        .offset = 0,
    },
};
