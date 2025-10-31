const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const shd = @import("shaders/shader.glsl.zig");
const std = @import("std");

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var shapes_vertex = std.BoundedArray(shd.Shapevertexdata, MAX_SHAPES).init(0) catch unreachable;
    var transforms = std.BoundedArray(shd.Transform, MAX_TRANSFORMS).init(0) catch unreachable;
    var shapes = std.BoundedArray(shd.Shape, MAX_SHAPES).init(0) catch unreachable;
    var paints = std.BoundedArray(shd.Paint, MAX_SHAPES).init(0) catch unreachable;
};

const MAX_SHAPES = 2048;
const MAX_TRANSFORMS = 512;

const Transform = struct {
    matrix: [4][4]f32,

    pub fn unfold(self: *Transform) [16]f32 {
        return @as([16]f32, @bitCast(self.matrix));
    }
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    const shapes_vertex_buffer: sg.Buffer = sg.makeBuffer(.{ .usage = .{ .storage_buffer = true, .dynamic_update = true }, .size = @sizeOf(shd.Shapevertexdata) * MAX_SHAPES });

    const transforms_buffer = sg.makeBuffer(.{ .usage = .{ .storage_buffer = true, .dynamic_update = true }, .size = @sizeOf(Transform) * MAX_TRANSFORMS });

    const shapes_buffer: sg.Buffer = sg.makeBuffer(.{ .usage = .{ .storage_buffer = true, .dynamic_update = true }, .size = @sizeOf(shd.Shape) * MAX_SHAPES });

    const paints_buffer: sg.Buffer = sg.makeBuffer(.{ .usage = .{ .storage_buffer = true, .dynamic_update = true }, .size = @sizeOf(shd.Paint) * MAX_SHAPES });

    state.bind.storage_buffers[0] = shapes_vertex_buffer;
    state.bind.storage_buffers[1] = transforms_buffer;
    state.bind.storage_buffers[2] = shapes_buffer;
    state.bind.storage_buffers[3] = paints_buffer;

    // create a shader and pipeline object
    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.shaderShaderDesc(sg.queryBackend())),
    });
}

const VertexShaderParams = struct {
    screen_size: [2]f32,
};

const FragmentShaderParams = struct {
    time: f32,
    output_gamma: f32,
    text_unit_range: f32,
    text_in_bias: f32,
    text_out_bias: f32,
};

export fn frame() void {
    const vertex_params = VertexShaderParams{ .screen_size = .{ 1000, 800 } };
    const fragment_params = FragmentShaderParams{ .time = 0.0, .output_gamma = 2.2, .text_unit_range = 0.0, .text_in_bias = 0.0, .text_out_bias = 0.0 };

    state.shapes_vertex.append(shd.Shapevertexdata{ .quad_min = .{ 0.0, 0.0 }, .quad_max = .{ 100.0, 100.0 }, .tex_min = .{ 0.0, 0.0 }, .tex_max = .{ 0.0, 0.0 }, .xform = 0 }) catch unreachable;
    state.shapes.append(shd.Shape{ .kind = 1, .radius = .{ 50.0, 0.0, 0.0, 0.0 }, .cv0 = .{ 50.0, 50.0 }, .cv1 = .{ 0.0, 0.0 }, .cv2 = .{ 0.0, 0.0 }, .count = 0, .mode = 0, .next = 0, .paint = 0, .start = 0, .stroke = 0, .width = 0 }) catch unreachable;
    state.paints.append(shd.Paint{ .kind = 1, ._noise = 0.0, .col0 = .{ 1.0, 0.0, 0.0, 1.0 }, .col1 = undefined, .col2 = undefined, .cv0 = undefined, .cv1 = undefined, .cv2 = undefined, .cv3 = undefined }) catch unreachable;
    state.transforms.append(shd.Transform{ .matrix = .{ 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0 } }) catch unreachable;

    if (state.shapes_vertex.len > 0) {
        sg.updateBuffer(state.bind.storage_buffers[0], sg.Range{ .ptr = @ptrCast(&state.shapes_vertex.buffer), .size = @intCast(state.shapes_vertex.len) });
    }
    if (state.transforms.len > 0) {
        sg.updateBuffer(state.bind.storage_buffers[1], sg.Range{ .ptr = @ptrCast(&state.transforms.buffer), .size = @intCast(state.transforms.len) });
    }
    if (state.shapes.len > 0) {
        sg.updateBuffer(state.bind.storage_buffers[2], sg.Range{ .ptr = @ptrCast(&state.shapes.buffer), .size = @intCast(state.shapes.len) });
    }
    if (state.paints.len > 0) {
        sg.updateBuffer(state.bind.storage_buffers[3], sg.Range{ .ptr = @ptrCast(&state.paints.buffer), .size = @intCast(state.paints.len) });
    }

    sg.beginPass(.{ .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyUniforms(@intCast(shd.shaderUniformBlockSlot("vs_params").?), sg.Range{ .ptr = @ptrCast(&vertex_params), .size = @intCast(shd.shaderUniformBlockSize("vs_params").?) });
    sg.applyUniforms(@intCast(shd.shaderUniformBlockSlot("fs_params").?), sg.Range{ .ptr = @ptrCast(&fragment_params), .size = @intCast(shd.shaderUniformBlockSize("fs_params").?) });
    sg.applyBindings(state.bind);
    sg.draw(0, 4, @intCast(state.shapes.len));
    sg.endPass();
    sg.commit();

    state.shapes_vertex.clear();
    state.shapes.clear();
    state.transforms.clear();
    state.paints.clear();
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .width = 640,
        .height = 480,
        .icon = .{ .sokol_default = true },
        .window_title = "Lizard Farce Window",
        .logger = .{ .func = slog.func },
    });
}
