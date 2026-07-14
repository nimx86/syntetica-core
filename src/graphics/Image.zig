const std = @import("std");

const stb_image = @import("stb-image");
const rl = @import("raylib");

const Allocator = std.mem.Allocator;
const Image = @This();

/// size must be equal to width * height
bytes: [*]u8,

width: usize,
height: usize,
mipmaps: usize,

pub fn initFromFile(io: std.Io, gpa: Allocator, f: std.Io.File) !Image {
    var buffer: [64]u8 = undefined;
    var reader = std.Io.File.Reader.init(f, io, &buffer); 

    const size = try f.length(io);
    const contents = try std.Io.Reader.readAlloc(&reader.interface, gpa, @intCast(size));

    const img = try rl.loadImageFromMemory(".png", contents);
    return .{
        .bytes = @alignCast(@ptrCast(img.data)),
        .width = @intCast(img.width),
        .height = @intCast(img.height),
        .mipmaps = @intCast(img.mipmaps),
    };
}

pub fn initFromFileStr(filename: [:0]const u8) !Image {
    // TODO: make this work
    // const img = try stb_image.load_image(filename, 4);
    const img = try rl.loadImage(filename);

    std.debug.print("img: {}\n", .{img});
    return .{
        .bytes = @alignCast(@ptrCast(img.data)),
        .width = @intCast(img.width),
        .height = @intCast(img.height),
        .mipmaps = @intCast(img.mipmaps),
    };
}
