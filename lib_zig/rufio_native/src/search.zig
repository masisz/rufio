//! G mode のコンテンツ検索エンジン。
//!
//! Ruby 実装（GlobalSearch#scan_roots / #scan_content）と同じ結果を返しつつ、
//! 次の手法で ripgrep 以上の速度を狙う:
//! - 全 CPU コアでディレクトリを並列走査（ワークスタックで負荷分散）
//! - getdirentries64 による大きなバッファでの一括ディレクトリ読み込み（macOS）
//! - openat/fstatat で親ディレクトリ fd から相対オープン（パス解決を省略）
//! - 希少バイト 2 点を SIMD で同時比較する大文字小文字無視リテラル検索
//! - 行番号はマッチ発生時のみ SIMD で改行を数える（非マッチファイルは数えない）
//! - スレッドローカル出力バッファでロック回数を削減し、上限超過時は背圧で待機
const std = @import("std");
const c = std.c;
const os = @import("os.zig");

pub const FileMeta = os.FileMeta;

pub const MAX_NEEDLE = 1024;
pub const MAX_THREADS = 64;

const VLEN = 32;
const Vec = @Vector(VLEN, u8);

/// Ruby 実装と同じく先頭 8KB に NUL があればバイナリとみなす
const BINARY_SAMPLE = 8192;
const READ_BUFFER = 256 * 1024;
/// サイズ不明時の初回読み込み量（多くのソースファイルが 1 回で収まる）
const FIRST_READ = 16 * 1024;
const LOCAL_FLUSH = 64 * 1024;
/// Ruby 側が取り出していない出力がこれを超えたらワーカーは待機する
const MAX_PENDING = 8 * 1024 * 1024;

/// スニペット用に返すマッチ前後のバイト幅（Ruby 側で 30 文字前 + 200 文字に切り出す）
const SNIPPET_BEFORE = 30 * 4;
const SNIPPET_WINDOW = 1024;

pub const RECORD_HEADER = 25;

pub const Kind = enum(u8) {
    match = 1,
    document = 2,
    err = 3,
};

pub const State = enum(u8) {
    idle = 0,
    scanning = 1,
    done = 2,
    cancelled = 3,
    failed = 4,
};

inline fn fold(b: u8) u8 {
    return if (b >= 'A' and b <= 'Z') b | 0x20 else b;
}

/// 一般的なソースコード/テキストでの出現頻度の目安（大きいほど頻出）
fn byteRank(b: u8) u8 {
    const letters = "etaoinsrhldcumfpgwybvkxjqz";
    if (b >= 'a' and b <= 'z') {
        const idx = std.mem.indexOfScalar(u8, letters, b).?;
        return @intCast(230 - idx * 6);
    }
    return switch (b) {
        ' ' => 255,
        '\t', '\n' => 200,
        '0'...'9' => 130,
        '_', '(', ')', ',', '.', ';', '=', '"', '\'', '/', '-', '*', ':' => 140,
        0xE3 => 150, // ひらがな・カタカナの UTF-8 先頭バイト
        0x80...0xBF => 120, // UTF-8 継続バイト
        else => 60,
    };
}

