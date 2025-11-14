const std = @import("std");
const math = @import("math.zig");
const Shape = @import("shape.zig");
const Font = @import("font.zig");
const Context = @import("context.zig");
const Color = @import("color.zig");
const Self = @This();

const Glyph = struct {
	position: math.Vec2,
	advance: f32,
	shape: ?Shape,
};

origin: math.Vec2,
offset: math.Vec2 = .zero(),
size: math.Vec2 = .zero(),
glyphs: std.ArrayList(Glyph) = .empty,
allocator: std.mem.Allocator,

pub fn init(origin: math.Vec2, allocator: std.mem.Allocator) Self {
	return Self {
		.origin = origin,
		.allocator = allocator,
	};
}

pub fn write_string(self: *Self, string: []const u8, font: *Font, scale: f32) !void {
	try self.glyphs.ensureUnusedCapacity(self.allocator, string.len);
	var view = try std.unicode.Utf8View.init(string);
	var iter = view.iterator();
	while (iter.nextCodepoint()) |char| {
		if (char == '\n') {
			self.offset.x = 0;
			self.offset.y += font.metrics.lineHeight * scale;
			try self.glyphs.append(self.allocator, .{
				.position = self.origin.add(self.offset),
				.advance = 1,
				.shape = null,
			});
			continue;
		}
		if (font.getGlyph(char) orelse font.getGlyph('?')) |glyph| {
			const top_left = self.offset.add(math.Vec2.new(
				glyph.planeBounds.left,
				font.metrics.ascender + font.metrics.descender - glyph.planeBounds.top
			).scale(scale));
			const bottom_right = self.offset.add(math.Vec2.new(
				glyph.planeBounds.right,
				font.metrics.ascender + font.metrics.descender - glyph.planeBounds.bottom
			).scale(scale));
			try self.glyphs.append(self.allocator, .{
				.position = self.origin.add(self.offset),
				.advance = glyph.advance,
				.shape = Shape.msdf(
					top_left,
					bottom_right,
					.new(glyph.atlasBounds.left, @as(f32, @floatFromInt(font.image.height)) - glyph.atlasBounds.top),
					.new(glyph.atlasBounds.right, @as(f32, @floatFromInt(font.image.height)) - glyph.atlasBounds.bottom)
				)
			});
			self.size.x += glyph.advance * scale;
			self.offset.x += glyph.advance * scale;
		}
	}
	try self.glyphs.append(self.allocator, .{
		.position = self.origin.add(self.offset),
		.advance = 1,
		.shape = null,
	});
	self.size.y = @max(self.size.y, font.metrics.ascender * scale);
}

pub fn translate(self: *Self, factor: math.Vec2) void {
	self.origin = self.origin.sub(self.size.mul(factor));
}

pub fn draw(self: *const Self, ctx: *Context, paint: anytype) void {
	for (self.glyphs.items) |*glyph| {
		if (glyph.shape) |*shape| {
			shape.variant.msdf.top_left = shape.variant.msdf.top_left.add(self.origin);
			shape.variant.msdf.bottom_right = shape.variant.msdf.bottom_right.add(self.origin);
			shape.draw(ctx, paint);
		}
	}
}
