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

/// not to be confused with std.Io
pub const engine_io = @import("io");

const log = std.log.scoped(.root);
const Synt = @This();
pub const KeyBind = engine_io.graphical.KeyBindManager.KeyBind;

// TODO: get rid of this
const glfw = graphics.glfw;
/// syntetica version
pub const version: default.Version = .initVer(0, 1, 0, 0);

allocator: std.mem.Allocator,
appname: [*:0]const u8 = "unnamed",

ecs: ECS.EntityComponentSystem,
components: ECS.DefaultComponents,

keybinds: engine_io.graphical.KeyBindManager,
renderer: graphics.Renderer,
textures: graphics.TextureManager,

io: std.Io,

prefix_dir: std.Io.Dir,

fn init(synt: *Synt) !void {
    _ = synt;
}

fn deinit(synt: *Synt) void {
    synt.prefix_dir.close(synt.io);
    synt.renderer.deinit();
}

pub fn new(appname: [*:0]const u8, allocator: std.mem.Allocator, io: std.Io) !*Synt {
    const self = try allocator.create(Synt);

    self.appname = appname;
    self.allocator = allocator;
    self.io = io;

    self.ecs = .init(allocator, self);
    self.components = try .register(self);

    try graphics.Renderer.init(
        self,
        .raylib,
//        if(glfw.isVulkanSupported()) .vulkan else .opengl
    );

    try self.ecs.registerSystem(graphics.Renderer.System);
    self.keybinds = try .init(allocator, self, Synt.engine_io.graphical.raylib_impl.vtable);

    const exe_path = try std.process.executableDirPathAlloc(self.io, self.allocator);
    defer self.allocator.free(exe_path);
    log.debug("exe path: {s}", .{exe_path});

    const exe_dir = try std.Io.Dir.openDirAbsolute(self.io, exe_path, .{});
    defer exe_dir.close(self.io);
    self.prefix_dir = try exe_dir.openDir(self.io, "..", .{});

    // needs to be done after setting the prefix dir
    self.textures = try .init(self.prefix_dir, self.io);

    self.addTexture(&.{"synt", "test_texture"}) catch {
        log.warn("failed registering texture synt:test_texture", .{});
    };

    return self;
}

pub fn run(synt: *Synt) !void {
    try synt.init();
    defer synt.deinit();

    while (synt.renderer.isWindowOpen()) {
        const window_size = synt.renderer.getWindowSize();

        render: {
            // if the window is minimized, skip processing rendering stuff
            if(window_size.eqlScalar(0)) break :render;

            synt.renderer.loopStart();
            defer synt.renderer.loopEnd();
        }

        synt.keybinds.poll(synt);

        synt.ecs.tick();
    }
}

pub fn stop(synt: *Synt) void {
    synt.renderer.closeWindow();
}

pub fn addTexture(synt: *Synt, comptime texture_path: []const []const u8) !void {
    return synt.textures.registerTexture(
        synt.allocator, &synt.renderer, synt.io, texture_path
    );
}

pub fn getTexture(
    synt: *Synt, comptime texture_path: []const []const u8
) !graphics.Renderer.Texture {
    return synt.textures.getTexture(texture_path);
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
