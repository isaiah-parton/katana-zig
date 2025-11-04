const math = @import("math.zig");
const std = @import("std");
const json = @import("std").json;

const Rect = struct {
	top_left: math.Vec2,
	bottom_right: math.Vec2,
};

const Glyph = struct {
	source: Rect,
	bounds: Rect,
	advance: f32,
};

first_rune: i32,
size: f32,
space_advance: f32,
ascend: f32,
descend: f32,
line_height: f32,
distance_range: f32,
glyphs: []Glyph,
placeholder_glyph: Glyph,

pub fn load_from_memory(image_data: []u8, json_data: []u8) !@This() {
	const value = (try json.parseFromSlice(json.Value, std.heap.page_allocator, json_data, .{})).value;

	const atlas_object = value.object.get("atlas").?;

}
