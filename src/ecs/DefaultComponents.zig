const ComponentIndex = @import("Component.zig").Index;
const Syntetica = @import("syntetica");

const DefaultComponents = @This();

pub const Transform = struct {
    x: f32,
    y: f32,
    rot: f32,
};

// /////////////// //
// general purpose // 
// /////////////// //

transform: ComponentIndex,
texture: ComponentIndex,

pub fn register(synt: *Syntetica) !DefaultComponents {
    return DefaultComponents{ 
        .transform = try synt.ecs.registerComponent(Transform, "Transform"),
        .texture = try synt.ecs.registerComponent(Syntetica.graphics.Renderer.Texture, "Texture"),
    };
}

