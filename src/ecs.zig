const std = @import("std");
const Syntetica = @import("syntetica");

pub const Entity = @import("ecs/Entity.zig");
pub const Component = @import("ecs/Component.zig");
pub const System = @import("ecs/System.zig");
pub const DefaultComponents = @import("ecs/DefaultComponents.zig");
pub const SystemCreateInfo = System.SystemCreateInfo;

const Allocator = std.mem.Allocator;
const ComponentIndex = Component.Index;
const EntityIndex = Entity.Index;
const log = std.log.scoped(.ecs);

/// Main entity-component-system manager. The Entity.zig, Component.zig and System.zig are 
/// kind of like more low level implementations of each thing, while this ties all of them 
/// together into an easier-to-use interface.
pub const EntityComponentSystem = struct {
    pub const Error = error {
        ComponentNotFoundInEntity,
    };

    allocator: Allocator,
    synt: *Syntetica,

    /// the number of ticks that passed
    tick_count: u64 = 0,

    entities: Entity,
    components: Component,
    systems: System,

    /// user-defined data type of user-registered components for use in 
    /// systems. Modify using .addComponentList(). 
    component_list: ?*const anyopaque = null,

    pub fn init(gpa: Allocator, synt: *Syntetica) EntityComponentSystem {
        return .{
            .entities = .empty,
            .components = .empty,
            .systems = .empty,
            .allocator = gpa,
            .synt = synt,
        };
    }

    /// register a component under a name. Returns the ID of the component.
    pub fn registerComponent(
        self: *EntityComponentSystem, 
        T: type, 
        name: []const u8
    ) Allocator.Error!ComponentIndex {
        const component = try self.components.registerComponent(self.allocator, T, name);

        return component;
    }

    /// unregister a component. There is no need to do this regurarely
    /// as deinitializing the ECS removes all component registries.
    pub fn unregisterComponent(self: *EntityComponentSystem, id: ComponentIndex) void {
        self.components.unregisterComponent(self.allocator, id);
    }

    /// given a component index returns its name
    pub fn getComponentIndexByName(
        self: *EntityComponentSystem, name: []const u8
    ) Component.Error!ComponentIndex {
        return self.components.getIndexByName(name);
    }

    /// given a component name returns its index
    pub fn getComponentNameByIndex(
        self: *EntityComponentSystem, id: ComponentIndex,
    ) []const u8 {
        return self.components.getNameByIndex(id);
    }

    /// spawns an entity into the world with the given components
    pub fn spawnEntity(
        self: *EntityComponentSystem, components: []const ComponentIndex
    ) Allocator.Error!EntityIndex {
        return self.entities.spawnEntity(&self.components, self.allocator, components);
    }

    /// kill an entity
    pub fn killEntity(self: *EntityComponentSystem, entity_id: EntityIndex) void {
        self.entities.killEntity(self.allocator, &self.components, entity_id);
    }

    /// for a given index to data in an entity, copies the value provided
    /// for said data into the memory of the entity.
    pub fn setEntityData(
        self: *EntityComponentSystem, 
        entity_id: EntityIndex, 
        data_index: usize, 
        data: anytype
    ) void {
        const entity = self.entities.registry.get(@intFromEnum(entity_id));

        const component = entity.component[data_index];
        const bytes_offset_for_component = entity.data_index[data_index];

        const component_data_ptr = 
            self.components.getComponentDataPtr(
                @TypeOf(data), component, bytes_offset_for_component
            );

        component_data_ptr.* = data;
    }

    /// prints some data for debugging
    pub fn dumpEntityInfo(self: *EntityComponentSystem, entity_id: EntityIndex) void {
        log.info("entity@{}", .{@intFromEnum(entity_id)});

        const data = self.entities.registry.get(@intFromEnum(entity_id));
        log.info(" > components ({}): ", .{data.component.len});
        for(data.component, data.data_index) |component, index| {
            log.info("  >> {}@{s} :: data located at {}", .{
                @intFromEnum(component), self.getComponentNameByIndex(component), index
            });
            const component_registry = self.components.registry.get(@intFromEnum(component));
            const data_owner_according_to_registry = component_registry.owners.items[
                @divExact(index, component_registry.data_size)
            ];
            log.info("  >> registry says owner is: Entity@{}, the index being stored at {}", .{
                @intFromEnum(data_owner_according_to_registry.entity_id), 
                data_owner_according_to_registry.component_index
            });
        }
    }

    /// given an entity_id, component type and the component_id, returns the pointer 
    /// pointer to that component in the entity. Cannot error if the component exists 
    /// in the entity.
    pub fn getComponentPtrFromEntity(
        self: *EntityComponentSystem, 
        entity_id: EntityIndex, 
        ComponentT: type, 
        component_id: ComponentIndex
    ) Error!*ComponentT {
        const entity = self.entities.registry.get(@intFromEnum(entity_id));

        // find the wanted component index in the component array
        const component_data_index = 
            std.mem.findScalar(ComponentIndex, entity.component, component_id) 
            orelse return Error.ComponentNotFoundInEntity;

        const offset = entity.data_index[component_data_index];
        return self.components.getComponentDataPtr(ComponentT, component_id, offset);
    }

    /// adds a user-owned, user-defined pointer to the user's component index registry 
    /// for faster access and bypassing the need of referencing components by name.
    pub fn addComponentList(self: *EntityComponentSystem, list: *const anyopaque) void {
        self.component_list = list;
    } 

    /// registers a system into the ECS. The SystemType type must implement a function 
    /// of signiature fn(*Syntetica, *SystemCreateInfo) System.Error!void. Check the file 
    /// description for System.zig for more info.
    pub fn registerSystem(
        self: *EntityComponentSystem, SystemType: anytype
    ) System.Error!void {
        try self.systems.registerSystem(
            self.synt, self.allocator, SystemType, self.component_list
        );
    }

    /// runs a single tick of the system.
    pub fn tick(self: *EntityComponentSystem) void {
        var it = self.components.registry.iterator();
        while (it.next()) |_| {
            self.systems.tick(self.synt, &self.components, @enumFromInt(it.current));
        }
    }
};
