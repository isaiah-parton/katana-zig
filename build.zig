const std = @import("std");
pub const shdc = @import("shdc");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shader_step = try shdc.createSourceFile(b, .{
        .shdc_dep = b.dependency("shdc", .{}),
        .input = "src/shaders/shader.glsl",
        .output = "src/shaders/shader.glsl.zig",
        .slang = .{
            .glsl430 = false,
            .glsl410 = true,
            .glsl310es = false,
            .glsl300es = false,
            .metal_macos = true,
            .hlsl5 = true,
            .wgsl = true,
        },
        .reflection = true,
    });

    const dep_zmath = b.dependency("zmath", .{
    	.target = target,
     	.optimize = optimize,
    });

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const dep_zstdbi = b.dependency("zstbi", .{});

    const imports: []const std.Build.Module.Import = &.{
	    .{
	        .name = "sokol",
	        .module = dep_sokol.module("sokol"),
	    },
	    .{
	    	.name = "zmath",
	     	.module = dep_zmath.module("root"),
	    },
		.{
			.name = "zstbi",
			.module = dep_zstdbi.module("root"),
		}
    };

    const lib_mod = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize, .imports = imports});

    const exe_mod = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize, .imports = imports });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "katana_zig",
        .root_module = lib_mod,
    });

    lib.step.dependOn(shader_step);

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "katana_zig",
        .root_module = exe_mod,
    });

    exe.step.dependOn(shader_step);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
