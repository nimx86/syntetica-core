const std = @import("std");
const graphics = @import("graphics");
const Synt = @import("syntetica");

pub const keyBindFnPtr = *const fn(*Synt) void;

pub const Modifier = packed struct {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    super: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
    pressed: bool = true,
    repeated: bool = false,

    const IntType = @Int(.unsigned, @bitSizeOf(Modifier));

    pub fn toInt(mod: Modifier) IntType {
        return @bitCast(mod);
    }
};

/// doesn't have the key cause that is stored in the hashmap
pub const GlobalKeyBind = struct {
    modifier: Modifier,
    function: ?keyBindFnPtr,
};
