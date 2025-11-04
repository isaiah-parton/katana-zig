const std = @import("std");
const shd = @import("shaders/shader.glsl.zig");
const Color = @import("color.zig");

pub const MAX_SHAPES = 2048;
pub const MAX_TRANSFORMS = 512;
pub const MAX_PAINTS = 512;

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

shape_spatials: std.BoundedArray(shd.ShapeSpatial, MAX_SHAPES),
shapes: std.BoundedArray(shd.Shape, MAX_SHAPES),
transforms: std.BoundedArray(shd.Transform, MAX_TRANSFORMS),
paints: std.BoundedArray(shd.Paint, MAX_PAINTS),
last_transform: ?Transform = null,
transform_stack: std.ArrayList(Transform),

pub fn init() Self {
    return Self{
        .shape_spatials = .{},
        .shapes = .{},
        .transforms = .{},
        .paints = .{},
        .transform_stack = std.ArrayList(Transform).init(std.heap.page_allocator),
    };
}

pub fn push_matrix(self: *Self) void {
    self.transform_stack.append(Transform{ .matrix = .{ .{ 1.0, 0.0, 0.0, 0.0 }, .{ 0.0, 1.0, 0.0, 0.0 }, .{ 0.0, 0.0, 1.0, 0.0 }, .{ 0.0, 0.0, 0.0, 1.0 } } }) catch unreachable;
}

pub fn pop_matrix(self: *Self) void {
	self.transform_stack.pop();
}
