//! Misc functions used by most of the systems

const std = @import("std");

fn getTypeName(comptime T: type) [:0]const u8 {
    var iter = std.mem.splitBackwardsScalar(u8, @typeName(T), '.');
    return @as([:0]const u8, iter.first() ++ "");
}

pub fn EnumFromTypeSlice(types: []const type) type {
    var texture_fields: [types.len]std.builtin.Type.EnumField = undefined;

    inline for(types, 0..) |meta, i| {
        texture_fields[i] = .{
            .name = getTypeName(meta),
            .value = i,
        };
    }
    
    return @Enum(&.{}, u32, &texture_fields, false);
}

pub fn EnumFromTypeSliceTerminated(comptime types: []const type, comptime last_field: []const u8) type {
    var texture_fields: [types.len + 1]std.builtin.Type.EnumField = undefined;

    inline for(types, 0..) |meta, i| {
        texture_fields[i] = .{
            .name = getTypeName(meta),
            .value = i,
        };
    }

    texture_fields[types.len] = .{.name = last_field, .value = types.len};

    return @Enum(&.{}, u32, &texture_fields, false);
}
