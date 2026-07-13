const std = @import("std");
const default = @import("default");

const Component = @import("Component.zig");

const Allocator = std.mem.Allocator;
const Entity = @This();

pub const empty = Entity{
    .registry = .empty,
};

/// Structure for resolving the location of data for an entity
pub const EntityDataLink = struct{
    /// ID of the entity
    entity_id: Index,

    /// index of the component's data in the DataSpecifier
    component_index: usize,
};

/// Entity Index
pub const Index = enum(usize){_};

/// Structure of arrays, used for identifying components
/// and their values.
pub const DataSpecifier = struct {
    const empty = DataSpecifier{
        .component = std.mem.zeroes([]Component.Index),
    };

    /// index of the component
    component: []Component.Index,

    /// offset of the data for said 
    /// component
    data_index: []usize,
};

pub const EntityTemplate = struct {
    components: []Component.Index,
};

registry: default.FreeList.SimpleLinked.Unmanaged(DataSpecifier),

/// creates a new entity in the world with the given components
pub fn spawnEntity(
    self: *Entity, 
    component_registry: *Component, 
    gpa: Allocator, 
    components: []const Component.Index
) Allocator.Error!Index {
    // reserve a space for our entity
    const result = try self.registry.reserveGetPtr(gpa);

    // duplicate the wanted components into the component list

    // TODO: (potential optimization) check if this memory was already allocated, if it was, perform checks to 
    // see if it can be reused
    result.ptr.component = try gpa.dupe(Component.Index, components);

    result.ptr.data_index = try gpa.alloc(usize, components.len);

    // for every component this entity has
    for(components, 0..) |component_id, i| {
        // reserve memory for this entity on this component
        const data_offset = try component_registry.reserveComponentData(gpa, component_id);
        
        std.debug.print("[->] bind Entity@{} as owner of {s}@{} data at offset {}\n", .{
            result.index, 
            component_registry.getNameByIndex(component_id), 
            @intFromEnum(component_id), 
            data_offset,
        });
        // bind this entity as the owner of the allocated memory
        try component_registry.bindOwnerToComponentDataIndex(
            gpa, 
            component_id, 
            data_offset,
            i,
            @enumFromInt(result.index)
        );

        // store the indexes to our data
        result.ptr.data_index[i] = data_offset;
    }
    return @enumFromInt(result.index);
}

/// kill an entity
pub fn killEntity(self: *Entity, gpa: Allocator, component_registry: *Component, entity_id: Index) void {
    const entity = self.registry.getPtr(@intFromEnum(entity_id));
    for(entity.data_index, entity.component) |offset, component_id| {
        component_registry.releaseComponentData(self, component_id, offset);
    }

    // TODO: (potential optimization) do not free here and instad 
    // keep the memory for future use
    gpa.free(entity.component);
    gpa.free(entity.data_index);

    self.registry.remove(@intFromEnum(entity_id));
}