/// 大文字小文字を無視するリテラル検索（ASCII のみ畳み込み、それ以外は完全一致）
pub const Matcher = struct {
    needle: [MAX_NEEDLE]u8,
    len: usize,
    i1: usize,
    i2: usize,
    m1: Vec,
    t1: Vec,
    m2: Vec,
    t2: Vec,

    pub fn init(needle: []const u8) Matcher {
        var self: Matcher = undefined;
        self.len = @min(needle.len, MAX_NEEDLE);
        for (needle[0..self.len], 0..) |b, i| self.needle[i] = fold(b);

        // 最も希少な 2 バイトを候補判定に使う
        var best: usize = 0;
        var i: usize = 1;
        while (i < self.len) : (i += 1) {
            if (byteRank(self.needle[i]) < byteRank(self.needle[best])) best = i;
        }
        var second: usize = best;
        i = 0;
        while (i < self.len) : (i += 1) {
            if (i == best) continue;
            if (second == best or byteRank(self.needle[i]) < byteRank(self.needle[second])) second = i;
        }
        self.i1 = best;
        self.i2 = second;

        const b1 = if (self.len > 0) self.needle[best] else 0;
        const b2 = if (self.len > 0) self.needle[second] else 0;
        self.m1 = @splat(foldMask(b1));
        self.t1 = @splat(b1);
        self.m2 = @splat(foldMask(b2));
        self.t2 = @splat(b2);
        return self;
    }

    fn foldMask(b: u8) u8 {
        return if (b >= 'a' and b <= 'z') 0x20 else 0;
    }

    inline fn verify(self: *const Matcher, at: []const u8) bool {
        for (self.needle[0..self.len], at[0..self.len]) |n, h| {
            if (fold(h) != n) return false;
        }
        return true;
    }

    pub fn find(self: *const Matcher, hay: []const u8) ?usize {
        const n = self.len;
        if (n == 0) return 0;
        if (hay.len < n) return null;
        const last = hay.len - n;
        const hi = @max(self.i1, self.i2);
        const zero: Vec = @splat(0);

        var p: usize = 0;
        if (hay.len >= hi + 2 * VLEN) {
            const end = hay.len - hi - 2 * VLEN;
            while (p <= end) : (p += 2 * VLEN) {
                const a0: Vec = hay[p + self.i1 ..][0..VLEN].*;
                const b0: Vec = hay[p + self.i2 ..][0..VLEN].*;
                const a1: Vec = hay[p + VLEN + self.i1 ..][0..VLEN].*;
                const b1: Vec = hay[p + VLEN + self.i2 ..][0..VLEN].*;
                const x0 = ((a0 | self.m1) ^ self.t1) | ((b0 | self.m2) ^ self.t2);
                const x1 = ((a1 | self.m1) ^ self.t1) | ((b1 | self.m2) ^ self.t2);
                // 候補なしの判定を 1 命令に寄せる（NEON では umin で済む）
                if (@reduce(.Min, @min(x0, x1)) != 0) continue;
                const lo_mask: u32 = @bitCast(x0 == zero);
                const hi_mask: u32 = @bitCast(x1 == zero);
                var mask: u64 = (@as(u64, hi_mask) << 32) | lo_mask;
                while (mask != 0) : (mask &= mask - 1) {
                    const cand = p + @ctz(mask);
                    if (cand <= last and self.verify(hay[cand..])) return cand;
                }
            }
        }
        while (p <= last) : (p += 1) {
            if (fold(hay[p + self.i1]) == self.needle[self.i1] and self.verify(hay[p..])) return p;
        }
        return null;
    }
};

pub fn countNewlines(bytes: []const u8) usize {
    const nl: Vec = @splat('\n');
    const one: Vec = @splat(1);
    const zero: Vec = @splat(0);
    var total: usize = 0;
    var i: usize = 0;
    while (i + VLEN <= bytes.len) {
        var acc: Vec = zero;
        var rounds: usize = 0;
        while (rounds < 255 and i + VLEN <= bytes.len) : ({
            rounds += 1;
            i += VLEN;
        }) {
            const v: Vec = bytes[i..][0..VLEN].*;
            acc += @select(u8, v == nl, one, zero);
        }
        total += @reduce(.Add, @as(@Vector(VLEN, u16), acc));
    }
    for (bytes[i..]) |b| total += @intFromBool(b == '\n');
    return total;
}

pub fn hasSuffixIgnoreCase(name: []const u8, suffix: []const u8) bool {
    if (suffix.len > name.len) return false;
    for (name[name.len - suffix.len ..], suffix) |a, b| {
        if (fold(a) != fold(b)) return false;
    }
    return true;
}

/// Ruby の File.extname と同じ規則（先頭のドットは拡張子とみなさない）
pub fn extname(name: []const u8) []const u8 {
    var start: usize = 0;
    while (start < name.len and name[start] == '.') start += 1;
    const dot = std.mem.lastIndexOfScalar(u8, name[start..], '.') orelse return "";
    return name[start + dot ..];
}

/// NUL 区切りの文字列リスト
const StringList = struct {
    data: []u8 = &.{},
    items: [][]const u8 = &.{},

    fn init(packed_bytes: []const u8) !StringList {
        if (packed_bytes.len == 0) return .{};
        const alloc = std.heap.c_allocator;
        const data = try alloc.dupe(u8, packed_bytes);
        const count = std.mem.count(u8, data, "\x00") + 1;
        const items = try alloc.alloc([]const u8, count);
        var it = std.mem.splitScalar(u8, data, 0);
        var n: usize = 0;
        while (it.next()) |item| : (n += 1) items[n] = item;
        return .{ .data = data, .items = items };
    }

    fn deinit(self: *StringList) void {
        const alloc = std.heap.c_allocator;
        if (self.data.len > 0) alloc.free(self.data);
        if (self.items.len > 0) alloc.free(self.items);
    }
};

