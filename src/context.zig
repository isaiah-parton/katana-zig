const std = @import("std");
const shd = @import("shaders/shader.glsl.zig");
const sokol = @import("sokol");
const zstbi = @import("zstbi");
const sg = sokol.gfx;
const sglue = sokol.glue;
const sapp = sokol.app;
const math = @import("math.zig");
const Color = @import("color.zig");

pub const MAX_SHAPES = 2048;
pub const MAX_TRANSFORMS = 512;
pub const MAX_PAINTS = 512;
pub const MAX_VERTICES = 1024;
pub const TEXTURE_SIZE = 2048;

const Atlas = struct {
	dirty: bool = true,
	image: sg.Image,
	sampler: sg.Sampler,
	data: []u8,
	width: u32,
	height: u32,
	allocator: std.mem.Allocator,
	offset_x: u32 = 0,
	offset_y: u32 = 0,
	max_height: u32 = 0,
	rects: std.ArrayList(math.Rect),

	pub fn init(allocator: std.mem.Allocator, label: []const u8, size: u32) Atlas {
		const pixels = allocator.alloc(u8, size * size * 4) catch unreachable;
    	@memset(pixels, 0);
		return Atlas {
			.allocator = allocator,
			.image = sg.makeImage(.{
				.label = std.fmt.allocPrintSentinel(allocator, "{s} texture", .{label}, 0) catch unreachable,
				.pixel_format = .RGBA8,
				.width = @intCast(size),
				.height = @intCast(size),
				.type = ._2D,
				.usage = .{
					.dynamic_update = true
				}
			}),
			.sampler = sg.makeSampler(.{
				.label = std.fmt.allocPrintSentinel(allocator, "{s} sampler", .{label}, 0) catch unreachable,
				.min_filter = .LINEAR,
				.mag_filter = .LINEAR,
				.wrap_u = .CLAMP_TO_EDGE,
				.wrap_v = .CLAMP_TO_EDGE
			}),
			.data = pixels,
			.width = size,
			.height = size,
			.rects = std.ArrayList(math.Rect).initCapacity(allocator, 8) catch unreachable,
		};
	}

	pub fn destroy(self: *Atlas) void {
		sg.destroyImage(self.image);
		sg.destroySampler(self.sampler);
		self.allocator.free(self.data);
	}

	pub fn addImage(self: *Atlas, data: []u8, width: u32, height: u32) !math.Rect {
		try self.addImageData(data, self.offset_x, self.offset_y, width, height);
		const rect = math.Rect.new(@floatFromInt(self.offset_x), @floatFromInt(self.offset_y), @floatFromInt(width), @floatFromInt(height));
		self.offset_x += width;
		if (self.offset_x + width > self.width) {
			self.offset_x = 0;
			self.offset_y += self.max_height;
		}
		self.max_height = @max(self.max_height, height);
		return rect;
	}

	pub fn addImageData(self: *Atlas, data: []u8, left: u32, top: u32, width: u32, height: u32) !void {
		if (left + width > self.width or top + height > self.height) {
			return error.OutOfBounds;
		}
		for (0..height) |y| {
	        for (0..width) |x| {
	        	const src_index = (top + y * self.width + left + x) * 4;
	         	const dst_index = (top + y * width + left + x) * 4;
	            self.data[src_index] = data[dst_index];
	            self.data[src_index + 1] = data[dst_index + 1];
	            self.data[src_index + 2] = data[dst_index + 2];
	            self.data[src_index + 3] = data[dst_index + 3];
	        }
	    }
		self.dirty = true;
	}

	pub fn upload(self: *Atlas) void {
		var image_data = sg.ImageData{};
	    image_data.mip_levels[0] = .{.ptr = self.data.ptr, .size = self.data.len};
	    sg.updateImage(self.image, image_data);
	    self.dirty = false;
	}
};

