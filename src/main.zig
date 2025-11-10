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

const Ball = struct {
	position: math.Vec2,
	last_position: math.Vec2,
	force: math.Vec2,
	radius: f32,
	color: Color,

	pub fn spawn(position: math.Vec2, force: math.Vec2) Ball {
		return Ball{
			.position = position,
			.last_position = position,
			.force = force,
			.radius = 10 + state.rng.random().float(f32) * 20,
			.color = Color.BLUE,
		};
	}
};

const state = struct {
	var frame_count: u32 = 0;
	var fps: u32 = 0;
	var last_second: std.time.Instant = undefined;
    var ctx: Context = undefined;
    var font: Font = undefined;
    var balls: std.ArrayList(Ball) = .{};
    var rng = std.Random.DefaultPrng.init(911);
    var image: math.Rect = undefined;
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    var arena: std.heap.ArenaAllocator = .init(gpa.allocator());
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

    state.image = state.ctx.loadUserImage("src/images/pexels-pixabay-315191.jpg") catch |e| {
    	std.log.err("{any}", .{e});
     	unreachable;
    };

    for (0..100) |_| {
    	state.balls.append(state.gpa.allocator(), Ball.spawn(
     		.new(state.rng.random().float(f32) * sapp.widthf(), state.rng.random().float(f32) * sapp.heightf()),
       		math.Vec2.new(state.rng.random().float(f32) * 2 - 1, state.rng.random().float(f32) * 2 - 1).scale(100),
     	)) catch unreachable;
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

    for (state.balls.items, 0..) |*ball, i| {
    	Shape.circle(ball.position, ball.radius)
       		.draw(&state.ctx, RadialGradient{.center = ball.position.add(math.Vec2.new(5, -5)), .radius = ball.radius, .inner_color = Color.LIGHT_BLUE, .outer_color = Color.BLUE});

     	const boundary_bounciness = 0.2;

     	const left_overlap = @max(0, ball.radius - ball.position.x);
      	const top_overlap = @max(0, ball.radius - ball.position.y);
       	const right_overlap = @max(0, ball.position.x - (sapp.widthf() - ball.radius));
        const bottom_overlap = @max(0, ball.position.y - (sapp.heightf() - ball.radius));

        const friction = math.Vec2.new(
        	1 + @min(1, top_overlap + bottom_overlap) * 0.01,
        	1 + @min(1, left_overlap + right_overlap) * 0.01
        );

      	ball.position.x += (left_overlap - right_overlap) * (1.0 + boundary_bounciness);
      	ball.position.y += (top_overlap - bottom_overlap) * (1.0 + boundary_bounciness);

        for (state.balls.items, 0..) |*other, j| {
        	if (i == j) continue;

        	const distance = ball.position.sub(other.position).length();
        	const overlap = ball.radius + other.radius - distance;

        	if (overlap > 0) {
        		const direction = ball.position.sub(other.position).normalize();
        		ball.position = ball.position.add(direction.mul(overlap / 2));
        		other.position = other.position.sub(direction.mul(overlap / 2));
        	}
        }

        const velocity = ball.position.sub(ball.last_position);

        ball.last_position = ball.position;
     	ball.position = ball.position.add(velocity.add(ball.force.mul(delta_time)).div(friction));
      	ball.force = .new(0, 4);
    }

    Text.from_string(&state.font, std.fmt.allocPrint(state.arena.allocator(), "FPS: {d}", .{state.fps}) catch unreachable, 20, .new(0, 0)).draw(&state.ctx, Color.from_hex(0x00ff1aff));

    state.ctx.endDrawing();
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .swap_interval = 1,
        .width = 800,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .window_title = "new world order",
        .logger = .{ .func = slog.func },
    });
}
