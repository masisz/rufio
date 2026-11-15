//! Persistent UTF-8 subsequence index, bounded top-K and a Ruby-independent C ABI.
//!
//! Candidates are stored once as concatenated UTF-8 with a start offset and a
//! codepoint count each (about 12 bytes per candidate beyond the text). Folded
//! characters and bonuses are decoded per query into worker buffers, and only
//! for candidates that pass the subsequence check.
//!
//! A query whose previous query is a subsequence of it only scores the previous
//! matches plus candidates added since; everything else scans all candidates.
//! Large scans are split into chunks that worker threads claim atomically. All
//! buffers are allocated before threads start, so workers never allocate.
const std = @import("std");
const Allocator = std.mem.Allocator;
const NEGATIVE = -(1 << 60);
const MAX_QUERY_BYTES = 1024;
const MAX_CANDIDATE_BYTES = 65536;
const MAX_RESULTS = 10000;
const CHUNK = 1024;
const MAX_THREADS = 16;

pub const Match = struct { id: usize, score: i64 };

fn better(a: Match, b: Match) bool {
    return a.score > b.score or (a.score == b.score and a.id < b.id);
}

fn fold(char: u21) u21 {
    return if (char >= 'A' and char <= 'Z') char + 32 else char;
}

fn separator(char: u21) bool {
    return switch (char) {
        '/', '\\', '_', '-', '.', ' ' => true,
        else => false,
    };
}

fn nextChar(bytes: []const u8, pos: usize, len: *usize) u21 {
    if (bytes[pos] < 0x80) {
        len.* = 1;
        return bytes[pos];
    }
    len.* = std.unicode.utf8ByteSequenceLength(bytes[pos]) catch unreachable;
    return std.unicode.utf8Decode(bytes[pos .. pos + len.*]) catch unreachable;
}

/// Folded characters, bonuses and (optionally) byte offsets of validated UTF-8.
fn decode(bytes: []const u8, chars: []u21, bonuses: []u8, offsets: ?[]u32) void {
    var basename: usize = 0;
    var previous: u21 = 0;
    var i: usize = 0;
    var pos: usize = 0;
    while (pos < bytes.len) : (i += 1) {
        var len: usize = 1;
        const char = nextChar(bytes, pos, &len);
        if (offsets) |list| list[i] = @intCast(pos);
        chars[i] = fold(char);
        const boundary = i == 0 or separator(previous) or
            (previous >= 'a' and previous <= 'z' and char >= 'A' and char <= 'Z');
        bonuses[i] = 16 + @as(u8, if (boundary) 8 else 0);
        if (char == '/' or char == '\\') basename = i + 1;
        previous = char;
        pos += len;
    }
    for (bonuses[basename..i]) |*bonus| bonus.* += 8;
    // The first character of the file name ranks file-name prefixes above matches inside words.
    if (basename < i) bonuses[basename] += 8;
}

/// One pass over the raw bytes: non-matches never pay for decoding or the DP.
fn contains(bytes: []const u8, needle: []const u21, ascii_needle: bool) bool {
    if (needle.len == 0) return true;
    var matched: usize = 0;
    if (ascii_needle) {
        // UTF-8 continuation and lead bytes are >= 0x80 and never equal ASCII.
        for (bytes) |byte| {
            if (fold(byte) == needle[matched]) {
                matched += 1;
                if (matched == needle.len) return true;
            }
        }
        return false;
    }
    var pos: usize = 0;
    while (pos < bytes.len) {
        var len: usize = 1;
        if (fold(nextChar(bytes, pos, &len)) == needle[matched]) {
            matched += 1;
            if (matched == needle.len) return true;
        }
        pos += len;
    }
    return false;
}

fn isSubsequence(small: []const u21, large: []const u21) bool {
    var matched: usize = 0;
    for (large) |char| {
        if (matched < small.len and char == small[matched]) matched += 1;
    }
    return matched == small.len;
}

// Worst retained match at the root: O(N log K), never sort N matches.
fn siftUp(items: []Match, start: usize) void {
    var i = start;
    while (i > 0) {
        const parent = (i - 1) / 2;
        if (!better(items[parent], items[i])) break;
        std.mem.swap(Match, &items[parent], &items[i]);
        i = parent;
    }
}

