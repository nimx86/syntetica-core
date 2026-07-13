const std = @import("std");
const default = @import("default");

const Entity = @import("Entity.zig");

const Component = @This();
const FreeList = default.FreeList.SimpleLinked;
const Allocator = std.mem.Allocator;
pub const Index = enum(usize){_};

pub const ComponentData = struct {
    /// must be allocated on the heap
    name: []u8,
    data_size: usize,
    data: std.ArrayList(u8) = .empty,
    owners: std.ArrayList(Entity.EntityDataLink) = .empty,
};

pub const empty: Component = .{
    .registry = .empty,
    .names = .empty,
};

pub const Error = error{
    ComponentNotFound,
};

registry: FreeList.Unmanaged(ComponentData),
names: std.StringHashMapUnmanaged(Index),

/// register a component using a comptime type, the name is duplicated 
/// and owned by the Component
pub fn registerComponent(
    self: *Component, gpa: Allocator, T: type, name: []const u8
) Allocator.Error!Index {
    const component_data: ComponentData = .{ 
        .name = try gpa.dupe(u8, name),
        .data_size = @sizeOf(T), 
        .data = .empty 
    };

    return self.registerComponentRaw(gpa, component_data);
}

/// register a component without the need of a type, by initializing the ComponentData
pub fn registerComponentRaw(
    self: *Component, gpa: Allocator, component_data: ComponentData
) Allocator.Error!Index {
    const id = try self.registry.insert(gpa, component_data);
    try self.names.put(gpa, component_data.name, @enumFromInt(id));

    return @enumFromInt(id);
}

/// insert data into the respective component's data array, returns 
/// the index of the inserted data. Asserts that the size of data is the 
/// same as registered component's size
pub fn insertComponentData(
    self: *Component, 
    gpa: Allocator, 
    component_id: Index, 
    component: anytype
) Allocator.Error!usize {
    return self.insertComponentDataRaw(gpa, component_id, &std.mem.toBytes(component));
}

/// insert data as an array of bytes into the respective component's 
/// data array, returns the index of the inserted data. Asserts that the 
/// data is the same len as registered component's size.
pub fn insertComponentDataRaw(
    self: *Component, 
    gpa: Allocator, 
    component_id: Index, 
    component_data: []const u8,
) Allocator.Error!usize {
    const ptr = self.registry.getPtr(@intFromEnum(component_id));
    std.debug.assert(ptr.data_size == component_data.len);

    const index = ptr.data.items.len;
    try ptr.data.appendSlice(gpa, component_data);

    return index;
}

/// make a reservation for a specific index to be used to store data
/// in the future. Reading the memory at the given index is UB.
pub fn reserveComponentData(
    self: *Component,
    gpa: Allocator,
    component_id: Index,
) Allocator.Error!usize {
    const ptr = self.registry.getPtr(@intFromEnum(component_id));

    // the index of the reserved data is the current lenght 
    // of the data array
    const index = ptr.data.items.len;
    try ptr.data.ensureUnusedCapacity(gpa, ptr.data_size);
    
    // needs to expand only by one
    try ptr.owners.ensureUnusedCapacity(gpa, 1);

    // set the reserved data to 0
    ptr.data.appendNTimesAssumeCapacity(0, ptr.data_size);

    return index;
}

