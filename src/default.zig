pub const QueueList = @import("default/QueueList.zig");
pub const FreeList = @import("default/FreeList.zig");
//pub const ArrayLinkedList = @import("default/ArrayLinkedList.zig");
pub const math = @import("default/math.zig");
pub const meta = @import("default/meta.zig");
pub const Vec2 = @import("default/Vec2.zig");
pub const Size = @import("default/Size.zig");

/// 12 bytes            10 bytes        7 bytes      3 bytes
/// |-------PATCH-------|-----MINOR-----|---MAJOR----|-VARIANT--|
/// = 32b total
pub const Version = packed struct {
    patch: u12,
    minor: u10,
    major: u7,
    variant: u3,

    pub fn initVer(vr: u3, ma: u12, mi: u10, pa: u7) Version {
        return .{ .variant = vr, .major = ma, .minor = mi, .patch = pa};
    }

    pub fn toU32(self: Version) u32 {
        return @bitCast(self);
    }
};
