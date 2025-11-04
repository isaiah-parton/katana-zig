const math = @import("math.zig");
const std = @import("std");
const zstbi = @import("zstbi");
const json = @import("std").json;

const Self = @This();

const Rect = struct {
	left: f32,
	top: f32,
	right: f32,
	bottom: f32,

	pub fn zero() Rect {
		return Rect{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
	}
};

const Glyph = struct {
	unicode: i32 = 0,
	advance: f32 = 0,
	atlasBounds: Rect = .zero(),
	planeBounds: Rect = .zero(),
};

firstGlyph: i32 = 0,
atlas: struct {
	distanceRange: f32 = 0,
	size: f32 = 0,
},
metrics: struct {
	emSize: f32 = 0,
	lineHeight: f32 = 0,
	ascender: f32 = 0,
	descender: f32 = 0,
	underlineY: f32 = 0,
	underlineThickness: f32 = 0,
},
glyphs: []Glyph,
image: zstbi.Image = undefined,
rect: math.Rect = undefined,

pub fn loadFromMemory(image_data: []u8, json_data: []u8) !Self {
	var data = (try json.parseFromSlice(Self, std.heap.page_allocator, json_data, .{ .ignore_unknown_fields = true })).value;
	data.firstGlyph = data.glyphs[0].unicode;
	data.image = try zstbi.Image.loadFromMemory(image_data, 4);
	return data;
}

pub fn loadFromFiles(image_path: []const u8, json_path: []const u8) !Self {
	const json_data = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, json_path, std.math.maxInt(usize));
	defer std.heap.page_allocator.free(json_data);

	const image_data = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, image_path, std.math.maxInt(usize));
	defer std.heap.page_allocator.free(image_data);

	return try loadFromMemory(image_data, json_data);
}

pub fn getGlyph(self: *const Self, unicode: i32) ?Glyph {
	if (unicode < self.firstGlyph or unicode >= self.firstGlyph + @as(i32, @intCast(self.glyphs.len))) return null;
	return self.glyphs[@intCast(unicode - self.firstGlyph)];
}
