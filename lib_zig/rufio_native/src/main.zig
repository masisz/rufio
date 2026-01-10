const std = @import("std");
const c = @cImport({
    @cInclude("dirent.h");
    @cInclude("sys/stat.h");
    @cInclude("string.h");
    @cInclude("stdlib.h");
    @cInclude("pthread.h");
});

/// スキャン状態
pub const ScanState = enum(u8) {
    idle = 0,
    scanning = 1,
    done = 2,
    cancelled = 3,
    failed = 4,
};

/// ディレクトリエントリ情報（内部保持用）
const DirEntry = struct {
    name: []u8,
    is_dir: bool,
    size: u64,
    mtime: i64,
    executable: bool,
    hidden: bool,

    fn deinit(self: *DirEntry) void {
        c.free(self.name.ptr);
    }
};

/// 非同期スキャナーコア（状態を保持）
const AsyncScanner = struct {
    entries: []DirEntry,
    capacity: usize,
    count: usize,
    state: ScanState,
    progress: usize,
    total_estimate: usize,
    mutex: c.pthread_mutex_t,
    path_copy: ?[*:0]u8,
    max_entries: usize,
    thread: c.pthread_t,
    thread_started: bool,

    fn init() !*AsyncScanner {
        const self = @as(?*AsyncScanner, @ptrCast(@alignCast(c.malloc(@sizeOf(AsyncScanner))))) orelse return error.OutOfMemory;

        self.*.capacity = 64;
        const entries_size = self.*.capacity * @sizeOf(DirEntry);
        const entries_ptr = c.malloc(entries_size) orelse {
            c.free(self);
            return error.OutOfMemory;
        };
        self.*.entries = @as([*]DirEntry, @ptrCast(@alignCast(entries_ptr)))[0..self.*.capacity];
        self.*.count = 0;
        self.*.state = .idle;
        self.*.progress = 0;
        self.*.total_estimate = 0;
        self.*.path_copy = null;
        self.*.max_entries = 0;
        self.*.thread_started = false;

        // mutex初期化
        _ = c.pthread_mutex_init(&self.*.mutex, null);

        return self;
    }

    fn deinit(self: *AsyncScanner) void {
        // スレッドが実行中なら待機
        if (self.thread_started) {
            _ = c.pthread_join(self.thread, null);
        }

        // 各エントリの名前を解放
        for (self.entries[0..self.count]) |*entry| {
            entry.deinit();
        }

        // パスのコピーを解放
        if (self.path_copy) |path| {
            c.free(path);
        }

        // エントリ配列を解放
        c.free(self.entries.ptr);

        // mutex破棄
        _ = c.pthread_mutex_destroy(&self.mutex);

        // 自身を解放
        c.free(self);
    }

    fn clear(self: *AsyncScanner) void {
        // 既存のエントリをクリア
        for (self.entries[0..self.count]) |*entry| {
            entry.deinit();
        }
        self.count = 0;
        self.progress = 0;
        self.total_estimate = 0;
    }

    fn ensureCapacity(self: *AsyncScanner, needed: usize) !void {
        if (needed <= self.capacity) return;

        const new_capacity = @max(needed, self.capacity * 2);
        const new_size = new_capacity * @sizeOf(DirEntry);
        const new_ptr = c.realloc(self.entries.ptr, new_size) orelse return error.OutOfMemory;
        self.entries = @as([*]DirEntry, @ptrCast(@alignCast(new_ptr)))[0..new_capacity];
        self.capacity = new_capacity;
    }

    fn isCancelled(self: *AsyncScanner) bool {
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        return self.state == .cancelled;
    }

    fn setState(self: *AsyncScanner, new_state: ScanState) void {
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        self.state = new_state;
    }

    fn scan(self: *AsyncScanner, path: [*:0]const u8, max_entries: usize) !void {
        // クリア
        self.clear();

        const dir = c.opendir(path) orelse return error.CannotOpenDir;
        defer _ = c.closedir(dir);

        const path_len = c.strlen(path);
        const path_slice = path[0..path_len];

        while (c.readdir(dir)) |entry| {
            // キャンセルチェック
            if (self.isCancelled()) {
                return error.Cancelled;
            }

            // エントリ数制限チェック
            if (max_entries > 0 and self.count >= max_entries) break;

            const name_ptr = @as([*:0]const u8, @ptrCast(&entry.*.d_name));
            const name_len = c.strlen(name_ptr);
            const name_slice = name_ptr[0..name_len];

            // "." と ".." をスキップ
            if (std.mem.eql(u8, name_slice, ".") or std.mem.eql(u8, name_slice, "..")) {
                continue;
            }

            // 容量確保
            try self.ensureCapacity(self.count + 1);

            // フルパスを構築
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const full_path = std.fmt.bufPrintZ(&path_buf, "{s}/{s}", .{ path_slice, name_slice }) catch continue;

            // ファイル情報を取得
            var stat_buf: c.struct_stat = undefined;
            if (c.lstat(full_path.ptr, &stat_buf) != 0) {
                continue;
            }

            // 名前をコピー
            const name_copy_ptr = c.malloc(name_len + 1) orelse return error.OutOfMemory;
            const name_copy_bytes = @as([*]u8, @ptrCast(@alignCast(name_copy_ptr)));
            const name_copy = name_copy_bytes[0..name_len];
            @memcpy(name_copy, name_slice);
            name_copy_bytes[name_len] = 0;

            // エントリを追加
            self.entries[self.count] = DirEntry{
                .name = name_copy,
                .is_dir = (stat_buf.st_mode & c.S_IFMT) == c.S_IFDIR,
                .size = @intCast(stat_buf.st_size),
                .mtime = @intCast(stat_buf.st_mtimespec.tv_sec),
                .executable = (stat_buf.st_mode & c.S_IXUSR) != 0,
                .hidden = name_slice[0] == '.',
            };
            self.count += 1;

            // 進捗更新
            _ = c.pthread_mutex_lock(&self.mutex);
            self.progress = self.count;
            _ = c.pthread_mutex_unlock(&self.mutex);
        }
    }

    fn scanAsync(self: *AsyncScanner, path: [*:0]const u8, max_entries: usize) !void {
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);

        if (self.state == .scanning) {
            return error.AlreadyScanning;
        }

        // パスをコピー
        const path_len = c.strlen(path);
        const path_copy_ptr = c.malloc(path_len + 1) orelse return error.OutOfMemory;
        const path_copy_bytes = @as([*:0]u8, @ptrCast(@alignCast(path_copy_ptr)));
        @memcpy(path_copy_bytes[0..path_len], path[0..path_len]);
        path_copy_bytes[path_len] = 0;

        // 古いパスを解放
        if (self.path_copy) |old_path| {
            c.free(old_path);
        }

        self.path_copy = path_copy_bytes;
        self.max_entries = max_entries;
        self.state = .scanning;

        // スレッド開始
        const result = c.pthread_create(&self.thread, null, scanWorkerEntry, self);
        if (result != 0) {
            self.state = .failed;
            return error.ThreadCreateFailed;
        }
        self.thread_started = true;
    }

    fn scanWorker(self: *AsyncScanner) void {
        const path = self.path_copy orelse {
            self.setState(.failed);
            return;
        };

        self.scan(path, self.max_entries) catch |err| {
            // キャンセルエラーの場合は状態を変更しない（既にcancelledになっている）
            if (err == error.Cancelled) {
                return;
            }
            self.setState(.failed);
            return;
        };

        self.setState(.done);
    }
};