fn siftDown(items: []Match) void {
    var i: usize = 0;
    while (i * 2 + 1 < items.len) {
        var child = i * 2 + 1;
        if (child + 1 < items.len and better(items[child], items[child + 1])) child += 1;
        if (!better(items[i], items[child])) break;
        std.mem.swap(Match, &items[i], &items[child]);
        i = child;
    }
}

fn pushTop(heap: *std.ArrayList(Match), limit: usize, item: Match) void {
    if (limit == 0) return;
    if (heap.items.len < limit) {
        heap.appendAssumeCapacity(item);
        siftUp(heap.items, heap.items.len - 1);
    } else if (better(item, heap.items[0])) {
        heap.items[0] = item;
        siftDown(heap.items);
    }
}

/// Scores one contiguous range of work items. Owns its buffers; never allocates.
const Worker = struct {
    engine: *const Engine,
    needle: []const u21,
    ascii_needle: bool,
    narrowed: []const u32,
    range_start: usize,
    work: usize,
    next_chunk: *std.atomic.Value(usize),
    ids: []u32,
    chunk_counts: []u32,
    rows: []i64,
    chars: []u21,
    bonuses: []u8,
    heap: std.ArrayList(Match) = .empty,
    limit: usize,
    total: u64 = 0,

    fn run(self: *Worker) void {
        while (true) {
            const chunk = self.next_chunk.fetchAdd(1, .monotonic);
            const begin = chunk * CHUNK;
            if (begin >= self.work) return;
            const end = @min(begin + CHUNK, self.work);
            var count: u32 = 0;
            for (begin..end) |item| {
                const id: usize = if (item < self.narrowed.len) self.narrowed[item] else self.range_start + item - self.narrowed.len;
                const n = self.engine.char_counts.items[id];
                if (self.needle.len > n) continue;
                const bytes = self.engine.bytesOf(id);
                if (!contains(bytes, self.needle, self.ascii_needle)) continue;
                var value: i64 = 0;
                if (self.needle.len > 0) {
                    decode(bytes, self.chars[0..n], self.bonuses[0..n], null);
                    value = score(self.chars[0..n], self.bonuses[0..n], self.needle, self.rows, null) orelse continue;
                }
                self.ids[begin + count] = @intCast(id);
                count += 1;
                self.total += 1;
                pushTop(&self.heap, self.limit, .{ .id = id, .score = value });
            }
            self.chunk_counts[chunk] = count;
        }
    }
};

