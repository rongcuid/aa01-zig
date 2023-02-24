const std = @import("std");
// const vkgen = @import("vulkan-zig/generator/index.zig");

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "aa01-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath("src");
    // Vulkan memory allocator
    exe.addCSourceFile("src/vma.cpp", &[_][]const u8{});
    // Nuklear
    exe.defineCMacro("NK_INCLUDE_DEFAULT_ALLOCATOR", null);
    exe.defineCMacro("NK_INCLUDE_FIXED_TYPES", null);
    exe.defineCMacro("NK_INCLUDE_FONT_BAKING", null);
    exe.defineCMacro("NK_INCLUDE_DEFAULT_FONT", null);
    exe.defineCMacro("NK_INCLUDE_VERTEX_BUFFER_OUTPUT", null);

    exe.addCSourceFile("src/nuklear.c", &[_][]const u8{});
    // Libraries
    exe.linkLibC();
    exe.linkLibCpp();
    exe.linkSystemLibrary("sdl2");
    exe.linkSystemLibrary("sdl2_image");
    exe.linkSystemLibrary("sdl2_mixer");
    exe.linkSystemLibrary("sdl2_ttf");
    exe.linkSystemLibrary("vulkan");
    exe.linkSystemLibrary("shaderc");

    exe.install();

    // // Create a step that generates vk.zig (stored in zig-cache) from the provided vulkan registry.
    // const gen = vkgen.VkGenerateStep.create(b, "vk.xml", "vk.zig");
    // // Add the generated file as package to the final executable
    // exe.addPackage(gen.getPackage("vkz"));

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
