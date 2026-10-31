const std = @import("std");
const c = std.c;
const search = @import("search.zig");
const os = @import("os.zig");

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
    mutex: os.Mutex,
    path_copy: ?[*:0]u8,
    max_entries: usize,
    thread: ?std.Thread,

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
        self.*.thread = null;
        self.*.mutex = .{};

        return self;
    }

    fn deinit(self: *AsyncScanner) void {
        // スレッドが実行中なら待機
        if (self.thread) |thread| thread.join();

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
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.state == .cancelled;
    }

    fn setState(self: *AsyncScanner, new_state: ScanState) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.state = new_state;
    }

    fn scan(self: *AsyncScanner, path: [*:0]const u8, max_entries: usize) !void {
        // クリア
        self.clear();

        var scratch: os.Scratch = .{};
        try scratch.init();
        defer scratch.deinit();
        var dir = os.Dir.open(std.mem.span(path), &scratch) orelse return error.CannotOpenDir;
        defer dir.close();

        while (dir.next() catch return error.ReadFailed) |entry| {
            // キャンセルチェック
            if (self.isCancelled()) {
                return error.Cancelled;
            }

            // エントリ数制限チェック
            if (max_entries > 0 and self.count >= max_entries) break;

            // ファイル情報を取得（シンボリックリンクは辿らない）
            const info = dir.currentInfo(entry) orelse continue;

            // 容量確保
            try self.ensureCapacity(self.count + 1);

            // 名前をコピー
            const name_len = entry.name.len;
            const name_copy_ptr = c.malloc(name_len + 1) orelse return error.OutOfMemory;
            const name_copy_bytes = @as([*]u8, @ptrCast(@alignCast(name_copy_ptr)));
            const name_copy = name_copy_bytes[0..name_len];
            @memcpy(name_copy, entry.name);
            name_copy_bytes[name_len] = 0;

            // エントリを追加
            self.entries[self.count] = DirEntry{
                .name = name_copy,
                .is_dir = info.kind == .dir,
                .size = info.size,
                .mtime = info.mtime_sec,
                .executable = info.executable,
                .hidden = entry.name[0] == '.',
            };
            self.count += 1;

            // 進捗更新
            self.mutex.lock();
            self.progress = self.count;
            self.mutex.unlock();
        }
    }

    fn scanAsync(self: *AsyncScanner, path: [*:0]const u8, max_entries: usize) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state == .scanning) {
            return error.AlreadyScanning;
        }

        // パスをコピー
        const path_len = std.mem.len(path);
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

        // 前回のスキャンスレッドは完了済みなので回収してから開始
        if (self.thread) |thread| thread.join();
        self.thread = std.Thread.spawn(.{}, scanWorker, .{self}) catch {
            self.thread = null;
            self.state = .failed;
            return error.ThreadCreateFailed;
        };
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
    scanner.mutex.lock();
    defer scanner.mutex.unlock();
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
    scanner.mutex.lock();
    defer scanner.mutex.unlock();

    current.* = scanner.progress;
    total.* = scanner.total_estimate;
}

/// キャンセル
export fn core_async_cancel(handle: u64) void {
    if (handle == 0) return;

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    scanner.mutex.lock();
    defer scanner.mutex.unlock();

    if (scanner.state == .scanning) {
        scanner.state = .cancelled;
    }
}

/// エントリ数を取得
export fn core_async_get_count(handle: u64) usize {
    if (handle == 0) return 0;

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    scanner.mutex.lock();
    defer scanner.mutex.unlock();
    return scanner.count;
}

/// 指定インデックスのエントリ名を取得
export fn core_async_get_name(handle: u64, index: usize, buf: [*]u8, buf_size: usize) usize {
    if (handle == 0) return 0;

    const scanner = @as(*AsyncScanner, @ptrFromInt(handle));
    scanner.mutex.lock();
    defer scanner.mutex.unlock();

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
    scanner.mutex.lock();
    defer scanner.mutex.unlock();

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

// ============================================================
// コンテンツ検索（G mode）: NUL 区切りのリストを長さ付きで受け取る
// ============================================================

/// 検索を開始してハンドルを返す（失敗時は 0）。threads=0 で CPU 数
export fn core_search_create(
    roots: [*]const u8,
    roots_len: usize,
    query: [*]const u8,
    query_len: usize,
    excluded: [*]const u8,
    excluded_len: usize,
    documents: [*]const u8,
    documents_len: usize,
    threads: u32,
    cache_handle: u64,
) u64 {
    const cache: ?*search.Cache = if (cache_handle == 0) null else @ptrFromInt(cache_handle);
    const s = search.Search.create(
        roots[0..roots_len],
        query[0..query_len],
        excluded[0..excluded_len],
        documents[0..documents_len],
        threads,
        cache,
    ) catch return 0;
    return @intFromPtr(s);
}

export fn core_search_state(handle: u64) u8 {
    if (handle == 0) return @intFromEnum(search.State.failed);
    const s: *search.Search = @ptrFromInt(handle);
    return @intFromEnum(s.getState());
}

/// 溜まったレコードを取り出す。返したポインタは次の drain/destroy まで有効
export fn core_search_drain(handle: u64, out_len: *usize) ?[*]const u8 {
    out_len.* = 0;
    if (handle == 0) return null;
    const s: *search.Search = @ptrFromInt(handle);
    const data = s.drain();
    out_len.* = data.len;
    return if (data.len == 0) null else data.ptr;
}

export fn core_search_skipped(handle: u64) u64 {
    if (handle == 0) return 0;
    const s: *search.Search = @ptrFromInt(handle);
    return s.skipped.load(.acquire);
}

export fn core_search_cancel(handle: u64) void {
    if (handle == 0) return;
    const s: *search.Search = @ptrFromInt(handle);
    s.cancel();
}

export fn core_search_destroy(handle: u64) void {
    if (handle == 0) return;
    const s: *search.Search = @ptrFromInt(handle);
    s.destroy();
}

/// 検索間で共有するファイル内容キャッシュ（max_bytes はキャッシュする内容の上限）
export fn core_cache_create(max_bytes: u64) u64 {
    const cache = search.Cache.create(max_bytes) catch return 0;
    return @intFromPtr(cache);
}

export fn core_cache_bytes(handle: u64) u64 {
    if (handle == 0) return 0;
    const cache: *search.Cache = @ptrFromInt(handle);
    return cache.cachedBytes();
}

/// 使用中の検索をすべて destroy してから呼ぶこと
export fn core_cache_destroy(handle: u64) void {
    if (handle == 0) return;
    const cache: *search.Cache = @ptrFromInt(handle);
    cache.destroy();
}
