//! Persistent UTF-8 subsequence index, bounded top-K and a Ruby-independent C ABI.
const std = @import("std");
const Allocator = std.mem.Allocator;
const NEGATIVE = -(1 << 60);
const MAX_QUERY_BYTES = 1024;
const MAX_CANDIDATE_BYTES = 65536;
const MAX_RESULTS = 10000;

const Candidate = struct {
    chars: []u21,
    offsets: []u32,
    bonuses: []u8,

    fn init(allocator: Allocator, text: []const u8) !Candidate {
        const view = try std.unicode.Utf8View.init(text);
        const count = try std.unicode.utf8CountCodepoints(text);
        const chars = try allocator.alloc(u21, count);
        errdefer allocator.free(chars);
        const offsets = try allocator.alloc(u32, count);
        errdefer allocator.free(offsets);
        const bonuses = try allocator.alloc(u8, count);
        errdefer allocator.free(bonuses);
        var it = view.iterator();
        var i: usize = 0;
        var basename: usize = 0;
        var previous: u21 = 0;
        while (it.i < text.len) : (i += 1) {
            offsets[i] = @intCast(it.i);
            const char = it.nextCodepoint().?;
            chars[i] = fold(char);
            const boundary = i == 0 or separator(previous) or
                (previous >= 'a' and previous <= 'z' and char >= 'A' and char <= 'Z');
            bonuses[i] = 16 + @as(u8, if (boundary) 8 else 0);
            if (char == '/' or char == '\\') basename = i + 1;
            previous = char;
        }
        for (bonuses[basename..]) |*bonus| bonus.* += 8;
        return .{ .chars = chars, .offsets = offsets, .bonuses = bonuses };
    }

    fn deinit(self: Candidate, allocator: Allocator) void {
        allocator.free(self.chars);
        allocator.free(self.offsets);
        allocator.free(self.bonuses);
    }
};

fn fold(char: u21) u21 {
    return if (char >= 'A' and char <= 'Z') char + 32 else char;
}

fn separator(char: u21) bool {
    return switch (char) {
        '/', '\\', '_', '-', '.', ' ' => true,
        else => false,
    };
}

pub const Match = struct { id: usize, score: i64 };

fn better(a: Match, b: Match) bool {
    return a.score > b.score or (a.score == b.score and a.id < b.id);
}

pub const Engine = struct {
    allocator: Allocator,
    candidates: std.ArrayList(Candidate) = .empty,
    matches: std.ArrayList(Match) = .empty,
    output: std.ArrayList(u8) = .empty,
    total: u64 = 0,
    max_chars: usize = 0,

    pub fn init(allocator: Allocator) Engine {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Engine) void {
        for (self.candidates.items) |candidate| candidate.deinit(self.allocator);
        self.candidates.deinit(self.allocator);
        self.matches.deinit(self.allocator);
        self.output.deinit(self.allocator);
    }

    /// Validate the full batch first. Failed allocation rolls back this batch.
    pub fn add(self: *Engine, batch: []const u8) !void {
        if (batch.len == 0) return;
        if (batch[batch.len - 1] != 0) return error.InvalidInput;
        var strings = std.mem.splitScalar(u8, batch[0 .. batch.len - 1], 0);
        while (strings.next()) |text| {
            if (text.len > MAX_CANDIDATE_BYTES or !std.unicode.utf8ValidateSlice(text)) return error.InvalidInput;
        }
        const original_len = self.candidates.items.len;
        errdefer {
            for (self.candidates.items[original_len..]) |candidate| candidate.deinit(self.allocator);
            self.candidates.shrinkRetainingCapacity(original_len);
        }
        strings.reset();
        var max_chars = self.max_chars;
        while (strings.next()) |text| {
            const candidate = try Candidate.init(self.allocator, text);
            errdefer candidate.deinit(self.allocator);
            try self.candidates.append(self.allocator, candidate);
            max_chars = @max(max_chars, candidate.chars.len);
        }
        self.max_chars = max_chars;
    }

    /// Serialized by the Ruby session; no concurrent mutation on a handle.
    pub fn query(self: *Engine, text: []const u8, limit: usize) !void {
        if (text.len > MAX_QUERY_BYTES or limit > MAX_RESULTS or
            std.mem.indexOfScalar(u8, text, 0) != null or !std.unicode.utf8ValidateSlice(text)) return error.InvalidInput;
        var query_chars: [MAX_QUERY_BYTES]u21 = undefined;
        var iterator = (try std.unicode.Utf8View.init(text)).iterator();
        var length: usize = 0;
        while (iterator.nextCodepoint()) |char| {
            query_chars[length] = fold(char);
            length += 1;
        }
        const needle = query_chars[0..length];
        self.matches.clearRetainingCapacity();
        self.output.clearRetainingCapacity();
        self.total = 0;
        const rows = try self.allocator.alloc(i64, self.max_chars * 2);
        defer self.allocator.free(rows);
        try self.matches.ensureTotalCapacity(self.allocator, @min(limit, self.candidates.items.len));
        for (self.candidates.items, 0..) |candidate, id| {
            const value = score(candidate, needle, rows, null) orelse continue;
            self.total += 1;
            if (limit == 0) continue;
            const item = Match{ .id = id, .score = value };
            if (self.matches.items.len < limit) {
                self.matches.appendAssumeCapacity(item);
                self.siftUp(self.matches.items.len - 1);
            } else if (better(item, self.matches.items[0])) {
                self.matches.items[0] = item;
                self.siftDown();
            }
        }
        std.mem.sort(Match, self.matches.items, {}, struct {
            fn less(_: void, a: Match, b: Match) bool {
                return better(a, b);
            }
        }.less);
        try self.write(u64, self.total);
        try self.write(u32, @intCast(self.matches.items.len));
        for (self.matches.items) |item| {
            try self.write(u64, @intCast(item.id));
            try self.write(i64, item.score);
            try self.write(u32, @intCast(length));
            if (length == 0) continue;
            const candidate = self.candidates.items[item.id];
            const trace = try self.allocator.alloc(u32, candidate.chars.len * length);
            defer self.allocator.free(trace);
            _ = score(candidate, needle, rows, trace);
            const final = rows[(length % 2) * candidate.chars.len ..][0..candidate.chars.len];
            var end: usize = 0;
            for (final, 0..) |value, i| {
                if (value > final[end]) end = i;
            }
            var positions: [MAX_QUERY_BYTES]u32 = undefined;
            var row = length;
            while (row > 0) {
                row -= 1;
                positions[row] = candidate.offsets[end];
                end = trace[row * candidate.chars.len + end];
            }
            for (positions[0..length]) |position| try self.write(u32, position);
        }
    }

    fn write(self: *Engine, comptime T: type, value: T) !void {
        var buf: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &buf, value, .little);
        try self.output.appendSlice(self.allocator, &buf);
    }

    // Worst retained match at the root: O(N log K), never sort N matches.
    fn siftUp(self: *Engine, start: usize) void {
        var i = start;
        while (i > 0) {
            const parent = (i - 1) / 2;
            if (!better(self.matches.items[parent], self.matches.items[i])) break;
            std.mem.swap(Match, &self.matches.items[parent], &self.matches.items[i]);
            i = parent;
        }
    }

    fn siftDown(self: *Engine) void {
        var i: usize = 0;
        while (i * 2 + 1 < self.matches.items.len) {
            var child = i * 2 + 1;
            if (child + 1 < self.matches.items.len and better(self.matches.items[child], self.matches.items[child + 1])) child += 1;
            if (!better(self.matches.items[i], self.matches.items[child])) break;
            std.mem.swap(Match, &self.matches.items[i], &self.matches.items[child]);
            i = child;
        }
    }
};

