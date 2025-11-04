const std = @import("std");
const Color = @import("color.zig");
const Context = @import("context.zig");
const math = @import("math.zig");
const shd = @import("shaders/shader.glsl.zig");
const zm = @import("zmath");
const Self = @This();

pub const Kind = enum {
    none,
    circle,
    rect,
    arc,
    line,
    bezier,
    path,
    msdf,
};

const Variant = union(Kind) {
	none: struct {},
	circle: struct {
		center: math.Vec2,
		radius: f32,
	},
	rect: struct {
		top_left: math.Vec2,
		bottom_right: math.Vec2,
		corner_radii: [4]f32,
	},
	arc: struct {
		center: math.Vec2,
		start_angle: f32,
		end_angle: f32,
		radius: f32,
	},
	line: [2]math.Vec2,
	bezier: [3]math.Vec2,
	path: struct {
		origin: math.Vec2,
		points: std.ArrayList(math.Vec2),
	},
	msdf: struct {
		top_left: math.Vec2,
		bottom_right: math.Vec2,
		source_top_left: math.Vec2,
		source_bottom_right: math.Vec2,
	},
};

variant: Variant,
color: ?Color = null,
width: f32 = 0,
outlined: bool = false,

pub fn circle(center: math.Vec2, radius: f32) Self {
    return Self{
    	.variant = .{
	     	.circle = .{
	    		.center = center,
	    		.radius = radius,
	    	}
	     }
    };
}

pub fn rect(top_left: math.Vec2, bottom_right: math.Vec2) Self {
	return Self{
		.variant = .{
			.rect = .{
				.top_left = top_left,
				.bottom_right = bottom_right,
				.corner_radii = .{0, 0, 0, 0},
			}
		}
	};
}

pub fn bezier(a: math.Vec2, b: math.Vec2, c: math.Vec2) Self {
	return Self {
		.variant = .{
			.bezier = .{a, b, c}
		}
	};
}

pub fn line(a: math.Vec2, b: math.Vec2) Self {
	return Self {
		.variant = .{
			.line = .{a, b}
		}
	};
}

pub fn msdf(top_left: math.Vec2, bottom_right: math.Vec2, source_top_left: math.Vec2, source_bottom_right: math.Vec2) Self {
	return Self {
		.variant = .{
			.msdf = .{
				.top_left = top_left,
				.bottom_right = bottom_right,
				.source_top_left = source_top_left,
				.source_bottom_right = source_bottom_right,
			}
		}
	};
}

const PathOptions = struct {
	origin: math.Vec2,
	allocator: std.mem.Allocator = std.heap.page_allocator,
};

pub fn path(opts: PathOptions) Self {
	return Self {
		.variant = .{
			.path = .{
				.origin = opts.origin,
				.points = std.ArrayList(math.Vec2).init(opts.allocator)
			}
		}
	};
}

pub fn lineTo(self: *Self, point: math.Vec2) void {
	const last_point = self.variant.path.points.getLastOrNull() orelse self.variant.path.origin;
	self.variant.path.points.append(last_point) catch unreachable;
	self.variant.path.points.append(last_point.lerp(point, 0.5)) catch unreachable;
	self.variant.path.points.append(point) catch unreachable;
}

pub fn quadTo(self: *Self, control: math.Vec2, point: math.Vec2) void {
	const last_point = self.variant.path.points.getLastOrNull() orelse self.variant.path.origin;
	self.variant.path.points.append(last_point) catch unreachable;
	self.variant.path.points.append(control) catch unreachable;
	self.variant.path.points.append(point) catch unreachable;
}

pub fn close(self: *Self) void {
	self.lineTo(self.variant.path.origin);
}

pub fn rounded(self: Self, top_left: f32, top_right: f32, bottom_left: f32, bottom_right: f32) Self {
	var new = self;
	new.variant.rect.corner_radii = .{top_left, top_right, bottom_left, bottom_right};
	return new;
}

pub fn fill(self: Self, color: Color) Self {
	var new = self;
	new.color = color;
	return new;
}

