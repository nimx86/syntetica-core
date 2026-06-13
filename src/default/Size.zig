pub fn Size(T: type) type {
    return struct {
        const ThisSize = @This();

        w: T,
        h: T,

        /// Initialize size with width and height
        pub fn init(w: T, h: T) ThisSize {
            return .{
                .w = w,
                .h = h,
            };
        }
    };
}

/// Creates a new size struct, types of width and height must match.
pub fn size(w: anytype, h: @TypeOf(w)) Size(@TypeOf(w)) {
    return Size(@TypeOf(w)).init(w, h);
}
