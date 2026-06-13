const std = @import("std");
const root = @import("syntetica");
const builtin = @import("builtin");

const graphics = root.graphics;
const glfw = root.glfw;
const vk = root.vk;
const Allocator = std.mem.Allocator;

//const required_layer_names = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const required_layer_names = [_][*:0]const u8{};

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

fn glfwKeyCallback(w: *glfw.Window, k: glfw.Key, _: c_int, action: glfw.Action, _: glfw.Mods) callconv(.c) void {
    if((k == .escape) and (action == .press))
        w.setShouldClose(true);
}

fn getGlfwInstanceProcAddr(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction {
    return @ptrCast(glfw.getInstanceProcAddress(
        instance,
        procname,
    ).?);
}

fn checkLayerSupport(vkb: *const vk.BaseWrapper, alloc: Allocator) !bool {
    const available_layers = try vkb.enumerateInstanceLayerPropertiesAlloc(alloc);
    defer alloc.free(available_layers);
    for (required_layer_names) |required_layer| {
        for (available_layers) |layer| {
            if (std.mem.eql(u8, std.mem.span(required_layer), std.mem.sliceTo(&layer.layer_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }
    return true;
}

fn findGPU(vki: *vk.InstanceWrapper, instance: vk.Instance, extension_names: [][*:0]const u8, alloc: Allocator) !vk.PhysicalDevice {
    const devices = try vki.enumeratePhysicalDevicesAlloc(instance, alloc);
    defer alloc.free(devices);
//    errdefer alloc.free(devices);

    if(devices.len == 0) return error.NoSuitableDeviceFound;

    var best_candidate: struct {
        score: u32 = 0,
        id: vk.PhysicalDevice = .null_handle,
        name: [256] u8 = undefined,
    } = .{};
    forgpudev: for(devices) |device| {
        const properties = vki.getPhysicalDeviceProperties(device);
        const features = vki.getPhysicalDeviceFeatures(device);

        // no geometry shader support is a dealbraker
        std.debug.print("checking geometry shader availablitiy...", .{});
        if(features.geometry_shader == .false) continue;
        std.debug.print("OKAY.\n", .{});

        std.debug.print("checking support for API 1.0...", .{});
        if(properties.api_version <= vk.API_VERSION_1_0.toU32()) continue;
        std.debug.print("OKAY.\n", .{});

        std.debug.print("checking queue availablitiy...", .{});
        const queue_families = try vki.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, alloc);
        defer alloc.free(queue_families);

        var score: u32 = 0;
        for(queue_families, 0..) |queue, i| {
            if(queue.queue_flags.graphics_bit == true) break
            // if we reached the end of the loop and no suitable queue was found 
            else if(i >= queue_families.len - 1) continue :forgpudev;
        }
        std.debug.print("FOUND.\n", .{});

        std.debug.print("checking support for extensions...", .{});
        const availableExtensions = try vki.enumerateDeviceExtensionPropertiesAlloc(device, null, alloc);
        defer alloc.free(availableExtensions);

        var confirmed: u32 = 0;
        for(availableExtensions) |extension| {
            const nullterm_ext_name: [*:0]const u8 = @ptrCast(&extension.extension_name);
            const ext_name = std.mem.span(nullterm_ext_name);

            for(extension_names) |name| {
                if(std.mem.eql(u8, ext_name, std.mem.span(name))) 
                    confirmed += 1;
            }
        }
        std.debug.print("SUPPORTS: {}/{}\n", .{confirmed, extension_names.len});
        if(extension_names.len != confirmed) continue :forgpudev;

        if(properties.device_type == .discrete_gpu) score += 1;
        score += properties.limits.max_image_dimension_2d;

        if(best_candidate.score < score) 
            best_candidate = .{ .score = score, .id = device };

        best_candidate.name = properties.device_name;
    }
    if(best_candidate.id == .null_handle) return error.NoSuitableDeviceFound;

    std.debug.print("found GPU: {s}\n", .{best_candidate.name});

    return best_candidate.id;
}

fn createLogicalDevice(vki: *vk.InstanceWrapper, physical_device: vk.PhysicalDevice, extensions: [][*:0]const u8, allocator: Allocator) !vk.Device {
    const queue_family_properties = 
        try vki.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, allocator);

    var graphics_family: ?u32 = null;
    for(queue_family_properties, 0..) |property, i| {
        if(graphics_family == null and property.queue_flags.graphics_bit == true) 
            graphics_family = @intCast(i);
    }
    if(graphics_family == null) return error.FailedFindingSuitableGraphicsFamily;

    const create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = 1,
        .p_queue_create_infos = &[_]vk.DeviceQueueCreateInfo{
            .{
                .queue_family_index = graphics_family.?,
                .queue_count = 1,
                .p_queue_priorities = &([_]f32{1}),
            },
        },
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = @ptrCast(extensions),
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = undefined,
    };

    return vki.createDevice(physical_device, &create_info, null);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // GLFW //////////////
    try glfw.init();
    defer glfw.terminate();
    errdefer glfw.terminate();

    if(!glfw.isVulkanSupported()) return error.VulkanUnsupported;

    // create a window
    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);

    const window = try glfw.createWindow(1000, 800, "My window", null, null);
    _ = window.setKeyCallback(glfwKeyCallback);

    // VULKAN ////////
    var vkb: vk.BaseWrapper = .load(getGlfwInstanceProcAddr);
    if( !(try checkLayerSupport(&vkb, allocator)) ) return error.MissingLayer;

    const appinfo: vk.ApplicationInfo = .{
        .api_version = vk.API_VERSION_1_0.toU32(),
        .application_version = vk.makeApiVersion(1, 0, 0, 0).toU32(),
        .engine_version = vk.makeApiVersion(1, 0, 0, 0).toU32(),
        .p_application_name = "Syntetica",
        .p_engine_name = "Syntetica",
    };

    var extension_names: std.ArrayList([*:0]const u8) = .empty;
    defer extension_names.deinit(allocator);
//    try extension_names.append(allocator, vk.extensions.ext_debug_utils.name);

    // the following extensions are to support vulkan in mac os
    // see https://github.com/glfw/glfw/issues/2335
    comptime if(builtin.target.os.tag == .macos) {
        try extension_names.append(allocator, vk.extensions.khr_portability_enumeration.name);
        try extension_names.append(allocator, vk.extensions.khr_get_physical_device_properties_2.name);
    };

//    var glfw_exts_count: u32 = 0;
//    const glfw_exts = try glfw.getRequiredInstanceExtensions();
//    try extension_names.appendSlice(allocator, @ptrCast(glfw_exts[0..glfw_exts.len]));

    const instanceinfo: vk.InstanceCreateInfo = .{
        .p_application_info = &appinfo,
        .enabled_layer_count = required_layer_names.len,
        .pp_enabled_layer_names = @ptrCast(&required_layer_names),
        .enabled_extension_count = @intCast(extension_names.items.len),
        .pp_enabled_extension_names = extension_names.items.ptr,
        // enumerate_portability_bit_khr to support vulkan in mac os
        // see https://github.com/glfw/glfw/issues/2335
        .flags = .{ .enumerate_portability_bit_khr = true },
    };

    // create an instance and instance wrapper
    const instance = try vkb.createInstance(&instanceinfo, null);
    var vki = vk.InstanceWrapper.load(instance, vkb.dispatch.vkGetInstanceProcAddr.?);
    defer vki.destroyInstance(instance, null);

    const gpu = try findGPU(&vki, instance, extension_names.items, allocator);
    const ldev = try createLogicalDevice(&vki, gpu, extension_names.items, allocator);
    _ = ldev;

    // create a surface
    std.debug.print("creating a surface...", .{});
    var surface: vk.SurfaceKHR = undefined;
    try glfw.createWindowSurface(instance, window, null, &surface);
    std.debug.print("OKAY.\n", .{});

    while(!window.shouldClose()) {
        glfw.pollEvents();
    }
}
