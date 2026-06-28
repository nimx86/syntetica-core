const std = @import("std");
const vk = @import("vulkan");

const Context = @import("RenderContext.zig");

const Allocator = std.mem.Allocator;
const Swapchain = @This();

const PresentState = enum {optimal, suboptimal};

pub const empty = Swapchain{
    .allocator = .failing,

    .surface_format = undefined,
    .present_mode = @enumFromInt(0),
    .extent = .{
        .width = 0,
        .height = 0,
    },
    .handle = .null_handle,
    .swap_images = std.mem.zeroes([]Swapchain.Image),
    .image_index = 0,
    .next_image_acquired = .null_handle,
};

allocator: Allocator,

surface_format: vk.SurfaceFormatKHR,
present_mode: vk.PresentModeKHR,
extent: vk.Extent2D,
handle: vk.SwapchainKHR,

swap_images: []Swapchain.Image,
image_index: u32,
next_image_acquired: vk.Semaphore,

/// gets the actual extent given the surface capabilities
fn getExtent(capabilities: vk.SurfaceCapabilitiesKHR, extent: vk.Extent2D) vk.Extent2D {
    // if the width/height value of the capabailities is set to the maximum value of 
    // uint32, it needs to be handled by setting the extent to the best possible allowed 
    // value. The extent argument should be equal to the framebuffer size.
    if(capabilities.current_extent.width == std.math.maxInt(u32)) {
        return .{
            // make sure the values don't exceed the capabilities
            .width = std.math.clamp(
                extent.width, 
                capabilities.min_image_extent.width, 
                capabilities.max_image_extent.width
            ),
            .height = std.math.clamp(
                extent.height, 
                capabilities.min_image_extent.height, 
                capabilities.max_image_extent.height
            )
        };
    } else {
        // however if the value is set to a normal number than we just choose it as the 
        // value of our extent
        return capabilities.current_extent;
    }
}

/// gets the format in which the image can be presented on a surface
fn getSwapSurfaceFormat(s: *Swapchain, ctx: *Context) !vk.SurfaceFormatKHR {
    // this is the surface format we are trying to get,
    // TODO: make this a list of acceptable formats so that if this 
    // one is not available we can try for the next one, and then the 
    // next one and so on..
    const preffered: vk.SurfaceFormatKHR = .{
        .format = .b8g8r8a8_srgb,
        .color_space = .srgb_nonlinear_khr,
    };

    const supported_formats = 
        try ctx.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(
            ctx.physical_device.handle, 
            ctx.surface, 
            s.allocator
        );
    defer s.allocator.free(supported_formats);

    for(supported_formats) |format| {
        // found it
        if(std.meta.eql(format, preffered)) return preffered;
    } else {
        // one format must always be supported
        return supported_formats[0];
    }
}

/// Checks supported present modes and returns the best one
fn getPresentMode(s: *Swapchain, ctx: *Context) !vk.PresentModeKHR {
    const supported_present_modes = 
        try ctx.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
            ctx.physical_device.handle, 
            ctx.surface, 
            s.allocator
        );
    defer s.allocator.free(supported_present_modes);

    // we want mailbox, but if it's not supported we choose fifo
    if(std.mem.findScalar(vk.PresentModeKHR, supported_present_modes, .mailbox_khr)) |_|
        return .mailbox_khr;

    // always supported
    return .fifo_khr;
}

fn createSwapchainImages(s: *Swapchain, ctx: *Context) !void {
    const images = try ctx.device.getSwapchainImagesAllocKHR(s.handle, s.allocator);
    defer s.allocator.free(images);

    s.swap_images = try s.allocator.alloc(Swapchain.Image, images.len);
    errdefer s.allocator.free(s.swap_images);

    var count: usize = 0;

    // if any of the function in the loop were to fail, we need to deintialize the 
    // swap images that were intialized
    errdefer for(s.swap_images[0..count]) |swap_image| swap_image.deinit(ctx);

    // initialize swap images
    for(images) |image| {
        s.swap_images[count] = try Image.init(ctx, image, s.surface_format.format);
        count += 1;
    }
}

