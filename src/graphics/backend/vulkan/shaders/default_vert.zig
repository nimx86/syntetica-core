const std = @import("std");
const gpu = std.gpu;

const a_pos = @extern(*addrspace(.input) @Vector(2, f32), .{
    .name = "a_pos",
    .decoration = .{ .location = 0 },
});
const a_color = @extern(*addrspace(.input) @Vector(3, f32), .{
    .name = "a_color",
    .decoration = .{ .location = 1 },
});
const v_color = @extern(*addrspace(.output) @Vector(3, f32), .{
    .name = "v_color",
    .decoration = .{ .location = 0 },
});

export fn main() callconv(.spirv_vertex) void {
    gpu.position_out.* = .{ a_pos.*[0], a_pos.*[1], 0.0, 1.0 };
    v_color.* = a_color.*;
}
