const std = @import("std");
const Self = @This();
const Allocator = std.mem.Allocator;

pub const Managed = struct {
    gpa: Allocator,
    collection: Self,

    pub inline fn init(path: []const u8, gpa: Allocator) !Managed {
        return .{
            .gpa = gpa,
            .collection = try Self.init(path, gpa),
        };
    }
    pub inline fn initBufferSize(path: []const u8, gpa: Allocator, buf_size: usize) !Managed {
        return .{
            .gpa = gpa,
            .collection = try Self.initBufferSize(path, gpa, buf_size),
        };
    }
    pub inline fn addFile(self: *Managed, comptime name: []const u8, ext: FileType) !*File {
        return self.collection.addFile(name, ext, self.gpa);
    }
    pub inline fn addTxt(self: *Managed, comptime name: []const u8) !*File {
        return self.addFile(name, .txt);
    }
    pub inline fn addZon(self: *Managed, comptime name: []const u8) !*File {
        return self.addFile(name, .zon);
    }
    pub inline fn addBin(self: *Managed, comptime name: []const u8) !*File {
        return self.addFile(name, .bin);
    }
    pub inline fn addCustom(self: *Managed, comptime name: []const u8, ext: [3]u8) !*File {
        return self.addFile(name, .{ .custom = .{ .ext = ext } });
    }
    pub inline fn addCollection(self: *Managed, path: []const u8) !VirtualManaged {
        return self.collection.addCollection(path, self.gpa);
    }
};

/// A collection that uses another collection's data but it's own allocator
pub const VirtualManaged = struct {
    gpa: Allocator,
    collection: *Self,

    pub inline fn init(path: []const u8, gpa: Allocator) !VirtualManaged {
        return .{
            .gpa = gpa,
            .collection = try Self.init(path, gpa),
        };
    }
    pub inline fn initBufferSize(
        path: []const u8, 
        gpa: Allocator, 
        buf_size: usize
    ) !VirtualManaged {
        return .{
            .gpa = gpa,
            .collection = try Self.initBufferSize(path, gpa, buf_size),
        };
    }
    pub inline fn addFile(
        self: VirtualManaged, 
        comptime name: []const u8, 
        ext: FileType
    ) !*File {
        return self.collection.addFile(name, ext, self.gpa);
    }
    pub inline fn addTxt(self: VirtualManaged, comptime name: []const u8) !*File {
        return self.addFile(name, .txt);
    }
    pub inline fn addZon(self: VirtualManaged, comptime name: []const u8) !*File {
        return self.addFile(name, .zon);
    }
    pub inline fn addBin(self: VirtualManaged, comptime name: []const u8) !*File {
        return self.addFile(name, .bin);
    }
    pub inline fn addCustom(self: VirtualManaged, comptime name: []const u8, ext: [3]u8) !*File {
        return self.addFile(name, .{ .custom = .{ .ext = ext } });
    }
    pub inline fn addCollection(self: VirtualManaged, path: []const u8) !VirtualManaged {
        return self.collection.addCollection(path, self.gpa);
    }
};

pub const FileArrayList = std.ArrayListUnmanaged(
    union(enum){ file: File, collection: Self }
);

const extension_size = 3;
pub const FileType = union(enum) {
    zon: void, // zon file
    bin: void, // binary file
    txt: void, // plaintext
    custom: struct{
        ext: [extension_size]u8,
    },
};
pub const FileTypeEnum = @typeInfo(File).@"union".tag_type.?;

pub const File = struct {
    file_type: FileType,
    file: std.fs.File,
    // file doesn't need to be loaded
    // but the file must be registered
    content: ?std.ArrayListUnmanaged(u8),

    /// load the file into memory, asserts the file is not already loaded
    pub fn load(self: *File, gpa: Allocator) !void {
        std.debug.assert(self.content == null);

        self.content = try std.ArrayListUnmanaged(u8).initCapacity(gpa, 64);

        try self.file.seekTo(0);

        const buf_size: comptime_int = 64;

        var buf_reader: [buf_size]u8 = undefined;
        var reader = self.file.reader(&buf_reader);

        // read file contents into memory
        while(reader.interface.takeByte()) |b| {
            try self.content.?.append(gpa, b);
        } else |e| {
            if(e != error.EndOfStream) return e;
        }
    }

    pub fn reload(self: *File, gpa: Allocator) !void {
        std.debug.assert(self.content != null);

        try self.file.seekTo(0);

        const buf_size: comptime_int = 64;

        var buf_reader: [buf_size]u8 = undefined;
        var reader = self.file.reader(&buf_reader);

        // read file contents into memory
        var i: usize = 0;
        while(reader.interface.takeByte()) |b| : (i += 1) {
            try self.content.?.insert(gpa, i, b);
        } else |e| switch(e) {
            error.EndOfStream => {},
            else => return e,
        }
    }

    /// doesn't load the file from the filesystem, instead just assumes 
    /// it's supposed to be empty
    pub inline fn assumeEmpty(self: *File, gpa: Allocator) !void {
        self.content = try std.ArrayListUnmanaged(u8).initCapacity(gpa, 64);
    }

    /// dumps the contents into the corresponding system file
    pub fn flush(self: *File) !void {
        std.debug.assert(self.content != null);

        var buf: [64]u8 = undefined;
        var w = self.file.writer(&buf);
        _ = try w.interface.write(self.content.?.items);
        try w.end();
    }

    pub fn destroy(self: *File, gpa: Allocator) void {
        if(self.content != null) self.content.?.deinit(gpa);
        self.file.close();
    }

    /// after done using the writer it must be deleted otherwise the original File will
    /// not contain the contents written in the file
    pub inline fn createWriter(self: *File, gpa: Allocator) std.Io.Writer.Allocating {
        return std.Io.Writer.Allocating.fromArrayList(gpa, &self.content.?);
    }
    pub inline fn deleteWriter(self: *File, w: *std.Io.Writer.Allocating) void {
        self.content = w.toArrayList();
    }

    pub fn parseZon(self: *File, T: type, gpa: Allocator) !T {
        std.debug.assert(self.content != null);
        std.debug.assert(self.file_type == .zon);
        return std.zon.parse.fromSlice(T, gpa, self.content.?, null, .{});
    }
    pub fn saveZon(self: *File, zon: anytype, gpa: Allocator) !void {
        std.debug.assert(self.file_type == .zon);

        if(self.content == null) try self.assumeEmpty(gpa);
        var w = self.createWriter(gpa);

        try std.zon.stringify.serialize(zon, .{}, &w.writer);

        self.deleteWriter(&w);
    }

    pub inline fn loadBinAlloc(self: *File, gpa: Allocator) []u8 {
        if(self.content == null) self.load(gpa);

        const mem: []u8 = gpa.alloc(u8, self.content.?.items.len);
        @memcpy(mem, self.content.?.items);

        return mem;
    }

    pub inline fn loadBin(self: *File, gpa: Allocator) []u8 {
        if(self.content == null) self.load(gpa);

        return self.content.?.items;
    }
};