fn destroySwapChainImages(s: *Swapchain, ctx: *Context) void {
    for(s.swap_images) |image| {
        image.deinit(ctx);
    }
    s.allocator.free(s.swap_images);
}

pub fn init(
    context: *Context, 
    alloc: Allocator, 
    extent: vk.Extent2D, 
    inherit_handle: vk.SwapchainKHR,
) !Swapchain {
    var self: Swapchain = .empty;
    self.allocator = alloc;

    // get the capabilities of our device
    const capabilities = try context.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
        context.physical_device.handle, 
        context.surface
    );

    // the extent we get isn't always correct, so we need to get the actual 
    // surface extent
    const surface_extent = getExtent(capabilities, extent);
    if(surface_extent.width == 0 or surface_extent.height == 0) return error.InvalidExtent;
    self.extent = surface_extent;

    self.surface_format = try self.getSwapSurfaceFormat(context);
    self.present_mode = try self.getPresentMode(context);

    // minimum image count specifies the minimum amount of images it requires to function,
    // but sticking to this minimum can cause blockades where we need to wait for the driver
    // to complete internal operations before we can render to new images, so we request one
    // more than the needed.
    var image_count = capabilities.min_image_count + 1;

    // if the max image count is 0, that means the amount of images is unlimited
    if(capabilities.max_image_count > 0)
        image_count = @min(image_count, capabilities.max_image_count);

    const queue_family_index = [_]u32{
        context.graphics_queue.family, context.present_queue.family
    };

    // if the families are not the same then we can use the concurrent model where they run 
    // in parallel, but if they are the same we need to use the exclusive model.
    const sharing_mode: vk.SharingMode = 
        if(context.graphics_queue.family != context.present_queue.family) .concurrent
        else .exclusive;

    const swapchain_create_info = vk.SwapchainCreateInfoKHR{
        .surface = context.surface,
        .min_image_count = image_count,
        .image_format = self.surface_format.format,
        .image_color_space = self.surface_format.color_space,
        .image_extent = self.extent,

        // a value more than 1 is used for stereoscopic displays
        .image_array_layers = 1,
        .image_usage = .{
            .color_attachment_bit = true, // for rendering directly
            .transfer_dst_bit = true, // for rendering to a seperate and then post processing
        },
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = @intCast(queue_family_index.len),
        .p_queue_family_indices = &queue_family_index,

        // this is used for rotations and stuff of the rendered image
        .pre_transform = capabilities.current_transform,

        // TODO: since this is just an example for now, we disable transparency
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = self.present_mode,
        .clipped = .true,

        // if the swapchain becomes unoptimal, we need to recreate it
        .old_swapchain = inherit_handle,
    };

    const swapchain_handle = 
        try context.device.createSwapchainKHR(&swapchain_create_info, null);
    errdefer context.device.destroySwapchainKHR(swapchain_handle, null);

    // destroy the inherited handle after creating a new swapchain
    if(inherit_handle != .null_handle) {
        context.device.destroySwapchainKHR(inherit_handle, null);
    }

    // set the handle
    self.handle = swapchain_handle;

    try self.createSwapchainImages(context);
    errdefer self.destroySwapChainImages(context);

    self.next_image_acquired = try context.device.createSemaphore(&.{}, null);
    errdefer context.device.destroySemaphore(self.next_image_acquired, null);

    const result = try context.device.acquireNextImageKHR(
        self.handle, std.math.maxInt(u64), self.next_image_acquired, .null_handle
    );
    if(result.result == .not_ready or result.result == .timeout) 
        return error.FailedAcquiringImage;

    self.image_index = 0;
    return self;
}

/// deinitializes everything about the swapchain except the 
/// swapchain itself
pub fn clearSwapchain(s: *Swapchain, ctx: *Context) void {
    s.destroySwapChainImages(ctx);
    ctx.device.destroySemaphore(s.next_image_acquired, null);
}

