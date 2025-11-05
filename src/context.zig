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
				.label = std.fmt.allocPrintZ(allocator, "{s} texture", .{label}) catch unreachable,
				.pixel_format = .RGBA8,
				.width = @intCast(size),
				.height = @intCast(size),
				.type = ._2D,
				.usage = .{
					.dynamic_update = true
				}
			}),
			.sampler = sg.makeSampler(.{
				.label = std.fmt.allocPrintZ(allocator, "{s} sampler", .{label}) catch unreachable,
				.min_filter = .LINEAR,
				.mag_filter = .LINEAR,
				.wrap_u = .CLAMP_TO_EDGE,
				.wrap_v = .CLAMP_TO_EDGE
			}),
			.data = pixels,
			.width = size,
			.height = size,
			.rects = .init(allocator),
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
	    image_data.subimage[0][0] = .{.ptr = self.data.ptr, .size = self.data.len};
	    sg.updateImage(self.image, image_data);
	    self.dirty = false;
	}
};

const Self = @This();

bindings: sg.Bindings = .{},
pipeline: sg.Pipeline = .{},
// Shapes
shape_spatials: std.BoundedArray(shd.ShapeSpatial, MAX_SHAPES),
shapes: std.BoundedArray(shd.Shape, MAX_SHAPES),
// Transform matrices
transforms: std.BoundedArray(shd.Transform, MAX_TRANSFORMS),
last_transform: ?math.Mat4 = null,
transform_stack: std.ArrayList(math.Mat4),
// Fill and stroke styles for shapes
paints: std.BoundedArray(shd.Paint, MAX_PAINTS),
// Vertices for paths
vertices: std.BoundedArray(math.Vec2, MAX_VERTICES),
// Atlas for MSDF shapes
msdf_atlas: Atlas,
// Atlas for user images
paint_atlas: Atlas,

pub fn init() Self {
    const shape_spatials_buffer = sg.makeBuffer(.{
    	.usage = .{ .storage_buffer = true, .dynamic_update = true },
     	.size = @sizeOf(shd.ShapeSpatial) * MAX_SHAPES,
      	.label = "Shape vertices"
    });

    const transforms_buffer = sg.makeBuffer(.{
    	.usage = .{ .storage_buffer = true, .dynamic_update = true },
     	.size = @sizeOf(shd.Transform) * MAX_TRANSFORMS,
      	.label = "Transforms"
    });

    const shapes_buffer = sg.makeBuffer(.{
    	.usage = .{ .storage_buffer = true, .dynamic_update = true },
     	.size = @sizeOf(shd.Shape) * MAX_SHAPES,
      	.label = "Shapes"
    });

    const paints_buffer = sg.makeBuffer(.{
    	.usage = .{ .storage_buffer = true, .dynamic_update = true },
     	.size = @sizeOf(shd.Paint) * MAX_SHAPES,
      	.label = "Paints"
    });

    const vertices_buffer = sg.makeBuffer(.{
    	.usage = .{ .storage_buffer = true, .dynamic_update = true },
     	.size = @sizeOf(shd.Vertex) * MAX_VERTICES,
      	.label = "Vertices"
    });

    var bindings: sg.Bindings = .{};

    const msdf_atlas = Atlas.init(std.heap.page_allocator, "MSDF", TEXTURE_SIZE);
    bindings.images[shd.shaderImageSlot("msdf_texture").?] = msdf_atlas.image;
    bindings.samplers[shd.shaderSamplerSlot("msdf_sampler").?] = msdf_atlas.sampler;

    const paint_atlas = Atlas.init(std.heap.page_allocator, "Paint", TEXTURE_SIZE);
    bindings.images[shd.shaderImageSlot("paint_texture").?] = paint_atlas.image;
    bindings.samplers[shd.shaderSamplerSlot("paint_sampler").?] = paint_atlas.sampler;

    bindings.storage_buffers[0] = shape_spatials_buffer;
    bindings.storage_buffers[1] = transforms_buffer;
    bindings.storage_buffers[2] = shapes_buffer;
    bindings.storage_buffers[3] = paints_buffer;
    bindings.storage_buffers[4] = vertices_buffer;

    // create a shader and pipeline object
   	const pipeline = sg.makePipeline(.{
       	.label = "Blade",
    	.shader = sg.makeShader(shd.shaderShaderDesc(sg.queryBackend())),
     	.primitive_type = .TRIANGLE_STRIP,
      	.blend_color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        .color_count = 1,
        .colors = .{
        	.{
         		.pixel_format = .BGRA8,
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
         	},
         	.{},
         	.{},
         	.{}
        },
    });

    return Self{
        .shape_spatials = .{},
        .shapes = .{},
        .transforms = .{},
        .paints = .{},
        .vertices = .{},
        .transform_stack = std.ArrayList(math.Mat4).init(std.heap.page_allocator),
        .msdf_atlas = msdf_atlas,
        .paint_atlas = paint_atlas,
        .pipeline = pipeline,
        .bindings = bindings,
    };
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
	if (self.shape_spatials.len > 0) {
        sg.updateBuffer(
        	self.bindings.storage_buffers[0],
         	sg.Range{ .ptr = @ptrCast(&self.shape_spatials.buffer), .size = @intCast(self.shape_spatials.len * @sizeOf(shd.ShapeSpatial)) }
        );
        self.shape_spatials.clear();
    }
    if (self.transforms.len > 0) {
        sg.updateBuffer(
        	self.bindings.storage_buffers[1],
         	sg.Range{ .ptr = @ptrCast(&self.transforms.buffer), .size = @intCast(self.transforms.len * @sizeOf(shd.Transform)) }
        );
        self.transforms.clear();
    }
    if (self.shapes.len > 0) {
        sg.updateBuffer(
        	self.bindings.storage_buffers[2],
         	sg.Range{ .ptr = @ptrCast(&self.shapes.buffer), .size = @intCast(self.shapes.len * @sizeOf(shd.Shape)) }
        );
        self.shapes.clear();
    }
    if (self.paints.len > 0) {
        sg.updateBuffer(
        	self.bindings.storage_buffers[3],
         	sg.Range{ .ptr = @ptrCast(&self.paints.buffer), .size = @intCast(self.paints.len * @sizeOf(shd.Paint)) }
        );
        self.paints.clear();
    }
    if (self.vertices.len > 0) {
    	sg.updateBuffer(
     		self.bindings.storage_buffers[4],
       		sg.Range{.ptr = @ptrCast(&self.vertices.buffer), .size = @intCast(self.vertices.len * @sizeOf(math.Vec2))},
     	);
     	self.vertices.clear();
    }
}

pub fn beginDrawing(self: *Self) void {
	self.last_transform = null;
	self.transform_stack.clearRetainingCapacity();
	self.paints.append(shd.Paint{
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
    self.transforms.append(shd.Transform{
    	.matrix = .{
     		1.0, 0.0, 0.0, 0.0,
       		0.0, 1.0, 0.0, 0.0,
         	0.0, 0.0, 1.0, 0.0,
          	0.0, 0.0, 0.0, 1.0
     	}
    }) catch unreachable;
}

pub fn endDrawing(self: *Self) void {
	const shape_count = self.shapes.len;

	if (self.msdf_atlas.dirty) {
		self.msdf_atlas.upload();
	}
	if (self.paint_atlas.dirty) {
		self.paint_atlas.upload();
	}
	self.uploadData();

	var pass_action = sg.PassAction{};
    pass_action.colors[0] = .{.load_action = .CLEAR, .clear_value = .{.r = 0, .g = 0, .b = 0, .a = 1}};

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
