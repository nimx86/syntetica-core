const std = @import("std");
const raylib = @import("raylib");
const raygui = @import("raygui");
const default = @import("default");

const ir = @import("IR.zig");
const types = @import("types.zig");

const Vec2 = default.Vec2.Vec2(types.IntType);
