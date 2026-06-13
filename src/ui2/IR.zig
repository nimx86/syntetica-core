//! intermediate representation of the UI layout

const std = @import("std");
const default = @import("default");

const types = @import("types.zig");
const meta = @import("meta.zig");
/// IR element
const Element = @import("Element.zig");

const IR = @This();
const FreeList = default.FreeList;
const Vec2 = default.Vec2.Vec2(types.IntType);
const IntType = types.IntType;
const Allocator = std.mem.Allocator;

/// Resolved link of a single element in the element memory
pub const ElementLink = struct {
    /// type of the element
    which: Element.Type,

    /// index of the element in array 
    index: Element.Index,
};

/// Helper API for building out the actual IR
pub const Builder = struct {
    /// always looks in the container_list, so we only need one index.
    current_container: Element.Index,

    IR: *IR,

    pub fn init(gpa: Allocator) Builder {
        const b: Builder = .{
            .IR = gpa.create(IR),
            .current_container = 0,
        };

        return b;
    }

    /// Appends a container to the container list and assigns it as 
    /// the current container.
    pub fn containerAppendAssign(b: *Builder) !Element.Index {
        // assign current container
        b.current_container = try b.containerAppend();

        // return the index of the container
        return b.current_container;
    }

    /// Appends a container but doesn't assign it as the current container
    pub inline fn containerAppend(b: *Builder) !Element.Index {
        return b.IR.reserveElement(.container);
    }

    /// adds a new element to the current container
    pub fn addElement(b: *Builder) !Element.Index {
        const elem_id = b.IR.reserveElement(.element);

        b.IR.getPtr(.container, b.current_container)
            .children.append(b.IR.allocator, elem_id);
    }
};

pub const empty: IR = .{
    .container_list = .empty,
    .element_list = .empty,
    .spacer_list = .empty,
    .elements = .empty,
    .allocator = std.heap.page_allocator,
};

/// global index
root_container: Element.GlobalIndex = 0,

container_list: FreeList.SimpleLinked.Unmanaged(Element.Container),
element_list: FreeList.SimpleLinked.Unmanaged(Element.Element),
spacer_list: FreeList.SimpleLinked.Unmanaged(Element.Spacer),

elements: FreeList.SimpleLinked.Unmanaged(ElementLink),

allocator: Allocator,

/// reserves a single global index for an element.
pub fn reserveElement(ir: *IR, T: Element.Type) !Element.GlobalIndex {
    // reserve space in the respective list 
    const reserved_element_id: usize = try switch(T) {
        .container => ir.container_list.reserve(ir.allocator),
        .element => ir.element_list.reserve(ir.allocator),
        .spacer => ir.spacer_list.reserve(ir.allocator),
    };

    // add the global index, make this be returned maybe?
    const global_index = try ir.elements.insert(ir.allocator, .{
        .which = T,
        .index = reserved_element_id,
    });

    // TODO: make this return both the global index and local index
    return global_index;
}

/// retrieves the parent's link of the given element
pub fn getElemParentID(ir: *IR, global_index: Element.GlobalIndex) Element.GlobalIndex {
    const link = ir.elements.getPtr(global_index).*;
    
    // .header.parent is a global index of the parent.
    return ir.getPtr(link.which, link.index).header.parent;
}

/// retrieves the pointer to the element based on the type of the 
/// element and the index of the element. returns one of the 3 types
/// based on the mentioned selection. This function is comptime, for 
/// a runtime alternative use .getPtrByLink(...)
pub fn getPtr(
    ir: IR,
    comptime T: Element.Type, 
    i: Element.Index,
) *switch(T) { // choose type
    .container => Element.Container,
    .element => Element.Element,
    .spacer => Element.Spacer,
} {
    return switch (T) { // choose which list to use
        .container => ir.container_list,
        .element => ir.element_list,
        .spacer => ir.spacer_list
    }.getPtr(i);
}

/// retrieves the pointer to the element with it's corresponding element 
/// link. This function is runtime friendly, for a more comptime friendly 
/// alternative, use .getPtr(...) method.
pub fn getPtrByLink(
    ir: IR,
    link: ElementLink,
) Element.NodePtr {
    return switch(link.which) {
        .container => .{ .container = ir.container_list.getPtr(link.index) },
        .element => .{ .element = ir.element_list.getPtr(link.index) },
        .spacer => .{ .spacer = ir.spacer_list.getPtr(link.index) },
    };
}

/// returns an element link using a global index
pub fn getLinkByGlobalIndex(ir: IR, id: Element.GlobalIndex) ElementLink {
    return ir.elements.get(id);
} 

pub fn format(ir: *const IR, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try ir.debugPrint(0, ir.root_container, w);
}

fn debugPrint(
    ir: *const IR, 
    indent: usize, 
    container: Element.GlobalIndex, 
    w: *std.Io.Writer
) std.Io.Writer.Error!void {
    const elem_link = ir.getLinkByGlobalIndex(container);
    const elem_ptr = ir.getPtr(.container, elem_link.index);
    const pl = ir.getLinkByGlobalIndex(elem_ptr.header.parent);

    for(0..indent) |_| try w.print("    ", .{});
    try w.print("[{}][C::{}] <- $[{}:{}]\n", .{
        elem_ptr.header.globalid, elem_link.index,
        pl.which, pl.index,
    });

    for(0..indent) |_| try w.print("    ", .{});
    try w.print("  - padding: {}\n", .{elem_ptr.padding});

    for(0..indent) |_| try w.print("    ", .{});
    try w.print("  - direction: {}\n", .{elem_ptr.direction_rule});

    for(0..indent) |_| try w.print("    ", .{});
    try w.print("  - sizing: {}\n", .{elem_ptr.header.sizing_rule});

    for(0..indent) |_| try w.print("    ", .{});
    try w.print("  - individual_offset: {}\n", .{elem_ptr.individual_offset});

    const new_indent = indent + 1;

    for(elem_ptr.children.items) |child| {
        const link = ir.getLinkByGlobalIndex(child);
        switch (link.which) {
            .element => {
                const child_ptr = ir.getPtr(.element, link.index);
                const parent_link = ir.getLinkByGlobalIndex(child_ptr.header.parent);

                for(0..new_indent) |_| try w.print("    ", .{});
                try w.print("[{}][E:{}::{}] UID({?}) <- $[{}:{}::{}]\n", .{
                    child_ptr.header.globalid, child_ptr.which, link.index,
                    child_ptr.header.uid,
                    parent_link.which, parent_link.index, child_ptr.header.parent,
                });
            },

            .container => {
                try ir.debugPrint(new_indent, child, w);
            },

            .spacer => try w.print("[-- SPACER --]\n", .{}),
        }
    }
}
