//! TODO

const std = @import("std");
const graphics = @import("graphics");
const io = @import("io");
const Syntetica = @import("syntetica");

const glfw = graphics.glfw;

pub const WindowData = struct{
    syntetica_instance: *Syntetica,
};

fn glfwKeyCallback(
    w: *glfw.Window, 
    k: glfw.Key, 
    _: c_int, 
    action: glfw.Action, 
    glfw_modifier: glfw.Mods
) callconv(.c) void {
    const window_data = w.getUserPointer(graphics.Renderer.WindowData).?;

    const keybinds = 
        window_data.syntetica_instance.keybinds.get(@intFromEnum(k)) orelse return;

    var mod: io.Modifier = .{
        .shift = glfw_modifier.shift,
        .alt = glfw_modifier.alt,
        .caps_lock = glfw_modifier.caps_lock,
        .control = glfw_modifier.control,
        .num_lock = glfw_modifier.num_lock,
        .super = glfw_modifier.super,
        .repeated = false,
        .pressed = false,
    };

    switch (action) {
        .press => mod.pressed = true,
        .repeat => mod.repeated = true,
        .release => {},
    }

    for(keybinds.items) |keybind|
        if(keybind.modifier.toInt() == mod.toInt()) (keybind.function orelse continue)(window_data.syntetica_instance);
}

fn init(synt: *Syntetica) anyerror!*anyopaque {
    const window_data = try synt.allocator.create(WindowData);
    window_data.syntetica_instance = synt;

    // TODO: cast
    const window_ptr = synt.renderer.getWindowPointer();

    self.window.setUserPointer(window_data);

    _ = synt.renderer.window.setKeyCallback(glfwKeyCallback);
}

fn deinit(*anyopaque) void {
    const window_data = self.renderer.window.getUserPointer(WindowData).?;
    self.ctx.allocator.destroy(window_data);
}

pub const vtable = io.KeyImplVtable{
    .init = init,
};
