const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 動的ライブラリ（Ruby ABI 非依存・Fiddle 経由でロード）
    const lib = b.addLibrary(.{
        .name = "rufio_zig",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(lib);

    // ripgrep との比較用 CLI
    const cli = b.addExecutable(.{
        .name = "rufio_search",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(cli);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/search_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const test_step = b.step("test", "検索エンジンの単体テストを実行");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
