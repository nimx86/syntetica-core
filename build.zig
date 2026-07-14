const std = @import("std");

const Library = struct {
    const ModuleList = std.ArrayList(struct{mod: *std.Build.Module, name: []const u8});

    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    b: *std.Build,
    core: *std.Build.Module,

    modules: ModuleList = undefined,
    allocator: std.mem.Allocator = std.heap.page_allocator,

    pub fn init(self: *Library, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.modules = ModuleList.initCapacity(self.allocator, 10) catch @panic("");
        self.modules.append(self.allocator, .{ .name = "syntetica", .mod = self.core }) catch @panic("");
    }

    pub fn addModule(self: *Library, comptime name: []const u8) *std.Build.Module {
        const mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/" ++ name ++ ".zig"),
            .optimize = self.optimize,
            .target = self.target,
        });

        self.modules.append(self.allocator, .{ .mod = mod, .name = name }) catch @panic("");

        return mod;
    }

    pub fn addLibrary(self: *Library, name: []const u8, mod: *std.Build.Module) void {
        self.modules.append(self.allocator, .{ .mod = mod, .name = name }) catch @panic("");
    }

    pub fn getModule(self: *Library, id: usize) *std.Build.Module {
        return self.modules.items[id].mod;
    }

    pub fn confirm(self: *Library) void {
        for(self.modules.items) |mod| {
            for (self.modules.items) |mod1| {
                mod.mod.addImport(mod1.name, mod1.mod);
            }
        }
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var syntetica_core: Library = .{
        .b = b,
        .optimize = optimize,
        .target = target,
        .core = b.addModule("syntetica", .{
            .root_source_file = b.path("src/root.zig"),
            .optimize = optimize,
            .target = target,
        }),
    };
    syntetica_core.init(b.allocator); // TODO: rewrite this to use more of a tree structure
    _ = syntetica_core.addModule("default");
    _ = syntetica_core.addModule("config");
    _ = syntetica_core.addModule("ui");
    _ = syntetica_core.addModule("ecs");
    _ = syntetica_core.addModule("fs");
    _ = syntetica_core.addModule("io");
    const mod_graphics = syntetica_core.addModule("graphics");

    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const vulkan = b.dependency("vulkan", .{
        .registry = vulkan_headers.path("registry/vk.xml"),
    }).module("vulkan-zig");
    mod_graphics.addImport("vulkan", vulkan);

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
        .import_vulkan = true,
    });

    const zglfw_mod = zglfw.module("root");
    zglfw_mod.addImport("vulkan", vulkan);
    mod_graphics.addImport("glfw", zglfw_mod);

    if (target.result.os.tag != .emscripten) {
        mod_graphics.linkLibrary(zglfw.artifact("glfw"));
    }

    const zig_stb_image = b.dependency("zig_stb_image", .{
        .target = target,
        .optimize = optimize,
    });
    mod_graphics.addImport("stb-image", zig_stb_image.module("stb_image"));

    // add shaders
    const spirv_target = b.resolveTargetQuery(.{
        .cpu_arch = .spirv32,
        .os_tag = .vulkan,
        .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
        .ofmt = .spirv,
    });

    const vert_spv = b.addObject(.{
        .name = "default_vert",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/graphics/backend/vulkan/shaders/default_vert.zig"),
            .target = spirv_target,
        }),
        .use_llvm = false,
    });
    mod_graphics.addAnonymousImport("default_vertex_shader", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = vert_spv.getEmittedBin(),
    });
    // const vert_install = b.addInstallFileWithDir(vert_spv.getEmittedBin(), .prefix, "shaders/vert.spv");
    // vert_install.step.dependOn(&vert_spv.step);
    // b.getInstallStep().dependOn(&vert_install.step);

    const frag_spv = b.addObject(.{
        .name = "default_frag",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/graphics/backend/vulkan/shaders/default_frag.zig"),
            .target = spirv_target,
        }),
        .use_llvm = false,
    });
    mod_graphics.addAnonymousImport("default_fragment_shader", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = frag_spv.getEmittedBin(),
    });
    // const frag_install = b.addInstallFileWithDir(frag_spv.getEmittedBin(), .prefix, "shaders/frag.spv");
    // frag_install.step.dependOn(&frag_spv.step);
    // b.getInstallStep().dependOn(&frag_install.step);

    // RAYLIB /////////
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C addLibrary

    syntetica_core.core.linkLibrary(raylib_artifact);
    syntetica_core.addLibrary("raylib", raylib);
    syntetica_core.addLibrary("raygui", raygui);

    syntetica_core.confirm();

    const resources_install = b.addInstallDirectory(.{ 
        .source_dir = b.path("src/res"),
        .install_dir = .prefix,
        .install_subdir = "res/tex/synt" 
    });
    b.getInstallStep().dependOn(&resources_install.step);

    // EXAMPLES ///////////////////////////
    const examples = [_][]const u8{
        "graphics"
    };
    for (examples) |example_name| {
        const default_install_path = b.fmt("zig-out/bin/{s}", .{example_name});
        const example_path = b.fmt("examples/{s}", .{example_name}); 
        const example = b.addExecutable(.{
            .name = example_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("{s}/main.zig", .{example_path})),
                .target = target,
                .optimize = optimize,
            }),
        });
        example.root_module.addImport("syntetica", syntetica_core.core);

        const inst_dir = b.addInstallDirectory(.{ 
            .source_dir = b.path(b.fmt("{s}/res", .{example_path})), 
            .install_dir = .bin, 
            .install_subdir = "res" 
        });
        const inst_art = b.addInstallArtifact(example, .{.dest_dir = .{ .override = .bin}});

        const run_example = b.addSystemCommand(&.{
            b.fmt("{s}/../{s}", .{
                b.install_path, 
                example.installed_path orelse default_install_path
            })
        });
        run_example.step.dependOn(&inst_art.step);
        run_example.step.dependOn(&inst_dir.step);

        const example_step = b.step(
            b.fmt("example_{s}", .{example_name}), 
            b.fmt("Run the {s} example", .{example_name})
        );
        example_step.dependOn(&example.step);
        example_step.dependOn(&run_example.step);
    }
}

pub fn addShader(b: *std.Build) void {
    _ = b;
    @panic("not implemented");
}
