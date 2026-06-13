//! Syntetica public API

const std = @import("std");
pub const rl = @import("raylib");
pub const rlgui = @import("raygui");
pub const default = @import("default");
pub const config = @import("config");
pub const ECS = @import("ecs");
pub const fs = @import("fs");
pub const ui = @import("ui");
pub const graphics = @import("graphics");
pub const glfw = @import("zglfw");
pub const vk = @import("vulkan");

const log = std.log.scoped(.root);
const Synt = @This();

ecs: ECS = .empty,

pub fn new() Synt {
    return .{};
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
