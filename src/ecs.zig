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

pub const EntityComponentSystem = struct {
    const Error = error {
        ComponentNotFoundInEntity,
    };

    allocator: Allocator,
    synt: *Syntetica,

    tick_count: u64 = 0,

    entities: Entity,
    components: Component,
    systems: System,

    component_list: ?*const anyopaque = null,

    pub fn init(gpa: Allocator, synt: *Syntetica) EntityComponentSystem {
        return .{
            .components = .empty,
            .entities = .empty,
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
        log.debug("registering component: {}@{s}", .{@intFromEnum(component), name});

        return component;
    }

    /// unregister a component. There is no need to do this regurarely
    /// as deinitializing the ECS removes all component registries.
    pub fn unregisterComponent(self: *EntityComponentSystem, id: ComponentIndex) void {
        self.components.unregisterComponent(self.allocator, id);
    }

    /// given a component index returns its name
    pub fn getComponentIndexByName(
        self: *EntityComponentSystem, 
        name: []const u8
    ) Component.Error!ComponentIndex {
        return self.components.getIndexByName(name);
    }

    /// given a component name returns its index
    pub fn getComponentNameByIndex(
        self: *EntityComponentSystem,
        id: ComponentIndex,
    ) []const u8 {
        return self.components.getNameByIndex(id);
    }

    /// spawns an entity into the world with the given components
    pub fn spawnEntity(self: *EntityComponentSystem, components: []const ComponentIndex) Allocator.Error!EntityIndex {
        //log.info("create entity with components: {any}", .{components});
        const id = try self.entities.spawnEntity(&self.components, self.allocator, components);
        log.info("spawn Entity@{}", .{@intFromEnum(id)});

        return id;
    }

    /// kill an entity
    pub fn killEntity(self: *EntityComponentSystem, entity_id: EntityIndex) void {
        log.info("Kill entity of index: {}\n", .{entity_id});
        self.entities.killEntity(self.allocator, &self.components, entity_id);
    }

    /// for a given index to data in an entity, copies the value provided
    /// for said data into the memory of the entity.
    pub fn setEntityData(self: *EntityComponentSystem, entity_id: EntityIndex, data_index: usize, data: anytype) void {
        const entity = self.entities.registry.get(@intFromEnum(entity_id));

        const component = entity.component[data_index];
        const bytes_offset_for_component = entity.data_index[data_index];

        const component_data_ptr = 
            self.components.getComponentDataPtr(@TypeOf(data), component, bytes_offset_for_component);

        component_data_ptr.* = data;
    }

    pub fn dumpEntityInfo(self: *EntityComponentSystem, entity_id: EntityIndex) void {
        log.info("entity@{}", .{@intFromEnum(entity_id)});

        const data = self.entities.registry.get(@intFromEnum(entity_id));
        log.info(" > components ({}): ", .{data.component.len});
        for(data.component, data.data_index) |component, index| {
            log.info("  >> {}@{s} :: data located at {}", .{@intFromEnum(component), self.getComponentNameByIndex(component), index});
            const component_registry = self.components.registry.get(@intFromEnum(component));
            const data_owner_according_to_registry = component_registry.owners.items[@divExact(index, component_registry.data_size)];
            log.info("  >> registry says owner is: Entity@{}, the index being stored at {}", .{
                @intFromEnum(data_owner_according_to_registry.entity_id), 
                data_owner_according_to_registry.component_index
            });
        }
    }

    pub fn getComponentPtrFromEntity(
        self: *EntityComponentSystem, 
        entity_id: EntityIndex, 
        ComponentT: type, 
        component_id: ComponentIndex
    ) Error!*ComponentT {
        const entity = self.entities.registry.get(@intFromEnum(entity_id));

        const component_data_index = std.mem.findScalar(ComponentIndex, entity.component, component_id) 
            orelse return Error.ComponentNotFoundInEntity;

        const offset = entity.data_index[component_data_index];
        return self.components.getComponentDataPtr(ComponentT, component_id, offset);
    }

    pub fn addComponentList(self: *EntityComponentSystem, list: *const anyopaque) void {
        self.component_list = list;
    } 

    pub fn registerSystem(self: *EntityComponentSystem, SystemType: anytype) !void {
        try self.systems.registerSystem(self.synt, self.allocator, SystemType, self.component_list);
    }

    pub fn tick(self: *EntityComponentSystem) void {
        var it = self.components.registry.iterator();
        while (it.next()) |_| {
            self.systems.tick(self.synt, &self.components, @enumFromInt(it.current));
        }
    }
};

// const DataBaseUnmanaged = struct {
//     pub const Reference = struct {
//         // table's ID
//         archetype: Index = 0,
//
//         // entity's ID inside the table
//         table: Index = 0,
//     };
//
//     pub const EntityTemplate = struct {
//         pub const empty: EntityTemplate = .{
//             .db = undefined,
//         };
//
//         db: *DataBaseUnmanaged,
//
//         pub fn init(db: *DataBaseUnmanaged) EntityTemplate {
//             const self: EntityTemplate = .empty;
//
//             self.db = db;
//
//             return self;
//         }
//     };
//
//     pub const empty: DataBaseUnmanaged = .{ 
//         .components = .empty,
//         .bitset_buffer = undefined,
//         .archetype = undefined,
//         .table_grow = 0,
//     };
//
//     const DataBaseError = error {
//         tableExists,
//     };
//
//     const Column = struct {
//         component: Index = 0,
//         data: std.ArrayList(Index) = .empty,
//     };
//     const Table = struct {
//         entries: usize = 0,
//         columns: std.ArrayList(Column) = .empty,
//     };
//     const TableID = struct {
//         index: usize = 0,
//         ptr: *Table = undefined,
//     };
//
//     const ArchetypeContext = struct {
//         pub fn hash(_: ArchetypeContext, b: std.DynamicBitSetUnmanaged) u32 {
//             const bytes: []u8 = @ptrCast(@alignCast(b.masks[0..b.capacity()]));
//             return std.hash.XxHash32.hash(0, bytes);
//         }
//         pub inline fn eql(_: ArchetypeContext, a: std.DynamicBitSetUnmanaged, b: std.DynamicBitSetUnmanaged, _: usize) bool {
//             return a.eql(b);
//         }
//     };
//
//     const ArchetypeMap = std.ArrayHashMap(std.DynamicBitSetUnmanaged, Table, ArchetypeContext, true);
//
//     components: comp.TableUnmanaged,
//     bitset_buffer: std.DynamicBitSetUnmanaged,
//     archetype: ArchetypeMap,
//     table_grow: usize = 0,
//
//     pub fn getTable(self: *DataBaseUnmanaged) !TableID {
//         const result = try self.archetype.getOrPut(self.bitset_buffer);
//         if(result.found_existing) return DataBaseError.tableExists;
//
//         return .{
//             .index = result.index, 
//             .ptr = result.value_ptr
//         };
//     }
//
//     pub fn init(allocator: Allocator, grow_capacity: u32) !DataBaseUnmanaged {
//         const self: DataBaseUnmanaged = .{
//             .components = try comp.TableUnmanaged.init(allocator, grow_capacity),
//             .bitset_buffer = try std.DynamicBitSetUnmanaged.initEmpty(allocator, grow_capacity),
//             .archetype = ArchetypeMap.init(allocator),
//         };
//         errdefer self.components.deinit(allocator);
//         errdefer self.bitset_buffer.deinit(allocator);
//         errdefer self.archetype.deinit();
//
//         return self;
//     }
//
//     pub fn deinit(self: *DataBaseUnmanaged, gpa: std.mem.Allocator) void {
//         var archetype_it = self.archetype.iterator();
//         while(archetype_it.next()) |*entry| {
//             const table: *Table = entry.value_ptr;
//             for (table.columns.items) |*columns| {
//                 columns.data.deinit(gpa);
//             }
//             table.columns.deinit(gpa);
//             table.entries = 0;
//         }
//         self.archetype.deinit();
//         self.components.deinit(gpa);
//         self.bitset_buffer.deinit(gpa);
//     }
//
//     pub inline fn getBitset(self: *DataBaseUnmanaged) *std.DynamicBitSetUnmanaged {
//         return &self.bitset_buffer;
//     }
//
//     pub fn createTable(self: *DataBaseUnmanaged, gpa: Allocator) !Index {
//         const table_result = try self.archetype.getOrPut(self.bitset_buffer);
//         if(table_result.found_existing) return table_result.index;
//
//         const table_id = table_result.index;
//         const table_ptr = table_result.value_ptr;
//         const component_count = self.bitset_buffer.count();
//
//         // initialize the table with default values
//         table_ptr.entries = 0;
//         table_ptr.columns = .empty;
//
//         // initialize table with rows
//         try table_ptr.columns.ensureTotalCapacity(gpa, component_count);
//         table_ptr.columns.appendNTimesAssumeCapacity(Column{}, component_count);
//
//         // iterate over every component an entity has
//         var it = self.bitset_buffer.iterator(.{});
//         var i: usize = 0;
//         while (it.next()) |component_id| : (i += 1) {
//             const component_table = &self.components.table;
//             // ensure component storage has enough inital memory without 
//             // the need for resizing
//             try component_table.items[component_id].ensureFitsNItems(gpa, self.table_grow);
//
//             // intialize table by setting each row to the corresponding
//             // component ID
//             table_ptr.columns.items[i].component = component_id;
//
//             // initialize the rows with defined capacity
//             table_ptr.columns.items[i].data = try .initCapacity(gpa, self.table_grow);
//         }
//
//         return table_id;
//     }
//
//     pub fn reserveEntry(self: *DataBaseUnmanaged, gpa: Allocator, table_id: usize) !usize {
//         const table: *Table = &self.archetype.unmanaged.entries.items(.value)[table_id];
//
//         // in every column of our entity
//         for(table.columns.items) |*column| {
//             // get the data id from our component data table,
//             // this is where the actual data lies
//             const data_id = try self.components.get(column.component).addOne(gpa);
//
//             // add the entity ID, adding the data ID to the 
//             // component data array
//             try column.data.append(gpa, data_id);
//         }
//         table.entries += 1;
//
//         return table.entries - 1;
//     }
//
//     /// Appends an entry into the specified table and returns 
//     /// the index it was appended to. 
//     ///
//     /// values - all the components, asserts that 
//     /// values.len == amount of components the table has
//     pub fn appendEntry(
//         self: *DataBaseUnmanaged, 
//         gpa: Allocator, 
//         table_id: usize, 
//         values: []const []const u8
//     ) !usize {
//         const table: *Table = &self.archetype.unmanaged.entries.items(.value)[table_id];
//         std.debug.assert(values.len == table.columns.items.len);
//
//         // for every column
//         for(table.columns.items, 0..) |*column, i| {
//             // alias
//             const component_table = &self.components.table.items[column.component];
//
//             // first get the data id from component data
//             // this also ensures our new component fits
//             const component_data_id = try component_table.addOne(gpa);
//
//             // copy the passed data into the component table's data
//             @memcpy(
//                 component_table.data.items[component_data_id..component_table.data.items.len],
//                 values[i][0..component_table.data_size]
//             );
//
//             // then append the id to the column
//             try column.data.append(gpa, component_data_id);
//         }
//
//         table.entries += 1;
//
//         return table.entries - 1;
//     }
//
//     /// for a given table, finds which column has the component of reference index 
//     /// component_id.
//     pub fn findColumnForComponent(
//         self: *DataBaseUnmanaged,
//         table_id: usize,
//         component_id: usize,
//     ) !usize {
//         const table: *Table = &self.archetype.unmanaged.entries.items(.value)[table_id];
//
//         for(table.columns.items, 0..) |column, i| {
//             if(column.component != component_id) continue;
//             return i;
//         } else return error.ComponentNotFound;       
//     }
//
//     /// Modifies an entry's component based on the component's uid but value needs to 
//     /// be supplied at comptime, for a runtime solution, see .modifyEntryComponent().
//     pub fn modifyEntryComponentTyped(
//         self: *DataBaseUnmanaged, 
//         path: Reference, 
//         component_id: usize, 
//         value: anytype
//     ) !void {
//         const val = &std.mem.toBytes(value);
//
//         return self.modifyEntryComponent(path, component_id, val);
//     }
//
//     /// Modifies an entry's component based on the column's id but value needs to 
//     /// be supplied at comptime, for a runtime solution, see .modifyEntryColumn().
//     pub fn modifyEntryColumnTyped(
//         self: *DataBaseUnmanaged, 
//         path: Reference, 
//         column_id: usize, 
//         value: anytype
//     ) void {
//         const val = &std.mem.toBytes(value);
//
//         self.modifyEntryColumn(path, column_id, val);
//     }
//
//     pub fn modifyEntryComponent(
//         self: *DataBaseUnmanaged,
//         path: Reference,
//         component_id: usize,
//         value: []const u8
//     ) !void {
//         const column_id = try self.findColumnForComponent(path.archetype, component_id);
//
//         self.modifyEntryColumn(path, column_id, value);
//     }
//
//     pub fn modifyEntryColumn(
//         self: *DataBaseUnmanaged,
//         path: Reference,
//         column_id: usize,
//         value: []const u8
//     ) void {
//         const table: *Table = &self.archetype.unmanaged.entries.items(.value)[path.archetype];
//
//         const componentID = table.columns.items[column_id].component;
//
//         const components = &self.components;
//         const entity_ID = table.columns.items[column_id].data.items[path.table];
//         @memcpy(
//             components.get(componentID).getSlice(entity_ID),
//             value
//         );
//     }
//
//     pub fn getEntryPtrColumnTyped(
//         self: *DataBaseUnmanaged,
//         path: Reference,
//         column_id: usize,
//         T: type
//     ) *T {
//         const table: *Table = &self.archetype.unmanaged.entries.items(.value)[path.archetype];
//         const component_id = table.columns.items[column_id].component;
//
//         const entity_data_id = table.columns.items[column_id].data.items[path.table];
//         const slice = self.components.get(component_id).getSlice(entity_data_id);
//
//         return @alignCast(std.mem.bytesAsValue(T, slice));
//     }
//
//     pub fn getEntryColumn(
//         self: *DataBaseUnmanaged,
//         path: Reference,
//         column_id: usize,
//     ) []u8 {
//         const table: *Table = &self.archetype.unmanaged.entries.items(.value)[path.archetype];
//         const component_id = table.columns.items[column_id].component;
//
//         const entity_data_id = table.columns.items[column_id].data.items[path.table];
//         return self.components.get(component_id).getSlice(entity_data_id);
//     }
// };
//
// pub const Component = struct {
//     pub const ID = usize;
//
//     ecs: *ECS,
//
//     pub inline fn register(self: *Component, T: type) !ID {
//         return self.ecs.db.components.add(
//             self.ecs.gpa, 
//             try .initWithType(T, self.ecs.grow_size, self.ecs.gpa)
//         );
//     }
// };
//
// pub const Entity = struct {
//     ecs: *ECS,
//
//     pub fn create(self: *Entity, components: []const usize) !DataBaseUnmanaged.Reference {
//         for (components) |component_id| {
//             self.ecs.db.bitset_buffer.set(component_id);
//         }
//
//         const table_id = try self.ecs.db.createTable(self.ecs.gpa);
//
//         self.ecs.db.bitset_buffer.unsetAll();
//
//         const entry_id = try self.ecs.db.reserveEntry(self.ecs.gpa, table_id);
//
//         return .{ .archetype = table_id, .table = entry_id };
//     }
// };
//
// pub const System = struct {
//
// };
//
// pub const empty: ECS = .{
//     .grow_size = 0,
//     .db = .empty,
//     .entity_lookup = .empty,
//     .gpa = undefined,
//     .entity = undefined,
//     .component = undefined,
//     .system = undefined,
// };
//
// const ECS = @This();
//
// grow_size: u32 = 100,
// db: DataBaseUnmanaged = .empty,
// entity_lookup: std.ArrayList(DataBaseUnmanaged.Reference),
// gpa: Allocator,
//
// entity: Entity,
// component: Component,
// system: System,
//
// pub fn init(self: *ECS, gpa: Allocator, grow_size: u32) !void {
//     self.db = try DataBaseUnmanaged.init(gpa, grow_size);
//     self.grow_size = grow_size;
//     self.gpa = gpa;
//     self.entity_lookup = try .initCapacity(gpa, grow_size);
//     self.entity = .{ .ecs = self };
//     self.component = .{ .ecs = self };
//     self.system = .{ .ecs = self };
// }
//
// pub fn deinit(self: *ECS) void {
//     self.entity_lookup.deinit(self.gpa);
//     self.db.deinit(self.gpa);
//     self.system.fn_queue.deinit(self.gpa);
// }
//
// test "ECS" {
//     const Transform = struct {
//         x: i32,
//         y: i32,
//         z: i32
//     };
//
//     const Tile = struct {
//         max_durability: i32,
//         current_durability: i32,
//     };
//
//     var world: ECS = .empty;
//     try world.init(std.testing.allocator, 20);
//     defer world.deinit();
//
//     const transform = try world.component.register(Transform);
//     const tile = try world.component.register(Tile);
//
//     const Sys = struct {
//         const system_config: ECS.System.API.Config = .{
//             .operates_on = &.{0}
//         };
//
//         fn tick(component: *ECS.System.API) ECS.System.API.ExecutionError!void {
//             const cmp = component.asTyped(Transform);
//
//             cmp.x += 1;
//
//             std.debug.print("[Sys] COMPONENT: {}\n", .{cmp});
//         }
//     };
//     try world.system.registerCtx(Sys);
//
//     const Sys1 = struct {
//         const system_config: ECS.System.API.Config = .{
//             .operates_on = &.{0, 1}
//         };
//
//         fn tick(component: *ECS.System.API) ECS.System.API.ExecutionError!void {
//             switch (component.component_id) {
//                 0 => {
//                     const cmp = component.asTyped(Transform);
//
//                     cmp.y += 1;
//                     std.debug.print("[Sys1] COMPONENT: {}\n", .{cmp});
//                 },
//
//                 1 => {
//                     const cmp = component.asTyped(Tile);
//
//                     cmp.current_durability -= 1;
//                     std.debug.print("[Sys1] CMP: {}\n", .{cmp});
//                 },
//
//                 else => unreachable,
//             }
//         }
//     };
//     try world.system.registerCtx(Sys1);
//
//     const entity = try world.entity.create(&.{transform, tile});
//     _ = try world.entity.create(&.{transform});
//
//     for(0..20) |_| {
//         try world.system.tick();
//     }
//
//     std.debug.print("ENT = {} ; TRANSFORM = {}\n", .{entity, transform});
// }

// test "DataBaseUnmanaged.createTable" {
//     var db: DataBaseUnmanaged = try .init(std.testing.allocator, 20);
//     defer db.deinit(std.testing.allocator);
//
//     const Transform = struct {
//         x: i32,
//         y: i32,
//         z: i32,
//     };
//
//     const PhysicsObject = struct {
//         const requires = .{Transform};
//
//         velocity: i32,
//     };
//
//     const transform = try db.components.add(std.testing.allocator, try .initWithType(Transform, 20, std.testing.allocator));
//     const physics_object = try db.components.add(std.testing.allocator, try .initWithType(PhysicsObject, 20, std.testing.allocator));
//
//     const bst = db.getBitset();
//     bst.set(transform);
//     bst.set(physics_object);
//     const ref = try db.createTable(std.testing.allocator);
//
//     bst.unsetAll();
//     bst.set(transform);
//     const tab = try db.createTable(std.testing.allocator);
//
//     var val: Transform = .{
//         .x = 0xB0_0B_1E_5,
//         .y = 0xAA_AA_AA,
//         .z = 0xDD_DD_DD,
//     };
//     const val1: PhysicsObject = .{
//         .velocity = 0,
//     };
//     const ent1 = try db.appendEntry(std.testing.allocator, ref, &.{@ptrCast(&std.mem.toBytes(val)), @ptrCast(&std.mem.toBytes(val1))});
//     const ent1_1 = try db.appendEntry(std.testing.allocator, ref, &.{@ptrCast(&std.mem.toBytes(val)), @ptrCast(&std.mem.toBytes(val1))});
//     const ent2 = try db.appendEntry(std.testing.allocator, tab, &.{@ptrCast(&std.mem.toBytes(val))});
//     std.debug.print("ENTITY 1: {}\n", .{ent1});
//     std.debug.print("ENTITY 1.1: {}\n", .{ent1_1});
//     std.debug.print("ENTITY 2: {}\n;", .{ent2});
//
//     std.debug.print("DUMP: \n", .{});
//     for(db.components.table.items, 0..) |comp, i| {
//         std.debug.print("COMPONENT ID: {}\n", .{i});
//         comp.memDump();
//     }
//
//     val.x = 12;
//     val.z = 20;
//     try db.modifyEntryComponent(.{
//         .table = ent1_1,
//         .archetype = ref,
//     }, transform, @ptrCast(&std.mem.toBytes(val)));
//
//     std.debug.print("DUMP 1: \n", .{});
//     for(db.components.table.items, 0..) |comp, i| {
//         std.debug.print("COMPONENT ID: {}\n", .{i});
//         comp.memDump();
//     }
//
//     const slice = db.getEntryPtrColumnTyped(.{
//         .table = ent1_1,
//         .archetype = ref,
//     }, try db.findColumnForComponent(ref, transform), Transform);
//
//     std.debug.print("SLICE: {}\n", .{slice.*});
// }
