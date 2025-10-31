const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const std = @import("std");

// Defined in dawn.cpp
const DawnNativeInstance = ?*opaque {};
const DawnProcsTable = ?*opaque {};
extern fn dniCreate() DawnNativeInstance;
extern fn dniDestroy(dni: DawnNativeInstance) void;
extern fn dniGetWgpuInstance(dni: DawnNativeInstance) ?wgpu.Instance;
extern fn dnGetProcs() DawnProcsTable;

// Defined in Dawn codebase
extern fn dawnProcSetProcs(procs: DawnProcsTable) void;

pub const WindowProvider = struct {
    window: *anyopaque,
    fn_getTime: *const fn () f64,
    fn_getFramebufferSize: *const fn (window: *const anyopaque) [2]u32,
    fn_getWin32Window: *const fn (window: *const anyopaque) callconv(.c) *anyopaque = undefined,
    fn_getX11Display: *const fn () callconv(.c) *anyopaque = undefined,
    fn_getX11Window: *const fn (window: *const anyopaque) callconv(.c) u32 = undefined,
    fn_getWaylandDisplay: ?*const fn () callconv(.c) *anyopaque = null,
    fn_getWaylandSurface: ?*const fn (window: *const anyopaque) callconv(.c) *anyopaque = null,
    fn_getCocoaWindow: *const fn (window: *const anyopaque) callconv(.c) ?*anyopaque = undefined,

    fn getTime(self: WindowProvider) f64 {
        return self.fn_getTime();
    }

    fn getFramebufferSize(self: WindowProvider) [2]u32 {
        return self.fn_getFramebufferSize(self.window);
    }

    fn getWin32Window(self: WindowProvider) ?*anyopaque {
        return self.fn_getWin32Window(self.window);
    }

    fn getX11Display(self: WindowProvider) ?*anyopaque {
        return self.fn_getX11Display();
    }

    fn getX11Window(self: WindowProvider) u32 {
        return self.fn_getX11Window(self.window);
    }

    fn getWaylandDisplay(self: WindowProvider) ?*anyopaque {
        if (self.fn_getWaylandDisplay) |f| {
            return f();
        } else {
            return @as(?*anyopaque, null);
        }
    }

    fn getWaylandSurface(self: WindowProvider) ?*anyopaque {
        if (self.fn_getWaylandSurface) |f| {
            return f(self.window);
        } else {
            return @as(?*anyopaque, null);
        }
    }

    fn getCocoaWindow(self: WindowProvider) ?*anyopaque {
        return self.fn_getCocoaWindow(self.window);
    }
};

const SurfaceDescriptorTag = enum {
    metal_layer,
    windows_hwnd,
    xlib,
    wayland,
    canvas_html,
};

const SurfaceDescriptor = union(SurfaceDescriptorTag) {
    metal_layer: struct {
        label: ?[*:0]const u8 = null,
        layer: *anyopaque,
    },
    windows_hwnd: struct {
        label: ?[*:0]const u8 = null,
        hinstance: *anyopaque,
        hwnd: *anyopaque,
    },
    xlib: struct {
        label: ?[*:0]const u8 = null,
        display: *anyopaque,
        window: u32,
    },
    wayland: struct {
        label: ?[*:0]const u8 = null,
        display: *anyopaque,
        surface: *anyopaque,
    },
    canvas_html: struct {
        label: ?[*:0]const u8 = null,
        selector: [*:0]const u8,
    },
};

fn isLinuxDesktopLike(tag: std.Target.Os.Tag) bool {
    return switch (tag) {
        .linux,
        .freebsd,
        .openbsd,
        .dragonfly,
        => true,
        else => false,
    };
}