pub const Engine = struct {
    allocator: Allocator,
    text: std.ArrayList(u8) = .empty,
    starts: std.ArrayList(usize) = .empty,
    char_counts: std.ArrayList(u32) = .empty,
    matches: std.ArrayList(Match) = .empty,
    output: std.ArrayList(u8) = .empty,
    total: u64 = 0,
    max_chars: usize = 0,
    /// Candidates scored by the last query (instrumentation for narrowing).
    scanned: usize = 0,
    /// Worker threads; 0 picks the CPU count (at most MAX_THREADS).
    threads: usize = 0,
    /// Scans below this many candidates stay on the calling thread. 2048 was the fastest of
    /// 1024-16384 on 50k-168k paths (4 cores): narrowed steps no longer fall back to one thread.
    min_parallel: usize = 2048,
    previous_query: std.ArrayList(u21) = .empty,
    previous_ids: std.ArrayList(u32) = .empty,
    previous_count: usize = 0,
    has_previous: bool = false,

    pub fn init(allocator: Allocator) Engine {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Engine) void {
        self.text.deinit(self.allocator);
        self.starts.deinit(self.allocator);
        self.char_counts.deinit(self.allocator);
        self.matches.deinit(self.allocator);
        self.output.deinit(self.allocator);
        self.previous_query.deinit(self.allocator);
        self.previous_ids.deinit(self.allocator);
    }

    pub fn count(self: *const Engine) usize {
        return self.starts.items.len;
    }

    /// Bytes held for candidates and the narrowing state.
    pub fn storageBytes(self: *const Engine) usize {
        return self.text.capacity + self.starts.capacity * @sizeOf(usize) +
            self.char_counts.capacity * @sizeOf(u32) + self.previous_ids.capacity * @sizeOf(u32) +
            self.previous_query.capacity * @sizeOf(u21);
    }

    fn bytesOf(self: *const Engine, id: usize) []const u8 {
        const end = if (id + 1 < self.starts.items.len) self.starts.items[id + 1] else self.text.items.len;
        return self.text.items[self.starts.items[id]..end];
    }

    /// Validate the full batch first and reserve space, so a batch is added whole or not at all.
    pub fn add(self: *Engine, batch: []const u8) !void {
        if (batch.len == 0) return;
        if (batch[batch.len - 1] != 0) return error.InvalidInput;
        var strings = std.mem.splitScalar(u8, batch[0 .. batch.len - 1], 0);
        var number: usize = 0;
        var bytes: usize = 0;
        while (strings.next()) |text| {
            if (text.len > MAX_CANDIDATE_BYTES or !std.unicode.utf8ValidateSlice(text)) return error.InvalidInput;
            number += 1;
            bytes += text.len;
        }
        if (self.starts.items.len + number > std.math.maxInt(u32)) return error.OutOfMemory;
        try self.text.ensureUnusedCapacity(self.allocator, bytes);
        try self.starts.ensureUnusedCapacity(self.allocator, number);
        try self.char_counts.ensureUnusedCapacity(self.allocator, number);
        strings.reset();
        while (strings.next()) |text| {
            const chars = std.unicode.utf8CountCodepoints(text) catch unreachable;
            self.starts.appendAssumeCapacity(self.text.items.len);
            self.text.appendSliceAssumeCapacity(text);
            self.char_counts.appendAssumeCapacity(@intCast(chars));
            self.max_chars = @max(self.max_chars, chars);
        }
    }

    fn threadCount(self: *const Engine, work: usize) usize {
        if (work < self.min_parallel) return 1;
        const wanted = if (self.threads == 0) (std.Thread.getCpuCount() catch 1) else self.threads;
        const chunks = (work + CHUNK - 1) / CHUNK;
        return @max(1, @min(@min(wanted, MAX_THREADS), chunks));
    }

    /// Serialized by the Ruby session; no concurrent mutation on a handle.
    pub fn query(self: *Engine, text: []const u8, limit: usize) !void {
        return self.queryPositions(text, limit, limit);
    }

    /// Like query, but recovers match positions only for the best `position_limit` results;
    /// the others report zero positions (callers compute them on demand when shown).
    pub fn queryPositions(self: *Engine, text: []const u8, limit: usize, position_limit: usize) !void {
        if (text.len > MAX_QUERY_BYTES or limit > MAX_RESULTS or
            std.mem.indexOfScalar(u8, text, 0) != null or !std.unicode.utf8ValidateSlice(text)) return error.InvalidInput;
        var query_chars: [MAX_QUERY_BYTES]u21 = undefined;
        var iterator = (try std.unicode.Utf8View.init(text)).iterator();
        var length: usize = 0;
        var ascii_needle = true;
        while (iterator.nextCodepoint()) |char| {
            query_chars[length] = fold(char);
            if (char >= 0x80) ascii_needle = false;
            length += 1;
        }
        const needle = query_chars[0..length];
        self.matches.clearRetainingCapacity();
        self.output.clearRetainingCapacity();
        self.total = 0;

        // Narrow only when every match of the new query must match the previous one.
        const narrow = self.has_previous and length > 0 and isSubsequence(self.previous_query.items, needle);
        self.has_previous = false;
        const narrowed: []const u32 = if (narrow) self.previous_ids.items else &.{};
        const range_start = if (narrow) self.previous_count else 0;
        const work = narrowed.len + (self.starts.items.len - range_start);
        self.scanned = work;

        var next_ids: std.ArrayList(u32) = .empty;
        defer next_ids.deinit(self.allocator);
        try next_ids.resize(self.allocator, work);
        const chunk_counts = try self.allocator.alloc(u32, (work + CHUNK - 1) / CHUNK);
        defer self.allocator.free(chunk_counts);
        @memset(chunk_counts, 0);

        const thread_count = self.threadCount(work);
        var workers: [MAX_THREADS]Worker = undefined;
        var prepared: usize = 0;
        defer for (workers[0..prepared]) |*worker| {
            self.allocator.free(worker.rows);
            self.allocator.free(worker.chars);
            self.allocator.free(worker.bonuses);
            worker.heap.deinit(self.allocator);
        };
        var next_chunk = std.atomic.Value(usize).init(0);
        while (prepared < thread_count) : (prepared += 1) {
            const rows = try self.allocator.alloc(i64, self.max_chars * 2);
            errdefer self.allocator.free(rows);
            const chars = try self.allocator.alloc(u21, self.max_chars);
            errdefer self.allocator.free(chars);
            const bonuses = try self.allocator.alloc(u8, self.max_chars);
            errdefer self.allocator.free(bonuses);
            var heap: std.ArrayList(Match) = .empty;
            try heap.ensureTotalCapacity(self.allocator, @min(limit, work));
            workers[prepared] = .{
                .engine = self,
                .needle = needle,
                .ascii_needle = ascii_needle,
                .narrowed = narrowed,
                .range_start = range_start,
                .work = work,
                .next_chunk = &next_chunk,
                .ids = next_ids.items,
                .chunk_counts = chunk_counts,
                .rows = rows,
                .chars = chars,
                .bonuses = bonuses,
                .heap = heap,
                .limit = limit,
            };
        }
        try self.matches.ensureTotalCapacity(self.allocator, @min(limit, work) * thread_count);

        // Threads that fail to start leave their chunks to the others.
        var spawned: [MAX_THREADS]?std.Thread = @splat(null);
        for (1..thread_count) |index| {
            spawned[index] = std.Thread.spawn(.{ .stack_size = 256 * 1024 }, Worker.run, .{&workers[index]}) catch null;
        }
        workers[0].run();
        for (spawned[1..thread_count]) |thread| {
            if (thread) |t| t.join();
        }

        // Compact the per-chunk match lists in chunk order: ids stay ascending.
        var matched: usize = 0;
        for (chunk_counts, 0..) |chunk_count, chunk| {
            const begin = chunk * CHUNK;
            std.mem.copyForwards(u32, next_ids.items[matched .. matched + chunk_count], next_ids.items[begin .. begin + chunk_count]);
            matched += chunk_count;
        }
        next_ids.shrinkRetainingCapacity(matched);
        for (workers[0..thread_count]) |*worker| {
            self.total += worker.total;
            self.matches.appendSliceAssumeCapacity(worker.heap.items);
        }
        std.mem.sort(Match, self.matches.items, {}, struct {
            fn less(_: void, a: Match, b: Match) bool {
                return better(a, b);
            }
        }.less);
        self.matches.shrinkRetainingCapacity(@min(limit, self.matches.items.len));

        try self.writeResults(needle, &workers[0], position_limit);

        if (length > 0) {
            self.previous_query.clearRetainingCapacity();
            try self.previous_query.appendSlice(self.allocator, needle);
            std.mem.swap(std.ArrayList(u32), &self.previous_ids, &next_ids);
            self.previous_count = self.starts.items.len;
            self.has_previous = true;
        }
    }

    fn writeResults(self: *Engine, needle: []const u21, worker: *Worker, position_limit: usize) !void {
        try self.write(u64, self.total);
        try self.write(u32, @intCast(self.matches.items.len));
        if (self.matches.items.len == 0) return;
        const offsets = try self.allocator.alloc(u32, self.max_chars);
        defer self.allocator.free(offsets);
        for (self.matches.items, 0..) |item, rank| {
            const with_positions = rank < position_limit;
            try self.write(u64, @intCast(item.id));
            try self.write(i64, item.score);
            try self.write(u32, if (with_positions) @intCast(needle.len) else 0);
            if (needle.len == 0 or !with_positions) continue;
            const n = self.char_counts.items[item.id];
            const chars = worker.chars[0..n];
            decode(self.bytesOf(item.id), chars, worker.bonuses[0..n], offsets[0..n]);
            const trace = try self.allocator.alloc(u32, n * needle.len);
            defer self.allocator.free(trace);
            _ = score(chars, worker.bonuses[0..n], needle, worker.rows, trace);
            const final = worker.rows[(needle.len % 2) * n ..][0..n];
            var end: usize = 0;
            for (final, 0..) |value, i| {
                if (value > final[end]) end = i;
            }
            var positions: [MAX_QUERY_BYTES]u32 = undefined;
            var row = needle.len;
            while (row > 0) {
                row -= 1;
                positions[row] = offsets[end];
                end = trace[row * n + end];
            }
            for (positions[0..needle.len]) |position| try self.write(u32, position);
        }
    }

    fn write(self: *Engine, comptime T: type, value: T) !void {
        var buf: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &buf, value, .little);
        try self.output.appendSlice(self.allocator, &buf);
    }
};

