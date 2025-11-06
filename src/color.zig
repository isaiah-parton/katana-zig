const std = @import("std");
const shd = @import("shaders/shader.glsl.zig");

const Self = @This();

pub const WHITE = Self.new(255, 255, 255, 255);
pub const BLACK = Self.new(0, 0, 0, 255);
pub const BLUE = Self.new(0, 0, 255, 255);
pub const LIGHT_BLUE = Self.new(123, 176, 250, 255);
pub const RED = Self.new(255, 0, 0, 255);

r: u8,
g: u8,
b: u8,
a: u8,

pub fn new(r: u8, g: u8, b: u8, a: u8) Self {
    return Self{ .r = r, .g = g, .b = b, .a = a };
}

pub fn from_hex(hex: u32) Self {
    return Self{ .r = @truncate(hex >> 24), .g = @truncate(hex >> 16), .b = @truncate(hex >> 8), .a = @truncate(hex) };
}

pub fn fade(self: Self, a: f32) Self {
    return Self{ .r = self.r, .g = self.g, .b = self.b, .a = @intFromFloat(a * 255.0) };
}

pub fn normalize(self: Self) [4]f32 {
    return [4]f32{ @as(f32, @floatFromInt(self.r)) / 255.0, @as(f32, @floatFromInt(self.g)) / 255.0, @as(f32, @floatFromInt(self.b)) / 255.0, @as(f32, @floatFromInt(self.a)) / 255.0 };
}

pub fn shaderPaint(self: Self) shd.Paint {
	return shd.Paint{
		.kind = 1,
		.col0 = self.normalize(),
		.col1 = undefined,
		.col2 = undefined,
		.cv0 = undefined,
		.cv1 = undefined,
		.cv2 = undefined,
		.cv3 = undefined,
		._noise = 0,
	};
}