fn Buffer(elem: type) type {
	return struct {
		array: std.ArrayList(elem),
		buffer: sg.Buffer,

		pub fn init(allocator: std.mem.Allocator, label: [*c]const u8, capacity: usize) @This() {
			return .{
				.array = std.ArrayList(elem).initCapacity(allocator, capacity) catch unreachable,
				.buffer = sg.makeBuffer(.{
			    	.usage = .{ .storage_buffer = true, .dynamic_update = true },
			     	.size = @sizeOf(shd.ShapeSpatial) * capacity,
			      	.label = label
			    }),
			};
		}

		pub fn upload(self: *@This()) void {
			if (self.array.items.len == 0) return;
			sg.updateBuffer(self.buffer, .{.ptr = @ptrCast(self.array.items.ptr), .size = @sizeOf(elem) * self.array.items.len});
			self.array.clearRetainingCapacity();
		}

		pub fn view(self: *const @This()) sg.View {
			return sg.makeView(.{.storage_buffer = .{.buffer = self.buffer}});
		}
	};
}

const Self = @This();

bindings: sg.Bindings = .{},
pipeline: sg.Pipeline = .{},
// Shapes
shape_spatials: Buffer(shd.ShapeSpatial),
shapes: Buffer(shd.Shape),
// Transform matrices
transforms: Buffer(shd.Transform),
last_transform: ?math.Mat4 = null,
transform_stack: std.ArrayList(math.Mat4),
// Fill and stroke styles for shapes
paints: Buffer(shd.Paint),
// Vertices for paths
vertices: Buffer(math.Vec2),
// Atlas for MSDF shapes
msdf_atlas: Atlas,
// Atlas for user images
paint_atlas: Atlas,

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    var self = Self{
    	.shape_spatials = Buffer(shd.ShapeSpatial).init(allocator, "Shape Spatials", MAX_SHAPES),
    	.shapes = Buffer(shd.Shape).init(allocator, "Shapes", MAX_SHAPES),
    	.transforms = Buffer(shd.Transform).init(allocator, "Transforms", MAX_TRANSFORMS),
    	.paints = Buffer(shd.Paint).init(allocator, "Paints", MAX_PAINTS),
    	.vertices = Buffer(math.Vec2).init(allocator, "Vertices", MAX_VERTICES),
    	.transform_stack = std.ArrayList(math.Mat4).initCapacity(allocator, 64) catch unreachable,
    	.msdf_atlas = Atlas.init(allocator, "MSDF", TEXTURE_SIZE),
    	.paint_atlas = Atlas.init(allocator, "Paint", TEXTURE_SIZE),
    	.allocator = allocator,
    };

    self.bindings.views[shd.VIEW_msdf_texture] = sg.makeView(.{
    	.texture = .{
     		.image = self.msdf_atlas.image
     	}
    });
    self.bindings.samplers[shd.SMP_msdf_sampler] = self.msdf_atlas.sampler;

    self.bindings.views[shd.VIEW_paint_texture] = sg.makeView(.{
    	.texture = .{
     		.image = self.paint_atlas.image,
     	}
    });
    self.bindings.samplers[shd.SMP_paint_sampler] = self.paint_atlas.sampler;

    self.bindings.views[shd.VIEW_shapesVertexBuffer] = self.shape_spatials.view();
    self.bindings.views[shd.VIEW_xformsBuffer] = self.transforms.view();
    self.bindings.views[shd.VIEW_shapesBuffer] = self.shapes.view();
    self.bindings.views[shd.VIEW_paintsBuffer] = self.paints.view();
    self.bindings.views[shd.VIEW_verticesBuffer] = self.vertices.view();

    // create a shader and pipeline object
    var pipeline_desc = sg.PipelineDesc{
	    .label = "Blade",
		.shader = sg.makeShader(shd.shaderShaderDesc(sg.queryBackend())),
	 	.primitive_type = .TRIANGLE_STRIP,
	  	.blend_color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
	    .color_count = 1,
    };
    pipeline_desc.colors[0] = .{
  		.pixel_format = .RGBA8,
  		.write_mask = .RGBA,
       	.blend = .{
            .enabled = true,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            .op_rgb = .DEFAULT,
            .op_alpha = .REVERSE_SUBTRACT,
            .src_factor_alpha = .ONE,
            .dst_factor_alpha = .ONE
        }
   	};
   	self.pipeline = sg.makePipeline(pipeline_desc);

    return self;
}

pub fn pushMatrix(self: *Self) void {
    self.transform_stack.append(math.Mat4.identity()) catch unreachable;
}

