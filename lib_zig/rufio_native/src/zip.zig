//! ZIP のデータ処理エンジン（展開・圧縮）。
//!
//! 安全性の検証（パス・シンボリックリンク・上限・重複範囲）と、ディレクトリ作成・rename・
//! 権限と日時の設定は Ruby 側（ZipExtractor / ZipWriter）が行う。ここではエントリ単位の
//! データ処理だけをスレッドで並列に行う。
//!
//! - 展開: ZIP 内の指定範囲を読み、Stored はそのまま、Deflate は伸長し、宣言サイズを超えた時点で
//!   打ち切り、CRC-32 を検証して一時ファイル（新規作成のみ）に書く
//! - 圧縮: ファイルを raw DEFLATE で一時ファイルに書き、CRC-32・圧縮後サイズ・元サイズを返す
const std = @import("std");
const os = @import("os.zig");
const flate = std.compress.flate;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
const Crc32 = std.hash.Crc32;

const alloc = std.heap.c_allocator;

pub const MAX_THREADS = 16;
const IO_BUFFER = 64 * 1024;
/// flate.Compress は 200KB 超あり、初期化時に一時的にスタックへ載るため余裕を持たせる
const WORKER_STACK = 4 * 1024 * 1024;

pub const State = enum(u8) {
    idle = 0,
    running = 1,
    done = 2,
    cancelled = 3,
    failed = 4,
};

/// タスクごとの結果（Ruby 側 NativeZip::STATUS_* と一致させる）
pub const Status = enum(u8) {
    ok = 0,
    crc_mismatch = 1,
    size_mismatch = 2,
    corrupt = 3,
    io_error = 4,
    cancelled = 5,
    too_large = 6,
    pending = 255,
};

pub const Kind = enum { extract, deflate };

const Task = struct {
    // 展開
    data_offset: u64 = 0,
    compressed_size: u64 = 0,
    size: u64 = 0,
    crc: u32 = 0,
    method: u8 = 0,
    // 圧縮
    source: ?[:0]u8 = null,
    // 共通
    output: ?[:0]u8 = null,
    status: Status = .pending,
    // 圧縮の結果
    out_crc: u32 = 0,
    out_compressed: u64 = 0,
    out_size: u64 = 0,
};

/// 1 スレッド分の作業領域
const Worker = struct {
    scratch: os.Scratch = .{},
    in_buf: []u8 = &.{},
    out_buf: []u8 = &.{},
    window: []u8 = &.{},

    fn init(self: *Worker) !void {
        try self.scratch.init();
        errdefer self.deinit();
        self.in_buf = try alloc.alloc(u8, IO_BUFFER);
        self.out_buf = try alloc.alloc(u8, IO_BUFFER);
        self.window = try alloc.alloc(u8, flate.max_window_len);
    }

    fn deinit(self: *Worker) void {
        self.scratch.deinit();
        if (self.in_buf.len > 0) alloc.free(self.in_buf);
        if (self.out_buf.len > 0) alloc.free(self.out_buf);
        if (self.window.len > 0) alloc.free(self.window);
        self.* = .{};
    }
};

/// ZIP 内の [offset, offset+remaining) を読む Reader
const RegionReader = struct {
    reader: Reader,
    file: os.File,
    offset: u64,
    remaining: u64,
    failed: bool = false,

    const vtable: Reader.VTable = .{ .stream = stream, .readVec = readVec };

    fn init(file: os.File, offset: u64, length: u64, buffer: []u8) RegionReader {
        return .{
            .reader = .{ .vtable = &vtable, .buffer = buffer, .seek = 0, .end = 0 },
            .file = file,
            .offset = offset,
            .remaining = length,
        };
    }

    /// 自分のバッファに直接読み込む（Reader の実装として許されている方式）
    fn fill(r: *Reader) Reader.Error!void {
        const self: *RegionReader = @fieldParentPtr("reader", r);
        if (self.remaining == 0) return error.EndOfStream;
        if (r.seek > 0) {
            const unread = r.end - r.seek;
            std.mem.copyForwards(u8, r.buffer[0..unread], r.buffer[r.seek..r.end]);
            r.seek = 0;
            r.end = unread;
        }
        const space = r.buffer[r.end..];
        if (space.len == 0) return;
        const want: usize = @intCast(@min(space.len, self.remaining));
        const n = self.file.pread(space[0..want], self.offset) orelse {
            self.failed = true;
            return error.ReadFailed;
        };
        if (n == 0) return error.EndOfStream;
        r.end += n;
        self.offset += n;
        self.remaining -= n;
    }

    fn stream(r: *Reader, w: *Writer, limit: std.Io.Limit) Reader.StreamError!usize {
        _ = w;
        _ = limit;
        try fill(r);
        return 0;
    }

    fn readVec(r: *Reader, data: [][]u8) Reader.Error!usize {
        _ = data;
        try fill(r);
        return 0;
    }
};

