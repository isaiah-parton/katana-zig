const std = @import("std");
const Color = @import("color.zig");
const Context = @import("context.zig");
const shd = @import("shaders/shader.glsl.zig");
const math = @import("math.zig");

const Self = @This();

center: math.Vec2,
radius: f32,
inner_color: Color,
outer_color: Color,

pub fn shaderPaint(self: *const Self) shd.Paint {
	return shd.Paint{
		.kind = 4,
		.col0 = self.inner_color.normalize(),
		.col1 = self.outer_color.normalize(),
		.col2 = .{0, 0, 0, 0},
		.cv0 = self.center,
		.cv1 = math.Vec2.new(self.radius, 0),
		.cv2 = math.Vec2.zero(),
		.cv3 = math.Vec2.zero(),
		._noise = 0,
	};
}
