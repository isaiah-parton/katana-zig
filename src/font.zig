const math = @import("math.zig");
const std = @import("std");
const zstbi = @import("zstbi");
const json = @import("std").json;
const msdfgen = @import("msdfgen");

const Self = @This();

var freetype_handle: msdfgen.FreetypeHandle = .init() catch |e| std.debug.print("Error initializing freetype: {}\n", .{e});

const FontSource = struct {
	font: msdfgen.FontHandle,
	charset: msdfgen.Charset,
	geometry: msdfgen.FontGeometry,

	pub fn init(path: []const u8) !@This() {
		const font = try freetype_handle.loadFont(path);
		const charset = try msdfgen.Charset.ascii();
		var geometry = try msdfgen.FontGeometry.init();
		const glyphs_loaded = geometry.loadCharset(font, 1.0, charset);
		if (!glyphs_loaded) {
			return error.EmptyFont;
		}
		const glyphs = geometry.getGlyphs();
		for (0..glyphs.count) |i| {
			glyphs.setEdgeColoring(i, .by_distance, 3.0, 0);
		}
		return .{
			.font = font,
			.charset = charset,
			.geometry = geometry,
		};
	}

	pub fn generateSDF(self: *@This(), unicode: u21) ![]f32 {
		var shape: msdfgen.Shape = undefined;
		if (self.font.loadGlyph(&shape, unicode, .EM_NORMALIZED) == null) {
			return error.GlyphNotFound;
		}
		const w: f32 = 64.0;
		const h: f32 = 64.0;
		var data = try std.heap.c_allocator.alloc(f32, w * h);
		shape.generateMTSDF(.{
			.data = &data,
			.w = w,
			.h = h,
			.range = 2.0,
			.sx = 1.0,
			.sy = 1.0,
			.dx = 0.0,
			.dy = 0.0
		});
		return data;
	}

	pub fn deinit(self: *@This()) void {
		self.font.deinit();
		self.charset.deinit();
		self.geometry.deinit();
		self.* = undefined;
	}
};

const Glyph = struct {
	unicode: i32 = 0,
	advance: f32 = 0,
	atlasBounds: math.Rect = .zero(),
	planeBounds: math.Rect = .zero(),
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
