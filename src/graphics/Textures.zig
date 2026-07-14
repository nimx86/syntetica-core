const std = @import("std");
const Synt = @import("syntetica");

const Renderer = @import("Renderer.zig");

const Allocator = std.mem.Allocator;
const Manager = @This();

pub const Error = error {
    TextureAlreadyRegistered,
    TextureDoesntExist,
};

pub const empty: Manager = .{
    .textures = .empty,
};

// TODO: (potential optimization) Make the textures be loaded into vram as one 
// bit texture in pages of textures, after that, make this hashmap only store the 
// page index + texture rect offset to each texture.
textures: std.StringHashMapUnmanaged(Renderer.Texture),
texture_dir: std.Io.Dir,

fn comptimeBuildPath(comptime path: []const []const u8) []const u8 {
    comptime var full_path_str: []const u8 = ".";
    inline for(path) |val| full_path_str = full_path_str ++ "/" ++ val;
    full_path_str = full_path_str ++ ".png";

    return full_path_str;
}

pub fn init(prefix: std.Io.Dir, io: std.Io) std.Io.Dir.OpenError!Manager {
    return .{ 
        .textures = .empty, 
        .texture_dir = try prefix.openDir(io, "res/tex", .{}) 
    };
}

pub fn registerTexture(
    self: *Manager, 
    gpa: Allocator, 
    renderer: *Renderer, 
    io: std.Io,
    comptime path: []const []const u8
) !void {
    const full_path_str = comptime comptimeBuildPath(path);

    const result = try self.textures.getOrPut(gpa, full_path_str);
    if(result.found_existing) return Error.TextureAlreadyRegistered;

    const resource = try self.texture_dir.openFile(io, full_path_str, .{});

    const img = Renderer.Image.initFromFile(io, gpa, resource) catch unreachable;
    result.value_ptr.* = try renderer.vramLoadTexture(img);
}

pub fn getTexture(
    self: *Manager, comptime path: []const []const u8
) Error!Renderer.Texture {
    const full_path_str = comptime comptimeBuildPath(path);

    return self.textures.get(full_path_str) orelse Error.TextureDoesntExist;
}
