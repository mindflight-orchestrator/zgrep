const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translated = b.addTranslateC(.{
        .root_source_file = b.path("include/zgrep_pcre2.h"),
        .target = target,
        .optimize = optimize,
    });
    translated.addIncludePath(b.path("include"));
    const pcre2 = translated.createModule();

    const core = b.addModule("zgrep", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "pcre2", .module = pcre2 }},
        .link_libc = true,
    });
    core.addIncludePath(b.path("include"));
    core.addCSourceFile(.{
        .file = b.path("src/pcre2_shim.c"),
        .flags = &.{ "-std=c11", "-O3" },
    });
    core.linkSystemLibrary("pcre2-8", .{});

    const zgrep = addExecutable(b, "zgrep", core, target, optimize);
    const zegrep = addExecutable(b, "zegrep", core, target, optimize);
    b.installArtifact(zgrep);
    b.installArtifact(zegrep);

    const run_step = b.step("run", "Run zgrep");
    const run_cmd = b.addRunArtifact(zgrep);
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{ .root_module = core });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const cli_tests = b.addSystemCommand(&.{ "bash", "tests/differential.sh" });
    cli_tests.addArtifactArg(zgrep);
    cli_tests.addArtifactArg(zegrep);
    test_step.dependOn(&cli_tests.step);

    const regex_tests = b.addSystemCommand(&.{ "bash", "tests/regex-semantics.sh" });
    regex_tests.addArtifactArg(zgrep);
    test_step.dependOn(&regex_tests.step);

    const fuzz_step = b.step("test-fuzz", "Run deterministic BRE/ERE differential fuzz tests");
    const fuzz_tests = b.addSystemCommand(&.{ "bash", "tests/regex-fuzz.sh" });
    fuzz_tests.addArtifactArg(zgrep);
    fuzz_step.dependOn(&fuzz_tests.step);

    const stress_step = b.step("test-stress", "Run large-file differential stress tests");
    const stress_tests = b.addSystemCommand(&.{ "bash", "tests/stress.sh" });
    stress_tests.addArtifactArg(zgrep);
    stress_step.dependOn(&stress_tests.step);
}

fn addExecutable(
    b: *std.Build,
    name: []const u8,
    core: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = optimize != .Debug,
            .imports = &.{.{ .name = "zgrep", .module = core }},
        }),
    });
}
