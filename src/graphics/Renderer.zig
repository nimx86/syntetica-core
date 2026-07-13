const std = @import("std");
const Synt = @import("syntetica");
const default = @import("default");

pub const vk = @import("backend/vk.zig");
pub const raylib = @import("backend/raylib/raylib.zig");
pub const Image = @import("Image.zig");

const math = default.math;
const input = Synt.input;
const Renderer = @This();
const log = std.log.scoped(.renderer);

/// used to universally reffer to a texture
pub const Texture = struct {
    id: enum(usize) {_},

    width: usize,
    height: usize,
    mipmaps: usize,
};

pub const RenderRect = struct {
    pos: math.Vec2i,
    size: default.Size.Size(usize),
};

pub const Implementation = enum {
    vulkan,
    opengl,
    raylib,

    pub fn getVtable(impl: Implementation) GraphicsInterfaceVtable {
        return switch (impl) {
            .vulkan => vk.RendererInterface.vtable,
            .raylib => raylib.vtable,
            .opengl => @panic("no implementation"),
        };
    }
};

pub const GraphicsInterfaceVtable = struct {
    pub const ImplError = error{
        InitFailed,
        LoadingTextureFailed,
    };

    id_string: []const u8 = "uknown",

    /// this function accepts a pointer to a pointer where the underlying 
    /// implementation is expected to allocate a pointer to it's data and 
    /// set the first argument to that pointer.
    init: *const fn(**anyopaque, *Synt) ImplError!void,

    /// deinitializes the implementation
    deinit: *const fn(*anyopaque) void,

    /// checks if the implementation's main window is open
    isWindowOpen: *const fn(*anyopaque) bool,

    /// closes the window
    closeWindow: *const fn(*anyopaque) void,

    /// optional. Returns the pointer to the main window
    getWindowPointer: ?*const fn(*anyopaque) *anyopaque = null,

    /// gets the window size
    getWindowSize: *const fn(*anyopaque) math.Vec2i,

    /// function that runs at every frame's start, optional
    loopStart: ?*const fn(*anyopaque) void = null,

    /// function that runs at every frame's end, optional
    loopEnd: ?*const fn(*anyopaque) void = null,

    /// loads an array of bytes into vram
    vramLoadTexture: *const fn(*anyopaque, Image) ImplError!Texture,

    /// unloads texture from vram
    vramUnloadTexture: *const fn(*anyopaque, Texture) void,

    /// draw a texture, sample is specified by the 3rd argument, the size/placement
    /// is specified by the following argument and the rotation is specified by the last
    /// argument, in radians.
    drawTexture: *const fn(*anyopaque, Texture, RenderRect, RenderRect, f32) void,
};

pub const RenderError = error{
    NotImplemented,
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
pub fn deinit(renderer: Renderer) void {
    renderer.vtable.deinit(renderer.data_ptr);
}

pub fn isWindowOpen(renderer: Renderer) bool {
    return renderer.vtable.isWindowOpen(renderer.data_ptr);
}

pub fn closeWindow(renderer: Renderer) void {
    renderer.vtable.closeWindow(renderer.data_ptr);
}

pub fn getWindowPointer(renderer: Renderer) RenderError!*anyopaque {
    if(renderer.vtable.getWindowPointer == null) return RenderError.NotImplemented;
    return renderer.vtable.getWindowPointer.?(renderer.data_ptr);
}

pub fn getWindowSize(renderer: Renderer) math.Vec2i {
    return renderer.vtable.getWindowSize(renderer.data_ptr);
}

/// for functions that can be optionally implemented but don't return anything,
/// any time they aren't implemented they will simply be skipped.
pub fn loopStart(renderer: Renderer) void {
    if(renderer.vtable.loopStart != null) renderer.vtable.loopStart.?(renderer.data_ptr);
}

pub fn loopEnd(renderer: Renderer) void {
    if(renderer.vtable.loopEnd != null) renderer.vtable.loopEnd.?(renderer.data_ptr);
}

pub fn vramLoadTexture(renderer: Renderer, image: Image) !Texture {
    return renderer.vtable.vramLoadTexture(renderer.data_ptr, image);
}

pub fn vramUnloadTexture(renderer: Renderer, texture: Texture) void {
    renderer.vtable.vramUnloadTexture(renderer.data_ptr, texture);
}

pub fn drawTexture(
    renderer: Renderer, 
    texture: Texture,
    sample: ?RenderRect,
    rect: RenderRect,
    rotation: f32
) void {
    const default_renderrect: RenderRect = .{ 
        .pos = .initScalar(0),
        .size = .init(texture.width, texture.height),
    };
    renderer.vtable.drawTexture(
        renderer.data_ptr, texture, sample orelse default_renderrect, rect, rotation
    );
}

pub const System = struct {
    const Transform = Synt.ECS.Component.Transform;

    fn texture(texture_twptr: *anyopaque, eid: Synt.ECS.Entity.Index, s: *Synt) void {
        const texture_ptr: *Texture = @alignCast(@ptrCast(texture_twptr));
        const transform = s.ecs.getComponentPtrFromEntity(
            eid, 
            Transform, 
            s.components.transform
        ) catch {
            log.warn("Entity@{} has no Transform@{} component, skipping.", .{@intFromEnum(eid), @intFromEnum(s.components.transform)});
            return;
        };

        s.renderer.drawTexture(texture_ptr.*, null, .{ 
            .size = .{.w = texture_ptr.width * 2, .h = texture_ptr.height * 2},
            .pos = .val(@intFromFloat(transform.x), @intFromFloat(transform.y))
        }, transform.rot);
    }

    pub fn init(synt: *Synt, create_info: *Synt.ECS.SystemCreateInfo) Synt.ECS.System.Error!void {
        try create_info.operatesOn(&.{synt.components.texture});
        try create_info.addFunctions(&.{texture});
    }
};
