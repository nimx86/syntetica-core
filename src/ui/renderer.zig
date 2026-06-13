const ir = @import("IR.zig");
const raylib = @import("raylib");
const raygui = @import("raygui");
const types = @import("types.zig");
pub const FreeList = @import("default").FreeList.SimpleLinkedFreeList(RenderData, 200);
const Vec2 = @import("default").Vec2.Vec2(types.IntType);
const std = @import("std");

pub const RenderData = union {
    container: struct {
        scroll: raylib.Vector2,
        view: raylib.Rectangle,
    },
};

pub const draw = struct {
    pub fn button(offset: Vec2, root: *ir.Element) void {
        root.user_data = @intFromBool(raygui.button(
            .init(
                @floatFromInt(root.position.x + offset.x), 
                @floatFromInt(root.position.y + offset.y), 
                @floatFromInt(root.size.w),
                @floatFromInt(root.size.h)
            ), 
            root.decl_ptr.specific.element.data.button.text
        ));
    }

    pub fn container(offset: Vec2, root: *ir.Element, scroll: *raylib.Vector2, view: *raylib.Rectangle) void {
        root.user_data = raygui.scrollPanel(
            .init(
                @floatFromInt(root.position.x + offset.x), @floatFromInt(root.position.y + offset.y), 
                @floatFromInt(root.size.w + 5), @floatFromInt(root.size.h + 5)
            ), 
            null, 
            .init(
                @floatFromInt(root.position.x), @floatFromInt(root.position.y), 
                @floatFromInt(root.children_size.w), @floatFromInt(root.children_size.h)
            ),
            scroll, 
            view
        );
    }

    pub fn text(offset: Vec2, root: *ir.Element) void {
        root.user_data = @intFromBool(raygui.labelButton(
            .init(
                @floatFromInt(root.position.x + offset.x), 
                @floatFromInt(root.position.y + offset.y), 
                @floatFromInt(root.size.w),
                @floatFromInt(root.size.h)
            ), 
            root.decl_ptr.specific.element.data.label.text 
        ));
    }

}; 

pub fn drawElement(offset: Vec2, data: *FreeList, elem: types.Elements, root: *ir.Element) void {
    _ = data;
    switch (elem) {
        .button => draw.button(offset, root),
        .label => draw.text(offset, root),
    }
}

pub fn drawTree(offset: Vec2, data: *FreeList, tree: *ir.Element) void {
    switch (tree.decl_ptr.specific) {
        .element => |*elem| {
            drawElement(offset, data, elem.which, tree);
        },
        .container => {
            const cont_data = &data.getPtr(tree.data_id).container;

            draw.container(
                offset,
                tree, 
                &data.getPtr(tree.data_id).container.scroll, 
                &data.getPtr(tree.data_id).container.view
            );

            raylib.beginScissorMode(
                @intFromFloat(cont_data.view.x + @as(f32, @floatFromInt(offset.x))),
                @intFromFloat(cont_data.view.y + @as(f32, @floatFromInt(offset.y))),
                @intFromFloat(cont_data.view.width + 10), // these numbers are aquired by trial and error
                @intFromFloat(cont_data.view.height + 10)
            );

            for(tree.children.?) |*child| drawTree(
                Vec2.init(
                    offset.x + @as(i32, @intFromFloat(cont_data.scroll.x)), 
                    offset.y + @as(i32, @intFromFloat(cont_data.scroll.y)),
                ),
                data, 
                child
            );

            raylib.endScissorMode();
        },
        .switch_container => {
            const cont_data = &data.getPtr(tree.data_id).container;

            draw.container(
                offset,
                tree, 
                &data.getPtr(tree.data_id).container.scroll, 
                &data.getPtr(tree.data_id).container.view
            );

            raylib.beginScissorMode(
                @intFromFloat(cont_data.view.x + @as(f32, @floatFromInt(offset.x))),
                @intFromFloat(cont_data.view.y + @as(f32, @floatFromInt(offset.y))),
                @intFromFloat(cont_data.view.width), // these numbers are aquired by trial and error
                @intFromFloat(cont_data.view.height)
            );

            drawTree(
                Vec2.init(
                    offset.x + @as(i32, @intFromFloat(cont_data.scroll.x)), 
                    offset.y + @as(i32, @intFromFloat(cont_data.scroll.y)),
                ),
                data, 
                &tree.children.?[tree.data_id]
            );
        },
        .spacer => {},
    }
}

pub fn renderLayout(data: *FreeList, lay: *ir) void {
    drawTree(.init(0, 0), data, &lay.tree[lay.root_id]);
}