pub fn popMatrix(self: *Self) void {
	self.transform_stack.pop();
}

pub fn rotate(self: *Self, angle: f32) void {
	if (angle == 0.0) {
		return;
	}
	var current_matrix = self.transform_stack.getLastOrNull() orelse math.Mat4.identity();
	current_matrix = math.Mat4.mul(current_matrix, math.Mat4.rotate(angle, .new(0, 0, 1)));
	self.transform_stack.append(current_matrix) catch unreachable;
}

pub fn translate(self: *Self, vector: math.Vec2) void {
	var current_matrix = self.transform_stack.getLastOrNull() orelse math.Mat4.identity();
	current_matrix = math.Mat4.mul(current_matrix, math.Mat4.translate(math.Vec3.new(vector.x, vector.y, 0.0)));
	self.transform_stack.append(current_matrix) catch unreachable;
}

pub fn scale(self: *Self, factor: math.Vec2) void {
	var current_matrix = self.transform_stack.getLastOrNull() orelse math.Mat4.identity();
	current_matrix = math.Mat4.mul(current_matrix, math.Mat4.scale(math.Vec3.new(factor.x, factor.y, 1)));
	self.transform_stack.append(current_matrix) catch unreachable;
}

pub fn loadUserImage(self: *Self, path: [:0]const u8) !math.Rect {
	const image = try zstbi.Image.loadFromFile(path, 4);
	return try self.paint_atlas.addImage(image.data, image.width, image.height);
}

pub fn uploadData(self: *Self) void {
	self.shape_spatials.upload();
	self.shapes.upload();
	self.paints.upload();
	self.transforms.upload();
	self.vertices.upload();
}

pub fn beginDrawing(self: *Self) void {
	self.last_transform = null;
	self.transform_stack.clearRetainingCapacity();
	self.paints.array.append(self.allocator, shd.Paint{
		.kind = 0,
		._noise = 0.0,
		.col0 = undefined,
		.col1 = undefined,
		.col2 = undefined,
		.cv0 = undefined,
		.cv1 = undefined,
		.cv2 = undefined,
		.cv3 = undefined
	}) catch unreachable;
    self.transforms.array.append(self.allocator, shd.Transform{
    	.matrix = .{
     		1.0, 0.0, 0.0, 0.0,
       		0.0, 1.0, 0.0, 0.0,
         	0.0, 0.0, 1.0, 0.0,
          	0.0, 0.0, 0.0, 1.0
     	}
    }) catch unreachable;
}

pub fn endDrawing(self: *Self) void {
	const shape_count = self.shapes.array.items.len;

	if (self.msdf_atlas.dirty) {
		self.msdf_atlas.upload();
	}
	if (self.paint_atlas.dirty) {
		self.paint_atlas.upload();
	}
	self.uploadData();

	var pass_action = sg.PassAction{};
    pass_action.colors[0] = .{.load_action = .CLEAR, .clear_value = .{.r = 0.02, .g = 0.05, .b = 0.1, .a = 1}};

    const vertex_params = shd.VsParams{
    	.screen_size = .new(
     		@floatFromInt(sapp.width()),
       		@floatFromInt(sapp.height())
     	)
    };
    const fragment_params = shd.FsParams{
    	.time = 0.0,
     	.output_gamma = 1.0,
      	.text_unit_range = 0.001,
       	.text_in_bias = 0.0,
        .text_out_bias = 0.0
    };

    sg.beginPass(.{ .swapchain = sglue.swapchain(), .action = pass_action });
    sg.applyPipeline(self.pipeline);
    sg.applyUniforms(@intCast(shd.shaderUniformBlockSlot("vs_params").?), sg.Range{ .ptr = @ptrCast(&vertex_params), .size = @intCast(shd.shaderUniformBlockSize("vs_params").?) });
    sg.applyUniforms(@intCast(shd.shaderUniformBlockSlot("fs_params").?), sg.Range{ .ptr = @ptrCast(&fragment_params), .size = @intCast(shd.shaderUniformBlockSize("fs_params").?) });
    sg.applyBindings(self.bindings);
    sg.draw(0, 4, @intCast(shape_count));
    sg.endPass();
    sg.commit();
}
