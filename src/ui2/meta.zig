//! "meta programming" - used to define the layout in a zig-friendly way
//! (also should allow parsing of .ui.zon files in the future)

const std = @import("std");

const IR = @import("IR.zig");
const types = @import("types.zig");
const Element = @import("Element.zig");
const api = @import("api.zig");

const IntType = types.IntType;
const Allocator = std.mem.Allocator;

pub const API = struct {
    IR: *IR,

    /// interface to the component vtable and functions
    component: types.ElementInterface = .{},
    selected_container_globalID: usize,
    selected_container: usize,

    const ContainerConf = struct {
        /// padding on the sides of the children of the container
        padding: Element.Padding = .{},
        /// the direction elements are going to be placed in
        direction: Element.GrowDirectionRule = .left_to_right,
        /// which sizing rule the container will follow
        sizing: Element.SizingRule = .{ .height = .grow, .width = .grow },
        /// the space between individual children in the container
        individual_offset: IntType = 0,
    };

    /// creates a new element, avoid the usage of this outside interface implementation
    pub fn createElement(self: *API) struct{
        globalid: Element.GlobalIndex,
        array_index: Element.Index,
        element_ptr: *Element.Element,
        parent_ptr: *Element.Container,
    } {
        // reserve the element
        const global_elemid = self.IR.reserveElement(.element) 
            catch @panic("failed reserving element for UI.");

        const link = self.IR.getLinkByGlobalIndex(global_elemid);

        // set the current selected container as the parent of 
        // the created element
        const elem_ptr = self.IR.getPtr(.element, link.index);

        // intialize the new element to 0
        elem_ptr.* = .empty;
        
        // make sure to set the global id of the selected container as 
        // the parent
        elem_ptr.header.parent = self.selected_container_globalID;
        std.debug.print("[+] ADD element with gid: {}\n", .{global_elemid});
        std.debug.print("  + selected container: {}\n", .{self.selected_container_globalID});
        const parentl = self.IR.getLinkByGlobalIndex(elem_ptr.header.parent);
        std.debug.print("  + parent is: [{}:{}]\n", .{parentl.which, parentl.index});
        elem_ptr.header.globalid = global_elemid;

        const parent_ptr = self.IR.getPtr(.container, self.selected_container);

        // append the newly created element to the parent container's thing
        parent_ptr.children.append(self.IR.allocator, global_elemid)
            catch @panic("failed appending new children to element.");

        return .{
            .globalid = global_elemid,
            .array_index = link.index,
            .element_ptr = elem_ptr,
            .parent_ptr = parent_ptr,
        };
    }

    /// used for configuring the root container
    pub fn rootConf(self: *API, conf: ContainerConf) void {
        const ptr = self.IR.container_list.getRootPtr();
        ptr.header.sizing_rule = conf.sizing;
        ptr.direction_rule = conf.direction;
        ptr.padding = conf.padding;
        ptr.individual_offset = conf.individual_offset;
    }

    /// after adding all the elements, call .end(...)
    pub fn container(self: *API, conf: ContainerConf) void {
        const global_elemid = self.IR.reserveElement(.container) catch 
            @panic("reserving element failed at an unrecoverable stage.");
        const link = self.IR.getLinkByGlobalIndex(global_elemid);
        const current_container_ptr = self.IR.container_list.getPtr(self.selected_container);

        // append the newly created container's global id to the parent container's 
        // child list.
        current_container_ptr.children.append(self.IR.allocator, global_elemid) catch 
            @panic("append failed at an unrecoverable stage");

        const ptr = self.IR.getPtr(.container, link.index);

        std.debug.print("creating container at: G:{}; L:{}\n", .{global_elemid, link.index});

        // make sure the container's children array is propperly initialized
        ptr.children = .empty;

        // assign the parent container to be the currently assigned container's global ID
        ptr.header.parent = self.selected_container_globalID;
        ptr.header.globalid = global_elemid;

        ptr.header.sizing_rule = conf.sizing;
        ptr.direction_rule = conf.direction;
        ptr.padding = conf.padding;
        ptr.individual_offset = conf.individual_offset;

        // assign the global index of the current working container
        self.selected_container_globalID = global_elemid;

        // select the newly created container as the current container
        // must go at the end because the assignment of the parent container 
        // requires this value to be unchanged
        self.selected_container = link.index;
    }

    /// call after all elements after .container(...) were added.
    pub fn end(self: *API) void {
        // if this function is ran on the root container, skip it.
        if(self.IR.container_list.root.? == self.selected_container) return;

        // otherwise set the current container to be the last container
        self.selected_container = 
            self.IR.container_list.links[self.selected_container].prev;

        self.selected_container_globalID = 
            self.IR.getPtr(.container, self.selected_container).header.globalid;

        std.debug.print("selecting container at link $[C:{}::{}]\n", .{self.selected_container, self.selected_container_globalID});
    }
};

/// takes a ui builder function and returns the IR it produces.
pub fn createIR(fx: *const fn(*API) void, gpa: Allocator) !IR {
    var ir: IR = .empty;
    ir.allocator = gpa;

    // create the root container
    const globalid = try ir.reserveElement(.container);

    // set the root container to be the newly created
    // container
    ir.root_container = globalid;

    // get the link to the root container
    const link = ir.getLinkByGlobalIndex(globalid);

    const root_container_ptr = ir.getPtr(.container, link.index);
    root_container_ptr.* = .empty;

    std.debug.print("root container global id: {}\n", .{globalid});
    std.debug.print(" + link: [{}:{}]\n", .{link.which, link.index});
    root_container_ptr.header.globalid = globalid;
    root_container_ptr.header.parent = 0;

    // make sure the children array for the root container is 
    // propperly intialized
    ir.container_list.getPtr(link.index).children = .empty;

    var builder_api: API = .{
        .IR = &ir,
        
        // make the first selected container the root container
        .selected_container = link.index,
        .selected_container_globalID = globalid,
    };

    // run the function on the builderr api
    fx(&builder_api);

    return ir;
}

// pub fn main(h: *meta.API) void {
//     h.container(.{}); {
//         h.component.button("test");
//         h.component.label("label1");
//
//         h.container(.{});
//             h.button("test");
//         h.end();
//     }
// }
