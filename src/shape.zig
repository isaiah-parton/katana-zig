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
		allocator: std.mem.Allocator,
	},
	msdf: struct {
		top_left: math.Vec2,
		bottom_right: math.Vec2,
		source_top_left: math.Vec2,
		source_bottom_right: math.Vec2,
	},
};

variant: Variant,
image: ?math.Rect = null,
width: f32 = 0,
outline_type: u32 = 0,

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
	allocator: std.mem.Allocator,
};

pub fn path(opts: PathOptions) Self {
	return Self {
		.variant = .{
			.path = .{
				.origin = opts.origin,
				.points = std.ArrayList(math.Vec2).initCapacity(opts.allocator, 8) catch unreachable,
				.allocator = opts.allocator
			}
		}
	};
}

pub fn lineTo(self: *Self, point: math.Vec2) void {
	const last_point = self.variant.path.points.getLastOrNull() orelse self.variant.path.origin;
	const allocator = self.variant.path.allocator;
	self.variant.path.points.append(allocator, last_point) catch unreachable;
	self.variant.path.points.append(allocator, last_point.lerp(point, 0.5)) catch unreachable;
	self.variant.path.points.append(allocator, point) catch unreachable;
}

pub fn quadTo(self: *Self, control: math.Vec2, point: math.Vec2) void {
	const last_point = self.variant.path.points.getLastOrNull() orelse self.variant.path.origin;
	const allocator = self.variant.path.allocator;
	self.variant.path.points.append(allocator, last_point) catch unreachable;
	self.variant.path.points.append(allocator, control) catch unreachable;
	self.variant.path.points.append(allocator, point) catch unreachable;
}

pub fn close(self: *Self) void {
	self.lineTo(self.variant.path.origin);
}

pub fn rounded(self: Self, top_left: f32, top_right: f32, bottom_left: f32, bottom_right: f32) Self {
	var new = self;
	new.variant.rect.corner_radii = .{top_left, top_right, bottom_left, bottom_right};
	return new;
}

pub fn outline(self: Self, width: f32) Self {
	var new = self;
	new.width = width;
	new.outline_type = 1;
	return new;
}

pub fn glow(self: Self, radius: f32) Self {
	var new = self;
	new.width = radius;
	new.outline_type = 4;
	return new;
}

pub fn draw(self: Self, ctx: *Context, paint: anytype) void {
	_ = self.drawEx(ctx, paint);
}

const DrawResult = struct {
	index: u32,
	bounds: math.Rect,
};

