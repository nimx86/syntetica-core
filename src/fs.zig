const std = @import("std");
const Synt = @import("syntetica");

pub const Collection = @import("fs/Collection.zig");

pub const Manager = struct{
    io: *std.Io,
    data_dir: std.Io.Dir,

    /// goes through the data directory and validates the existance of required
    /// files/directories
    ///
    /// data_dir/ 
    /// + engine_data/
    ///   + engine_config.zon 
    ///   + app_conf.zon 
    ///   + shaders/
    ///     + default_fragment.bin
    ///     + default_vertex.bin
    ///   + resources/
    ///     + missing.png
    /// + app_data/
    fn validatePaths(manager: *Manager) !void {
        const engine_data = manager.data_dir.openDir(manager.io, "engine_data", .{}) 
            catch |e| 
                if(e == error.FileNotFound) return error.EngineDataNonexistant 
                else return e;
        defer engine_data.close(manager.io);

        const engine_conf = engine_data.openFile(manager.io, "engine_config.zon", .{}) 
            catch |e|
                if(e == error.FileNotFound) return error.EngineConfigNonexistant
                else return e;
        defer engine_conf.close(manager.io);

        const app_conf = engine_data.openFile(manager.io, "app_conf.zon", .{})
            catch |e|
                if(e == error.FileNotFound) return error.ApplicationConfigNonexistant
                else return e;
        defer app_conf.close(manager.io);

        const shader_dir = engine_data.openDir(manager.io, "shaders", .{})
            catch |e|
                if(e == error.FileNotFound) return error.ShaderDirectoryNonexistant
                else return e;
        defer shader_dir.close(manager.io);

        const default_fragment = engine_data.openFile(manager.io, "default_fragment.bin", .{})
            catch |e|
                if(e == error.FileNotFound) return error.DefaultFragmentShaderNonexistant
                else return e;
        defer default_fragment.close(manager.io);

        const default_vertex = engine_data.openFile(manager.io, "default_vertex.bin", .{})
            catch |e|
                if(e == error.FileNotFound) return error.DefaultVertexShaderNonexistant
                else return e;
        defer default_vertex.close(manager.io);

        const app_data = manager.data_dir.openDir(manager.io, "app_data", .{})
            catch |e| 
                if(e == error.FileNotFound) return error.AppDataNonexistant
                else return e;
        defer app_data.close(manager.io);
    }

    /// if the executable directory has a directory named "syntetica_unpack", and none 
    /// of the application paths exist in filesystem (eg. "~/.local/share/APPNAME"), 
    /// then the directory is extracted from and the corresponding resources are moved 
    /// to their corresponding locations, with the directory attempting to be deleted
    pub fn init(instance: *Synt) Manager {
        _ = instance;
    }
};
