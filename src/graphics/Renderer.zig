const std = @import("std");
const Synt = @import("syntetica");
pub const glfw = @import("glfw");

pub const vk = @import("backend/vk.zig");

const input = Synt.input;
const Renderer = @This();
const log = std.log.scoped(.renderer);

pub const Implementation = enum {
    vulkan,
    opengl,

    pub fn getVtable(impl: Implementation) GraphicsInterfaceVtable {
        return switch (impl) {
            .vulkan => vk.RendererInterface.vtable,
            .opengl => @panic("no implementation"),
        };
    }
};

pub const WindowData = struct{
    syntetica_instance: *Synt,
};

pub const GraphicsInterfaceVtable = struct {
    /// this function accepts a pointer to a pointer where the underlying 
    /// implementation is expected to allocate a pointer to it's data and 
    /// set the first argument to that pointer.
    init: *const fn(**anyopaque, *Synt) anyerror!void,

    /// deinitializes the implementation
    deinit: *const fn(*anyopaque) void,
};

window: *glfw.Window,
vtable: GraphicsInterfaceVtable,
data_ptr: *anyopaque,

/// Initialize the renderer with a chosen "official" implementation
pub fn init(synt: *Synt, allocator: std.mem.Allocator, impl: Implementation) !void {
    return Renderer.initImplementation(synt, allocator, impl.getVtable());
}

/// Initialize the renderer with a custom implmentation in the form 
/// of a vtable
pub fn initImplementation(synt: *Synt, allocator: std.mem.Allocator, vtable: GraphicsInterfaceVtable) !void {

    // create a window
    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);

    synt.renderer.window = try glfw.createWindow(1000, 800, "My window", null, null);
    log.debug("window ptr: {*}", .{synt.renderer.window});

    const window_data = try allocator.create(WindowData);
    window_data.syntetica_instance = synt;
    synt.renderer.window.setUserPointer(window_data);

    synt.renderer.vtable = vtable;

    try synt.renderer.vtable.init(&synt.renderer.data_ptr, synt);
}

/// Change the implementation without resetting the renderer
pub fn changeImplementation(r: *Renderer, synt: *Synt, impl: Implementation) !void {
    return r.changeImplementationCustom(synt, impl.getVtable());
}

/// Change the implementation to a custom vtable without 
/// resetting the renderer
pub fn changeImplementationCustom(r: *Renderer, synt: *Synt, vtable: GraphicsInterfaceVtable) !void {
    r.vtable.deinit(r.data_ptr);
    r.vtable = vtable;

    return r.vtable.init(&r.data_ptr, synt);
}

/// deinitializes the renderer
pub fn deinit(renderer: *Renderer, allocator: std.mem.Allocator) void {
    renderer.vtable.deinit(renderer.data_ptr);

    const window_data = renderer.window.getUserPointer(WindowData).?;
    allocator.destroy(window_data);

    renderer.window.destroy();

}