var root_path: []const u8 = undefined;
var root_dir: std.fs.Dir = undefined;

buffer: []u8,
dir: std.fs.Dir,
files: FileArrayList,

/// assumes buffer size of 64, see `.initBufferSize()` to change that.
pub inline fn init(path: []const u8, gpa: Allocator) !Self {
    return Self.initBufferSize(path, gpa, 64);
}

pub fn initBufferSize(path: []const u8, gpa: Allocator, buf_size: usize) !Self {
    // TODO: This is wrong, fix it.
    root_path = try std.fs.selfExeDirPathAlloc(gpa);
    root_dir = try std.fs.openDirAbsolute(root_path, .{});

    return .{
        .buffer = try gpa.alloc(u8, buf_size),
        .dir = try root_dir.makeOpenPath(path, .{.iterate = true}),
        .files = try FileArrayList.initCapacity(gpa, 30)
    };
}

/// adds a file to the collection
pub fn addFile(self: *Self, comptime name: []const u8, ext: FileType, gpa: Allocator) !*File {
    const collection = &self.dir;
    
    const extension_text: []const u8 = switch(ext) {
        .zon => ".zon",
        .txt => ".txt",
        .bin => ".bin",
        .custom => |x| "." ++ x.ext,
    };

    // figure out the filename
    const filename = if(@inComptime()) name: {
        break :name name ++ extension_text;
    } else name: {
        // + 1 for the dot
        const buf: []u8 = try gpa.alloc(u8, name.len + extension_size + 1);

        @memcpy(buf[0..name.len], name);
        @memcpy(buf[name.len..], extension_text);

        break :name buf;
    };
    defer if(!@inComptime()) gpa.free(filename);

    // open or create the file
    const f = collection.openFile(filename, .{.mode = .read_write}) catch |e| create_file: {
        if(e == error.FileNotFound) {
            break :create_file try collection.createFile(filename, .{.read = true});
        } else return e;
    };
    try f.seekTo(0);

    // add the file to the collection's array of files 
    // but don't load the file yet
    try self.files.append(gpa, .{.file = .{
        .file = f,
        .file_type = ext,
        .content = null,
    }});

    return &self.files.items[self.files.items.len - 1].file;
}

pub inline fn addTxt(self: *Self, comptime name: []const u8, gpa: Allocator) !*File {
    return self.addFile(name, .txt, gpa);
}

pub inline fn addZon(self: *Self, comptime name: []const u8, gpa: Allocator) !*File {
    return self.addFile(name, .zon, gpa);
}

pub inline fn addBin(self: *Self, comptime name: []const u8, gpa: Allocator) !*File {
    return self.addFile(name, .bin, gpa);
}

pub inline fn addCustom(
    self: *Self, 
    comptime name: []const u8, 
    ext: [3]u8, 
    gpa: Allocator
) !*File {
    return self.addFile(name, .{ .custom = .{ .ext = ext } }, gpa);
}

/// returns a virtual managed collection
pub fn addCollection(self: *Self, path: []const u8, gpa: Allocator) !Self.VirtualManaged {
    const dirpath = dirpath: {
        var parent_path = try self.dir.realpathAlloc(gpa, ".");
        const parent_path_len = parent_path.len + 1;
        errdefer gpa.free(parent_path);

        parent_path = try gpa.realloc(parent_path, parent_path_len + path.len);
        parent_path[parent_path_len - 1] = '/';
        @memcpy(parent_path[parent_path_len..], path);

        std.debug.print(" > path: {s}\n", .{parent_path});

        break :dirpath parent_path;
    };
    defer gpa.free(dirpath);

    try self.files.append(gpa, .{.collection = try .init(dirpath, gpa)});

    return .{
        .gpa = gpa,
        .collection = &self.files.items[self.files.items.len - 1].collection,
    };
}