pub fn deinit(s: *Swapchain, ctx: *Context) void {
    if(s.handle == .null_handle) return;
    s.clearSwapchain(ctx);
    ctx.device.destroySwapchainKHR(s.handle, null);
}

pub fn getCurrentSwapImage(s: Swapchain) Image {
    return s.swap_images[s.image_index];
}

pub fn getCurrentImage(s: Swapchain) vk.Image {
    return s.getCurrentSwapImage().image;
}

pub fn present(s: *Swapchain, command_buffer: vk.CommandBuffer, ctx: *Context) !PresentState {
    // make sure the frame finished rendering 
    const current = s.getCurrentSwapImage();
    try current.waitForFence(ctx);
    try current.resetFence(ctx);

    // submit the command buffer
    const wait_stage = [_]vk.PipelineStageFlags{
        .{ .top_of_pipe_bit = true}
    };
    const submit_info = vk.SubmitInfo{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&current.image_acquired),
        .p_wait_dst_stage_mask = &wait_stage,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&command_buffer),
        .signal_semaphore_count = 1,
        .p_signal_semaphores = @ptrCast(&current.render_finished)
    };
    try ctx.device.queueSubmit(
        ctx.graphics_queue.handle, &.{submit_info}, current.frame_fence
    );

    // present the current frame 
    const present_info = vk.PresentInfoKHR{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&current.render_finished),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&s.handle),
        .p_image_indices = @ptrCast(&s.image_index),
    };
    _ = try ctx.device.queuePresentKHR(ctx.present_queue.handle, &present_info);

    // acquire next frame
    const result = try ctx.device.acquireNextImageKHR(
        s.handle, std.math.maxInt(u64), s.next_image_acquired, .null_handle
    );

    std.mem.swap(
        vk.Semaphore, 
        &s.swap_images[result.image_index].image_acquired, 
        &s.next_image_acquired
    );
    s.image_index = result.image_index;

    return switch (result.result) {
        .success => .optimal,
        .suboptimal_khr => .suboptimal,
        else => unreachable,
    };
}

/// SwapImage
const Image = struct {
    image: vk.Image,
    view: vk.ImageView,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    pub fn init(context: *Context, image: vk.Image, format: vk.Format) !Image {
        const create_info = vk.ImageViewCreateInfo{
            .image = image,
            .view_type = .@"2d",
            .format = format,
            // make all the components be infered from the created defaults
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{ 
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };
        const view = try context.device.createImageView(&create_info, null);
        errdefer context.device.destroyImageView(view, null);

        const image_acquired = try context.device.createSemaphore(&.{}, null);
        errdefer context.device.destroySemaphore(image_acquired, null);

        const render_finished = try context.device.createSemaphore(&.{}, null);
        errdefer context.device.destroySemaphore(render_finished, null);

        const frame_fence = try context.device.createFence(
            &.{ .flags = .{ .signaled_bit = true } }, null
        );
        errdefer context.device.destroyFence(frame_fence, null);

        return Image{
            .image = image,
            .view = view,
            .image_acquired = image_acquired,
            .render_finished = render_finished,
            .frame_fence = frame_fence,
        };
    }

    pub fn deinit(self: Image, context: *Context) void { 
        self.waitForFence(context) catch return;

        context.device.destroyImageView(self.view, null);
        context.device.destroySemaphore(self.image_acquired, null);
        context.device.destroySemaphore(self.render_finished, null);
        context.device.destroyFence(self.frame_fence, null);
    }

    pub fn waitForFence(self: Image, context: *Context) !void {
        _ = try context.device.waitForFences(
            &.{self.frame_fence}, 
            .true, 
            std.math.maxInt(u64)
        );
    }

    pub fn resetFence(self: Image, context: *Context) !void {
        return context.device.resetFences(&.{self.frame_fence});
    }
};
