//! intermediate representation of the UI layout

const std = @import("std");

const types = @import("types.zig");
const meta = @import("meta.zig");

const IR = @This();
const Vec2 = @import("default").Vec2.Vec2(types.IntType);
const IntType = types.IntType;

const ElementEnum = enum {
    switch_container, container, spacer, element,
};

pub const Size = struct {
    w: IntType,
    h: IntType,
};

pub const Element = struct {
    which: ElementEnum,
    size: Size,
    position: Vec2,

    children_size: Size,
    // maybe can be sorted to optimize cache efficiency
    children: ?[]Element,

    // the amount of children that need to grow in each direction
    w_grow: usize = 1,
    h_grow: usize = 1,
    remaining_space: IntType = 0,

    id: usize,
    parent_id: ?usize,
    decl_ptr: *const meta.Element,

    // for raylib
    user_data: types.AdditionalData,

    // for additional user data and switch container's selection
    data_id: usize,
};

allocator: std.mem.Allocator,

meta_tree: *const meta.Element,

elements: usize = 0,
tree: []Element = undefined,
root_id: usize,

element_lookup: std.AutoHashMap(usize, *Element),

fn lessThanFnTTB(_:void, lhs: Element, _: Element) bool {
    return if(std.meta.activeTag(lhs.decl_ptr.shared.size.h) == .grow) false else true;
}

fn countMetaElems(self: *IR, tree: *const meta.Element) void {
    switch (tree.specific) {
        .container, .switch_container => |children| {
            self.elements += 1;
            for(children) |*child| self.countMetaElems(child);
        },
        
        else => self.elements += 1,
    }
}

fn copyToIRMemory(
    self: *IR, 
    tree: *const meta.Element, 
    parent_accumulated: usize, 
    accumulated: *usize, 
    index: usize, 
    parent_id: ?usize
) !void {
    const id = parent_accumulated + index;

    self.tree[id] = .{
        .which = switch (tree.specific) {
            .element => .element,
            .container => .container,
            .spacer => .spacer,
            .switch_container => .switch_container,
        },
        .size = .{ .w = 0, .h = 0 },
        .position = .initScalar(0),
        .w_grow = 0,
        .h_grow = 0,
        .id = id,
        .parent_id = parent_id,
        .children = null,
        .children_size = .{ .w = 0, .h = 0},
        .user_data = 0,
        .data_id = if(tree.specific != .switch_container) id else 0,
        .decl_ptr = tree,
    };

    if(tree.shared.uid != 0) {
        const r = try self.element_lookup.getOrPut(tree.shared.uid);
        if(r.found_existing) @panic("Found duplicate uid that are not 0");

        r.value_ptr.* = &self.tree[id];
    }

    switch (tree.specific) {
        .container, .switch_container => |elements| {
            const acc_before = accumulated.*;
            accumulated.* += elements.len;

            self.tree[id].children = 
                self.tree[(acc_before + 1)..(accumulated.* + 1)];

            for(elements, 0..) |*elem, i| {
                try self.copyToIRMemory(elem, acc_before + 1, accumulated, i, id);
            }
        },
        else => {}
    }
}

fn countGrowElems(self: *IR, tree: *Element, parent: ?*Element) void {
    if(
        parent == null and 
        (tree.decl_ptr.shared.size.w == .grow or 
        tree.decl_ptr.shared.size.h == .grow)
    ) {
        @panic("root node cannot grow.");
    } else if(parent != null) {
        if(parent.?.which != .switch_container) {
            if(tree.decl_ptr.shared.size.w == .grow) parent.?.w_grow += 1;
            if(tree.decl_ptr.shared.size.h == .grow) parent.?.h_grow += 1;
        } else {
            parent.?.w_grow = 1;
            parent.?.h_grow = 1;
        }
    }

    var empty: []Element = undefined;
    empty.len = 0;
    for(tree.children orelse empty) |*child|
        self.countGrowElems(child, tree);
}

pub fn pollEvents(self: *IR) void {
    for(self.tree) |*child| {
        switch(child.decl_ptr.specific) { 
            .element => |elem| {
                if(child.user_data != 0 and elem.hooks.active != null) 
                    elem.hooks.active.?(self)
                else if(elem.hooks.inactive != null) 
                    elem.hooks.inactive.?(self);

                child.user_data = 0;
            },
            else => {},
        }
    }
}

pub fn init(allocator: std.mem.Allocator, tree: *const meta.Element) !IR {
    var self: IR = .{
        .allocator = allocator,
        .meta_tree = tree,
        .root_id = 0,
        .element_lookup = @FieldType(IR, "element_lookup").init(allocator),
    };

    self.countMetaElems(tree);
    self.tree = try self.allocator.alloc(Element, self.elements);
    self.elements = 0;

    var accumulated: usize = 0;
    try self.copyToIRMemory(tree, 0, &accumulated, 0, null);

    self.countGrowElems(&self.tree[self.root_id], null);

    return self;
}

pub fn getElementByID(self: *IR, elem_uid: types.UIDType) !*Element {
    const v = self.element_lookup.get(elem_uid);

    if(v == null) return error.ElementNotFound
    else return v.?;
}

// pub fn insertElement(self: *IR, uid: types.UIDType, addelem: Element) !void {
//     if(elem.which != .container or elem.which != .switch_container) 
//         return error.not_a_container;
//
//     // resize the tree to hold an aditional element
//     self.tree = self.allocator.realloc(self.tree, self.tree.len + 1);
//
//     const elem = try self.getElementByID(uid);
//     const slice_ptr = elem.children.?.ptr;
//     const index = @intFromPtr(slice_ptr) - @intFromPtr(self.tree);
// }