/// Callers have already checked that `needle` is a subsequence of `chars`.
fn score(chars: []const u21, bonuses: []const u8, needle: []const u21, rows: []i64, trace: ?[]u32) ?i64 {
    if (needle.len == 0) return 0;
    const n = chars.len;
    if (needle.len > n) return null;
    @memset(rows[0..n], NEGATIVE);
    for (needle, 0..) |char, row| {
        const previous = rows[(row % 2) * n ..][0..n];
        const current = rows[((row + 1) % 2) * n ..][0..n];
        @memset(current, NEGATIVE);
        var prefix_score: i64 = NEGATIVE;
        var prefix_index: usize = 0;
        for (chars, 0..) |c, i| {
            if (i >= 2 and previous[i - 2] != NEGATIVE and previous[i - 2] + @as(i64, @intCast(i - 2)) > prefix_score) {
                prefix_score = previous[i - 2] + @as(i64, @intCast(i - 2));
                prefix_index = i - 2;
            }
            if (c != char) continue;
            if (row == 0) {
                // No penalty for the distance from the start: long directory prefixes must not
                // outweigh a match in the file name (the length penalty still prefers short paths).
                current[i] = @as(i64, bonuses[i]);
            } else {
                var value: i64 = if (prefix_score == NEGATIVE) NEGATIVE else prefix_score - @as(i64, @intCast(i)) + 1;
                var source = prefix_index;
                if (i > 0 and previous[i - 1] != NEGATIVE and previous[i - 1] + 24 > value) {
                    value = previous[i - 1] + 24;
                    source = i - 1;
                }
                if (value == NEGATIVE) continue;
                current[i] = value + bonuses[i];
                if (trace) |parents| parents[row * n + i] = @intCast(source);
            }
            if (row == 0) {
                if (trace) |parents| parents[i] = 0;
            }
        }
    }
    const final = rows[(needle.len % 2) * n ..][0..n];
    var best: i64 = NEGATIVE;
    for (final) |value| best = @max(best, value);
    if (best == NEGATIVE) return null;
    return best - @as(i64, @intCast(n)) + @as(i64, if (needle.len == n) 64 else 0);
}

