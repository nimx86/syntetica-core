//! To get started with creating a system, define a structure with a function called 
//! init or systemInit:
//! const ExampleSystem = struct {
//!     const Syntetica = @import("syntetica");
//!
//!     var components: *YourComponentsType = undefined;
//!
//!     fn functionThatOperatesOnAComponent(
//!         pointer_to_the_component: *anyopaque,
//!         entity_id: Syntetica.ECS.Entity.Index,
//!         syntetica_instance: *Syntetica
//!     ) void { ... }
//!
//!     pub fn init(
//!         synt: *Syntetica, create_info: *Syntetica.ECS.SystemCreateInfo
//!     ) Syntetica.ECS.System.Error!void {
//!         create_info.operatesOn(&.{ ... add your components here });
//!         create_info.addFunctions(&.{ ... add functions that run on components });
//!         create_info.onAll = ... this function will run for every component your 
//!                                 system operates on, by default set to null
//!         
//!         // if the components type has been set, this will not be null and will 
//!         // be available for use
//!         components = @alignCast(@ptrCast(create_info.components));
//!
//!         // note that functions added will operate on components in the order you added 
//!         // them. So for example if you set your operatesOn value to &.{A, B, C}, and then
//!         // add functions &.{F, G, H}, the function F will run for every A, G will run 
//!         // for every B and H will run for every C.
//!     } 
//! }
//!
//! After you are done defining your structure, register it to an ECS instance by doing 
//! var ecs = ECS.init(...);
//! ecs.registeSystem(ExampleSystem);

const std = @import("std");
const Syntetica = @import("syntetica");

const ECS = @import("ecs").EntityComponentSystem;

const Component = @import("Component.zig");
const Entity = @import("Entity.zig");

pub const Error = error {
    FailedInitializingSystem,
    ComponentListUnavailable,
} || Allocator.Error;

/// first argument is the pointer to a component instance's data 
pub const componentFunction = fn(*anyopaque, Entity.Index, *Syntetica) void;
const System = @This();
const Allocator = std.mem.Allocator;

pub const SystemCreateInfo = struct {
    /// allocator for use in methods for this 
    /// struct and for the creation of the system.
    allocator: Allocator,

    /// optionally can be used to get components passed from the 
    /// registerSystem function
    components: ?*const anyopaque = null,

    /// specifies which components the system operates 
    /// on.
    operates_on: std.ArrayList(Component.Index) = .empty,

    /// array of functions where each function will operate 
    /// on it's corresponding component in the order the 
    /// components were listed in .operates_on field.
    functions: std.ArrayList(*const componentFunction) = .empty,

    /// a function that will operate on all components 
    /// specified
    onAll: ?*const componentFunction = null,

    /// if the component list is supplied, cannot error.
    pub fn component(self: SystemCreateInfo, T: type) Error!*const T {
        return @alignCast(@ptrCast(
                self.components orelse 
                return SystemCreateInfo.Error.ComponentListUnavailable
        ));
    }

    /// sets the components on which the system operates on
    pub fn operatesOn(self: *SystemCreateInfo, components: []const Component.Index) Allocator.Error!void {
        try self.operates_on.appendSlice(self.allocator, components);
    }

    /// sets the functions on which the system operates on
    pub fn addFunctions(self: *SystemCreateInfo, fx: []const *const componentFunction) Allocator.Error!void {
        try self.functions.appendSlice(self.allocator, fx);
    }
};

pub const empty: System = .{
    .component_functions = .empty
};

component_functions: std.ArrayList(std.ArrayList(*const componentFunction)),

/// for a given system struct, validates that it has the correct functions
fn validateType(T: type) void {
    comptime { 
        if(!std.meta.hasFn(T, "init") and !std.meta.hasFn(T, "systemInit")) 
            @compileError("System must have a function named \"init\" or \"systemInit\" of signiature fn(*Syntetica, *SystemCreateInfo) System.Error!void");
    }
}

const RegisterSystemError = System.Error || Allocator.Error;