/// releases component data and replaces the data with the 
/// data of the last component, in the process updates data 
/// pointers for affected entities.
pub fn releaseComponentData(
    self: *Component,
    entity_registry: *Entity,
    component_id: Index,
    offset: usize,
) void {
    const reg = self.registry.getPtr(@intFromEnum(component_id));

    // edge case where this is the last remaining component
    if(reg.data.items.len <= reg.data_size) {
        // since this is the last component, just shrink to 0.
        reg.data.shrinkRetainingCapacity(0);
        reg.owners.shrinkRetainingCapacity(0);
        return;
    }

    // edge case where this is the last component in the array 
    if(offset == reg.data.items.len - reg.data_size) {
        reg.data.shrinkRetainingCapacity(offset);
        reg.owners.shrinkRetainingCapacity(@divExact(offset, reg.data_size));
        return;
    }

    // copy the memory from the last component to the memory of the 
    // just released component, effectively doing swapRemove.
    @memcpy(
        reg.data.items[offset..offset + reg.data_size], 
        reg.data.items[reg.data.items.len - reg.data_size..]
    );

    // to get the index of the owner, we normally divide the offset by 
    // the size of data stored. Since here the offset we are trying to get 
    // is reg.data.items.len - reg.data_size, with the full expression being
    // (reg.data.items.len - reg.data_size) / reg.data_size, that can be 
    // shortened to just (reg.data.items.len / reg.data_size) - 1.
    const replaced_data_owner = 
        reg.owners.items[@divExact(reg.data.items.len, reg.data_size) - 1];

    // get the data of the entity which's data needs to be changed
    const entity_data = 
        entity_registry.registry.getPtr(@intFromEnum(replaced_data_owner.entity_id));

    // make the entity have the new data offset
    entity_data.data_index[replaced_data_owner.component_index] = offset;

    // change ownership from the now deleted entity, to the new entity
    const owner_data = &reg.owners.items[@divExact(offset, reg.data_size)];
    owner_data.component_index = replaced_data_owner.component_index;
    owner_data.entity_id = replaced_data_owner.entity_id;

    // shrink the owners array
    reg.owners.shrinkRetainingCapacity(@divExact(reg.data.items.len, reg.data_size) - 1);

    // after swap-removing, shrink the size of the array. Needs to be called last 
    // since reg.data.items.len is changed
    reg.data.shrinkRetainingCapacity(reg.data.items.len - reg.data_size);
}

/// given an index to a component and the corresponding data offset, binds 
/// that data offset to an entity owner index. Asserts that the offset is 
/// divisible by the size of data, in other words, asserts that the offset is valid.
pub fn bindOwnerToComponentDataIndex(
    self: *Component, 
    component_id: Index, 
    offset: usize,
    component_pointer_index: usize,
    owner: Entity.Index
) Allocator.Error!void {
    const ptr = self.registry.getPtr(@intFromEnum(component_id));

    std.debug.assert(@mod(offset, ptr.data_size) == 0);

    const owner_offset = @divExact(offset, ptr.data_size);

    // assume capacity while inserting because this data 
    // was already allocated for when 
    ptr.owners.insertAssumeCapacity(owner_offset, .{
        .entity_id = owner, 
        .component_index = component_pointer_index 
    });
}

/// returns the pointer to type with data for set component id and offset. 
/// Asserts that the size of the type is the same as the registered component's 
/// size.
pub fn getComponentDataPtr(self: *Component, T: type, id: Index, offset: usize) *T {
    const raw_data_ptr = self.getComponentDataPtrRaw(id, offset);
    std.debug.assert(@sizeOf(T) == raw_data_ptr.len);

    return @alignCast(std.mem.bytesAsValue(T, raw_data_ptr));
}

/// gets the data slice of correct size for the set component id 
/// and data index (offset).
pub fn getComponentDataPtrRaw(
    self: *Component,
    id: Index,
    offset: usize,
) []u8 {
    const ptr = self.registry.getPtr(@intFromEnum(id));
    return ptr.data.items[offset..offset + ptr.data_size];
}

/// unregisters a component, does not free any data the components themselves
/// might store
pub fn unregisterComponent(self: *Component, gpa: Allocator, id: Index) void {
    const ptr = self.registry.getPtr(@intFromEnum(id));
    ptr.data.deinit(gpa);

    self.registry.remove(@intFromEnum(id));
}

/// for a given name returns the appropriate index, can't error if the 
/// name exists.
pub fn getIndexByName(self: *Component, name: []const u8) Error!Index {
    const id = self.names.get(name);

    return id orelse Error.ComponentNotFound;
}

/// for a given index returns the name associated.
pub fn getNameByIndex(self: *Component, id: Index) []const u8 {
    return self.registry.get(@intFromEnum(id)).name;
}

pub fn prettyPrint(self: *Component, w: std.Io.Writer, id: Index) !void {
    const name = self.getNameByIndex(id);
    w.print("{}@{s}", .{@intFromEnum(id), name});
}

const DefaultComponents = @import("DefaultComponents.zig");

pub const Transform = DefaultComponents.Transform;
