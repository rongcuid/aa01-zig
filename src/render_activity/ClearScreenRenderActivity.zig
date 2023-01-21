const std = @import("std");
const c = @import("../c.zig");
const vk = @import("../vk.zig");
const zeroInit = std.mem.zeroInit;

/// Clear screen color
clear_color: c.VkClearValue,
/// References the device render activity is on
device: c.VkDevice,

pub fn init(
    device: c.VkDevice,
    clear_color: c.VkClearValue,
) !@This() {
    return @This(){
        .device = device,
        .clear_color = clear_color,
    };
}

pub fn deinit() void {}

pub fn render(
    self: *@This(),
    /// Must be in Initial state
    cmd: c.VkCommandBuffer,
    out_image: c.VkImage,
    out_view: c.VkImageView,
    out_layout: c.VkImageLayout,
    out_area: c.VkRect2D,
) !void {
    const color_att_info = zeroInit(c.VkRenderingAttachmentInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO_KHR,
        .imageView = out_view,
        .imageLayout = c.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL_KHR,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = self.clear_color,
    });
    const rendering_info = zeroInit(c.VkRenderingInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO_KHR,
        .renderArea = out_area,
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_att_info,
    });

    // Start
    try begin_cmd(cmd);
    try begin_transition(cmd, out_image);
    vk.PfnD(.vkCmdBeginRenderingKHR).get(self.device)(cmd, &rendering_info);
    vk.PfnD(.vkCmdEndRenderingKHR).get(self.device)(cmd);
    try end_transition(cmd, out_image, out_layout);
    try end_cmd(cmd);
}

fn begin_cmd(cmd: c.VkCommandBuffer) !void {
    const begin_info = zeroInit(c.VkCommandBufferBeginInfo, .{ .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT });
    vk.check(
        c.vkBeginCommandBuffer(cmd, &begin_info),
        "Failed to begin command buffer",
    );
}

fn begin_transition(
    cmd: c.VkCommandBuffer,
    image: c.VkImage,
) !void {
    const image_barrier = zeroInit(c.VkImageMemoryBarrier, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .image = image,
        .subresourceRange = c.VkImageSubresourceRange {
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    c.vkCmdPipelineBarrier(
        cmd,
        c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        0,
        0,
        null,
        0,
        null,
        1,
        &image_barrier,
    );
}

fn end_transition(
    cmd: c.VkCommandBuffer,
    image: c.VkImage,
    out_layout: c.VkImageLayout,
) !void {
    if (out_layout == c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
        return;
    }
    const image_barrier = zeroInit(c.VkImageMemoryBarrier, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .srcAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .oldLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .newLayout = out_layout,
        .image = image,
        .subresourceRange = c.VkImageSubresourceRange {
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    c.vkCmdPipelineBarrier(
        cmd,
        c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        0,
        0,
        null,
        0,
        null,
        1,
        &image_barrier,
    );
}

fn end_cmd(cmd: c.VkCommandBuffer) !void {
    vk.check(
        c.vkEndCommandBuffer(cmd),
        "Failed to end command buffer",
    );
}
