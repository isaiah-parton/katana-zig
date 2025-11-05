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
    var ctx: Context = undefined;
    var font: Font = undefined;
    var balls: std.ArrayList(Ball) = .init(std.heap.page_allocator);
    var rng = std.Random.DefaultPrng.init(911);
};

const Transform = struct {
    matrix: [4][4]f32,

    pub fn unfold(self: *Transform) [16]f32 {
        return @as([16]f32, @bitCast(self.matrix));
    }
};

export fn init() void {
	zstbi.init(std.heap.page_allocator);

    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    state.ctx = .init();
    state.font = Font.loadFromFiles("src/fonts/Lexend-Medium.png", "src/fonts/Lexend-Medium.json") catch |e| {
    	std.log.err("{any}", .{e});
     	unreachable;
    };
    state.font.rect = state.ctx.addMSDF(state.font.image.data, state.font.image.width, state.font.image.height);

    for (0..100) |_| {
    	state.balls.append(Ball.spawn(
     		.new(state.rng.random().float(f32) * sapp.widthf(), state.rng.random().float(f32) * sapp.heightf()),
       		math.Vec2.new(state.rng.random().float(f32) * 2 - 1, state.rng.random().float(f32) * 2 - 1).scale(100),
     	)) catch unreachable;
    }
}

export fn frame() void {
	const delta_time = @as(f32, @floatCast(sapp.frameDuration()));

    state.ctx.beginDrawing();

    for (state.balls.items, 0..) |*ball, i| {
    	Shape.circle(ball.position, ball.radius).fill(ball.color).draw(&state.ctx);
     	const bounciness = 0.2;
     	const left_overlap = @max(0, ball.radius - ball.position.x);
      	const top_overlap = @max(0, ball.radius - ball.position.y);
       	const right_overlap = @max(0, ball.position.x - (sapp.widthf() - ball.radius));
        const bottom_overlap = @max(0, ball.position.y - (sapp.heightf() - ball.radius));
      	ball.position.x += (left_overlap - right_overlap) * (1.0 + bounciness);
       	ball.position.y += (top_overlap - bottom_overlap) * (1.0 + bounciness);

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
     	ball.position = ball.position.add(velocity.add(ball.force.mul(delta_time)));
      	ball.force = .new(0, 1);
    }

    var offset: f32 = 0;
    var scale: f32 = 12;
    for (0..15) |_| {
    	Text.from_string(&state.font, "Dies ire dies illa", scale, .new(0, offset), Color.WHITE).draw(&state.ctx);
     	offset += scale + 2;
      	scale *= 1.15;
    }

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
        .width = 800,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .window_title = "new world order",
        .logger = .{ .func = slog.func },
    });
}
