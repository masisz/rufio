const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 動的ライブラリを作成
    const lib = b.addExecutable(.{
        .name = "rufio_zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 共有ライブラリとしてリンク
    lib.linkage = .dynamic;
    lib.linkLibC();

    // RubyのヘッダーとライブラリへのパスをRubyから取得
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Rubyのインクルードパスを取得
    const ruby_include_result = b.run(&.{ "ruby", "-e", "puts RbConfig::CONFIG['rubyhdrdir']" });
    const ruby_include = std.mem.trim(u8, ruby_include_result, " \n\r\t");

    const ruby_arch_include_result = b.run(&.{ "ruby", "-e", "puts RbConfig::CONFIG['rubyarchhdrdir']" });
    const ruby_arch_include = std.mem.trim(u8, ruby_arch_include_result, " \n\r\t");

    const ruby_lib_dir_result = b.run(&.{ "ruby", "-e", "puts RbConfig::CONFIG['libdir']" });
    const ruby_lib_dir = std.mem.trim(u8, ruby_lib_dir_result, " \n\r\t");

    // インクルードパスを追加
    lib.addIncludePath(.{ .cwd_relative = ruby_include });
    lib.addIncludePath(.{ .cwd_relative = ruby_arch_include });

    // ライブラリパスを追加
    lib.addLibraryPath(.{ .cwd_relative = ruby_lib_dir });

    // Rubyライブラリとリンク
    lib.linkSystemLibrary("ruby.3.4");

    b.installArtifact(lib);
}
