//! used as a config for what types the ui "library" will use 
//! not really meant to be changed
//! TODO: Maybe include an engine setting to change this stuff or something idk 

const default = @import("default");
const std = @import("std");

const rl = @import("raylib");
const ir = @import("IR.zig");
const meta = @import("meta.zig");

pub const AdditionalData = i32;
pub const IntType = i32;
pub const Color = rl.Color;
pub const UIDType = usize;
pub const Allocator = std.mem.Allocator;

pub const UID_default: UIDType = 0;

pub const Elements = enum(u8) {
    button,
    label,
};

/// Vtable of functions for each component, used for defining the layout.
/// Intrusive interface.
pub const ElementInterface = struct {
    /// VTABLE function alias
    pub const VTFN = *const fn(*ElementInterface) void;
    
    /// custom data added to every element
    pub const syntui_ElementAdditionalData = struct {
        id: Elements,
    };

    /// holds all functions for the creating of individual elements
    // vtable: struct {
    //     button: *const @TypeOf(ElementInterface.button) = ElementInterface.button,
    // } = .{},

    /// holds aditional data, optional
    data: struct {
        button_data: std.ArrayList(Button) = .empty,
    } = .{},

    /// allocator
    gpa: Allocator = std.heap.page_allocator,

    pub const Button = struct {
        text: []u8,
        pressed: bool,
    };

    /// assigns the current container as the parent to the selected element.
    fn assignParent(vt: *ElementInterface, element_index: usize) void {
        const api: *meta.API = @fieldParentPtr("component", vt);

        // assign the current container as the parent
        api.IR.getPtr(.element, element_index).header.parent = 
            api.selected_container;
    }

    pub fn button(vt: *ElementInterface, text: ?[]const u8, id: usize) void {
        const api: *meta.API = @fieldParentPtr("component", vt);
        const element = api.createElement();
        element.element_ptr.which = .button;
        element.element_ptr.header.uid = id;

        vt.assignParent(element.array_index);

        const button_data: Button = .{
            .text = vt.gpa.dupe(u8, text orelse "")
                catch @panic("Out of memory."),
            .pressed = false,
        };

        // make sure we have enough space to fit the index
        vt.data.button_data.ensureTotalCapacity(vt.gpa, element.array_index)
            catch @panic("Failed ensuring enough memory");
        
        // make the array use the newly allocated memory
        vt.data.button_data.expandToCapacity();

        // insert the index
        vt.data.button_data.insert(vt.gpa, element.array_index, button_data)
            catch @panic("failed inserting element into data array");
    }
};

pub const ElementsData = union(Elements) {
    button: struct {
        text: [:0]const u8 = "",
    },
    label: struct {
        text: [:0]const u8 = "",
    },

    pub fn parse(element: Elements, data: anytype) ElementsData {
        return switch(element) {
            .button => .{ .button = .{
                .text = data[0],
            }},
            .label => .{ .label = .{
                .text = data[0],
            }},
        };
    }
};

pub const hookFnPtr = *const fn(*ir) void;

pub const ElementHook = struct {
    active: ?hookFnPtr = null,
    inactive: ?hookFnPtr = null,
    updated_text: ?hookFnPtr = null,
    updated_val: ?hookFnPtr = null,
};

pub const default_color: Color = .blank;
pub const Vec2 = @import("default").Vec2.Vec2(IntType);
