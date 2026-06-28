//! Used to keep track of all the related vulkan data in one place. Frequently
//! passed around in other parts of the wrapper

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const core = @import("syntetica");

const Instance = @import("RenderInstance.zig");

const RenderContext = @This();
const Alloc = std.mem.Allocator;
const log = std.log.scoped(.vulkan);

pub const empty = RenderContext{
    .allocator = .failing,
    .vk_layers = .empty,
    .vk_instance_extensions = .empty,
    .vk_device_extensions = .empty,

    .options = .empty,

    .vkb = undefined,
    
    .instance = undefined,
    .surface = .null_handle,
    .device = undefined,
    .physical_device = PhysicalDevice{
        .handle = .null_handle,
        .properties = undefined,
        .queues = DeviceQueues{
            .graphics_family = 0,
            .present_family = 0,
        },
    },
    .memory_properties = undefined,

    .graphics_queue = .empty,
    .present_queue = .empty,

    .debug_messanger = if(builtin.mode == .Debug) undefined else {},
};

allocator: Alloc,
//required_layers: []const [*:0]const u8,

vk_layers: std.ArrayList([*:0]const u8),
vk_instance_extensions: std.ArrayList([*:0]const u8),
vk_device_extensions: std.ArrayList([*:0]const u8),

options: RenderContext.InitOptions,

// wrappers // 
vkb: vk.BaseWrapper,

// vulkan context //
instance: vk.InstanceProxy,
surface: vk.SurfaceKHR,
device: vk.DeviceProxy,
physical_device: PhysicalDevice,
memory_properties: vk.PhysicalDeviceMemoryProperties,

// queues //
graphics_queue: RenderContext.Queue,
present_queue: RenderContext.Queue,

debug_messanger: if(builtin.mode == .Debug) vk.DebugUtilsMessengerEXT else void,

fn vkDebugUtilsMessengerCallback(
    severity: vk.DebugUtilsMessageSeverityFlagsEXT, 
    msg_type: vk.DebugUtilsMessageTypeFlagsEXT, 
    callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, 
    _: ?*anyopaque
) callconv(.c) vk.Bool32 {
    const SeverityFlag = vk.DebugUtilsMessageSeverityFlagsEXT;

    const vkdebuglog = std.log.scoped(.vk_debug);
    const severity_enum: enum {
        info, 
        warning, 
        verbose, 
        @"error", 
        uknown
    } = switch(severity.toInt()) {
        (SeverityFlag{.info_bit_ext = true}).toInt() => .info,
        (SeverityFlag{.verbose_bit_ext = true}).toInt() => .verbose,
        (SeverityFlag{.warning_bit_ext = true}).toInt() => .warning,
        (SeverityFlag{.error_bit_ext = true}).toInt() => .@"error",
        else => .uknown
    };

    // TODO: get rid of this abomination
    const type_str = 
        if (msg_type.general_bit_ext) "general" 
        else if (msg_type.validation_bit_ext) "validation" 
        else if (msg_type.performance_bit_ext) "performance" 
        else if (msg_type.device_address_binding_bit_ext) "device addr" 
        else "unknown";

    const message: [*c]const u8 = 
        if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";

    switch (severity_enum) {
        .info => vkdebuglog.info("({s}): {s}", .{type_str, message}),
        .verbose => vkdebuglog.debug("({s}): {s}", .{type_str, message}),
        .warning => vkdebuglog.warn("({s}): {s}", .{type_str, message}),
        .@"error" => vkdebuglog.err("({s}): {s}", .{type_str, message}),
        .uknown => vkdebuglog.info("(!uknown level): ({s}) {s}", .{type_str, message})
    }

    return .false;
}

const SupportResult = union(enum) {
    failed_at: usize,
    ok: void,
};