fn msgSend(obj: anytype, sel_name: [:0]const u8, args: anytype, comptime ReturnType: type) ReturnType {
    const args_meta = @typeInfo(@TypeOf(args)).@"struct".fields;

    const FnType = switch (args_meta.len) {
        0 => *const fn (@TypeOf(obj), objc.SEL) callconv(.C) ReturnType,
        1 => *const fn (@TypeOf(obj), objc.SEL, args_meta[0].type) callconv(.C) ReturnType,
        2 => *const fn (
            @TypeOf(obj),
            objc.SEL,
            args_meta[0].type,
            args_meta[1].type,
        ) callconv(.C) ReturnType,
        3 => *const fn (
            @TypeOf(obj),
            objc.SEL,
            args_meta[0].type,
            args_meta[1].type,
            args_meta[2].type,
        ) callconv(.C) ReturnType,
        4 => *const fn (
            @TypeOf(obj),
            objc.SEL,
            args_meta[0].type,
            args_meta[1].type,
            args_meta[2].type,
            args_meta[3].type,
        ) callconv(.C) ReturnType,
        else => @compileError("[zgpu] Unsupported number of args"),
    };

    const func = @as(FnType, @ptrCast(&objc.objc_msgSend));
    const sel = objc.sel_getUid(sel_name.ptr);

    return @call(.never_inline, func, .{ obj, sel } ++ args);
}

const objc = struct {
    const SEL = ?*opaque {};
    const Class = ?*opaque {};

    extern fn sel_getUid(str: [*:0]const u8) SEL;
    extern fn objc_getClass(name: [*:0]const u8) Class;
    extern fn objc_msgSend() void;
};

fn createSurfaceForWindow(instance: wgpu.Instance, window_provider: WindowProvider) wgpu.Surface {
    const os_tag = @import("builtin").target.os.tag;

    const descriptor = switch (os_tag) {
        .windows => SurfaceDescriptor{
            .windows_hwnd = .{
                .label = "basic surface",
                .hinstance = std.os.windows.kernel32.GetModuleHandleW(null).?,
                .hwnd = window_provider.getWin32Window().?,
            },
        },
        .macos => macos: {
            const ns_window = window_provider.getCocoaWindow().?;
            const ns_view = msgSend(ns_window, "contentView", .{}, *anyopaque); // [nsWindow contentView]

            // Create a CAMetalLayer that covers the whole window that will be passed to CreateSurface.
            msgSend(ns_view, "setWantsLayer:", .{true}, void); // [view setWantsLayer:YES]
            const layer = msgSend(objc.objc_getClass("CAMetalLayer"), "layer", .{}, ?*anyopaque); // [CAMetalLayer layer]
            if (layer == null) @panic("failed to create Metal layer");
            msgSend(ns_view, "setLayer:", .{layer.?}, void); // [view setLayer:layer]

            // Use retina if the window was created with retina support.
            const scale_factor = msgSend(ns_window, "backingScaleFactor", .{}, f64); // [ns_window backingScaleFactor]
            msgSend(layer.?, "setContentsScale:", .{scale_factor}, void); // [layer setContentsScale:scale_factor]

            break :macos SurfaceDescriptor{
                .metal_layer = .{
                    .label = "basic surface",
                    .layer = layer.?,
                },
            };
        },
        .emscripten => SurfaceDescriptor{
            .canvas_html = .{
                .label = "basic surface",
                .selector = "#canvas", // TODO: can this be somehow exposed through api?
            },
        },
        else => if (isLinuxDesktopLike(os_tag)) linux: {
            if (window_provider.getWaylandDisplay()) |wl_display| {
                break :linux SurfaceDescriptor{
                    .wayland = .{
                        .label = "basic surface",
                        .display = wl_display,
                        .surface = window_provider.getWaylandSurface().?,
                    },
                };
            } else {
                break :linux SurfaceDescriptor{
                    .xlib = .{
                        .label = "basic surface",
                        .display = window_provider.getX11Display().?,
                        .window = window_provider.getX11Window(),
                    },
                };
            }
        } else unreachable,
    };

    return switch (descriptor) {
        .metal_layer => |src| blk: {
            var desc: wgpu.SurfaceDescriptorFromMetalLayer = undefined;
            desc.chain.next = null;
            desc.chain.struct_type = .surface_descriptor_from_metal_layer;
            desc.layer = src.layer;
            break :blk instance.createSurface(.{
                .next_in_chain = @ptrCast(&desc),
                .label = if (src.label) |l| l else null,
            });
        },
        .windows_hwnd => |src| blk: {
            var desc: wgpu.SurfaceDescriptorFromWindowsHWND = undefined;
            desc.chain.next = null;
            desc.chain.struct_type = .surface_descriptor_from_windows_hwnd;
            desc.hinstance = src.hinstance;
            desc.hwnd = src.hwnd;
            break :blk instance.createSurface(.{
                .next_in_chain = @ptrCast(&desc),
                .label = if (src.label) |l| l else null,
            });
        },
        .xlib => |src| blk: {
            var desc: wgpu.SurfaceDescriptorFromXlibWindow = undefined;
            desc.chain.next = null;
            desc.chain.struct_type = .surface_descriptor_from_xlib_window;
            desc.display = src.display;
            desc.window = src.window;
            break :blk instance.createSurface(.{
                .next_in_chain = @ptrCast(&desc),
                .label = if (src.label) |l| l else null,
            });
        },
        .wayland => |src| blk: {
            var desc: wgpu.SurfaceDescriptorFromWaylandSurface = undefined;
            desc.chain.next = null;
            desc.chain.struct_type = .surface_descriptor_from_wayland_surface;
            desc.display = src.display;
            desc.surface = src.surface;
            break :blk instance.createSurface(.{
                .next_in_chain = @ptrCast(&desc),
                .label = if (src.label) |l| l else null,
            });
        },
        .canvas_html => |src| blk: {
            var desc: wgpu.SurfaceDescriptorFromCanvasHTMLSelector = .{
                .chain = .{ .struct_type = .surface_descriptor_from_canvas_html_selector, .next = null },
                .selector = src.selector,
            };
            break :blk instance.createSurface(.{
                .next_in_chain = @as(*const wgpu.ChainedStruct, @ptrCast(&desc)),
                .label = if (src.label) |l| l else null,
            });
        },
    };
}

