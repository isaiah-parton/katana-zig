const std = @import("std");
const math = @import("math.zig");
const Shape = @import("shape.zig");
const Font = @import("font.zig");
const Context = @import("context.zig");
const Color = @import("color.zig");
const Self = @This();

size: math.Vec2 = .zero(),
shapes: std.ArrayList(Shape),

pub fn from_string(font: *Font, string: []const u8, scale: f32, origin: math.Vec2) Self {
	var pos = origin;
	var shapes = std.ArrayList(Shape).initCapacity(std.heap.page_allocator, string.len) catch unreachable;
	var size = math.Vec2.zero();
	for (string) |char| {
		if (font.getGlyph(char)) |glyph| {
		    const top_left = pos.add(math.Vec2.new(glyph.planeBounds.left, font.metrics.ascender + font.metrics.descender - glyph.planeBounds.top).scale(scale));
		    const bottom_right = pos.add(math.Vec2.new(glyph.planeBounds.right, font.metrics.ascender + font.metrics.descender - glyph.planeBounds.bottom).scale(scale));
		    shapes.append(std.heap.page_allocator, Shape.msdf(
		    	top_left,
		    	bottom_right,
		      	.new(glyph.atlasBounds.left, @as(f32, @floatFromInt(font.image.height)) - glyph.atlasBounds.top),
		      	.new(glyph.atlasBounds.right, @as(f32, @floatFromInt(font.image.height)) - glyph.atlasBounds.bottom)
		    )) catch unreachable;
			size.x += glyph.advance * scale;
			size.y = @max(size.y, bottom_right.y - top_left.y);
			pos.x += glyph.advance * scale;
		}
	}
	return Self {
		.shapes = shapes,
		.size = size,
	};
}

pub fn draw(self: *const Self, ctx: *Context, paint: anytype) void {
	for (self.shapes.items) |shape| {
		shape.draw(ctx, paint);
	}
}