pub fn stroke(self: Self, color: Color, width: f32) Self {
	var new = self;
	new.color = color;
	new.width = width;
	new.outlined = true;
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
			.cv0 = math.Vec2.zero(),
			.cv1 = math.Vec2.zero(),
			.cv2 = math.Vec2.zero(),
			.cv3 = math.Vec2.zero(),
			._noise = 0,
		}
	) catch unreachable;
	switch (self.variant) {
		Variant.none => {},
		Variant.circle => |info| {
			ctx.shape_spatials.append(.{
				.quad_min = info.center.sub(info.radius),
				.quad_max = info.center.add(info.radius),
				.tex_min = math.Vec2.zero(),
				.tex_max = math.Vec2.zero(),
				.xform = 0
			}) catch unreachable;
			ctx.shapes.append(
				.{
					.kind = @intFromEnum(self.variant),
					.mode = 0,
					.next = 0,
					.cv0 = info.center,
					.cv1 = math.Vec2.zero(),
					.cv2 = math.Vec2.zero(),
					.radius = .{info.radius, 0, 0, 0},
					.width = 0,
					.start = 0,
					.count = 0,
					.stroke = 0,
					.paint = @intCast(ctx.paints.len - 1),
				}
			) catch unreachable;
		},
		Variant.rect => |info| {
			ctx.shape_spatials.append(.{
				.quad_min = info.top_left,
				.quad_max = info.bottom_right,
				.tex_min = math.Vec2.zero(),
				.tex_max = math.Vec2.zero(),
				.xform = 0
			}) catch unreachable;
			ctx.shapes.append(.{
				.kind = @intFromEnum(self.variant),
				.mode = 0,
				.next = 0,
				.cv0 = info.top_left,
				.cv1 = info.bottom_right,
				.cv2 = math.Vec2.zero(),
				.radius = info.corner_radii,
				.width = self.width,
				.start = 0,
				.count = 0,
				.stroke = @intFromBool(self.outlined),
				.paint = @intCast(ctx.paints.len - 1)
			}) catch unreachable;
		},
		Variant.arc => {},
		Variant.line => |points| {
			ctx.shape_spatials.append(.{
				.quad_min = math.Vec2.min(.{points[0], points[1]}).sub(self.width),
				.quad_max = math.Vec2.max(.{points[0], points[1]}).add(self.width),
				.tex_min = math.Vec2.zero(),
				.tex_max = math.Vec2.zero(),
				.xform = 0,
			}) catch unreachable;
			ctx.shapes.append(.{
				.kind = @intFromEnum(self.variant),
				.mode = 0,
				.next = 0,
				.cv0 = points[0],
				.cv1 = points[1],
				.cv2 = math.Vec2.zero(),
				.radius = .{0, 0, 0, 0},
				.width = self.width / 2,
				.start = 0,
				.count = 0,
				.stroke = 0,
				.paint = @intCast(ctx.paints.len - 1)
			}) catch unreachable;
		},
		Variant.bezier => |points| {
			ctx.shape_spatials.append(.{
				.quad_min = math.Vec2.min(.{points[0], points[1], points[2]}).sub(self.width),
				.quad_max = math.Vec2.max(.{points[0], points[1], points[2]}).add(self.width),
				.tex_min = math.Vec2.zero(),
				.tex_max = math.Vec2.zero(),
				.xform = 0,
			}) catch unreachable;
			ctx.shapes.append(.{
				.kind = @intFromEnum(self.variant),
				.mode = 0,
				.next = 0,
				.cv0 = points[0],
				.cv1 = points[1],
				.cv2 = points[2],
				.radius = .{0, 0, 0, 0},
				.width = self.width / 2,
				.start = 0,
				.count = 0,
				.stroke = 0,
				.paint = @intCast(ctx.paints.len - 1)
			}) catch unreachable;
		},
		Variant.path => |info| {
			var min_pos = math.Vec2.inf();
			var max_pos = math.Vec2.zero();
			const first_vertex = ctx.vertices.len;
			for (info.points.items) |point| {
				min_pos = math.Vec2.min(.{min_pos, point});
				max_pos = math.Vec2.max(.{max_pos, point});
				ctx.vertices.append(point) catch unreachable;
			}
			ctx.shape_spatials.append(.{
				.quad_min = min_pos.sub(self.width),
				.quad_max = max_pos.add(self.width),
				.tex_min = math.Vec2.zero(),
				.tex_max = math.Vec2.zero(),
				.xform = 0,
			}) catch unreachable;
			ctx.shapes.append(.{
				.kind = @intFromEnum(self.variant),
				.mode = 0,
				.next = 0,
				.cv0 = math.Vec2.zero(),
				.cv1 = math.Vec2.zero(),
				.cv2 = math.Vec2.zero(),
				.radius = .{0, 0, 0, 0},
				.width = self.width,
				.start = @intCast(first_vertex),
				.count = @intCast(@divFloor(info.points.items.len, 3)),
				.stroke = @intFromBool(self.outlined),
				.paint = @intCast(ctx.paints.len - 1)
			}) catch unreachable;
		},
		Variant.msdf => |info| {
			ctx.shape_spatials.append(.{
				.quad_min = info.top_left,
				.quad_max = info.bottom_right,
				.tex_min = info.source_top_left.div(2048),
				.tex_max = info.source_bottom_right.div(2048),
				.xform = 0,
			}) catch unreachable;
			ctx.shapes.append(.{
				.kind = @intFromEnum(self.variant),
				.mode = 0,
				.next = 0,
				.cv0 = math.Vec2.zero(),
				.cv1 = math.Vec2.zero(),
				.cv2 = math.Vec2.zero(),
				.radius = .{0, 0, 0, 0},
				.width = self.width,
				.start = 0,
				.count = 0,
				.stroke = @intFromBool(self.outlined),
				.paint = @intCast(ctx.paints.len - 1)
			}) catch unreachable;
		}
	}
}