/// 書き込み先ファイルへの Writer（CRC-32・サイズ計測、上限超過・キャンセルで打ち切り）
const FileSink = struct {
    writer: Writer,
    file: os.File,
    job: *Job,
    limit: ?u64,
    hash: bool,
    crc: Crc32 = .init(),
    written: u64 = 0,
    overflow: bool = false,
    cancelled: bool = false,
    io_failed: bool = false,

    const vtable: Writer.VTable = .{ .drain = drain };

    fn init(file: os.File, job: *Job, buffer: []u8, limit: ?u64, hash: bool) FileSink {
        return .{
            .writer = .{ .vtable = &vtable, .buffer = buffer },
            .file = file,
            .job = job,
            .limit = limit,
            .hash = hash,
        };
    }

    fn sink(self: *FileSink, bytes: []const u8) Writer.Error!void {
        if (bytes.len == 0) return;
        if (self.job.cancelled.load(.acquire)) {
            self.cancelled = true;
            return error.WriteFailed;
        }
        if (self.limit) |max| {
            if (self.written + bytes.len > max) {
                self.overflow = true;
                return error.WriteFailed;
            }
        }
        if (self.hash) self.crc.update(bytes);
        if (!self.file.writeAll(bytes)) {
            self.io_failed = true;
            return error.WriteFailed;
        }
        self.written += bytes.len;
        if (self.hash) _ = self.job.done_bytes.fetchAdd(bytes.len, .monotonic);
    }

    fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
        const self: *FileSink = @fieldParentPtr("writer", w);
        try self.sink(w.buffer[0..w.end]);
        w.end = 0;
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            try self.sink(bytes);
            n += bytes.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| {
            try self.sink(last);
            n += last.len;
        }
        return n;
    }

    fn failureStatus(self: *const FileSink) Status {
        if (self.cancelled) return .cancelled;
        if (self.overflow) return .too_large;
        return .io_error;
    }
};

