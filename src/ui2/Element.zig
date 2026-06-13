//! Stores the actual position/size of the element on screen

const std = @import("std");

const types = @import("types.zig");
const meta = @import("meta.zig");

const IR = @This();
const Vec2 = @import("default").Vec2.Vec2(types.IntType);
const Size = @import("default").Size.Size(types.IntType);
const IntType = types.IntType;

/// alias of the index of an element
pub const Index = usize;

/// alias for the global index of an element
pub const GlobalIndex = usize;

/// all possible root element types
pub const Type = enum {
    container, element, spacer,
};

/// determines the sizing rule for flexbox calculations
pub const SizingRule = struct {
    pub const SizeOptions = union(enum) {
        grow, fit, exact: IntType,

        pub fn val(v: IntType) SizeOptions {
            return .{ .exact = v };
        }
    };

    width: SizeOptions,
    height: SizeOptions,
};

/// determines the grow direction for flexbox calculations,
/// only used on a container
pub const GrowDirectionRule = enum {
    left_to_right, right_to_left, top_to_bottom, bottom_to_top,
};

/// determines the padding of a container in flexbox calculations
pub const Padding = struct {
    left: IntType = 0,
    right: IntType = 0,
    top: IntType = 0,
    bottom: IntType = 0,

    /// initialize all values of padding to a single value
    pub fn initAll(v: IntType) Padding {
        return .{
            .left = v, .right = v,
            .top = v, .bottom = v,
        };
    }
};

/// Header struct that goes into every element as base data
pub const Header = struct {
    /// size of the element
    size: Size,

    /// position of the element
    position: Vec2,

    /// user defined unique ID for a given element
    uid: ?types.UIDType,

    /// user defined custom data for each element
    data: types.ElementInterface.syntui_ElementAdditionalData,

    /// Sizing rule for flexbox calculations
    sizing_rule: SizingRule,

    /// The global index of the parent container
    parent: GlobalIndex,

    /// figure out a way to get rid of this, possibly with a table where 
    /// lookup of any value is possible
    globalid: GlobalIndex,

    pub const empty: Header = .{
        .size = .{ .w = 0, .h = 0 },
        .position = .{ .x = 0, .y = 0 },
        .uid = 0,
        .data = undefined,
        .sizing_rule = .{ .height = .val(0), .width = .val(0) },
        .parent = 0,
        .globalid = 0,
    };
};

/// Container element
pub const Container = struct {
    header: Header,

    /// children indices, these indices are not guaranteed
    /// to stay the same.
    children: std.ArrayList(GlobalIndex),

    /// The amount of children that needs to
    /// grow in each direciton
    grow: Vec2,

    /// grow direction for flexbox calculations 
    direction_rule: GrowDirectionRule,

    /// padding on the sides of children for flexbox calculations
    padding: Padding,

    /// offset of each child excluding the starting and the 
    /// ending ones.
    individual_offset: IntType,

    /// bandaid temporary field since I don't have time 
    /// TODO: Rething how the stuff that uses this field 
    /// should work.
    remaining_space: IntType,

    pub const empty: Container = .{
        .header = .empty,
        .children = .empty,
        .grow = .{ .x = 0, .y = 0 },
        .direction_rule = .left_to_right,
        .padding = .initAll(0),
        .individual_offset = 0,
        .remaining_space = 0,
    };
};

/// A switch container is basically a container but it's treated slightly
/// differently while rendering
pub const SwitchContainer = Container;

/// regular element, this is implementation defined
pub const Element = struct {
    header: Header,
    which: types.Elements,

    pub const empty: Element = .{
        .header = .empty,
        .which = @enumFromInt(0),
    };
};

/// not rendered, exists only as a concept when rendering
pub const Spacer = usize;

/// A node is any element, thus this type is used to reference 
/// any element's pointer with one type. Stores pointers to 
/// elements owned externally.
pub const NodePtr = union(enum) {
    container: *Container,
    element: *Element,
    spacer: *Spacer,

    /// gets the header pointer of the selected node. 
    /// Returns null if the selected node does not 
    /// have a header
    pub fn getHeaderPtr(node: NodePtr) *Header {
        return &(switch(node) {
            .container => |ptr| ptr.header,
            .element => |ptr| ptr.header,
            .spacer => @panic(""),
        });
    }

    /// gets the header pointer of the selected node. 
    /// Returns null if the selected node does not 
    /// have a header
    pub fn getHeader(node: NodePtr) Header {
        return node.getHeaderPtr().*;
    }
};
