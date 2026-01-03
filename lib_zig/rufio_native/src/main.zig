const std = @import("std");
const c = @cImport({
    @cInclude("ruby.h");
    @cInclude("dirent.h");
    @cInclude("sys/stat.h");
    @cInclude("string.h");
    @cInclude("time.h");
});

/// ディレクトリエントリ情報
const DirEntry = struct {
    name: []const u8,
    is_dir: bool,
    size: u64,
    mtime: i64,
    executable: bool,
    hidden: bool,
};

/// ディレクトリをスキャンしてRuby配列を返す
fn scanDirectory(self: c.VALUE, path_value: c.VALUE) callconv(.c) c.VALUE {
    _ = self;

    // パス文字列を取得
    var mutable_path = path_value;
    const path_str = c.rb_string_value_cstr(@ptrCast(&mutable_path));
    const path_len = c.strlen(path_str);
    const path = path_str[0..path_len];

    // ディレクトリを開く
    const dir = c.opendir(path_str) orelse {
        c.rb_raise(c.rb_eRuntimeError, "Failed to open directory");
        return c.Qnil;
    };
    defer _ = c.closedir(dir);

    // Ruby配列を作成
    const ary = c.rb_ary_new();

    // ディレクトリエントリを読み取り
    while (c.readdir(dir)) |entry| {
        const name_ptr = @as([*:0]const u8, @ptrCast(&entry.*.d_name));
        const name_len = c.strlen(name_ptr);
        const name = name_ptr[0..name_len];

        // "." と ".." をスキップ
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) {
            continue;
        }

        // フルパスを構築
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrintZ(&path_buf, "{s}/{s}", .{ path, name }) catch {
            continue;
        };

        // ファイル情報を取得
        var stat_buf: c.struct_stat = undefined;
        if (c.lstat(full_path.ptr, &stat_buf) != 0) {
            continue;
        }

        // ディレクトリかどうか
        const is_dir = (stat_buf.st_mode & c.S_IFMT) == c.S_IFDIR;

        // 実行可能かどうか
        const executable = (stat_buf.st_mode & c.S_IXUSR) != 0;

        // 隠しファイルかどうか
        const hidden = name[0] == '.';

        // Rubyハッシュを作成
        const hash = c.rb_hash_new();

        // ハッシュにキーと値を設定
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("name")), c.rb_str_new(name.ptr, @intCast(name.len)));
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("is_dir")), if (is_dir) c.Qtrue else c.Qfalse);
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("size")), c.ULL2NUM(@as(c_ulonglong, @intCast(stat_buf.st_size))));
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("mtime")), c.LL2NUM(@as(c_longlong, @intCast(stat_buf.st_mtimespec.tv_sec))));
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("executable")), if (executable) c.Qtrue else c.Qfalse);
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("hidden")), if (hidden) c.Qtrue else c.Qfalse);

        // 配列に追加
        _ = c.rb_ary_push(ary, hash);
    }

    return ary;
}

/// 高速スキャン（エントリ数制限付き）
fn scanDirectoryFast(self: c.VALUE, path_value: c.VALUE, max_entries_value: c.VALUE) callconv(.c) c.VALUE {
    _ = self;

    const max_entries = @as(usize, @intCast(c.NUM2INT(max_entries_value)));
    var mutable_path = path_value;
    const path_str = c.rb_string_value_cstr(@ptrCast(&mutable_path));
    const path_len = c.strlen(path_str);
    const path = path_str[0..path_len];

    const dir = c.opendir(path_str) orelse {
        c.rb_raise(c.rb_eRuntimeError, "Failed to open directory");
        return c.Qnil;
    };
    defer _ = c.closedir(dir);

    const ary = c.rb_ary_new();
    var count: usize = 0;

    while (c.readdir(dir)) |entry| {
        if (count >= max_entries) break;

        const name_ptr = @as([*:0]const u8, @ptrCast(&entry.*.d_name));
        const name_len = c.strlen(name_ptr);
        const name = name_ptr[0..name_len];

        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) {
            continue;
        }

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrintZ(&path_buf, "{s}/{s}", .{ path, name }) catch {
            continue;
        };

        var stat_buf: c.struct_stat = undefined;
        if (c.lstat(full_path.ptr, &stat_buf) != 0) {
            continue;
        }

        const is_dir = (stat_buf.st_mode & c.S_IFMT) == c.S_IFDIR;
        const executable = (stat_buf.st_mode & c.S_IXUSR) != 0;
        const hidden = name[0] == '.';

        const hash = c.rb_hash_new();
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("name")), c.rb_str_new(name.ptr, @intCast(name.len)));
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("is_dir")), if (is_dir) c.Qtrue else c.Qfalse);
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("size")), c.ULL2NUM(@as(c_ulonglong, @intCast(stat_buf.st_size))));
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("mtime")), c.LL2NUM(@as(c_longlong, @intCast(stat_buf.st_mtimespec.tv_sec))));
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("executable")), if (executable) c.Qtrue else c.Qfalse);
        _ = c.rb_hash_aset(hash, c.ID2SYM(c.rb_intern("hidden")), if (hidden) c.Qtrue else c.Qfalse);

        _ = c.rb_ary_push(ary, hash);
        count += 1;
    }

    return ary;
}

/// バージョン情報
fn getVersion(_: c.VALUE) callconv(.c) c.VALUE {
    const version = "1.0.0-zig";
    return c.rb_str_new(version.ptr, @intCast(version.len));
}

/// Ruby拡張の初期化
export fn Init_rufio_zig() void {
    // Rufioモジュールを取得または作成
    const rufio_module = c.rb_define_module("Rufio");

    // NativeScannerZigクラスを定義
    const scanner_class = c.rb_define_class_under(rufio_module, "NativeScannerZig", c.rb_cObject);

    // クラスメソッドを定義
    c.rb_define_singleton_method(scanner_class, "scan_directory", @ptrCast(&scanDirectory), 1);
    c.rb_define_singleton_method(scanner_class, "scan_directory_fast", @ptrCast(&scanDirectoryFast), 2);
    c.rb_define_singleton_method(scanner_class, "version", @ptrCast(&getVersion), 0);
}
