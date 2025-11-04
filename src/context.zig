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
msdf_image: sg.Image,
paint_image: sg.Image,

pub fn init(msdf_image: sg.Image, paint_image: sg.Image) Self {
    return Self{
        .shape_spatials = .{},
        .shapes = .{},
        .transforms = .{},
        .paints = .{},
        .vertices = .{},
        .transform_stack = std.ArrayList(Transform).init(std.heap.page_allocator),
        .msdf_image = msdf_image,
        .paint_image = paint_image,
    };
}

pub fn push_matrix(self: *Self) void {
    self.transform_stack.append(Transform{ .matrix = .{ .{ 1.0, 0.0, 0.0, 0.0 }, .{ 0.0, 1.0, 0.0, 0.0 }, .{ 0.0, 0.0, 1.0, 0.0 }, .{ 0.0, 0.0, 0.0, 1.0 } } }) catch unreachable;
}

pub fn pop_matrix(self: *Self) void {
	self.transform_stack.pop();
}
