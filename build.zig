const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gnu = translateGnu(b, target, optimize);
    const pcre2_c = translatePcre2(b, target, optimize);

    const core = addCore(b, target, optimize, pcre2_c, gnu, .c);
    const zgr = addExecutable(b, "zgr", core, target, optimize);
    b.installArtifact(zgr);

    const run_step = b.step("run", "Run zgr");
    const run_cmd = b.addRunArtifact(zgr);
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{ .root_module = core });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const cli_tests = b.addSystemCommand(&.{ "bash", "tests/differential.sh" });
    cli_tests.addArtifactArg(zgr);
    test_step.dependOn(&cli_tests.step);

    const regex_tests = b.addSystemCommand(&.{ "bash", "tests/regex-semantics.sh" });
    regex_tests.addArtifactArg(zgr);
    test_step.dependOn(&regex_tests.step);

    const locale_tests = b.addSystemCommand(&.{ "bash", "tests/locale-semantics.sh" });
    locale_tests.addArtifactArg(zgr);
    test_step.dependOn(&locale_tests.step);

    const fuzz_step = b.step("test-fuzz", "Run deterministic BRE/ERE differential fuzz tests");
    const fuzz_tests = b.addSystemCommand(&.{ "bash", "tests/regex-fuzz.sh" });
    fuzz_tests.addArtifactArg(zgr);
    fuzz_step.dependOn(&fuzz_tests.step);

    const stress_step = b.step("test-stress", "Run large-file differential stress tests");
    const stress_tests = b.addSystemCommand(&.{ "bash", "tests/stress.sh" });
    stress_tests.addArtifactArg(zgr);
    stress_step.dependOn(&stress_tests.step);

    const zpcre2 = b.dependency("zpcre2", .{
        .target = target,
        .optimize = optimize,
    }).module("zpcre2");
    const engine = b.createModule(.{
        .root_source_file = b.path("src/engine_zpcre2.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zpcre2", .module = zpcre2 },
            .{ .name = "gnu", .module = gnu },
        },
        .link_libc = true,
    });
    const core_zpcre2 = addCore(b, target, optimize, engine, gnu, .zpcre2);
    const zgr_zpcre2 = addExecutable(b, "zgr-zpcre2", core_zpcre2, target, optimize);
    b.installArtifact(zgr_zpcre2);

    const zpcre2_tests = b.addTest(.{ .root_module = core_zpcre2 });
    const run_zpcre2_tests = b.addRunArtifact(zpcre2_tests);
    const test_zpcre2 = b.step("test-zpcre2", "Run unit tests with the zpcre2 engine");
    test_zpcre2.dependOn(&run_zpcre2_tests.step);

    const test_zpcre2_gnu = b.step(
        "test-zpcre2-gnu",
        "Run GNU differential tests with zgr-zpcre2 (experimental)",
    );
    test_zpcre2_gnu.dependOn(&run_zpcre2_tests.step);

    const zpcre2_cli = b.addSystemCommand(&.{ "bash", "tests/differential.sh" });
    zpcre2_cli.addArtifactArg(zgr_zpcre2);
    test_zpcre2_gnu.dependOn(&zpcre2_cli.step);

    const zpcre2_regex = b.addSystemCommand(&.{ "bash", "tests/regex-semantics.sh" });
    zpcre2_regex.addArtifactArg(zgr_zpcre2);
    test_zpcre2_gnu.dependOn(&zpcre2_regex.step);

    const zpcre2_locale = b.addSystemCommand(&.{ "bash", "tests/locale-semantics.sh" });
    zpcre2_locale.addArtifactArg(zgr_zpcre2);
    test_zpcre2_gnu.dependOn(&zpcre2_locale.step);
}

const RegexBackend = enum { c, zpcre2 };

fn addCore(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pcre2: *std.Build.Module,
    gnu: *std.Build.Module,
    backend: RegexBackend,
) *std.Build.Module {
    _ = gnu;
    const core = if (backend == .c)
        b.addModule("zgrep", .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "pcre2", .module = pcre2 }},
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "pcre2", .module = pcre2 }},
            .link_libc = true,
        });
    core.addIncludePath(b.path("include"));
    core.addCSourceFile(.{
        .file = b.path("src/gnu_regex.c"),
        .flags = &.{ "-std=c11", "-O3" },
    });
    if (backend == .c) {
        core.addCSourceFile(.{
            .file = b.path("src/pcre2_shim.c"),
            .flags = &.{ "-std=c11", "-O3" },
        });
        core.linkSystemLibrary("pcre2-8", .{});
    }
    return core;
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

fn translateGnu(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const translated = b.addTranslateC(.{
        .root_source_file = b.path("include/zgrep_gnu.h"),
        .target = target,
        .optimize = optimize,
    });
    translated.addIncludePath(b.path("include"));
    return translated.createModule();
}

fn translatePcre2(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const translated = b.addTranslateC(.{
        .root_source_file = b.path("include/zgrep_pcre2.h"),
        .target = target,
        .optimize = optimize,
    });
    translated.addIncludePath(b.path("include"));
    return translated.createModule();
}
