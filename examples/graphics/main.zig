const std = @import("std");
const Syntetica = @import("syntetica");
const builtin = @import("builtin");

fn hookClose(synt: *Syntetica) void {
    synt.stop();
}

pub fn main() !void {
    var allocator = std.heap.DebugAllocator(.{ .verbose_log = true }).init;

    const synt: *Syntetica = try .new("my_app", allocator.allocator());

    try synt.bindKeybind(.{.control = true}, .escape, hookClose);

    try synt.run();
}
