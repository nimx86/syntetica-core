pub const meta = @import("ui/meta.zig");
pub const ir = @import("ui/IR.zig");
pub const solver = @import("ui/solver.zig");
pub const renderer = @import("ui/renderer.zig");

pub const ui2 = struct {
    pub const Element = @import("ui2/Element.zig");
    pub const IR = @import("ui2/IR.zig");
    pub const meta = @import("ui2/meta.zig");
    pub const renderer = @import("ui2/renderer.zig");
    pub const solver = @import("ui2/solver.zig");
    pub const types = @import("ui2/types.zig");
};
