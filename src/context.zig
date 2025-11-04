const std = @import("std");
const shd = @import("shaders/shader.glsl.zig");
const sokol = @import("sokol");
const sg = sokol.gfx;
const math = @import("math.zig");
const Color = @import("color.zig");

pub const MAX_SHAPES = 2048;
pub const MAX_TRANSFORMS = 512;
pub const MAX_PAINTS = 512;
pub const MAX_VERTICES = 1024;

pub const Transform = struct {
    matrix: [4][4]f32,

    pub fn equals(self: *Transform, other: *Transform) bool {
        return self.matrix == other.matrix;
    }

    pub fn unfold(self: *const Transform) [16]f32 {
        return @as([16]f32, @bitCast(self.matrix));
    }
};

const Self = @This();

// Shapes
shape_spatials: std.BoundedArray(shd.ShapeSpatial, MAX_SHAPES),
shapes: std.BoundedArray(shd.Shape, MAX_SHAPES),
// Transform matrices
transforms: std.BoundedArray(shd.Transform, MAX_TRANSFORMS),
last_transform: ?Transform = null,
transform_stack: std.ArrayList(Transform),
// Fill and stroke styles for shapes
paints: std.BoundedArray(shd.Paint, MAX_PAINTS),
// Vertices for paths
vertices: std.BoundedArray(math.Vec2, MAX_VERTICES),
// MSDF data for shapes
msdf: struct {
	image: sg.Image,
	data: []u8,
	width: u32,
	height: u32,
},
paint_image: sg.Image,

pub fn init(paint_image: sg.Image) Self {
	const size = 2048;
	const pixels = std.heap.page_allocator.alloc(u8, size * size * 4) catch unreachable;
    @memset(pixels, 0);
    return Self{
        .shape_spatials = .{},
        .shapes = .{},
        .transforms = .{},
        .paints = .{},
        .vertices = .{},
        .transform_stack = std.ArrayList(Transform).init(std.heap.page_allocator),
        .msdf = .{
        	.image = sg.makeImage(.{
				.label = "MSDF Image",
				.pixel_format = .RGBA8,
				.width = size,
				.height = size,
				.type = ._2D,
				.usage = .{
					.dynamic_update = true
				}
			}),
         	.data = pixels,
          	.width = size,
           	.height = size,
        },
        .paint_image = paint_image,
    };
}

pub fn pushMatrix(self: *Self) void {
    self.transform_stack.append(Transform{ .matrix = .{ .{ 1.0, 0.0, 0.0, 0.0 }, .{ 0.0, 1.0, 0.0, 0.0 }, .{ 0.0, 0.0, 1.0, 0.0 }, .{ 0.0, 0.0, 0.0, 1.0 } } }) catch unreachable;
}

pub fn popMatrix(self: *Self) void {
	self.transform_stack.pop();
}

pub fn addMSDF(self: *Self, data: []u8, width: u32, height: u32) math.Rect {
	for (0..height) |y| {
        for (0..width) |x| {
        	const src_index = (y * self.msdf.width + x) * 4;
         	const dst_index = (y * width + x) * 4;
            self.msdf.data[src_index] = data[dst_index];
            self.msdf.data[src_index + 1] = data[dst_index + 1];
            self.msdf.data[src_index + 2] = data[dst_index + 2];
            self.msdf.data[src_index + 3] = data[dst_index + 3];
        }
    }
    var image_data = sg.ImageData{};
    image_data.subimage[0][0] = .{.ptr = self.msdf.data.ptr, .size = self.msdf.data.len};
    sg.updateImage(self.msdf.image,image_data);
    return math.Rect.new(0, 0, @floatFromInt(width), @floatFromInt(height));
}
