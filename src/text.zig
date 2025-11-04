const std = @import("std");
const math = @import("math.zig");
const Shape = @import("shape.zig");
const Font = @import("font.zig");
const Context = @import("context.zig");
const Color = @import("color.zig");
const Self = @This();

shapes: std.ArrayList(Shape),

pub fn from_string(font: *Font, string: []const u8, scale: f32, origin: math.Vec2, color: Color) Self {
	var pos = origin;
	var shapes = std.ArrayList(Shape).init(std.heap.page_allocator);
	for (string) |char| {
		if (font.getGlyph(char)) |glyph| {
		    const top_left = pos.add(math.Vec2.new(glyph.planeBounds.left, -glyph.planeBounds.top).scale(scale));
		    const bottom_right = pos.add(math.Vec2.new(glyph.planeBounds.right, -glyph.planeBounds.bottom).scale(scale));
		    shapes.append(Shape.msdf(
		    	top_left,
		    	bottom_right,
		      	.new(glyph.atlasBounds.left, @as(f32, @floatFromInt(font.image.height)) - glyph.atlasBounds.top),
		      	.new(glyph.atlasBounds.right, @as(f32, @floatFromInt(font.image.height)) - glyph.atlasBounds.bottom)
		    ).fill(color)) catch unreachable;
			pos.x += glyph.advance * scale;
		}
	}
	return Self {
		.shapes = shapes,
	};
}

pub fn draw(self: *const Self, ctx: *Context) void {
	for (self.shapes.items) |shape| {
		shape.draw(ctx);
	}
}
