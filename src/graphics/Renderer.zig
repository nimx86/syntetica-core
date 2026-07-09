const std = @import("std");
const Synt = @import("syntetica");

pub const vk = @import("backend/vk.zig");
pub const raylib = @import("backend/raylib/raylib.zig");

const input = Synt.input;
const Renderer = @This();
const log = std.log.scoped(.renderer);

pub const Implementation = enum {
    vulkan,
    opengl,
    raylib,

    pub fn getVtable(impl: Implementation) GraphicsInterfaceVtable {
        return switch (impl) {
            .vulkan => vk.RendererInterface.vtable,
            .opengl => @panic("no implementation"),
        };
    }
};

pub const GraphicsInterfaceVtable = struct {
    id_string: []const u8 = "uknown",

    /// this function accepts a pointer to a pointer where the underlying 
    /// implementation is expected to allocate a pointer to it's data and 
    /// set the first argument to that pointer.
    init: *const fn(**anyopaque, *Synt) anyerror!void,

    /// deinitializes the implementation
    deinit: *const fn(*anyopaque) void,

    /// checks if the implementation's main window is open
    isWindowOpen: *const fn(*anyopaque) bool,

    closeWindow: *const fn(*anyopaque) void,
};

vtable: GraphicsInterfaceVtable,
data_ptr: *anyopaque,

/// Initialize the renderer with a chosen "official" implementation
pub fn init(synt: *Synt, impl: Implementation) !void {
    return Renderer.initImplementation(synt, impl.getVtable());
}

/// Initialize the renderer with a custom implmentation in the form 
/// of a vtable
pub fn initImplementation(
    synt: *Synt, 
    vtable: GraphicsInterfaceVtable
) !void {
    synt.renderer.vtable = vtable;

    try synt.renderer.vtable.init(&synt.renderer.data_ptr, synt);
}

/// Change the implementation without resetting the renderer
pub fn changeImplementation(r: *Renderer, synt: *Synt, impl: Implementation) !void {
    return r.changeImplementationCustom(synt, impl.getVtable());
}

/// Change the implementation to a custom vtable without 
/// resetting the renderer
pub fn changeImplementationCustom(
    r: *Renderer, 
    synt: *Synt, 
    vtable: GraphicsInterfaceVtable
) !void {
    r.vtable.deinit(r.data_ptr);
    r.vtable = vtable;

    return r.vtable.init(&r.data_ptr, synt);
}

/// deinitializes the renderer
pub fn deinit(renderer: *Renderer) void {
    renderer.vtable.deinit(renderer.data_ptr);

    renderer.window.destroy();
}

pub fn isWindowOpen(renderer: *Renderer) bool {
    return renderer.vtable.isWindowOpen(renderer.data_ptr);
}

pub fn closeWindow(renderer: *Renderer) void {
    renderer.vtable.closeWindow(renderer.data_ptr);
}
