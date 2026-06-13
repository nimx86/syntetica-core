const std = @import("std");

const meta = @import("meta.zig");
const IR = @import("IR.zig");
const types = @import("types.zig");
const Element = @import("Element.zig");
const Vec2 = types.Vec2;

const IntType = types.IntType;

fn calcPos(ir: *IR, elem: Element.GlobalIndex, offset: *IntType, pos_offset: Vec2) void {
    const link = ir.getLinkByGlobalIndex(elem);
    const elem_ptr = ir.getPtrByLink(link);
    const elem_header = elem_ptr.getHeaderPtr();

    const parent_link = ir.getLinkByGlobalIndex(elem_ptr.getHeader().parent);

    // this is known to always be a container
    const parent_ptr: *Element.Container = ir.getPtrByLink(parent_link).container;

    var thisoffset: Vec2 = .val(0, 0);
    switch(parent_ptr.direction_rule) {
        .left_to_right => {
            thisoffset = .val(offset.*, 0);
            
            elem_header.position = .val(
                parent_ptr.padding.left + thisoffset.x, 
                parent_ptr.padding.top,
            );

            elem_header.position.add(pos_offset);

            offset.* += elem_header.size.w;
        },

        .top_to_bottom => {
            thisoffset = .val(0, offset.*);

            elem_header.position = .val(
                parent_ptr.padding.left, 
                parent_ptr.padding.top + thisoffset.y
            );

            elem_header.position.add(pos_offset);

            offset.* += elem_header.size.h;
        },

        else => @panic("unsuported yet."),
    }

    var child_offset: IntType = 0;
    if(elem_ptr == .container) for(elem_ptr.container.children.items) |element_global_id| {
        calcPos(ir, element_global_id, &child_offset, elem_header.position);
    };

    // TODO: support for switch containers
}

fn calcSize(ir: *IR, elem: Element.GlobalIndex, offset: *IntType, largest: *IntType) void {
    const link = ir.getLinkByGlobalIndex(elem);
    const elem_ptr = ir.getPtrByLink(link);
    const elem_header = elem_ptr.getHeaderPtr();

    const parent_link = ir.getLinkByGlobalIndex(elem_header.parent);

    std.debug.print("parent link: {} for element: $[{s}:{}]\n", .{parent_link, 
        switch(link.which){ .container => "C", .element => "E", .spacer => "S" }, link.index });

    // this is known to always be a container
    const parent_ptr: *Element.Container = ir.getPtrByLink(parent_link).container;

    const parent_padding: Vec2 = .val(
        parent_ptr.padding.left + parent_ptr.padding.right, 
        parent_ptr.padding.top + parent_ptr.padding.bottom
    );

    elem_header.size.w = switch(elem_header.sizing_rule.width) {
        .exact => |val| val,
        .grow => switch(parent_ptr.header.sizing_rule.width) {
            .grow, .exact => switch(parent_ptr.direction_rule) {
                .left_to_right => largest.* - parent_padding.y,

                .top_to_bottom => @divFloor(
                    parent_ptr.remaining_space - parent_padding.x,
                    parent_ptr.grow.x
                ),

                else => @panic(""),
            },
            
            .fit => @panic("can't do that."),
        },
        else => 0,
    };

    elem_header.size.h = switch(elem_header.sizing_rule.height) {
        .exact => |val| val,
        .grow => switch(parent_ptr.header.sizing_rule.width) {
            .grow, .exact => switch(parent_ptr.direction_rule) {
                .left_to_right => largest.* - parent_padding.x,

                .top_to_bottom => @divFloor(
                    parent_ptr.remaining_space - parent_padding.y, 
                    parent_ptr.grow.y
                ),

                else => @panic(""),
            },

            .fit => @panic("can't do that."),
        },
        else => 0,
    };

    var padding: Vec2 = .initScalar(0);
    if(elem_ptr == .container) { // TODO: Implement switch container
        var child_offset: IntType = 0;

        var largest_child: IntType = switch(elem_ptr.container.direction_rule) {
            .left_to_right => elem_header.size.h,
            .top_to_bottom => elem_header.size.w,
            else => @panic(""),
        };

        const container: *Element.Container = elem_ptr.container;
        for(container.children.items) |child| {
            const child_size_type = 
                ir.getPtrByLink(ir.getLinkByGlobalIndex(child)).getHeader().sizing_rule;
            //std.debug.print("sizing rule: {}\n", .{child_size_type});
            
            const child_grow_direction = switch(elem_ptr.container.direction_rule) {
                .left_to_right => child_size_type.width,
                .top_to_bottom => child_size_type.height,
                else => @panic(""),
            };

            switch(child_grow_direction) {
                .grow => continue,
                else => calcSize(ir, child, &child_offset, &largest_child),
            }
        }

        elem_ptr.container.remaining_space = switch(elem_ptr.container.direction_rule) {
            .left_to_right => elem_header.size.w - child_offset,
            .top_to_bottom => elem_header.size.h - child_offset,
            else => @panic(""),
        };

        for(container.children.items) |child| {
            const child_size_type = 
                ir.getPtrByLink(ir.getLinkByGlobalIndex(child)).getHeader().sizing_rule;
            
            const child_grow_direction = switch(elem_ptr.container.direction_rule) {
                .left_to_right => child_size_type.width,
                .top_to_bottom => child_size_type.height,
                else => @panic(""),
            };

            switch(child_grow_direction) {
                .grow => calcSize(ir, child, &child_offset, &largest_child),
                else => continue,
            }
        }

        const expand: Vec2 = switch(elem_ptr.container.direction_rule) {
            .left_to_right => .val(child_offset, largest_child),
            .top_to_bottom => .val(largest_child, child_offset),
            else => @panic(""),
        };

        padding = .val(
            elem_ptr.container.padding.left + elem_ptr.container.padding.right,
            elem_ptr.container.padding.top + elem_ptr.container.padding.bottom,
        );

        // fit elements are exclusively containers
        elem_header.size.w = switch(elem_header.sizing_rule.width) {
            .fit => expand.x + padding.x,
            else => elem_header.size.w,
        };

        elem_header.size.h = switch(elem_header.sizing_rule.height) {
            .fit => expand.y + padding.y,
            else => elem_header.size.h,
        };
    }

    switch(parent_ptr.direction_rule) {
        .left_to_right => {
            offset.* += elem_header.size.w;

            largest.* = @max(largest.*, elem_header.size.h);
        },

        .top_to_bottom => {
            offset.* += elem_header.size.h;

            largest.* = @max(largest.*, elem_header.size.w);
        },

        else => @panic(""),
    }
}

pub fn recalculate(ir: *IR) void {
    var offset: IntType = 0;
    var largest: IntType = 0;

    calcSize(ir, ir.root_container, &offset, &largest);

    offset = 0;
    calcPos(ir, ir.root_container, &offset, .initScalar(0));
}
