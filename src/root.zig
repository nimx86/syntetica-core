//! Syntetica instance

const std = @import("std");
pub const rl = @import("raylib");
pub const rlgui = @import("raygui");
pub const default = @import("default");
pub const config = @import("config");
pub const ECS = @import("ecs");
pub const fs = @import("fs");
pub const ui = @import("ui");
pub const graphics = @import("graphics");

pub const input = @import("input.zig");

const log = std.log.scoped(.root);
const Synt = @This();
const glfw = graphics.Renderer.glfw;
/// syntetica version
pub const version: default.Version = .initVer(0, 1, 0, 0);

allocator: std.mem.Allocator,
appname: [*:0]const u8 = "unnamed",
//ecs: ECS = .empty,
keybinds: std.AutoHashMapUnmanaged(@typeInfo(glfw.Key).@"enum".tag_type, std.ArrayList(input.GlobalKeyBind)),

renderer: graphics.Renderer,

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

    var mod: input.Modifier = .{
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

fn init(synt: *Synt) !void {
    try glfw.init();

    try graphics.Renderer.init(
        synt, 
        synt.allocator, 
        if(glfw.isVulkanSupported()) .vulkan else .opengl
    );

    _ = synt.renderer.window.setKeyCallback(glfwKeyCallback);
}

fn deinit(synt: *Synt) void {
    synt.renderer.deinit(synt.allocator);

    glfw.terminate();
}

pub fn new(appname: [*:0]const u8, allocator: std.mem.Allocator) !*Synt {
    const self = try allocator.create(Synt);

    self.appname = appname;
    self.allocator = allocator;
    self.keybinds = .empty;

    return self;
}

pub fn run(synt: *Synt) !void {
    try synt.init();
    defer synt.deinit();

    while (!synt.renderer.window.shouldClose()) {
        const window_size: default.Vec2.Vec2(c_int) = .initScalar(0);
        glfw.getWindowSize(synt.renderer.window, &window_size.x, &window_size.y);

        glfw.pollEvents();

        // if the window is minimized, skip processing rendering stuff
        if(window_size.eqlScalar(0)) continue;
    }
}

pub fn stop(synt: *Synt) void {
    synt.renderer.window.setShouldClose(true);
}

pub fn bindKeybind(self: *Synt, conf: input.Modifier, key: glfw.Key, function: input.keyBindFnPtr) !void {
    const result = try self.keybinds.getOrPut(self.allocator, @intFromEnum(key));
    
    if(!result.found_existing) {
        result.value_ptr.* = .empty;
    }
    
    try result.value_ptr.append(self.allocator, .{
        .function = function,
        .modifier = conf,
    });
}

// const synt = syntetica.new();
// defer synt.close();
//
// // INIT ///
// synt.ecs.addComponent();
// synt.ecs.addSystem();
// 
// // RUN THE ENGINE //
// synt.run();
//
