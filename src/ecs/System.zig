const std = @import("std");

pub const SystemFn = *const fn(*API) API.ExecutionError!void;

pub const API = struct {
    pub const ExecutionError = error {
        GenericError,
        AllocationFailed,
        WorldInteractionFailed,
    };
    pub const Config = struct {
        operates_on: []const usize,

        update_fn: ?SystemFn = null,
    };

    bytes: []u8,
    component_id: usize,

    pub inline fn asTyped(self: *API, T: type) *T {
        return @alignCast(std.mem.bytesAsValue(T, self.bytes));
    }
};

pub const SysIR = struct {
    config: *const API.Config,
    tickAllFn: SystemFn,
};

ecs: *ECS,
fn_queue: std.ArrayListUnmanaged(SysIR) = .empty,

pub fn registerCtx(self: *System, ctx: anytype) !void {
    comptime if(!@hasDecl(ctx, "system_config")) 
        @compileError("ctx must have a public declaration with name system_config of type ecs.System.API.Config");

    const sys: SysIR = .{
        .config = &ctx.system_config,
        
        .tickAllFn = ctx.system_config.update_fn orelse ctx.tick,
    };

    return self.fn_queue.append(self.ecs.gpa, sys);
} 

pub fn tick(self: *System) !void {
    // for every function
    for(self.fn_queue.items) |ctx| {
        // for every component it operates on
        for(ctx.config.operates_on) |component_id| {
            // for every value
            var it = self.ecs.db.components.get(component_id).interator();
            while(it.next()) |component| {
                var api: API = .{
                    .component_id = component_id,
                    .bytes = component,
                };

                // TODO: add more query options for systems
                try ctx.tickAllFn(&api);
            }
        }
    }
}