/// malloc ベースの伸長バッファ
const Buf = struct {
    ptr: [*]u8 = undefined,
    len: usize = 0,
    cap: usize = 0,

    fn reserve(self: *Buf, need: usize) !void {
        if (need <= self.cap) return;
        const new_cap = @max(need, @max(self.cap * 2, 4096));
        const p = c.realloc(if (self.cap == 0) null else self.ptr, new_cap) orelse return error.OutOfMemory;
        self.ptr = @ptrCast(p);
        self.cap = new_cap;
    }

    fn append(self: *Buf, bytes: []const u8) !void {
        try self.reserve(self.len + bytes.len);
        @memcpy(self.ptr[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
    }

    fn items(self: *const Buf) []u8 {
        return if (self.cap == 0) &.{} else self.ptr[0..self.len];
    }

    fn deinit(self: *Buf) void {
        if (self.cap > 0) c.free(self.ptr);
        self.* = .{};
    }
};

const Job = struct {
    next: ?*Job,
    root: u32,
    len: usize,

    fn path(self: *Job) [:0]u8 {
        const base: [*]u8 = @ptrCast(self);
        return base[@sizeOf(Job)..][0..self.len :0];
    }

    fn create(root: u32, parent: []const u8, name: []const u8) ?*Job {
        const len = if (name.len == 0) parent.len else parent.len + 1 + name.len;
        const mem = c.malloc(@sizeOf(Job) + len + 1) orelse return null;
        const job: *Job = @ptrCast(@alignCast(mem));
        job.* = .{ .next = null, .root = root, .len = len };
        const p = job.path();
        @memcpy(p[0..parent.len], parent);
        if (name.len > 0) {
            p[parent.len] = '/';
            @memcpy(p[parent.len + 1 ..][0..name.len], name);
        }
        p[len] = 0;
        return job;
    }

    fn destroy(self: *Job) void {
        c.free(self);
    }
};

pub const Search = struct {
    matcher: Matcher,
    roots: StringList,
    excluded: StringList,
    documents: StringList,
    dedup: bool,
    cache: ?*Cache = null,

    mutex: os.Mutex = .{},
    work_cond: os.Cond = .{},
    stack: ?*Job = null,
    active: usize = 0,
    next_root: usize = 0,
    finished: bool = false,
    running: usize = 0,

    visit_mutex: os.Mutex = .{},
    visited: std.AutoHashMapUnmanaged(os.DirKey, void) = .empty,

    out_mutex: os.Mutex = .{},
    space_cond: os.Cond = .{},
    out: Buf = .{},
    taken: Buf = .{},

    state: std.atomic.Value(u8) = .init(@intFromEnum(State.idle)),
    cancelled: std.atomic.Value(bool) = .init(false),
    skipped: std.atomic.Value(u64) = .init(0),

    threads: [MAX_THREADS]std.Thread = undefined,
    thread_count: usize = 0,

    pub fn create(roots: []const u8, query: []const u8, excluded: []const u8, documents: []const u8, threads: usize, cache: ?*Cache) !*Search {
        if (query.len == 0 or query.len > MAX_NEEDLE or roots.len == 0) return error.InvalidArgument;
        const self = try std.heap.c_allocator.create(Search);
        errdefer std.heap.c_allocator.destroy(self);
        self.* = .{
            .matcher = Matcher.init(query),
            .roots = try StringList.init(roots),
            .excluded = try StringList.init(excluded),
            .documents = try StringList.init(documents),
            .dedup = false,
        };
        self.dedup = self.roots.items.len > 1;
        // 使用中のキャッシュは共有せず、キャッシュなしで検索する
        if (cache) |cc| {
            if (cc.begin()) self.cache = cc;
        }
        // 拡張子は Ruby 側で小文字化済みだが念のため揃える
        for (self.excluded.data) |*b| b.* = fold(b.*);
        for (self.documents.data) |*b| b.* = fold(b.*);

        const want = if (threads == 0) os.defaultThreads() else threads;
        const count = std.math.clamp(want, 1, MAX_THREADS);

        self.state.store(@intFromEnum(State.scanning), .release);
        // 起動したワーカーは nextJob でこのロックを待つので、running の確定前に終了することはない
        self.mutex.lock();
        self.advanceRootLocked();
        var spawned: usize = 0;
        while (spawned < count) : (spawned += 1) {
            self.threads[spawned] = std.Thread.spawn(.{ .stack_size = 512 * 1024 }, workerMain, .{self}) catch break;
        }
        self.thread_count = spawned;
        self.running = spawned;
        self.mutex.unlock();
        if (spawned == 0) self.state.store(@intFromEnum(State.failed), .release);
        return self;
    }

    pub fn cancel(self: *Search) void {
        self.cancelled.store(true, .release);
        self.mutex.lock();
        self.work_cond.broadcast();
        self.mutex.unlock();
        self.out_mutex.lock();
        self.space_cond.broadcast();
        self.out_mutex.unlock();
    }

    pub fn destroy(self: *Search) void {
        self.cancel();
        for (self.threads[0..self.thread_count]) |t| t.join();
        if (self.cache) |cc| cc.end(self.getState() == .done);
        while (self.stack) |job| {
            self.stack = job.next;
            job.destroy();
        }
        self.visited.deinit(std.heap.c_allocator);
        self.out.deinit();
        self.taken.deinit();
        self.roots.deinit();
        self.excluded.deinit();
        self.documents.deinit();
        std.heap.c_allocator.destroy(self);
    }

    pub fn getState(self: *Search) State {
        return @enumFromInt(self.state.load(.acquire));
    }

    /// 溜まった出力を取り出す（返したバッファは次の drain まで有効）
    pub fn drain(self: *Search) []const u8 {
        self.taken.len = 0;
        self.out_mutex.lock();
        std.mem.swap(Buf, &self.out, &self.taken);
        self.space_cond.broadcast();
        self.out_mutex.unlock();
        return self.taken.items();
    }

    fn advanceRootLocked(self: *Search) void {
        // 複数ブックマークは Ruby 実装同様に順番に走査し、重複ディレクトリは先勝ちにする
        while (self.next_root < self.roots.items.len) {
            const idx = self.next_root;
            self.next_root += 1;
            if (Job.create(@intCast(idx), self.roots.items[idx], "")) |job| {
                job.next = self.stack;
                self.stack = job;
                return;
            }
        }
        self.finished = true;
    }

    fn nextJob(self: *Search) ?*Job {
        self.mutex.lock();
        defer self.mutex.unlock();
        while (true) {
            if (self.cancelled.load(.acquire)) return null;
            if (self.stack) |job| {
                self.stack = job.next;
                self.active += 1;
                return job;
            }
            if (self.finished) return null;
            self.work_cond.wait(&self.mutex);
        }
    }

    fn finishJob(self: *Search, subdirs: ?*Job, subdirs_tail: ?*Job, subdir_count: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (subdirs) |head| {
            subdirs_tail.?.next = self.stack;
            self.stack = head;
        }
        self.active -= 1;
        if (self.active == 0 and self.stack == null) {
            self.advanceRootLocked();
            self.work_cond.broadcast();
        } else if (subdir_count > 1) {
            self.work_cond.broadcast();
        } else if (subdir_count == 1) {
            // 自スレッドが続けて取れるので起こすのは 1 つで足りる
            self.work_cond.signal();
        }
    }

    fn workerExit(self: *Search) void {
        self.mutex.lock();
        self.running -= 1;
        const last = self.running == 0;
        self.mutex.unlock();
        if (last) {
            const final: State = if (self.cancelled.load(.acquire)) .cancelled else .done;
            self.state.store(@intFromEnum(final), .release);
        }
    }

    fn publish(self: *Search, local: *Buf) void {
        if (local.len == 0) return;
        self.out_mutex.lock();
        while (self.out.len > MAX_PENDING and !self.cancelled.load(.acquire)) {
            self.space_cond.wait(&self.out_mutex);
        }
        self.out.append(local.items()) catch {};
        self.out_mutex.unlock();
        local.len = 0;
    }

    fn claimDirectory(self: *Search, dir: *os.Dir) bool {
        if (!self.dedup) return true;
        const key = dir.identity() orelse return true;
        self.visit_mutex.lock();
        defer self.visit_mutex.unlock();
        const gop = self.visited.getOrPut(std.heap.c_allocator, key) catch return true;
        return !gop.found_existing;
    }
};

fn workerMain(s: *Search) void {
    var w = Worker{ .s = s };
    defer w.deinit();
    if (w.init()) {
        while (s.nextJob()) |job| {
            w.processDir(job);
            job.destroy();
            s.finishJob(w.subdirs, w.subdirs_tail, w.subdir_count);
            w.subdirs = null;
            w.subdirs_tail = null;
            w.subdir_count = 0;
            if (w.out.len >= LOCAL_FLUSH) s.publish(&w.out);
        }
    } else |_| {}
    s.publish(&w.out);
    s.workerExit();
}

const Worker = struct {
    s: *Search,
    read: Buf = .{},
    scratch: os.Scratch = .{},
    out: Buf = .{},
    subdirs: ?*Job = null,
    subdirs_tail: ?*Job = null,
    subdir_count: usize = 0,
    key: Buf = .{},

    fn init(self: *Worker) !void {
        try self.read.reserve(READ_BUFFER);
        try self.scratch.init();
        try self.out.reserve(LOCAL_FLUSH * 2);
    }

    fn deinit(self: *Worker) void {
        while (self.subdirs) |job| {
            self.subdirs = job.next;
            job.destroy();
        }
        self.read.deinit();
        self.scratch.deinit();
        self.out.deinit();
        self.key.deinit();
    }

    fn cancelled(self: *Worker) bool {
        return self.s.cancelled.load(.monotonic);
    }

    fn record(self: *Worker, kind: Kind, root: u32, line: u64, offset: u32, dir: []const u8, name: []const u8, extra: []const u8) void {
        const path_len = if (name.len == 0) dir.len else dir.len + 1 + name.len;
        self.out.reserve(self.out.len + RECORD_HEADER + path_len + extra.len) catch return;
        var hdr: [RECORD_HEADER]u8 = undefined;
        hdr[0] = @intFromEnum(kind);
        std.mem.writeInt(u32, hdr[1..5], root, .little);
        std.mem.writeInt(u64, hdr[5..13], line, .little);
        std.mem.writeInt(u32, hdr[13..17], offset, .little);
        std.mem.writeInt(u32, hdr[17..21], @intCast(path_len), .little);
        std.mem.writeInt(u32, hdr[21..25], @intCast(extra.len), .little);
        self.out.append(&hdr) catch unreachable;
        self.out.append(dir) catch unreachable;
        if (name.len > 0) {
            self.out.append("/") catch unreachable;
            self.out.append(name) catch unreachable;
        }
        self.out.append(extra) catch unreachable;
    }

    fn recordErrno(self: *Worker, root: u32, dir: []const u8, name: []const u8) void {
        self.record(.err, root, 0, 0, dir, name, os.lastErrorMessage());
    }

    fn pushSubdir(self: *Worker, job: *Job, name: []const u8) void {
        const sub = Job.create(job.root, job.path(), name) orelse return;
        sub.next = self.subdirs;
        if (self.subdirs == null) self.subdirs_tail = sub;
        self.subdirs = sub;
        self.subdir_count += 1;
    }

    fn processDir(self: *Worker, job: *Job) void {
        const dir_path = job.path();
        var dir = os.Dir.open(dir_path, &self.scratch) orelse {
            self.recordErrno(job.root, dir_path, "");
            return;
        };
        defer dir.close();
        if (!self.s.claimDirectory(&dir)) return;

        while (!self.cancelled()) {
            const entry = dir.next() catch {
                self.recordErrno(job.root, dir_path, "");
                return;
            } orelse return;
            switch (entry.kind) {
                .dir => self.pushSubdir(job, entry.name),
                .file => self.handleFile(&dir, job, entry.name, if (entry.meta) |m| m.size else null, entry.meta),
                // ファイルへのシンボリックリンクは検索し、ディレクトリへのリンクは辿らない
                .symlink => if (dir.stat(entry.name, true)) |info| {
                    if (info.kind == .file) self.handleFile(&dir, job, entry.name, null, null);
                },
                .unknown => if (dir.stat(entry.name, false)) |info| switch (info.kind) {
                    .dir => self.pushSubdir(job, entry.name),
                    .file => self.handleFile(&dir, job, entry.name, info.size, null),
                    .symlink => if (dir.stat(entry.name, true)) |target| {
                        if (target.kind == .file) self.handleFile(&dir, job, entry.name, null, null);
                    },
                    else => {},
                },
                .other => {},
            }
        }
    }

    fn handleFile(self: *Worker, dir: *os.Dir, job: *Job, name: [:0]const u8, size: ?u64, meta: ?FileMeta) void {
        for (self.s.excluded.items) |ext| {
            if (ext.len > 0 and hasSuffixIgnoreCase(name, ext)) {
                _ = self.s.skipped.fetchAdd(1, .monotonic);
                return;
            }
        }
        const ext = extname(name);
        if (ext.len > 0) {
            for (self.s.documents.items) |doc| {
                if (doc.len == ext.len and hasSuffixIgnoreCase(ext, doc)) {
                    self.record(.document, job.root, 0, 0, job.path(), name, "");
                    return;
                }
            }
        }
        // 空ファイルはマッチし得ないので open すら省く
        if (size == 0) return;

        // キャッシュ済みで属性が一致すれば open/read を一切行わない
        var key: []const u8 = &.{};
        const cache = if (meta != null and meta.?.size <= MAX_CACHED_FILE) self.s.cache else null;
        if (cache) |cc| {
            key = self.cacheKey(job.path(), name) orelse return;
            if (cc.lookup(key, meta.?)) |hit| {
                switch (hit) {
                    .binary => _ = self.s.skipped.fetchAdd(1, .monotonic),
                    .text => |content| {
                        var line_no: u64 = 1;
                        self.searchLines(content, job, name, &line_no);
                    },
                }
                return;
            }
        }

        const file = dir.openFile(name) orelse {
            self.recordErrno(job.root, job.path(), name);
            return;
        };
        defer file.close();
        if (cache) |cc| {
            self.searchWholeFile(file, job, name, meta.?, cc, key);
        } else {
            self.searchFile(file, job, name, size, 0);
        }
    }

    fn cacheKey(self: *Worker, dir: []const u8, name: []const u8) ?[]const u8 {
        self.key.len = 0;
        self.key.append(dir) catch return null;
        self.key.append("/") catch return null;
        self.key.append(name) catch return null;
        return self.key.items();
    }

    /// dst を埋めるまで読む。通常ファイルの短い read は EOF なのでそこで止める（EOF 確認の read を省く）。
    /// エラー時は null
    fn readUpTo(file: os.File, dst: []u8) ?usize {
        var got: usize = 0;
        while (got < dst.len) {
            const want = dst.len - got;
            const n = file.read(dst[got..]) orelse return null;
            if (n == 0) break;
            got += n;
            if (n < want) break;
        }
        return got;
    }

    /// キャッシュ対象のファイルを丸ごと読み、判定結果と内容をキャッシュしてから検索する
    fn searchWholeFile(self: *Worker, file: os.File, job: *Job, name: []const u8, meta: FileMeta, cache: *Cache, key: []const u8) void {
        const size: usize = @intCast(meta.size);
        // 1 バイト余分に要求してファイルの伸長を検知する
        self.read.reserve(size + 1) catch return;
        const buf = self.read.ptr[0 .. size + 1];
        const first = if (size < FIRST_READ) size + 1 else BINARY_SAMPLE;
        var got = readUpTo(file, buf[0..first]) orelse return self.recordErrno(job.root, job.path(), name);
        if (std.mem.indexOfScalar(u8, buf[0..@min(got, BINARY_SAMPLE)], 0) != null) {
            cache.store(key, meta, null);
            _ = self.s.skipped.fetchAdd(1, .monotonic);
            return;
        }
        if (got == first and first < buf.len) {
            got += readUpTo(file, buf[got..]) orelse return self.recordErrno(job.root, job.path(), name);
        }
        if (got > size) {
            // 走査後にファイルが伸びた: キャッシュせず残りをストリーミングで処理
            self.searchFile(file, job, name, null, got);
            return;
        }
        cache.store(key, meta, buf[0..got]);
        var line_no: u64 = 1;
        self.searchLines(buf[0..got], job, name, &line_no);
    }

    /// 完全な行の並び（末尾は改行または EOF）を検索してマッチを記録する
    fn searchLines(self: *Worker, buf: []const u8, job: *Job, name: []const u8, line_no: *u64) void {
        const m = &self.s.matcher;
        var pos: usize = 0;
        var counted: usize = 0;
        while (pos < buf.len) {
            const rel = m.find(buf[pos..]) orelse break;
            const hit = pos + rel;
            line_no.* += countNewlines(buf[counted..hit]);
            counted = hit;
            const line_start = if (std.mem.lastIndexOfScalar(u8, buf[0..hit], '\n')) |i| i + 1 else 0;
            const line_end = if (std.mem.indexOfScalarPos(u8, buf, hit, '\n')) |i| i + 1 else buf.len;

            var start = if (hit - line_start > SNIPPET_BEFORE) hit - SNIPPET_BEFORE else line_start;
            while (start < hit and (buf[start] & 0xC0) == 0x80) start += 1;
            const stop = @min(line_end, start + SNIPPET_WINDOW);
            self.record(.match, job.root, line_no.*, @intCast(hit - start), job.path(), name, buf[start..stop]);
            if (self.out.len >= LOCAL_FLUSH) self.s.publish(&self.out);
            pos = line_end;
        }
        line_no.* += countNewlines(buf[counted..]);
    }

    /// ストリーミング検索。preloaded > 0 のときは read バッファ先頭に読み込み済み（バイナリ判定済み）
    fn searchFile(self: *Worker, file: os.File, job: *Job, name: []const u8, size: ?u64, preloaded: usize) void {
        var len: usize = preloaded;
        var eof = false;
        var checked_binary = preloaded > 0;
        var line_no: u64 = 1;
        // 小さいファイルは 1 回の read で読み切り、短い read を EOF とみなして 2 回目を省く。
        // 大きいファイルは先頭 8KB だけ読んでバイナリなら即座に打ち切る。
        var want: usize = if (size) |sz|
            (if (sz < FIRST_READ) @as(usize, @intCast(sz)) + 1 else BINARY_SAMPLE)
        else
            FIRST_READ;

        while (true) {
            if (self.cancelled()) return;
            if (!eof) {
                if (len == self.read.cap) {
                    // 1 行がバッファより長い場合のみ拡張する
                    self.read.reserve(self.read.cap * 2) catch return;
                }
                const req = @min(want, self.read.cap - len);
                want = self.read.cap;
                const n = file.read(self.read.ptr[len..][0..req]) orelse {
                    self.recordErrno(job.root, job.path(), name);
                    return;
                };
                if (n == 0) {
                    eof = true;
                } else {
                    len += n;
                    if (size != null and n < req) eof = true;
                }
            }
            const buf = self.read.ptr[0..len];

            if (!checked_binary) {
                if (!eof and len < BINARY_SAMPLE) continue;
                if (std.mem.indexOfScalar(u8, buf[0..@min(len, BINARY_SAMPLE)], 0) != null) {
                    _ = self.s.skipped.fetchAdd(1, .monotonic);
                    return;
                }
                checked_binary = true;
            }

            var end = len;
            if (!eof) {
                const last_nl = std.mem.lastIndexOfScalar(u8, buf, '\n') orelse continue;
                end = last_nl + 1;
            }
            self.searchLines(buf[0..end], job, name, &line_no);
            if (eof) return;

            const rest = len - end;
            if (rest > 0) std.mem.copyForwards(u8, self.read.ptr[0..rest], buf[end..len]);
            len = rest;
        }
    }
};


/// 1 ファイルあたりのキャッシュ上限（これを超えるファイルは毎回ストリーミングで読む）
const MAX_CACHED_FILE = 16 * 1024 * 1024;

/// 検索をまたいで保持するファイル内容キャッシュ。
/// G mode はキー入力のたびに全体を再検索するため、2 回目以降は open/read を省いて
/// メモリ上で検索する。走査時に取得する mtime/inode/サイズで毎回検証する。
pub const Cache = struct {
    const SHARDS = 64;

    const Entry = struct {
        meta: FileMeta,
        /// null はバイナリ判定済み
        data: ?[*]u8,
        len: usize,
        gen: u32,
    };

    const Shard = struct {
        mutex: os.Mutex = .{},
        map: std.StringHashMapUnmanaged(Entry) = .empty,
    };

    pub const Hit = union(enum) {
        binary,
        text: []const u8,
    };

    shards: [SHARDS]Shard = @splat(.{}),
    max_bytes: u64,
    bytes: std.atomic.Value(u64) = .init(0),
    gen: u32 = 0,
    busy: std.atomic.Value(bool) = .init(false),

    pub fn create(max_bytes: u64) !*Cache {
        const self = try std.heap.c_allocator.create(Cache);
        self.* = .{ .max_bytes = max_bytes };
        return self;
    }

    pub fn destroy(self: *Cache) void {
        for (&self.shards) |*shard| {
            var it = shard.map.iterator();
            while (it.next()) |kv| freeEntry(kv.key_ptr.*, kv.value_ptr.*);
            shard.map.deinit(std.heap.c_allocator);
        }
        std.heap.c_allocator.destroy(self);
    }

    pub fn cachedBytes(self: *Cache) u64 {
        return self.bytes.load(.acquire);
    }

    /// 1 つのキャッシュを同時に使える検索は 1 つだけ
    pub fn begin(self: *Cache) bool {
        if (self.busy.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) return false;
        self.gen +%= 1;
        return true;
    }

    /// 完走した検索のあとは、今回見つからなかった（削除・範囲外の）エントリを捨てる
    pub fn end(self: *Cache, completed: bool) void {
        if (completed) {
            var stale: std.ArrayList([]const u8) = .empty;
            defer stale.deinit(std.heap.c_allocator);
            for (&self.shards) |*shard| {
                stale.clearRetainingCapacity();
                var it = shard.map.iterator();
                while (it.next()) |kv| {
                    if (kv.value_ptr.gen != self.gen) stale.append(std.heap.c_allocator, kv.key_ptr.*) catch break;
                }
                for (stale.items) |key| {
                    const kv = shard.map.fetchRemove(key).?;
                    self.release(kv.value);
                    freeEntry(kv.key, kv.value);
                }
            }
        }
        self.busy.store(false, .release);
    }

    fn shardFor(self: *Cache, key: []const u8) *Shard {
        return &self.shards[std.hash.Wyhash.hash(0, key) % SHARDS];
    }

    fn freeEntry(key: []const u8, entry: Entry) void {
        if (entry.data) |p| c.free(p);
        std.heap.c_allocator.free(key);
    }

    fn release(self: *Cache, entry: Entry) void {
        if (entry.data != null) _ = self.bytes.fetchSub(entry.len, .monotonic);
    }

    pub fn lookup(self: *Cache, key: []const u8, meta: FileMeta) ?Hit {
        const shard = self.shardFor(key);
        shard.mutex.lock();
        defer shard.mutex.unlock();
        const entry = shard.map.getPtr(key) orelse return null;
        if (!entry.meta.eql(meta)) {
            // 変更されたファイル: 古い内容を捨てて読み直させる
            const kv = shard.map.fetchRemove(key).?;
            self.release(kv.value);
            freeEntry(kv.key, kv.value);
            return null;
        }
        entry.gen = self.gen;
        // 内容は同じ検索中に他スレッドから解放されない（同一パスは 1 スレッドしか扱わない）
        return if (entry.data) |p| .{ .text = p[0..entry.len] } else .binary;
    }

    pub fn store(self: *Cache, key: []const u8, meta: FileMeta, content: ?[]const u8) void {
        var data: ?[*]u8 = null;
        var len: usize = 0;
        if (content) |bytes| {
            // 予算を超える場合は保存しない（次回もディスクから読む）
            const prev = self.bytes.fetchAdd(bytes.len, .monotonic);
            if (prev + bytes.len > self.max_bytes) {
                _ = self.bytes.fetchSub(bytes.len, .monotonic);
                return;
            }
            const p: [*]u8 = @ptrCast(c.malloc(@max(bytes.len, 1)) orelse {
                _ = self.bytes.fetchSub(bytes.len, .monotonic);
                return;
            });
            @memcpy(p[0..bytes.len], bytes);
            data = p;
            len = bytes.len;
        }
        const owned_key = std.heap.c_allocator.dupe(u8, key) catch {
            if (data) |p| {
                c.free(p);
                _ = self.bytes.fetchSub(len, .monotonic);
            }
            return;
        };
        const shard = self.shardFor(key);
        shard.mutex.lock();
        defer shard.mutex.unlock();
        const gop = shard.map.getOrPut(std.heap.c_allocator, owned_key) catch {
            if (data) |p| {
                c.free(p);
                _ = self.bytes.fetchSub(len, .monotonic);
            }
            std.heap.c_allocator.free(owned_key);
            return;
        };
        if (gop.found_existing) {
            self.release(gop.value_ptr.*);
            freeEntry(gop.key_ptr.*, gop.value_ptr.*);
            gop.key_ptr.* = owned_key;
        }
        gop.value_ptr.* = .{ .meta = meta, .data = data, .len = len, .gen = self.gen };
    }
};