pub const Job = struct {
    kind: Kind,
    zip_path: ?[:0]u8 = null,
    tasks: []Task,
    level: flate.Compress.Options = .default,
    next: std.atomic.Value(usize) = .init(0),
    done_bytes: std.atomic.Value(u64) = .init(0),
    total_bytes: u64 = 0,
    cancelled: std.atomic.Value(bool) = .init(false),
    state: std.atomic.Value(u8) = .init(@intFromEnum(State.idle)),
    running: std.atomic.Value(usize) = .init(0),
    threads: [MAX_THREADS]std.Thread = undefined,
    thread_count: usize = 0,

    /// 展開ジョブ。tasks は (data_offset u64, compressed_size u64, size u64, crc u32, method u8, path_len u32, path) の並び
    pub fn createExtract(zip_path: []const u8, records: []const u8, threads: u32) !*Job {
        var count: usize = 0;
        var pos: usize = 0;
        while (pos < records.len) : (count += 1) {
            if (pos + 33 > records.len) return error.InvalidTasks;
            const len = std.mem.readInt(u32, records[pos + 29 ..][0..4], .little);
            pos += 33 + len;
            if (pos > records.len) return error.InvalidTasks;
        }

        const self = try create(.extract, count);
        errdefer self.destroyTasks();
        self.zip_path = try alloc.dupeSentinel(u8, zip_path, 0);
        pos = 0;
        for (self.tasks) |*task| {
            task.data_offset = std.mem.readInt(u64, records[pos..][0..8], .little);
            task.compressed_size = std.mem.readInt(u64, records[pos + 8 ..][0..8], .little);
            task.size = std.mem.readInt(u64, records[pos + 16 ..][0..8], .little);
            task.crc = std.mem.readInt(u32, records[pos + 24 ..][0..4], .little);
            task.method = records[pos + 28];
            const len = std.mem.readInt(u32, records[pos + 29 ..][0..4], .little);
            task.output = try alloc.dupeSentinel(u8, records[pos + 33 ..][0..len], 0);
            pos += 33 + len;
            self.total_bytes += task.size;
        }
        self.start(threads);
        return self;
    }

    /// 圧縮ジョブ。tasks は (source_len u32, source, output_len u32, output) の並び
    pub fn createDeflate(records: []const u8, level: i32, threads: u32) !*Job {
        var count: usize = 0;
        var pos: usize = 0;
        while (pos < records.len) : (count += 1) {
            for (0..2) |_| {
                if (pos + 4 > records.len) return error.InvalidTasks;
                pos += 4 + std.mem.readInt(u32, records[pos..][0..4], .little);
                if (pos > records.len) return error.InvalidTasks;
            }
        }

        const self = try create(.deflate, count);
        errdefer self.destroyTasks();
        self.level = levelOptions(level);
        pos = 0;
        for (self.tasks) |*task| {
            var len = std.mem.readInt(u32, records[pos..][0..4], .little);
            task.source = try alloc.dupeSentinel(u8, records[pos + 4 ..][0..len], 0);
            pos += 4 + len;
            len = std.mem.readInt(u32, records[pos..][0..4], .little);
            task.output = try alloc.dupeSentinel(u8, records[pos + 4 ..][0..len], 0);
            pos += 4 + len;
        }
        self.start(threads);
        return self;
    }

    fn create(kind: Kind, count: usize) !*Job {
        const self = try alloc.create(Job);
        errdefer alloc.destroy(self);
        const tasks = try alloc.alloc(Task, count);
        for (tasks) |*task| task.* = .{};
        self.* = .{ .kind = kind, .tasks = tasks };
        return self;
    }

    fn start(self: *Job, threads: u32) void {
        self.state.store(@intFromEnum(State.running), .release);
        if (self.tasks.len == 0) {
            self.state.store(@intFromEnum(State.done), .release);
            return;
        }
        const wanted: usize = if (threads == 0) os.defaultThreads() else threads;
        const count = @max(1, @min(@min(wanted, MAX_THREADS), self.tasks.len));
        self.running.store(count, .release);
        var spawned: usize = 0;
        while (spawned < count) : (spawned += 1) {
            self.threads[spawned] = std.Thread.spawn(.{ .stack_size = WORKER_STACK }, workerMain, .{self}) catch break;
        }
        self.thread_count = spawned;
        if (spawned < count) {
            // 起動できなかった分は終了済みとして数える
            if (self.running.fetchSub(count - spawned, .acq_rel) == count - spawned) self.finish();
            if (spawned == 0) self.state.store(@intFromEnum(State.failed), .release);
        }
    }

    fn finish(self: *Job) void {
        const final: State = if (self.cancelled.load(.acquire)) .cancelled else .done;
        self.state.store(@intFromEnum(final), .release);
    }

    pub fn getState(self: *Job) State {
        return @enumFromInt(self.state.load(.acquire));
    }

    pub fn cancel(self: *Job) void {
        self.cancelled.store(true, .release);
    }

    /// 圧縮では、読み込み済みバイト数の合計が分かるのは開始後なので total は随時更新される
    pub fn progress(self: *Job, done: *u64, total: *u64) void {
        done.* = self.done_bytes.load(.monotonic);
        total.* = if (self.kind == .extract) self.total_bytes else @max(self.total_bytes, done.*);
    }

    pub fn status(self: *Job, index: usize) Status {
        if (index >= self.tasks.len) return .io_error;
        return self.tasks[index].status;
    }

    pub fn deflateResult(self: *Job, index: usize, crc: *u32, compressed: *u64, size: *u64) Status {
        if (index >= self.tasks.len) return .io_error;
        const task = &self.tasks[index];
        crc.* = task.out_crc;
        compressed.* = task.out_compressed;
        size.* = task.out_size;
        return task.status;
    }

    /// 実行中ならキャンセルしてスレッドの終了を待ってから解放する
    pub fn destroy(self: *Job) void {
        self.cancel();
        for (self.threads[0..self.thread_count]) |thread| thread.join();
        self.destroyTasks();
    }

    fn destroyTasks(self: *Job) void {
        for (self.tasks) |task| {
            if (task.source) |path| alloc.free(path);
            if (task.output) |path| alloc.free(path);
        }
        alloc.free(self.tasks);
        if (self.zip_path) |path| alloc.free(path);
        alloc.destroy(self);
    }
};

