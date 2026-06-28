//! The render instance creates and manages the swapchain and the command buffers, it handles 
//! commands to draw and manage the rendered image

const std = @import("std");
const vk = @import("vulkan");

const Context = @import("RenderContext.zig");
const Swapchain = @import("Swapchain.zig");

const RenderInstance = @This();

pub const empty: RenderInstance = .{
    .swapchain = .empty,
    .pipeline_layout = .null_handle,
    .render_pass = .null_handle,
    .pipeline = .null_handle,
};

swapchain: Swapchain,
pipeline_layout: vk.PipelineLayout,
render_pass: vk.RenderPass,
pipeline: vk.Pipeline,

fn initPipeline(instance: *RenderInstance, ctx: *Context) !void {
    const create_info = vk.PipelineLayoutCreateInfo{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined
    };
    instance.pipeline_layout = try ctx.device.createPipelineLayout(&create_info, null);
}

fn createRenderPass(instance: *RenderInstance, ctx: *Context) !void {
    // checks if the swapchain is initialized
    std.debug.assert(instance.swapchain.handle != .null_handle);

    const color_attachment = vk.AttachmentDescription{
        .format = instance.swapchain.surface_format.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
    };

    const create_render_pass_info = vk.RenderPassCreateInfo{
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
    };

    instance.render_pass = try ctx.device.createRenderPass(&create_render_pass_info, null);
}

fn createPipeline(instance: *RenderInstance, ctx: *Context) !void {
    _ = instance;
    _ = ctx;
}

pub fn init(context: *Context, extent: vk.Extent2D) !RenderInstance {
    var self: RenderInstance = .empty;
    self.swapchain = try .init(context, context.allocator, extent, .null_handle);

    try self.initPipeline(context);
    try self.createRenderPass(context);

    return self;
}

/// does not deinitialize the context
pub fn deinit(self: *RenderInstance, ctx: *Context) void {
    ctx.device.destroyPipelineLayout(self.pipeline_layout, null);
    self.swapchain.deinit(ctx);
}
