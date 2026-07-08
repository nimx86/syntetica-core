//! The render instance creates and manages the swapchain and the command buffers, it handles 
//! commands to draw and manage the rendered image

const std = @import("std");
const vk = @import("vulkan");

const default_shaders = struct {
    const vertex align(@alignOf(u32)) = @embedFile("default_vertex_shader").*;
    const fragment align(@alignOf(u32)) = @embedFile("default_fragment_shader").*;
};

const Context = @import("RenderContext.zig");
const Swapchain = @import("Swapchain.zig");
const Vertex = @import("graphics").Vertex;

const RenderInstance = @This();

pub const empty: RenderInstance = .{
    .swapchain = .empty,
    .pipeline_layout = .null_handle,
    .render_pass = .null_handle,
    .pipeline = .null_handle,
};

pub const vertex_info = struct {
    pub const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    pub const attribute_description = [_]vk.VertexInputAttributeDescription{
        vk.VertexInputAttributeDescription{ // vertex shader input variable position
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },

        vk.VertexInputAttributeDescription{ // color
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
    };
};

swapchain: Swapchain,
pipeline_layout: vk.PipelineLayout,
render_pass: vk.RenderPass,
pipeline: vk.Pipeline,
framebuffers: []vk.Framebuffer,
command_pool: vk.CommandPool,

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
    const vertex_shader_create_info = vk.ShaderModuleCreateInfo{
        .code_size = default_shaders.vertex.len,
        .p_code = @ptrCast(&default_shaders.vertex),
    };
    const vertex_shader = try ctx.device.createShaderModule(&vertex_shader_create_info, null);

    const fragment_shader_create_info = vk.ShaderModuleCreateInfo{
        .code_size = default_shaders.fragment.len,
        .p_code = @ptrCast(&default_shaders.fragment),
    };
    const fragment_shader = try ctx.device.createShaderModule(&fragment_shader_create_info, null);

    const shader_stage_create_info = [_]vk.PipelineShaderStageCreateInfo{
        vk.PipelineShaderStageCreateInfo{
            .stage = .{ .vertex_bit = true },
            .module = vertex_shader,
            .p_name = "main",
        },
        vk.PipelineShaderStageCreateInfo{
            .stage = .{ .fragment_bit = true },
            .module = fragment_shader,
            .p_name = "main",
        },
    };

    const vertex_input_state_create_info = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&vertex_info.binding_description),
        .vertex_attribute_description_count = vertex_info.attribute_description.len,
        .p_vertex_attribute_descriptions = &vertex_info.attribute_description,
    };

    const input_assembly_state_create_info = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    const viewport_state_create_info = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined, // set when creating command buffers
        .scissor_count = 1,
        .p_scissors = undefined, // -- || --
    };

    const rasterization_state_create_info = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .clockwise,
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const multisample_state_create_info = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = .false,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const color_blend_attachment_state = vk.PipelineColorBlendAttachmentState{
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const color_blend_state_create_info = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_blend_attachment_state),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynamic_state = [_]vk.DynamicState{ .viewport, .scissor };
    const dynamic_state_create_info = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynamic_state.len,
        .p_dynamic_states = &dynamic_state,
    };

    // finally, configure pipeline create info
    const pipeline_create_info = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &shader_stage_create_info,
        .p_vertex_input_state = &vertex_input_state_create_info,
        .p_input_assembly_state = &input_assembly_state_create_info,
        .p_tessellation_state = null,
        .p_viewport_state = &viewport_state_create_info,
        .p_rasterization_state = &rasterization_state_create_info,
        .p_multisample_state = &multisample_state_create_info,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &color_blend_state_create_info,
        .p_dynamic_state = &dynamic_state_create_info,
        .layout = instance.pipeline_layout,
        .render_pass = instance.render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    _ = try ctx.device.createGraphicsPipelines(
        .null_handle, 
        &.{pipeline_create_info}, 
        null,
        (&instance.pipeline)[0..1],
    );
}

fn createFrameBuffers(inst: *RenderInstance, ctx: *Context) !void {
    const framebuffers = 
        try ctx.allocator.alloc(vk.Framebuffer, inst.swapchain.swap_images.len);
    errdefer ctx.allocator.free(framebuffers);

    // counts how many framebuffers were created so that in case of failure
    // we can see up until which point we have to go and free framebuffers
    var i: usize = 0;
    
    errdefer for(framebuffers[0..i]) |buf| ctx.device.destroyFramebuffer(buf, null);

    for(framebuffers) |*buffer| {
        const frame_buffer_create_info = vk.FramebufferCreateInfo{
            .render_pass = inst.render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&inst.swapchain.swap_images[i].view),
            .width = inst.swapchain.extent.width,
            .height = inst.swapchain.extent.height,
            .layers = 1,
        };

        buffer.* = try ctx.device.createFramebuffer(&frame_buffer_create_info, null);
        i += 1;
    }
}

pub fn init(context: *Context, extent: vk.Extent2D) !RenderInstance {
    var self: RenderInstance = .empty;
    self.swapchain = try .init(context, context.allocator, extent, .null_handle);

    try self.initPipeline(context);
    try self.createRenderPass(context);
    try self.createPipeline(context);
    try self.createFrameBuffers(context);

    const command_pool_create_info = vk.CommandPoolCreateInfo{
        .queue_family_index = context.graphics_queue.family,
    };
    self.command_pool = 
        try context.device.createCommandPool(&command_pool_create_info, null);


    return self;
}

/// does not deinitialize the context
pub fn deinit(self: *RenderInstance, ctx: *Context) void {
    ctx.device.destroyCommandPool(self.command_pool, null);
    for(self.framebuffers) |buf| ctx.device.destroyFramebuffer(buf, null);
    ctx.device.destroyPipeline(self.pipeline, null);
    ctx.device.destroyRenderPass(self.render_pass, null);
    ctx.device.destroyPipelineLayout(self.pipeline_layout, null);
    self.swapchain.deinit(ctx);
}