fn levelOptions(level: i32) flate.Compress.Options {
    return switch (level) {
        1 => .level_1,
        2 => .level_2,
        3 => .level_3,
        4 => .level_4,
        5 => .level_5,
        7 => .level_7,
        8 => .level_8,
        9 => .level_9,
        else => .default,
    };
}

fn workerMain(job: *Job) void {
    defer {
        if (job.running.fetchSub(1, .acq_rel) == 1) job.finish();
    }
    var worker: Worker = .{};
    worker.init() catch {
        markRemaining(job, .io_error);
        return;
    };
    defer worker.deinit();

    var zip: ?os.File = null;
    defer if (zip) |file| file.close();

    while (true) {
        const index = job.next.fetchAdd(1, .acq_rel);
        if (index >= job.tasks.len) return;
        const task = &job.tasks[index];
        if (job.cancelled.load(.acquire)) {
            task.status = .cancelled;
            continue;
        }
        switch (job.kind) {
            .extract => {
                if (zip == null) zip = os.openRead(job.zip_path.?, &worker.scratch);
                task.status = if (zip) |file| extractTask(job, task, file, &worker) else .io_error;
            },
            .deflate => task.status = deflateTask(job, task, &worker),
        }
    }
}

fn markRemaining(job: *Job, status: Status) void {
    while (true) {
        const index = job.next.fetchAdd(1, .acq_rel);
        if (index >= job.tasks.len) return;
        job.tasks[index].status = status;
    }
}

fn extractTask(job: *Job, task: *Task, zip: os.File, worker: *Worker) Status {
    if (task.method != 0 and task.method != 8) return .corrupt;
    if (task.method == 0 and task.compressed_size != task.size) return .size_mismatch;

    const out = os.createExclusive(task.output.?, &worker.scratch) orelse return .io_error;
    defer out.close();

    var sink = FileSink.init(out, job, worker.out_buf, task.size, true);
    var region = RegionReader.init(zip, task.data_offset, task.compressed_size, worker.in_buf);

    if (task.method == 0) {
        _ = region.reader.streamRemaining(&sink.writer) catch |err| switch (err) {
            error.WriteFailed => return sink.failureStatus(),
            error.ReadFailed => return if (region.failed) .io_error else .corrupt,
        };
    } else {
        const decompress = alloc.create(flate.Decompress) catch return .io_error;
        defer alloc.destroy(decompress);
        decompress.* = .init(&region.reader, .raw, worker.window);
        _ = decompress.reader.streamRemaining(&sink.writer) catch |err| switch (err) {
            error.WriteFailed => return sink.failureStatus(),
            error.ReadFailed => return if (region.failed) .io_error else .corrupt,
        };
    }
    sink.writer.flush() catch return sink.failureStatus();

    if (sink.written != task.size) return .size_mismatch;
    if (sink.crc.final() != task.crc) return .crc_mismatch;
    return .ok;
}

fn deflateTask(job: *Job, task: *Task, worker: *Worker) Status {
    const in = os.openRead(task.source.?, &worker.scratch) orelse return .io_error;
    defer in.close();
    const out = os.createExclusive(task.output.?, &worker.scratch) orelse return .io_error;
    defer out.close();

    var sink = FileSink.init(out, job, worker.out_buf, null, false);
    const compress = alloc.create(flate.Compress) catch return .io_error;
    defer alloc.destroy(compress);
    compress.* = flate.Compress.init(&sink.writer, worker.window, .raw, job.level) catch return sink.failureStatus();

    var crc: Crc32 = .init();
    var size: u64 = 0;
    while (true) {
        if (job.cancelled.load(.acquire)) return .cancelled;
        const n = in.pread(worker.in_buf, size) orelse return .io_error;
        if (n == 0) break;
        const chunk = worker.in_buf[0..n];
        crc.update(chunk);
        size += n;
        _ = job.done_bytes.fetchAdd(n, .monotonic);
        compress.writer.writeAll(chunk) catch return sink.failureStatus();
    }
    compress.finish() catch return sink.failureStatus();
    sink.writer.flush() catch return sink.failureStatus();

    task.out_crc = crc.final();
    task.out_compressed = sink.written;
    task.out_size = size;
    return .ok;
}
