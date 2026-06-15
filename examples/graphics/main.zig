const std = @import("std");
const root = @import("syntetica");
const builtin = @import("builtin");

const VkWrapper = @import("wrapper.zig");

const graphics = root.graphics;
const glfw = root.glfw;
const vk = root.vk;
const Allocator = std.mem.Allocator;

//const required_layer_names = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const required_layer_names = [_][*:0]const u8{};

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

fn glfwKeyCallback(
    w: *glfw.Window, 
    k: glfw.Key, 
    _: c_int, 
    action: glfw.Action, 
    _: glfw.Mods
) callconv(.c) void {
    if((k == .escape) and (action == .press))
        w.setShouldClose(true);
}

fn getGlfwInstanceProcAddress(
    instance: vk.Instance, 
    procname: [*:0]const u8
) vk.PfnVoidFunction {
    return @ptrCast(glfw.getInstanceProcAddress(instance, procname).?);
}

fn syntCreateSurfaceCallback(
    instance: vk.Instance,
    surface: *vk.SurfaceKHR,
    window_ptr_anon: *anyopaque,
) anyerror!void {
    const window_ptr: *glfw.Window = @alignCast(@ptrCast(window_ptr_anon));
    return glfw.createWindowSurface(instance, window_ptr, null, surface);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // GLFW //////////////
    try glfw.init();
    defer glfw.terminate();

    if(!glfw.isVulkanSupported()) return error.VulkanUnsupported;

    // create a window
    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);

    const window = try glfw.createWindow(1000, 800, "My window", null, null);
    _ = window.setKeyCallback(glfwKeyCallback);

    // VULKAN ////////////
    var wrapper = try VkWrapper.init(allocator, .{ 
        .createSurfaceCallback = syntCreateSurfaceCallback, 
        .window = @alignCast(@ptrCast(window)),
    });
    defer wrapper.deinit();

    // add layers
    try wrapper.addLayer("VK_LAYER_KHRONOS_validation");
 
    // add instance extensions
    if(builtin.mode == .Debug) {
        try wrapper.addInstanceExtension(vk.extensions.ext_debug_utils.name);
        try wrapper.addInstanceExtension(vk.extensions.khr_portability_enumeration.name);
        try wrapper.addInstanceExtension(
            vk.extensions.khr_get_physical_device_properties_2.name
        );
    }

    if(builtin.os.tag == .macos) {
        try wrapper.addInstanceExtension(
            vk.extensions.khr_portability_enumeration.name,
        );
        try wrapper.addInstanceExtension(
            vk.extensions.khr_get_physical_device_properties_2.name,
        );
    }

    try wrapper.addInstanceExtensions(try glfw.getRequiredInstanceExtensions());

    // add device extensions 
    try wrapper.addDeviceExtension(vk.extensions.khr_swapchain.name);

    try wrapper.load("appname", getGlfwInstanceProcAddress);

    while(!window.shouldClose()) {
        glfw.pollEvents();
    }
}