pub fn drawEx(self: Self, ctx: *Context, paint: anytype) DrawResult {
	if (!std.meta.eql(ctx.transform_stack.getLastOrNull(), ctx.last_transform)) {
		const transform = ctx.transform_stack.getLastOrNull().?;
		ctx.transforms.array.append(ctx.allocator, shd.Transform{.matrix = @bitCast(transform)}) catch unreachable;
		ctx.last_transform = transform;
	}
	const transform_index = ctx.transforms.array.items.len - 1;

	var shape_spatial: shd.ShapeSpatial = .{
		.quad_min = math.Vec2.zero(),
		.quad_max = math.Vec2.zero(),
		.tex_min = math.Vec2.zero(),
		.tex_max = math.Vec2.zero(),
		.xform = @intCast(transform_index)
	};

	if (self.image) |sourceRect| {
		shape_spatial.tex_min = .{
			.x = sourceRect.left / @as(f32, @floatFromInt(ctx.paint_atlas.width)),
			.y = sourceRect.top / @as(f32, @floatFromInt(ctx.paint_atlas.height))
		};
		shape_spatial.tex_max = .{
			.x = sourceRect.right / @as(f32, @floatFromInt(ctx.paint_atlas.width)),
			.y = sourceRect.bottom / @as(f32, @floatFromInt(ctx.paint_atlas.height))
		};
	}

	var paint_index: u32 = 0;
	if (@TypeOf(paint) != @TypeOf(null)) {
		if (@hasDecl(@TypeOf(paint), "shaderPaint")) {
			paint_index = @intCast(ctx.paints.array.items.len);
			ctx.paints.array.append(ctx.allocator, paint.shaderPaint()) catch unreachable;
		} else {
			@panic("Invalid paint provided!");
		}
	}

	var shape: shd.Shape = .{
		.kind = @intFromEnum(self.variant),
		.mode = 0,
		.next = 0,
		.cv0 = math.Vec2.zero(),
		.cv1 = math.Vec2.zero(),
		.cv2 = math.Vec2.zero(),
		.radius = .{0, 0, 0, 0},
		.width = 0,
		.start = 0,
		.count = 0,
		.stroke = 0,
		.paint = paint_index,
	};

	switch (self.variant) {
		Variant.none => {},
		Variant.circle => |info| {
			shape_spatial.quad_min = info.center.sub(info.radius);
			shape_spatial.quad_max = info.center.add(info.radius);
			shape.cv0 = info.center;
			shape.radius[0] = info.radius;
		},
		Variant.rect => |info| {
			shape_spatial.quad_min = info.top_left;
			shape_spatial.quad_max = info.bottom_right;
			shape.cv0 = info.top_left;
			shape.cv1 = info.bottom_right;
			shape.radius = info.corner_radii;
			shape.width = self.width;
			shape.stroke = @intCast(self.outline_type);
		},
		Variant.arc => {},
		Variant.line => |points| {
			shape_spatial.quad_min = math.Vec2.min(.{points[0], points[1]}).sub(self.width);
			shape_spatial.quad_max = math.Vec2.max(.{points[0], points[1]}).add(self.width);
			shape.cv0 = points[0];
			shape.cv1 = points[1];
			shape.width = self.width / 2;
		},
		Variant.bezier => |points| {
			shape_spatial.quad_min = math.Vec2.min(.{points[0], points[1], points[2]}).sub(self.width);
			shape_spatial.quad_max = math.Vec2.max(.{points[0], points[1], points[2]}).add(self.width);
			shape.cv0 = points[0];
			shape.cv1 = points[1];
			shape.cv2 = points[2];
			shape.width = self.width / 2;
		},
		Variant.path => |info| {
			var min_pos = math.Vec2.inf();
			var max_pos = math.Vec2.zero();
			const first_vertex = ctx.vertices.array.items.len;
			for (info.points.items) |point| {
				min_pos = math.Vec2.min(.{min_pos, point});
				max_pos = math.Vec2.max(.{max_pos, point});
				ctx.vertices.array.append(ctx.allocator, point) catch unreachable;
			}
			shape_spatial.quad_min = min_pos.sub(self.width);
			shape_spatial.quad_max = max_pos.add(self.width);
			shape.width = self.width;
			shape.start = @intCast(first_vertex);
			shape.count = @intCast(@divFloor(info.points.items.len, 3));
			shape.stroke = @intCast(self.outline_type);
		},
		Variant.msdf => |info| {
			shape_spatial.quad_min = info.top_left;
			shape_spatial.quad_max = info.bottom_right;
			shape_spatial.tex_min = info.source_top_left.div(2048);
			shape_spatial.tex_max = info.source_bottom_right.div(2048);
			shape.width = self.width;
			shape.stroke = @intCast(self.outline_type);
		}
	}

	// Apply mask
	if (ctx.mask_stack.getLastOrNull()) |mask| {
		shape.next = @intCast(mask.index);
		const left = @max(0, mask.top_left.x - shape_spatial.quad_min.x);
		const top = @max(0, mask.top_left.y - shape_spatial.quad_min.y);
		const right = @max(0, shape_spatial.quad_max.x - mask.bottom_right.x);
		const bottom = @max(0, shape_spatial.quad_max.y - mask.bottom_right.y);
		const source_factor = shape_spatial.tex_max.sub(shape_spatial.tex_min).div(shape_spatial.quad_max.sub(shape_spatial.quad_min));
		shape_spatial.tex_min.x += left * source_factor.x;
		shape_spatial.tex_min.y += top * source_factor.y;
		shape_spatial.tex_max.x -= right * source_factor.x;
		shape_spatial.tex_max.y -= bottom * source_factor.y;
		shape_spatial.quad_min.x += left;
		shape_spatial.quad_min.y += top;
		shape_spatial.quad_max.x -= right;
		shape_spatial.quad_max.y -= bottom;
	}

	if (shape.stroke == 4) {
		shape_spatial.quad_min.x -= shape.width;
		shape_spatial.quad_min.y -= shape.width;
		shape_spatial.quad_max.x += shape.width;
		shape_spatial.quad_max.y += shape.width;
	}

	if (shape_spatial.quad_min.x >= shape_spatial.quad_max.x or shape_spatial.quad_min.y >= shape_spatial.quad_max.y) {
		return .{
			.index = 0,
			.bounds = .new(shape_spatial.quad_min.x, shape_spatial.quad_min.y, shape_spatial.quad_min.x, shape_spatial.quad_min.y)
		};
	}

	ctx.shape_spatials.array.append(ctx.allocator, shape_spatial) catch unreachable;
	ctx.shapes.array.append(ctx.allocator, shape) catch unreachable;

	return .{
		.index = @intCast(ctx.shapes.array.items.len - 1),
		.bounds = .new(shape_spatial.quad_min.x, shape_spatial.quad_min.y, shape_spatial.quad_max.x, shape_spatial.quad_max.y)
	};
}
