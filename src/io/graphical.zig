const std = @import("std");
const Synt = @import("syntetica");
const default = @import("default");

const KeyCodes = @import("codes.zig");

const Allocator = std.mem.Allocator;

pub const KeyBindManager = struct {
    pub const keyBindFnPtr = *const fn(*Synt) void;

    pub const Modifier = struct {
        shift: bool = false,
        control: bool = false,
        alt: bool = false,
        super: bool = false,
        caps_lock: bool = false,
        num_lock: bool = false,

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


    };

    /// identifies the keybind by index
    keybind_identifier: default.FreeList.SimpleLinked.Unmanaged(Code),
    
    /// function hooks bound to an action. A null value here means that 
    /// the keybind is simply registered and not used globally
    keybind_action: std.array_hash_map.Auto(Code, ?keyBindFnPtr),

    pub fn init(allocator: Allocator) KeyBindManager {
        const self: KeyBindManager = undefined;
        self.keybind_identifier = .empty;
        self.keybind_action = .empty;
    }

    /// registers a local keybind, if the attempted keybind already exists, returns it's 
    /// index. Fails if the existing keybind is not local
    pub fn registerOrGetLocalKeybind(self: *KeyBindManager, allocator: Allocator) !KeyBind {
        const keybind: KeyBind = .{ 
            .identifier = try self.keybind_identifier.reserve(allocator),
            .manager = self,
        };

        try self.keybind_action.getOrPut(allocator, key: Code)

        return keybind;
    }
};
