const std = @import("std");
const Color = @import("color.zig");
const Context = @import("context.zig");
const shd = @import("shaders/shader.glsl.zig");
const zm = @import("zmath");
const Self = @This();

pub const Kind = enum {
    none,
    circle,
    arc,
    rect,
    bezier,
    line,
};

const Variant = union(Kind) {
	none: struct {},
	circle: struct {
		center: [2]f32,
		radius: f32,
	},
	arc: struct {
		center: [2]f32,
		start_angle: f32,
		end_angle: f32,
		radius: f32,
	},
	rect: struct {
		top_left: [2]f32,
		bottom_right: [2]f32,
		corner_radii: [4]f32,
	},
	bezier: struct {
		start: [2]f32,
		control: [2]f32,
		end: [2]f32,
	},
	line: struct {
		start: [2]f32,
		end: [2]f32,
	}
};

variant: Variant,
color: ?Color = null,

pub fn circle(center: [2]f32, radius: f32) Self {
    return Self{
    	.variant = .{
	     	.circle = .{
	    		.center = center,
	    		.radius = radius,
	    	}
	     }
    };
}

pub fn rect(top_left: [2]f32, bottom_right: [2]f32) Self {
	return Self{
		.variant = .{
			.rect = .{
				.top_left = top_left,
				.bottom_right = bottom_right,
			}
		}
	};
}

pub fn fill(self: Self, color: Color) Self {
	var new = self;
	new.color = color;
	return new;
}

pub fn draw(self: Self, ctx: *Context) void {
	if (!std.meta.eql(ctx.transform_stack.getLastOrNull(), ctx.last_transform)) {
		const transform = ctx.transform_stack.getLastOrNull().?;
		ctx.transforms.append(shd.Transform{.matrix = transform.unfold()}) catch unreachable;
		ctx.last_transform = transform;
	}
	ctx.paints.append(
		shd.Paint{
			.kind = 1,
			.col0 = (self.color orelse Color.WHITE).normalize(),
			.col1 = .{0, 0, 0, 0},
			.col2 = .{0, 0, 0, 0},
			.cv0 = .{0, 0},
			.cv1 = .{0, 0},
			.cv2 = .{0, 0},
			.cv3 = .{0, 0},
			._noise = 0,
		}
	) catch unreachable;
	switch (self.variant) {
		Variant.none => {},
		Variant.circle => |info| {
			ctx.shape_spatials.append(.{
				.quad_min = .{info.center[0] - info.radius, info.center[1] - info.radius},
				.quad_max = .{info.center[0] + info.radius, info.center[1] + info.radius},
				.tex_min = .{0.0, 0.0},
				.tex_max = .{0.0, 0.0},
				.xform = 0
			}) catch unreachable;
			ctx.shapes.append(
				.{
					.kind = @intFromEnum(self.variant),
					.mode = 0,
					.next = 0,
					.cv0 = info.center,
					.cv1 = .{0, 0},
					.cv2 = .{0, 0},
					.radius = .{info.radius, 0, 0, 0},
					.width = 0,
					.start = 0,
					.count = 0,
					.stroke = 0,
					.paint = @intCast(ctx.paints.len - 1),
				}
			) catch unreachable;
		},
		Variant.rect => {},
		Variant.arc => {},
		Variant.bezier => {},
		Variant.line => {},
	}
}