fn checkLayerSupport(w: *RenderContext) !SupportResult {
    // assert the wrapper is loaded
    std.debug.assert(w.vkb.dispatch.vkEnumerateInstanceExtensionProperties != null);

    const available_layers = try w.vkb.enumerateInstanceLayerPropertiesAlloc(w.allocator);
    defer w.allocator.free(available_layers);

    for(w.vk_layers.items, 0..) |required, i| {
        for(available_layers) |available| {
            if(
                std.mem.eql(
                    u8, 
                    std.mem.span(required), 
                    std.mem.sliceTo(&available.layer_name, 0)
                )
            ) break; // found the layer
        // if the loop exits as expected, it didn't find anything
        } else return .{ .failed_at = @intCast(i) };
    }

    return .ok;
}

fn checkInstanceExtensionSupport(w: *RenderContext) !SupportResult {
    const available_extenstions = 
        try w.vkb.enumerateInstanceExtensionPropertiesAlloc(null, w.allocator);
    defer w.allocator.free(available_extenstions);

    for(w.vk_instance_extensions.items, 0..) |extension, i| {
        for(available_extenstions) |available| {
            if(
                std.mem.eql(
                    u8,
                    std.mem.span(extension),
                    std.mem.sliceTo(&available.extension_name, 0)
                )
            ) break;
        } else return .{ .failed_at = @intCast(i) };
    }

    return .ok;
}

fn createSurface(w: *RenderContext) !void {
    return w.options.createSurfaceCallback(w.instance.handle, &w.surface, w.options.window);
}

fn physicalDeviceSupportsExtensions(w: RenderContext, pdev: vk.PhysicalDevice) !bool {
    const pdev_properties = try w.instance.enumerateDeviceExtensionPropertiesAlloc(
        pdev, null, w.allocator
    );
    defer w.allocator.free(pdev_properties);

    log.info("check physical device extension support: ", .{});
    for(w.vk_device_extensions.items) |ext| { 
        for(pdev_properties) |prop| {
            if(
                std.mem.eql(u8, 
                    std.mem.span(ext), 
                    std.mem.sliceTo(&prop.extension_name, 0)
                )
            ) {
                log.info(" - {s} supported", .{ext});
                break;
            }
        } else {
            log.warn(" - {s} not supported.", .{ext});
            return false;
        }
    }

    return true;
}

fn physicalDeviceSupportsSurface(w: RenderContext, pdev: vk.PhysicalDevice) !bool {
    var format_count: u32 = undefined;
    _ = try w.instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, w.surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try w.instance.getPhysicalDeviceSurfacePresentModesKHR(
        pdev, w.surface, &present_mode_count, null
    );

    // check if it has at least one of each
    return format_count > 0 and present_mode_count > 0;
}

const DeviceQueues = struct {
    graphics_family: u32,
    present_family: u32,
};

fn physicalDeviceGetQueues(w: RenderContext, pdev: vk.PhysicalDevice) !?DeviceQueues {
    const queue_families = 
        try w.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, w.allocator);
    defer w.allocator.free(queue_families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for(queue_families, 0..) |family, i| {
        if(graphics_family == null and family.queue_flags.graphics_bit == true)
            graphics_family = @intCast(i);

        const present_support = try w.instance.getPhysicalDeviceSurfaceSupportKHR(
            pdev, @intCast(i), w.surface
        );
        if(present_family == null and present_support == .true)
            present_family = @intCast(i);
    }

    if(graphics_family == null or present_family == null) return null;

    return DeviceQueues{
        .graphics_family = graphics_family.?,
        .present_family = present_family.?,
    };
}

const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,
    queues: DeviceQueues,
};

/// returns null if the physical device is not suitable.
fn isPhysicalDeviceSuitable(w: RenderContext, pdev: vk.PhysicalDevice) !?PhysicalDevice {
    if( !try w.physicalDeviceSupportsExtensions(pdev) ) return null;
    if( !try w.physicalDeviceSupportsSurface(pdev) ) return null;

    if( try w.physicalDeviceGetQueues(pdev) ) |queues| {
        const properties = w.instance.getPhysicalDeviceProperties(pdev);
        
        return PhysicalDevice{
            .properties = properties,
            .handle = pdev,
            .queues = queues,
        };
    }

    // physical device not suitable
    return null;
}