/// registers a system based on the supplied struct.
pub fn registerSystem(
    self: *System, 
    synt: *Syntetica, 
    gpa: Allocator, 
    SystemStruct: type, 
    components: ?*const anyopaque
) RegisterSystemError!void {
    validateType(SystemStruct);

    var create_info: SystemCreateInfo = .{ 
        .components = components, 
        .allocator = gpa,
        .operates_on = .empty,
        .functions = .empty,
        .onAll = null
    };

    // since there are two options for the init function, check if "init" is defined,
    // if it isn't call "systemInit". If neither are defined, it would've been caught 
    // earlier.
    if(std.meta.hasFn(SystemStruct, "init")) try SystemStruct.init(synt, &create_info)
    else try SystemStruct.systemInit(synt, &create_info);

    std.debug.assert( // system needs to operate on components
        !std.meta.eql(create_info.operates_on, @TypeOf(create_info.operates_on).empty)
    ); 
    std.debug.assert( // system must have functions that operate on components
        !std.meta.eql(create_info.functions, @TypeOf(create_info.functions).empty)
    ); 
    std.debug.assert( // number of components on which the system operates on must match the number of supplied functions. 
        create_info.operates_on.items.len == create_info.functions.items.len
    ); 

    try self.registerSystemRaw(
        gpa, create_info.operates_on.items, create_info.functions.items, create_info.onAll
    );

    // deinitialize the arraylists since they are not needed anymore
    create_info.operates_on.deinit(gpa);
    create_info.functions.deinit(gpa);
}

/// registers a system based on supplied arguments
pub fn registerSystemRaw(
    self: *System, 
    gpa: Allocator, 
    operates_on: []const Component.Index, 
    for_each: []const *const componentFunction, 
    onAll: ?*const componentFunction
) Allocator.Error!void {
    // get the biggest index so that we can expand the list to make that index 
    // correspond with an array of functions.
    var max_size_required: Component.Index = @enumFromInt(0);
    for(operates_on) |val| max_size_required = 
        if(@intFromEnum(val) > @intFromEnum(max_size_required)) val else max_size_required;

    const len_before_resize = self.component_functions.items.len;
    
    // resize (or don't) our array
    try self.component_functions.ensureTotalCapacity(gpa, @intFromEnum(max_size_required) + 1);

    // make sure the array is resized correctly
    self.component_functions.expandToCapacity();

    // initialize the newly allocated space with values
    for(self.component_functions.items[len_before_resize..]) |*val| {
        val.* = .empty;
    }

    // for each system function we want to register
    for(operates_on, for_each) |component_id, fnPtr| {

        // get the arraylist for our functions
        const list = &self.component_functions.items[@intFromEnum(component_id)];

        // append the function that operates on the component
        try list.append(gpa, fnPtr);

        // if the function that operates on all required components 
        // is not null, add it to the function list
        if(onAll) |fnOnAll|
            try list.append(gpa, fnOnAll);
    }
}

/// runs all functions for a given component, performing a tick for that component.
pub fn tick(
    self: *System, synt: *Syntetica, components: *Component, component_id: Component.Index
) void {
    const ptr = components.registry.getPtr(@intFromEnum(component_id));

    // for every piece of component data, we are iterating on owners since it has a single 
    // index for every component instance, whereas ptr.data.items would have ptr.data_size 
    // amount of indices for every component instance
    for(ptr.owners.items, 0..) |owner, i| {
        const fnarray = self.component_functions.items[@intFromEnum(component_id)];

        // get the bytes for the current component instance, the bytes are offset 
        // by ptr.data_size since we store each component instance as a sequence of bytes.
        // we are slicing till i * ptr.data_size * 2 since the start of the component 
        // instance's data is at i * ptr.data_size, which means that for a single instance, 
        // the end is at (i * ptr.data_size) + ptr.data_size = ptr.data_size * (i + 1)
        const bytes = ptr.data.items[
            i * ptr.data_size..ptr.data_size * (i + 1)
        ];

        // for every function registered to run on that component data
        for(fnarray.items) |function| {
            function(
                @ptrCast(bytes),
                owner.entity_id, synt
            );
        }
    }
}
