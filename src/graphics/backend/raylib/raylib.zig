const std = @import("std");
const Synt = @import("syntetica");
const graphics = @import("graphics");
const raylib = @import("raylib");
const math = @import("default").math;

const Renderer = graphics.Renderer;
const ImplError = Renderer.GraphicsInterfaceVtable.ImplError;
const Texture = Renderer.Texture;
const Image = Renderer.Image;
const RenderRect = Renderer.RenderRect;
const log = std.log.scoped(.impl_raylib);

pub const vtable = graphics.Renderer.GraphicsInterfaceVtable{
    .id_string = "raylib",

    .init = init,
    .deinit = deinit,
    .isWindowOpen = isWindowOpen,
    .closeWindow = closeWindow,
    .getWindowSize = getWindowSize,
    .loopStart = loopStart,
    .loopEnd = loopEnd,
    .vramLoadTexture = vramLoadTexture,
    .vramUnloadTexture = vramUnloadTexture,
    .drawTexture = drawTexture,
};

const Command = union(enum) {
    drawTexture: struct{
        texture: Texture,
        sample_rect: RenderRect,
        render_rect: RenderRect,
        rot: f32,
    }
};

fn cmdBufferDrawTexture(cmd: Command) void {
    const texture = cmd.drawTexture.texture;
    const sample_rect = cmd.drawTexture.sample_rect;
    const render_rect = cmd.drawTexture.render_rect;
    const rot = cmd.drawTexture.rot;

    const rltexture = raylib.Texture{
        .id = @intCast(@intFromEnum(texture.id)),
        .width = @intCast(texture.width),
        .height = @intCast(texture.height),
        .mipmaps = @intCast(texture.mipmaps),
        .format = .uncompressed_r8g8b8a8
    };
    raylib.drawTexturePro(
        rltexture, 
        .init(
            @floatFromInt(sample_rect.pos.x), 
            @floatFromInt(sample_rect.pos.y), 
            @floatFromInt(sample_rect.size.w), 
            @floatFromInt(sample_rect.size.h)
        ), 
        .init(
            @floatFromInt(render_rect.pos.x), 
            @floatFromInt(render_rect.pos.y), 
            @floatFromInt(render_rect.size.w), 
            @floatFromInt(render_rect.size.h)
        ), 
        .init(0, 0), 
        rot, 
        .white
    );
}

const ImplementationData = struct {
    allocator: std.mem.Allocator,
    command_buffer: std.ArrayList(Command)
};

fn init(ptr: **anyopaque, synt: *Synt) ImplError!void {
    const size: math.Vec2i = .init(
        raylib.getScreenWidth(), raylib.getScreenHeight()
    );
    raylib.initWindow(size.x, size.y, std.mem.span(synt.appname));
    raylib.setExitKey(.null);
    raylib.disableEventWaiting();

    const data_ptr = synt.allocator.create(ImplementationData) 
        catch return ImplError.InitFailed;
    data_ptr.allocator = synt.allocator;
    data_ptr.command_buffer = .empty;
    ptr.* = @alignCast(@ptrCast(data_ptr));
}

fn deinit(ptr: *anyopaque) void {
    const data_ptr: *ImplementationData = @alignCast(@ptrCast(ptr));

    data_ptr.command_buffer.deinit(data_ptr.allocator);
    data_ptr.allocator.destroy(data_ptr);
}

fn isWindowOpen(_: *anyopaque) bool {
    return !raylib.windowShouldClose();
}

fn closeWindow(_: *anyopaque) void {
    std.debug.print("closing window...\n", .{});
    raylib.closeWindow();
}

fn getWindowSize(_: *anyopaque) math.Vec2i {
    return math.Vec2i{
        .x = raylib.getScreenWidth(),
        .y = raylib.getScreenHeight()
    };
}

fn loopStart(_: *anyopaque) void {
    raylib.beginDrawing();
    raylib.clearBackground(.black);
}

fn loopEnd(ptr: *anyopaque) void {
    const data_ptr: *ImplementationData = @alignCast(@ptrCast(ptr));

    for(data_ptr.command_buffer.items) |command| {
        switch (command) {
            .drawTexture => {
                cmdBufferDrawTexture(command);
            }
        }
    }

    data_ptr.command_buffer.shrinkRetainingCapacity(0);

    raylib.endDrawing();
}

fn vramLoadTexture(_: *anyopaque, image: Image) ImplError!Texture {
    const rlimage: raylib.Image = .{ 
        .format = .uncompressed_r8g8b8a8,
        .data = image.bytes,
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .mipmaps = @intCast(image.mipmaps),
    };

    const rltexture = raylib.loadTextureFromImage(rlimage) catch |e| {
        log.err("Failed loading texture from image, error: {}", .{e});
        return ImplError.LoadingTextureFailed;
    };

    return Texture{
        .id = @enumFromInt(rltexture.id),
        .mipmaps = @intCast(rltexture.mipmaps),
        .width = @intCast(image.width),
        .height = @intCast(image.height),
    };
}

fn vramUnloadTexture(_: *anyopaque, texture: Texture) void {
    const rltexture: raylib.Texture = .{
        .id = @intCast(@intFromEnum(texture.id)),
        .mipmaps = @intCast(texture.mipmaps),
        .width = @intCast(texture.width),
        .height = @intCast(texture.height),
        .format = .uncompressed_r8g8b8a8,
    };

    raylib.unloadTexture(rltexture);
}

fn drawTexture(
    ptr: *anyopaque, 
    texture: Texture, 
    sample_rect: RenderRect, 
    render_rect: RenderRect, 
    rot: f32
) void {
    const data_ptr: *ImplementationData = @alignCast(@ptrCast(ptr));

    data_ptr.command_buffer.append(data_ptr.allocator, .{ .drawTexture = .{
        .texture = texture,
        .sample_rect = sample_rect,
        .render_rect = render_rect,
        .rot = rot,
    }}) catch {
        log.err("Failed to append drawTexture command to command buffer.", .{});
    };
}