fn adapterCallback(status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.c) void {
    switch (status) {
        .success => {
            const self: *Renderer = @ptrCast(@alignCast(userdata orelse return));
            const device = adapter.createDevice(.{});

            const size = self.window_provider.getFramebufferSize();

            const surface = createSurfaceForWindow(Global.instance.?, self.window_provider);
            const swap_chain = device.createSwapChain(surface, .{ .present_mode = .immediate, .width = size[0], .height = size[1], .usage = .{ .render_attachment = true }, .format = .bgra8_unorm });

            self.adapter = adapter;
            self.device = device;
            self.surface = surface;
            self.swap_chain = swap_chain;
        },
        .err, .unavailable, .unknown => {
            if (message) |msg| {
                std.log.err("Error requesting adapter {s}", .{msg});
            } else {
                std.log.err("Unknown error requesting adapter", .{});
            }
        },
    }
}

const Global = struct {
    pub var dawn_instance: DawnNativeInstance = null;
    pub var instance: ?wgpu.Instance = null;
};

pub const Renderer = struct {
    device: wgpu.Device = undefined,
    adapter: wgpu.Adapter = undefined,
    surface: wgpu.Surface = undefined,
    swap_chain: wgpu.SwapChain = undefined,
    window_provider: WindowProvider,

    const Self = @This();

    pub fn new(window_provider: WindowProvider) Self {
        dawnProcSetProcs(dnGetProcs());

        Global.dawn_instance = dniCreate();
        errdefer dniDestroy(Global.dawn_instance);

        if (Global.instance == null) {
            Global.instance = wgpu.createInstance(.{});
        }

        var self: Self = .{ .window_provider = window_provider };

        Global.instance.?.requestAdapter(.{ .power_preference = .low_power }, adapterCallback, @ptrCast(@constCast(&self)));

        return self;
    }

    pub fn destroy(self: Self) void {
        self.device.destroy();
        self.adapter.release();
        dniDestroy(Global.dawn_instance.?);
    }

    pub fn setOutputSize(self: *Self, width: u32, height: u32) void {
        self.swap_chain.configure(.rgba8_unorm, .{ .render_attachment = true }, width, height);
    }
};
