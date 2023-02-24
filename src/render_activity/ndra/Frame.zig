//! Non-shared data for each frame

const std = @import("std");
const c = @import("../../c.zig");
const vk = @import("../../vk.zig");
const zeroInit = std.mem.zeroInit;
const VulkanContext = @import("../../VulkanContext.zig");

const Pipeline = @import("Pipeline.zig");

const MAX_VERTS = 1024;
const MAX_INDEX = 1024;
const MAX_TEXTURES = 128;

allocator: std.mem.Allocator,
context: *VulkanContext,
/// Owns
verts: c.nk_buffer,
vertsBuffer: vk.Buffer,
/// Owns
idx: c.nk_buffer,
idxBuffer: vk.Buffer,
// Owns.
descriptor_pool: c.VkDescriptorPool,
// Owns. Clears every Frame
descriptor_sets: DescriptorSetMap,

const DescriptorSetMap = std.AutoHashMap(c.VkImageView, c.VkDescriptorSet);

pub fn init(allocator: std.mem.Allocator, context: *VulkanContext) !@This() {
    // Vert and index buffer on device
    const vertSize = MAX_VERTS * @sizeOf(Pipeline.Vertex);
    const vertsBuffer = try vk.Buffer.initExclusiveSequentialMapped(
        context.*.vma,
        vertSize,
        c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
    );
    const idxSize = MAX_INDEX * @sizeOf(c_short);
    const idxBuffer = try vk.Buffer.initExclusiveSequentialMapped(
        context.*.vma,
        idxSize,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
    );
    var verts: c.nk_buffer = undefined;
    c.nk_buffer_init_fixed(&verts, vertsBuffer.allocInfo.pMappedData, vertSize);
    var idx: c.nk_buffer = undefined;
    c.nk_buffer_init_fixed(&idx, idxBuffer.allocInfo.pMappedData, idxSize);

    var descriptor_pool: c.VkDescriptorPool = undefined;
    const poolSizes = [_]c.VkDescriptorPoolSize{
        .{
            .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = MAX_TEXTURES,
        },
    };
    const poolCI = zeroInit(c.VkDescriptorPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1,
        .poolSizeCount = @intCast(u32, poolSizes.len),
        .pPoolSizes = &poolSizes,
    });
    vk.check(
        c.vkCreateDescriptorPool(context.*.device, &poolCI, null, &descriptor_pool),
        "Failed to create descriptor pool",
    );
    const descriptor_sets = DescriptorSetMap.init(allocator);
    return @This(){
        .allocator = allocator,
        .context = context,
        .verts = verts,
        .vertsBuffer = vertsBuffer,
        .idx = idx,
        .idxBuffer = idxBuffer,
        .descriptor_pool = descriptor_pool,
        .descriptor_sets = descriptor_sets,
    };
}

pub fn deinit(self: *@This()) void {
    c.nk_buffer_free(&self.verts);
    c.nk_buffer_free(&self.idx);
    self.vertsBuffer.deinit();
    self.idxBuffer.deinit();
    self.descriptor_sets.deinit();
    c.vkDestroyDescriptorPool(self.context.*.device, self.descriptor_pool, null);
}