// スレッドエントリポイント
fn scanWorkerEntry(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const scanner = @as(*AsyncScanner, @ptrCast(@alignCast(arg)));
    scanner.scanWorker();
    return null;
}

// ============================================================
// ABI Boundary: Ruby ABI非依存・ハンドルベース
// ============================================================

/// 非同期スキャナーを作成（ハンドル返却）
export fn core_async_create() u64 {
    const scanner = AsyncScanner.init() catch return 0;
    return @intFromPtr(scanner);
}

/// 非同期スキャン開始
export fn core_async_scan(handle: u64, path: [*:0]const u8) i32 {
    if (handle == 0) return -1;

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    scanner.scanAsync(path, 0) catch return -1;
    return 0;
}

/// 高速スキャン（エントリ数制限付き）
export fn core_async_scan_fast(handle: u64, path: [*:0]const u8, max_entries: usize) i32 {
    if (handle == 0) return -1;

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    scanner.scanAsync(path, max_entries) catch return -1;
    return 0;
}

/// 状態取得
export fn core_async_get_state(handle: u64) u8 {
    if (handle == 0) return @intFromEnum(ScanState.failed);

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    _ = c.pthread_mutex_lock(&scanner.mutex);
    defer _ = c.pthread_mutex_unlock(&scanner.mutex);
    return @intFromEnum(scanner.state);
}

/// 進捗取得
export fn core_async_get_progress(handle: u64, current: *usize, total: *usize) void {
    if (handle == 0) {
        current.* = 0;
        total.* = 0;
        return;
    }

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    _ = c.pthread_mutex_lock(&scanner.mutex);
    defer _ = c.pthread_mutex_unlock(&scanner.mutex);

    current.* = scanner.progress;
    total.* = scanner.total_estimate;
}

/// キャンセル
export fn core_async_cancel(handle: u64) void {
    if (handle == 0) return;

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    _ = c.pthread_mutex_lock(&scanner.mutex);
    defer _ = c.pthread_mutex_unlock(&scanner.mutex);

    if (scanner.state == .scanning) {
        scanner.state = .cancelled;
    }
}

/// エントリ数を取得
export fn core_async_get_count(handle: u64) usize {
    if (handle == 0) return 0;

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    _ = c.pthread_mutex_lock(&scanner.mutex);
    defer _ = c.pthread_mutex_unlock(&scanner.mutex);
    return scanner.count;
}

/// 指定インデックスのエントリ名を取得
export fn core_async_get_name(handle: u64, index: usize, buf: [*]u8, buf_size: usize) usize {
    if (handle == 0) return 0;

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    _ = c.pthread_mutex_lock(&scanner.mutex);
    defer _ = c.pthread_mutex_unlock(&scanner.mutex);

    if (index >= scanner.count) return 0;

    const entry = &scanner.entries[index];
    const copy_len = @min(entry.name.len, buf_size - 1);
    @memcpy(buf[0..copy_len], entry.name[0..copy_len]);
    buf[copy_len] = 0;
    return copy_len;
}

/// 指定インデックスのエントリ属性を取得
export fn core_async_get_attrs(handle: u64, index: usize, is_dir: *u8, size: *u64, mtime: *i64, executable: *u8, hidden: *u8) i32 {
    if (handle == 0) return -1;

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    _ = c.pthread_mutex_lock(&scanner.mutex);
    defer _ = c.pthread_mutex_unlock(&scanner.mutex);

    if (index >= scanner.count) return -1;

    const entry = &scanner.entries[index];
    is_dir.* = if (entry.is_dir) 1 else 0;
    size.* = entry.size;
    mtime.* = entry.mtime;
    executable.* = if (entry.executable) 1 else 0;
    hidden.* = if (entry.hidden) 1 else 0;
    return 0;
}

/// スキャナーを破棄
export fn core_async_destroy(handle: u64) void {
    if (handle == 0) return;

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    scanner.deinit();
}

/// バージョン情報
export fn core_async_version() [*:0]const u8 {
    return "4.0.0-async";
}
