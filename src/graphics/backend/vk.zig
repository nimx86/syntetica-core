const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const default = @import("default");
pub const vulkan_lib = @import("vulkan");

pub const RenderContext = @import("vulkan/RenderContext.zig");
pub const RenderInstance = @import("vulkan/RenderInstance.zig");

/// vulkan alias that shouldn't be available outside
const vk = vulkan_lib;
const Allocator = std.mem.Allocator;
const Wrapper = @This();

pub const empty = Wrapper{
    .ctx = undefined,
    .instance = .empty,
};

ctx: *RenderContext,
instance: RenderInstance,

fn addExtensions(context: *RenderContext) !void {
    // add layers
    try context.addLayer("VK_LAYER_KHRONOS_validation");
 
    // add instance extensions
    if(builtin.mode == .Debug) {
        try context.addInstanceExtension(vk.extensions.ext_debug_utils.name);
    }

    try context.addInstanceExtension(
        vk.extensions.khr_portability_enumeration.name,
    );
    try context.addInstanceExtension(
        vk.extensions.khr_get_physical_device_properties_2.name,
    );

    try context.addInstanceExtensions(try glfw.getRequiredInstanceExtensions());

    // add device extensions 
    try context.addDeviceExtension(vk.extensions.khr_swapchain.name);
}

pub fn init(
    allocator: Allocator, 
    window: *glfw.Window, 
    appname: [*:0]const u8
) !Wrapper {
    var self: Wrapper = .empty;

    self.ctx = try .init(allocator, window);

    try addExtensions(self.ctx);

    try self.ctx.load(appname, getGlfwInstanceProcAddress);

    var extent: default.Vec2.Vec2(c_int) = .initScalar(0);
    glfw.getFramebufferSize(window, &extent.x, &extent.y);

    self.instance = try .init(self.ctx, .{
        .width = @intCast(extent.x),
        .height = @intCast(extent.y)
    });

    return self;
}

pub fn deinit(self: *Wrapper) void {
    self.instance.deinit(self.ctx);
    self.ctx.deinit();
}

// CALLBACKS //////////
fn syntCreateSurfaceCallback(
    instance: vk.Instance,
    surface: *vk.SurfaceKHR,
    window_ptr_anon: *anyopaque,
) anyerror!void {
    const window_ptr: *glfw.Window = @ptrCast(@alignCast(window_ptr_anon));
    return glfw.createWindowSurface(instance, window_ptr, null, surface);
}

fn getGlfwInstanceProcAddress(
    instance: vk.Instance, 
    procname: [*:0]const u8
) vk.PfnVoidFunction {
    return @ptrCast(glfw.getInstanceProcAddress(instance, procname).?);
}

/////////////////////////
// RENDERER VTABLE IMPLEMENTATION ////////
pub const RendererInterface = struct {
    const Renderer = @import("graphics").Renderer;
    const Synt = @import("syntetica");

    pub const vtable: Renderer.GraphicsInterfaceVtable = .{
        .init = RendererInterface.init,
        .deinit = RendererInterface.deinit,
    };

    fn init(ptr: **anyopaque, synt: *Synt) anyerror!void {
        const wrapper = try synt.allocator.create(Wrapper);
        std.debug.print("window_ptr_init_vtable: {*}\n", .{synt.renderer.window});
        wrapper.* = try .init(synt.allocator, synt.renderer.window, synt.appname);

        ptr.* = wrapper;
    }

    fn deinit(ptr: *anyopaque) void {
        const wrapper: *Wrapper = @alignCast(@ptrCast(ptr));
        wrapper.deinit();
    }
};
