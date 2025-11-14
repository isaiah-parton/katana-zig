const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const shd = @import("shaders/shader.glsl.zig");
const std = @import("std");
const math = @import("math.zig");
const zstbi = @import("zstbi");
const Context = @import("context.zig");
const Color = @import("color.zig");
const Font = @import("font.zig");
const Shape = @import("shape.zig");
const Text = @import("text.zig");
const RadialGradient = @import("radial_gradient.zig");


const state = struct {
	var frame_count: u32 = 0;
	var fps: u32 = 0;
	var last_second: std.time.Instant = undefined;
    var ctx: Context = undefined;
    var font: Font = undefined;
    var rng = std.Random.DefaultPrng.init(911);
    var image: math.Rect = undefined;
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    var arena: std.heap.ArenaAllocator = .init(gpa.allocator());
    var text: std.ArrayList(u8) = undefined;
    var cursor_pos: math.Vec2 = math.Vec2.new(0, 0);
    var cursor_target_pos: math.Vec2 = math.Vec2.new(0, 0);
    var last_input_time: std.time.Instant = undefined;
};

const Transform = struct {
    matrix: [4][4]f32,

    pub fn unfold(self: *Transform) [16]f32 {
        return @as([16]f32, @bitCast(self.matrix));
    }
};

export fn init() void {
	zstbi.init(std.heap.page_allocator);

	state.last_second = std.time.Instant.now() catch unreachable;
	state.text = std.ArrayList(u8).initCapacity(state.gpa.allocator(), 64) catch unreachable;

    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    state.ctx = .init(state.gpa.allocator());
    state.font = Font.loadFromFiles("src/fonts/Lexend-Medium.png", "src/fonts/Lexend-Medium.json") catch |e| {
    	std.log.err("{any}", .{e});
     	unreachable;
    };
    state.font.rect = state.ctx.msdf_atlas.addImage(state.font.image.data, state.font.image.width, state.font.image.height) catch |e| {
    	std.log.err("{any}", .{e});
     	unreachable;
    };

    state.last_input_time = std.time.Instant.now() catch unreachable;
}

export fn event(p: [*c]const sapp.Event) void {
	const e: *const sapp.Event = @ptrCast(p);
	switch (e.type) {
		.CHAR => {
			var bytes: [4]u8 = undefined;
			const len = std.unicode.utf8Encode(@intCast(e.char_code), bytes[0..4]) catch unreachable;
			state.text.appendSlice(state.gpa.allocator(), bytes[0..len]) catch unreachable;
			state.last_input_time = std.time.Instant.now() catch unreachable;
		},
		.KEY_DOWN => {
			if (e.key_code == .BACKSPACE) {
				_ = state.text.pop();
			} else if (e.key_code == .ENTER) {
				state.text.append(state.gpa.allocator(), '\n') catch unreachable;
			}
		},
		else => {}
	}
}

export fn frame() void {
	const delta_time = @as(f32, @floatCast(sapp.frameDuration()));
	const now = std.time.Instant.now() catch unreachable;
	if (now.since(state.last_second) > std.time.ns_per_s) {
		state.fps = state.frame_count;
		state.frame_count = 0;
		state.last_second = now;
	}
	state.frame_count += 1;

    state.ctx.beginDrawing();

    {
	    var text = Text.init(.new(0, 0), state.arena.allocator());
	    text.write_string(std.fmt.allocPrint(state.arena.allocator(), "FPS: {d}", .{state.fps}) catch unreachable, &state.font, 20) catch unreachable;
	    text.draw(&state.ctx, Color.from_hex(0x00ff1aff));
    }

    {
    	var text = Text.init(.new(0, 32), state.arena.allocator());
     	text.write_string(state.text.items, &state.font, 20) catch unreachable;
	    text.draw(&state.ctx, Color.WHITE);

	    Shape.rect(
				.new(state.cursor_pos.x, state.cursor_pos.y - 4),
				.new(state.cursor_pos.x + 2, state.cursor_pos.y + text.size.y + 4)
			)
			.draw(&state.ctx, Color.from_hex(0x00ff1aff));

		if (text.glyphs.getLastOrNull()) |glyph| {
	    	state.cursor_target_pos = glyph.position;
		}
	    state.cursor_pos = state.cursor_pos.add(state.cursor_target_pos.sub(state.cursor_pos).scale(25 * delta_time));
    }

    const origin = math.Vec2.new(sapp.widthf() / 2, sapp.heightf() / 2);
    {
    	var shape = Shape.path(.{ .origin = origin.add(math.Vec2.new(0, -100)), .allocator = state.arena.allocator() });
     	shape.lineTo(origin.add(math.Vec2.new(-100, 0)));
     	shape.lineTo(origin.add(math.Vec2.new(0, 100)));
     	shape.lineTo(origin.add(math.Vec2.new(100, 0)));
     	shape.close();
      	shape.draw(&state.ctx, Color.WHITE);
    }

    {
    	var shape = Shape.path(.{ .origin = origin.add(math.Vec2.new(0, -110)), .allocator = state.arena.allocator() });
     	shape.lineTo(origin.add(math.Vec2.new(-110, 0)));
     	shape.lineTo(origin.add(math.Vec2.new(0, 110)));
     	shape.lineTo(origin.add(math.Vec2.new(110, 0)));
     	shape.close();
      	shape.outline(1).draw(&state.ctx, Color.WHITE);
    }

    {
   		var text = Text.init(origin, state.arena.allocator());
    	text.write_string("CONNECT", &state.font, 24) catch unreachable;
     	text.translate(.new(0.5, 0.5));
	    text.draw(&state.ctx, Color.BLACK);
    }

    state.ctx.endDrawing();

    _ = state.arena.reset(.retain_capacity);
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .swap_interval = 1,
        .width = 800,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .window_title = "new world order",
        .logger = .{ .func = slog.func },
    });
}