const ffi_allocator = std.heap.smp_allocator;

pub export fn core_fuzzy_create() u64 {
    const engine = ffi_allocator.create(Engine) catch return 0;
    engine.* = Engine.init(ffi_allocator);
    return @intFromPtr(engine);
}

pub export fn core_fuzzy_add(handle: u64, data: [*]const u8, length: usize) i32 {
    if (handle == 0) return -1;
    const engine: *Engine = @ptrFromInt(handle);
    engine.add(data[0..length]) catch |err| return if (err == error.InvalidInput) -1 else -2;
    return 0;
}

pub export fn core_fuzzy_query(handle: u64, data: [*]const u8, length: usize, limit: u32) i32 {
    if (handle == 0) return -1;
    const engine: *Engine = @ptrFromInt(handle);
    engine.query(data[0..length], limit) catch |err| return if (err == error.InvalidInput) -1 else -2;
    return 0;
}

/// core_fuzzy_query that recovers positions only for the best `position_limit` results.
pub export fn core_fuzzy_query_positions(handle: u64, data: [*]const u8, length: usize, limit: u32, position_limit: u32) i32 {
    if (handle == 0) return -1;
    const engine: *Engine = @ptrFromInt(handle);
    engine.queryPositions(data[0..length], limit, position_limit) catch |err| return if (err == error.InvalidInput) -1 else -2;
    return 0;
}

pub export fn core_fuzzy_results(handle: u64, length: *usize) ?[*]const u8 {
    length.* = 0;
    if (handle == 0) return null;
    const engine: *Engine = @ptrFromInt(handle);
    length.* = engine.output.items.len;
    return engine.output.items.ptr;
}

/// Candidates scored by the last query; lets callers verify narrowing.
pub export fn core_fuzzy_scanned(handle: u64) u64 {
    if (handle == 0) return 0;
    const engine: *Engine = @ptrFromInt(handle);
    return engine.scanned;
}

pub export fn core_fuzzy_destroy(handle: u64) void {
    if (handle == 0) return;
    const engine: *Engine = @ptrFromInt(handle);
    engine.deinit();
    ffi_allocator.destroy(engine);
}
