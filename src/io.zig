//! not to be confused with std.Io, used for engine input/output, for example key events in the
//! application or filesystem operations.

const std = @import("std");
const graphics = @import("graphics");
const Synt = @import("syntetica");

/// window events such as key presses.
pub const graphical = @import("io/graphical.zig");

/// filesystem interaction and events.
pub const system = @import("io/system.zig");