fn score(candidate: Candidate, needle: []const u21, rows: []i64, trace: ?[]u32) ?i64 {
    if (needle.len == 0) return 0;
    const n = candidate.chars.len;
    if (needle.len > n) return null;
    // Reject non-matches in one pass before paying for the DP rows. In
    // particular, typing a missing character must not cost O(query length * N).
    var matched: usize = 0;
    for (candidate.chars) |char| {
        if (char == needle[matched]) matched += 1;
        if (matched == needle.len) break;
    }
    if (matched != needle.len) return null;
    @memset(rows[0..n], NEGATIVE);
    for (needle, 0..) |char, row| {
        const previous = rows[(row % 2) * n ..][0..n];
        const current = rows[((row + 1) % 2) * n ..][0..n];
        @memset(current, NEGATIVE);
        var prefix_score: i64 = NEGATIVE;
        var prefix_index: usize = 0;
        for (candidate.chars, 0..) |c, i| {
            if (i >= 2 and previous[i - 2] != NEGATIVE and previous[i - 2] + @as(i64, @intCast(i - 2)) > prefix_score) {
                prefix_score = previous[i - 2] + @as(i64, @intCast(i - 2));
                prefix_index = i - 2;
            }
            if (c != char) continue;
            if (row == 0) {
                current[i] = @as(i64, candidate.bonuses[i]) - @as(i64, @intCast(i));
            } else {
                var value: i64 = if (prefix_score == NEGATIVE) NEGATIVE else prefix_score - @as(i64, @intCast(i)) + 1;
                var source = prefix_index;
                if (i > 0 and previous[i - 1] != NEGATIVE and previous[i - 1] + 24 > value) {
                    value = previous[i - 1] + 24;
                    source = i - 1;
                }
                if (value == NEGATIVE) continue;
                current[i] = value + candidate.bonuses[i];
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

pub export fn core_fuzzy_results(handle: u64, length: *usize) ?[*]const u8 {
    length.* = 0;
    if (handle == 0) return null;
    const engine: *Engine = @ptrFromInt(handle);
    length.* = engine.output.items.len;
    return engine.output.items.ptr;
}

pub export fn core_fuzzy_destroy(handle: u64) void {
    if (handle == 0) return;
    const engine: *Engine = @ptrFromInt(handle);
    engine.deinit();
    ffi_allocator.destroy(engine);
}
