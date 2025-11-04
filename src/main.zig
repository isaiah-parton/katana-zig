const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const shd = @import("shaders/shader.glsl.zig");
const std = @import("std");
const Context = @import("context.zig");
const Color = @import("color.zig");
const Shape = @import("shape.zig");
const MAX_SHAPES = @import("context.zig").MAX_SHAPES;
const MAX_TRANSFORMS = @import("context.zig").MAX_TRANSFORMS;

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var ctx: Context = .init();
};

const Transform = struct {
    matrix: [4][4]f32,

    pub fn unfold(self: *Transform) [16]f32 {
        return @as([16]f32, @bitCast(self.matrix));
    }
};

export fn init() void {
    state.ctx = .init();
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    const shape_spatials_buffer: sg.Buffer = sg.makeBuffer(.{ .usage = .{ .storage_buffer = true, .dynamic_update = true }, .size = @sizeOf(shd.ShapeSpatial) * MAX_SHAPES, .label = "Shape vertices" });

    const transforms_buffer = sg.makeBuffer(.{ .usage = .{ .storage_buffer = true, .dynamic_update = true }, .size = @sizeOf(Transform) * MAX_TRANSFORMS, .label = "Transforms" });

    const shapes_buffer: sg.Buffer = sg.makeBuffer(.{ .usage = .{ .storage_buffer = true, .dynamic_update = true }, .size = @sizeOf(shd.Shape) * MAX_SHAPES, .label = "Shapes" });

    const paints_buffer: sg.Buffer = sg.makeBuffer(.{ .usage = .{ .storage_buffer = true, .dynamic_update = true }, .size = @sizeOf(shd.Paint) * MAX_SHAPES, .label = "Paints" });

    state.bind.storage_buffers[0] = shape_spatials_buffer;
    state.bind.storage_buffers[1] = transforms_buffer;
    state.bind.storage_buffers[2] = shapes_buffer;
    state.bind.storage_buffers[3] = paints_buffer;

    // create a shader and pipeline object
    state.pip = sg.makePipeline(.{
       	.label = "Blade",
    	.shader = sg.makeShader(shd.shaderShaderDesc(sg.queryBackend())),
     	.primitive_type = .TRIANGLE_STRIP,
      	.blend_color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        .color_count = 1,
        .colors = .{
        	.{
         		.pixel_format = .BGRA8,
           		.write_mask = .RGBA,
             	.blend = .{
		            .enabled = true,
		            .src_factor_rgb = .SRC_ALPHA,
		            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
		            .op_rgb = .DEFAULT,
		            .op_alpha = .REVERSE_SUBTRACT,
		            .src_factor_alpha = .ONE,
		            .dst_factor_alpha = .ONE
	            }
         	},
         	.{},
         	.{},
         	.{}
        },
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
    const vertex_params = VertexShaderParams{ .screen_size = .{ @floatFromInt(sapp.width()), @floatFromInt(sapp.height()) } };
    const fragment_params = FragmentShaderParams{ .time = 0.0, .output_gamma = 1.0, .text_unit_range = 0.0, .text_in_bias = 0.0, .text_out_bias = 0.0 };

    state.ctx.paints.append(shd.Paint{ .kind = 1, ._noise = 0.0, .col0 = .{ 1.0, 0.0, 0.0, 1.0 }, .col1 = undefined, .col2 = undefined, .cv0 = undefined, .cv1 = undefined, .cv2 = undefined, .cv3 = undefined }) catch unreachable;
    state.ctx.transforms.append(shd.Transform{ .matrix = .{ 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0 } }) catch unreachable;

    // Test drawing stuff
    Shape.circle(.{50, 50}, 50).fill(Color.RED).draw(&state.ctx);
    Shape.circle(.{150, 200}, 40).fill(Color.BLUE).draw(&state.ctx);

    if (state.ctx.shape_spatials.len > 0) {
        sg.updateBuffer(state.bind.storage_buffers[0], sg.Range{ .ptr = @ptrCast(&state.ctx.shape_spatials.buffer), .size = @intCast(state.ctx.shape_spatials.len * @sizeOf(shd.ShapeSpatial)) });
    }
    if (state.ctx.transforms.len > 0) {
        sg.updateBuffer(state.bind.storage_buffers[1], sg.Range{ .ptr = @ptrCast(&state.ctx.transforms.buffer), .size = @intCast(state.ctx.transforms.len * @sizeOf(shd.Transform)) });
    }
    if (state.ctx.shapes.len > 0) {
        sg.updateBuffer(state.bind.storage_buffers[2], sg.Range{ .ptr = @ptrCast(&state.ctx.shapes.buffer), .size = @intCast(state.ctx.shapes.len * @sizeOf(shd.Shape)) });
    }
    if (state.ctx.paints.len > 0) {
        sg.updateBuffer(state.bind.storage_buffers[3], sg.Range{ .ptr = @ptrCast(&state.ctx.paints.buffer), .size = @intCast(state.ctx.paints.len * @sizeOf(shd.Paint)) });
    }

    var pass_action = sg.PassAction{};

    pass_action.colors[0] = .{.load_action = .CLEAR, .clear_value = .{.r = 0, .g = 0, .b = 0, .a = 1}};

    sg.beginPass(.{ .swapchain = sglue.swapchain(), .action = pass_action });
    sg.applyPipeline(state.pip);
    sg.applyUniforms(@intCast(shd.shaderUniformBlockSlot("vs_params").?), sg.Range{ .ptr = @ptrCast(&vertex_params), .size = @intCast(shd.shaderUniformBlockSize("vs_params").?) });
    sg.applyUniforms(@intCast(shd.shaderUniformBlockSlot("fs_params").?), sg.Range{ .ptr = @ptrCast(&fragment_params), .size = @intCast(shd.shaderUniformBlockSize("fs_params").?) });
    sg.applyBindings(state.bind);
    sg.draw(0, 4, @intCast(state.ctx.shapes.len));
    sg.endPass();
    sg.commit();

    state.ctx.shape_spatials.clear();
    state.ctx.shapes.clear();
    state.ctx.transforms.clear();
    state.ctx.paints.clear();
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
