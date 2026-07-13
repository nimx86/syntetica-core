const std = @import("std");
const raylib = @import("raylib");
const io = @import("io");
const Synt = @import("syntetica");

pub const vtable = io.graphical.KeyBindManager.KeyImplVtable {
    .init = init,
    .deinit = deinit,
    .isModifierPressed = isModifierPressed,
    .isActionPressed = isActionPressed,
    .poll = poll,
};

fn init(_: *Synt) anyerror!*anyopaque {
    return undefined;
}

fn deinit(_: *anyopaque) void {}

fn isModifierPressed(_: *anyopaque, mod: io.graphical.KeyBindManager.Modifier) bool {

    const active_modifiers = io.graphical.KeyBindManager.Modifier{
        .caps_lock = raylib.isKeyDown(.caps_lock),
        .num_lock = raylib.isKeyDown(.num_lock),
        .super = raylib.isKeyDown(.left_super),
        .alt = raylib.isKeyDown(.left_alt),
        .control = raylib.isKeyDown(.left_control),
        .shift = raylib.isKeyDown(.left_shift),
    };

    return mod.toInt() == active_modifiers.toInt();
}

fn isActionPressed(_: *anyopaque, key: io.graphical.KeyBindManager.Action) bool {
    return switch(key) {
        .keyboard => |k| raylib.isKeyDown(@enumFromInt( @as(c_int, @intFromEnum(k)) )),
        .mouse_button => |m| 
            raylib.isMouseButtonDown(@enumFromInt( @as(c_int, @intFromEnum(m)) )),
        else => @panic("Not implemented"),
    };
}

fn poll(_: *anyopaque) void {
    raylib.pollInputEvents();
}
