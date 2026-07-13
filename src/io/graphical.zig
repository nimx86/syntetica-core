const std = @import("std");
const Synt = @import("syntetica");
const default = @import("default");

const KeyCodes = @import("codes.zig");
//pub const glfw_implementation = @import("glfw_implementation.zig");
pub const raylib_impl = @import("raylib_impl.zig");

const Allocator = std.mem.Allocator;

pub const KeyBindManager = struct {
    pub const KeyImplVtable = struct {
        init: *const fn(*Synt) anyerror!*anyopaque,
        deinit: *const fn(*anyopaque) void,
        poll: *const fn(*anyopaque) void,
        isActionPressed: *const fn(*anyopaque, Action) bool,
        isModifierPressed: *const fn(*anyopaque, Modifier) bool
    };

    pub const keyBindFnPtr = *const fn(*Synt) void;

    pub const Modifier = packed struct {
        shift: bool = false,
        control: bool = false,
        alt: bool = false,
        super: bool = false,
        caps_lock: bool = false,
        num_lock: bool = false,
        _padding: u2 = 0,

        const IntType = @Int(.unsigned, @bitSizeOf(Modifier));

        pub fn toInt(mod: Modifier) IntType {
            return @bitCast(mod);
        }
    };

    /// keys + mouse + gamepads/controllers
    pub const Action = union(enum) {
        gamepad_axis: KeyCodes.GamepadAxis,
        gamepad_button: KeyCodes.GamepadButton,
        mouse_button: KeyCodes.MouseButton,
        keyboard: KeyCodes.Keyboard,

        pub fn gamepadAxis(a: KeyCodes.GamepadAxis) Action {
            return .{ .gamepad_axis = a };
        }

        pub fn gamepadButton(a: KeyCodes.GamepadButton) Action {
            return .{ .gamepad_button = a };
        }

        pub fn mouse(a: KeyCodes.MouseButton) Action {
            return .{ .mouse_button = a };
        }

        pub fn keyboardKey(a: KeyCodes.Keyboard) Action {
            return .{ .keyboard = a };
        }
    };

    pub const Code = struct {
        modifier: Modifier = .{},
        action: Action = .{ .keyboard = .unknown },
    };

    /// KeyBind interface for checking if a registered 
    /// keybind is used.
    pub const KeyBind = struct {
        identifier: usize,
        manager: *KeyBindManager,

        pub fn setDefault(kb: KeyBind, mod: Modifier, action: Action) !void {
            try kb.manager.keybind_action.put(
                kb.manager.allocator, 
                .{ .modifier = mod, .action = action }, 
                null
            );

            kb.manager.keybind_identifier.getPtr(kb.identifier).* = 
                .{ .modifier = mod, .action = action };
        }

        pub fn isPressed(kb: KeyBind) bool {
            const keybind = kb.manager.keybind_identifier.get(kb.identifier);

            std.debug.assert(!std.meta.eql(keybind.action, Action{ .keyboard = .unknown }));

            if(!kb.manager.vtable.isModifierPressed(
                kb.manager.data_ptr, keybind.modifier)
            ) return false;

            if(!kb.manager.vtable.isActionPressed(
                kb.manager.data_ptr, keybind.action)
            ) return false;

            return true;
        }
    };

    allocator: Allocator,

    vtable: KeyImplVtable,
    data_ptr: *anyopaque,

    /// identifies the keybind by index
    keybind_identifier: default.FreeList.SimpleLinked.Unmanaged(Code),
    
    /// function hooks bound to an action. A null value here means that 
    /// the keybind is simply registered and not used globally
    keybind_action: std.array_hash_map.Auto(Code, ?keyBindFnPtr),

    /// stores links to identifiers under keybind's name
    keybind_label: std.StringHashMapUnmanaged(usize),

    pub fn init(allocator: Allocator, synt: *Synt, impl: KeyImplVtable) !KeyBindManager {
        var self: KeyBindManager = .{ 
            .allocator = allocator,
            .vtable = impl,
            .data_ptr = undefined,
            .keybind_identifier = .empty,
            .keybind_action = .empty,
            .keybind_label = .empty,
        };

        self.data_ptr = try self.vtable.init(synt);

        return self;
    }

    /// registers a local keybind, if the attempted keybind already exists, returns it's 
    /// index. Fails if the existing keybind is not local
    pub fn registerOrGetLocalKeybind(self: *KeyBindManager, name: []const u8) !KeyBind {
        const result = try self.keybind_label.getOrPut(self.allocator, name);
        if(result.found_existing) return .{ .identifier = result.value_ptr.*, .manager = self };

        // get the identifier of the code
        const identifier = try self.keybind_identifier.reserve(self.allocator);
        result.value_ptr.* = identifier;

        self.keybind_identifier.getPtr(identifier).action = .keyboardKey(.unknown);

        return .{
            .identifier = identifier,
            .manager = self,
        };
    }

    pub fn bindGlobalKeybind(
        self: *KeyBindManager,
        mod: Modifier,
        action: Action,
        fnptr: keyBindFnPtr,
        name: []const u8, 
    ) !void {
        const result = try self.keybind_label.getOrPut(self.allocator, name);
        if(result.found_existing) return;

        const id = try self.keybind_identifier.reserve(self.allocator);
        result.value_ptr.* = id;

        try self.keybind_action.put(
            self.allocator, 
            .{ .modifier = mod, .action = action }, 
            fnptr, 
        );
    }

    pub fn poll(self: KeyBindManager, synt: *Synt) void {
        var it = self.keybind_action.iterator();
        while (it.next()) |keybind| {
            if(
                self.vtable.isModifierPressed(self.data_ptr, keybind.key_ptr.modifier) and
                self.vtable.isActionPressed(self.data_ptr, keybind.key_ptr.action)
            ) if(keybind.value_ptr.*) |fx| fx(synt);
        }

        self.vtable.poll(self.data_ptr);
    }
};