fn pickPhysicalDevice(w: *RenderContext) !PhysicalDevice {
    const pdevs = try w.instance.enumeratePhysicalDevicesAlloc(w.allocator);
    defer w.allocator.free(pdevs);

    for(pdevs) |pdev| {
        if( try w.isPhysicalDeviceSuitable(pdev) ) |dev| return dev;
    } else return error.NoSuitableDevice;
}

fn initPhysicalDevice(w: *RenderContext, dev: RenderContext.PhysicalDevice) !vk.Device {
    const priority = [_]f32{1};

    const queue_create_info = [_]vk.DeviceQueueCreateInfo{
        vk.DeviceQueueCreateInfo{
            .queue_family_index = dev.queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
        vk.DeviceQueueCreateInfo{
            .queue_family_index = dev.queues.present_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        }
    };

    // check if the present family is the same as graphics family in which case we only 
    // need one queue instead of two for each.
    const queue_count: u32 = 
        if(dev.queues.present_family == dev.queues.graphics_family) 1 else 2;

    const device_create_info = vk.DeviceCreateInfo{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &queue_create_info,
        .enabled_extension_count = @intCast(w.vk_device_extensions.items.len),
        .pp_enabled_extension_names = @ptrCast(w.vk_device_extensions.items),
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = undefined,
    };

    return w.instance.createDevice(dev.handle, &device_create_info, null);
}

const Queue = struct {
    pub const empty = Queue{
        .handle = .null_handle,
        .family = 0,
    };

    handle: vk.Queue,
    family: u32,

    pub fn init(device: vk.DeviceProxy, family: u32) Queue {
        return .{ 
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

fn createInstance(w: *RenderContext, appname: [*:0]const u8) !void {
    const instance = try w.vkb.createInstance(
        &vk.InstanceCreateInfo{
            .p_application_info = &vk.ApplicationInfo{
                .p_application_name = appname,
                .p_engine_name = "Syntetica",
                .api_version = vk.API_VERSION_1_4.toU32(),

                // syntetica uses the same versioning system as Vulkan
                .engine_version = core.version.toU32(),

                // TODO: make syntetica require this info and then use it here
                .application_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
            },
            .enabled_layer_count = @intCast(w.vk_layers.items.len),
            .pp_enabled_layer_names = @ptrCast(w.vk_layers.items),

            .enabled_extension_count = @intCast(w.vk_instance_extensions.items.len),
            .pp_enabled_extension_names = @ptrCast(w.vk_instance_extensions.items),

            .flags = .{ .enumerate_portability_bit_khr = true },
        }, 
        null
    );

    const vki: *vk.InstanceWrapper = try w.allocator.create(vk.InstanceWrapper);

    vki.* = vk.InstanceWrapper.load(instance, w.vkb.dispatch.vkGetInstanceProcAddr.?);
    w.instance = vk.InstanceProxy.init(instance, vki);
}

fn destroyInstance(w: *RenderContext) void {
    w.instance.destroyInstance(null);
    w.allocator.destroy(w.instance.wrapper);
}

/// needs to be ran after an instance is created
fn setupDebug(w: *RenderContext) !void {
    comptime std.debug.assert(builtin.mode == .Debug);

    w.debug_messanger = try w.instance.createDebugUtilsMessengerEXT(
        &vk.DebugUtilsMessengerCreateInfoEXT{
            .message_severity = .{
                .error_bit_ext = true,
                .warning_bit_ext = true,
                .verbose_bit_ext = true,
                .info_bit_ext = true,
            },
            .message_type = .{ 
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
                .device_address_binding_bit_ext = true,
            },
            .pfn_user_callback = vkDebugUtilsMessengerCallback,
            .p_user_data = null,
        }, 
        null
    );
}

fn destroyDebug(w: *RenderContext) void {
    comptime std.debug.assert(builtin.mode == .Debug);
    w.instance.destroyDebugUtilsMessengerEXT(w.debug_messanger, null);
}

pub const InitOptions = struct {
    /// takes a function pointer of signature fn(vk.Instance, vk.SurfaceKHR, *anyopaque),
    /// where the arguments are as follows: the vulkan instance, vulkan surface and the 
    /// window pointer.
    createSurfaceCallback: *const fn(vk.Instance, *vk.SurfaceKHR, *anyopaque) anyerror!void,

    /// the window pointer owned by the caller.
    window: *anyopaque,

    pub const empty = InitOptions{
        .createSurfaceCallback = undefined,
        .window = undefined,
    };
};

pub fn init(
    alloc: Alloc, 
    options: InitOptions,
) !*RenderContext {
    var self: *RenderContext = try alloc.create(RenderContext);
    self.* = .empty;

    self.allocator = alloc;

    self.options = options;

    return self;
}

pub fn load(w: *RenderContext, appname: [*:0]const u8, loader: anytype) !void {
    log.info("device extensions: ", .{});
    for(w.vk_device_extensions.items) |extension| {
        log.info(" - {s}", .{extension});
    }
    log.info("instance extensions: ", .{});
    for(w.vk_instance_extensions.items) |extension| {
        log.info(" - {s}", .{extension});
    }

    w.vkb = .load(loader);

    switch(try w.checkLayerSupport()) {
        .failed_at => |index| {
            if(builtin.mode == .Debug) {
                log.err("Following layer isn't supported: {s}", .{
                    w.vk_layers.items[index]
                });
            }

            return error.UsuportedHardware;
        },
        .ok => {},
    }

    switch(try w.checkInstanceExtensionSupport()) {
        .failed_at => |index| {
            if(builtin.mode == .Debug) {
                log.err("Following instance extension isn't supported: {s}", .{
                    w.vk_layers.items[index]
                });
            }

            return error.UsuportedHardware;
        },
        .ok => {},
    }

    try w.createInstance(appname);
    errdefer w.destroyInstance();

    if(builtin.mode == .Debug) {
        try w.setupDebug();
        errdefer w.destroyDebug();
    }

    try w.createSurface();
    errdefer w.instance.destroySurfaceKHR(w.surface, null);

    const physical_dev = try w.pickPhysicalDevice();
    w.physical_device = physical_dev;
    log.info("using device: {s}", .{
        w.instance.getPhysicalDeviceProperties(physical_dev.handle).device_name}
    );

    const device = try w.initPhysicalDevice(physical_dev);
    
    const vkd = try w.allocator.create(vk.DeviceWrapper);
    vkd.* = .load(device, w.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    w.device = vk.DeviceProxy.init(device, vkd);
    errdefer w.device.destroyDevice(null);

    w.graphics_queue = .init(w.device, physical_dev.queues.graphics_family);
    w.present_queue = .init(w.device, physical_dev.queues.present_family);

    w.memory_properties = w.instance.getPhysicalDeviceMemoryProperties(physical_dev.handle);
}

pub fn deinit(w: *RenderContext) void {
    w.device.destroyDevice(null);
    w.allocator.destroy(w.device.wrapper);

    w.instance.destroySurfaceKHR(w.surface, null);
    if(builtin.mode == .Debug) w.destroyDebug();
    w.destroyInstance();
}

pub fn createRenderInstance(w: *RenderContext) Instance {
    return Instance.init(w);
}

pub fn addInstanceExtension(w: *RenderContext, name: [*:0]const u8) !void {
    return w.vk_instance_extensions.append(w.allocator, name);
}

pub fn addInstanceExtensions(w: *RenderContext, names: []const [*:0]const u8) !void {
    return w.vk_instance_extensions.appendSlice(w.allocator, names);
}

pub fn addDeviceExtension(w: *RenderContext, name: [*:0]const u8) !void {
    return w.vk_device_extensions.append(w.allocator, name);
}

pub fn addDeviceExtensions(w: *RenderContext, names: []const [*:0]const u8) !void {
    return w.vk_device_extensions.appendSlice(w.allocator, names);
}

pub fn addLayer(w: *RenderContext, name: [*:0]const u8) !void {
    return w.vk_layers.append(w.allocator, name);
}

pub fn addLayers(w: *RenderContext, names: []const [*:0]const u8) !void {
    return w.vk_layers.appendSlice(w.allocator, names);
}
