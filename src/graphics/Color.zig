const Self = @This();

/// Red
r: u8,

/// Green
g: u8,

/// Blue
b: u8,

/// Alpha
a: u8,

pub fn rgb(r: u8, g: u8, b: u8) Self {
    return .{.r = r, .g = g, .b = b, .a = 255};
}

pub fn rgba(r: u8, g: u8, b: u8, a: u8) Self {
    return .{.r = r, .g = g, .b = b, .a = a};
}

pub fn rgbaNormal(r: f64, g: f64, b: f64, a: f64) Normalized {
    return .{.r = r, .g = g, .b = b, .a = a};
}

pub fn rgbNormal(r: f64, g: f64, b: f64) NormalizedOpaque {
    return .{.r = r, .g = g, .b = b};
}

pub const Normalized = struct {
    r: f64,
    g: f64,
    b: f64,
    a: f64,
};

pub const NormalizedOpaque = struct {
    r: f64,
    g: f64,
    b: f64,
};
