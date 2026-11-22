const std = @import("std");
const fuzzy = @import("fuzzy.zig");

test "retains candidates, returns ranked top K and UTF-8 byte positions" {
    var engine = fuzzy.Engine.init(std.testing.allocator);
    defer engine.deinit();
    try engine.add("a___ab\x00ab\x00日本語/検索.rb\x00");
    try engine.query("ab", 1);
    try std.testing.expectEqual(@as(u64, 2), engine.total);
    try std.testing.expectEqual(@as(usize, 1), engine.matches.items.len);
    try std.testing.expectEqual(@as(usize, 1), engine.matches.items[0].id);
    try engine.query("日検", 10);
    try std.testing.expectEqual(@as(u64, 1), engine.total);
    const data = engine.output.items;
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, data[32..36], .little));
    try std.testing.expectEqual(@as(u32, 10), std.mem.readInt(u32, data[36..40], .little));
    try engine.add("ab\x00");
    try engine.query("ab", 10);
    try std.testing.expectEqual(@as(usize, 1), engine.matches.items[0].id);
    try std.testing.expectEqual(@as(usize, 3), engine.matches.items[1].id);
}

test "invalid UTF-8 and missing delimiters are rejected before adding" {
    var engine = fuzzy.Engine.init(std.testing.allocator);
    defer engine.deinit();
    try std.testing.expectError(error.InvalidInput, engine.add("ok\x00\xff\x00"));
    try std.testing.expectEqual(@as(usize, 0), engine.count());
    try std.testing.expectError(error.InvalidInput, engine.add("unterminated"));
    try std.testing.expectError(error.InvalidInput, engine.query("\xff", 1));
}

test "allocation failure releases partial candidates and search workspaces" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var engine = fuzzy.Engine.init(allocator);
    defer engine.deinit();
    try engine.add("a___ab\x00ab\x00日本語/検索.rb\x00");
    try engine.query("ab", 2);
    try engine.query("abb", 2);
    try engine.add("xab\x00");
    try engine.query("ab", 2);
    try engine.query("", 1);
}

test "allocation failure during parallel scoring releases worker buffers" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, parallelAllocationScenario, .{});
}

fn parallelAllocationScenario(allocator: std.mem.Allocator) !void {
    var engine = fuzzy.Engine.init(allocator);
    defer engine.deinit();
    engine.threads = 3;
    engine.min_parallel = 0;
    try engine.add("a___ab\x00ab\x00日本語/検索.rb\x00b\x00bab\x00");
    try engine.query("ab", 2);
    try engine.query("ab", 0);
}

/// Deterministic path-like candidates, NUL separated and terminated.
fn buildCandidates(allocator: std.mem.Allocator, count: usize, seed: u64) ![]u8 {
    const parts = [_][]const u8{ "lib", "src", "search", "controller", "Screen", "_", "-", ".rb", "/", "日本", "検索", "😀", "a", "B", "ctrl", "test" };
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (0..count) |_| {
        const pieces = random.intRangeAtMost(usize, 1, 12);
        for (0..pieces) |_| try out.appendSlice(allocator, parts[random.uintLessThan(usize, parts.len)]);
        try out.append(allocator, 0);
    }
    return out.toOwnedSlice(allocator);
}

fn freshOutput(allocator: std.mem.Allocator, batches: []const []const u8, text: []const u8, limit: usize) ![]u8 {
    var engine = fuzzy.Engine.init(allocator);
    defer engine.deinit();
    engine.threads = 1;
    for (batches) |batch| try engine.add(batch);
    try engine.query(text, limit);
    return allocator.dupe(u8, engine.output.items);
}

test "narrowing from the previous query returns identical results and scores fewer candidates" {
    const allocator = std.testing.allocator;
    const first = try buildCandidates(allocator, 3000, 1);
    defer allocator.free(first);
    const second = try buildCandidates(allocator, 500, 2);
    defer allocator.free(second);
    var engine = fuzzy.Engine.init(allocator);
    defer engine.deinit();
    engine.threads = 1;
    try engine.add(first);

    const typing = [_][]const u8{ "s", "sc", "sct", "sctr", "sctrl" };
    var previous_scanned: usize = engine.count();
    for (typing, 0..) |text, index| {
        try engine.query(text, 50);
        const expected = try freshOutput(allocator, &.{first}, text, 50);
        defer allocator.free(expected);
        try std.testing.expectEqualSlices(u8, expected, engine.output.items);
        if (index == 0) {
            try std.testing.expectEqual(engine.count(), engine.scanned);
        } else {
            try std.testing.expect(engine.scanned <= previous_scanned);
        }
        previous_scanned = engine.total;
    }
    try std.testing.expect(engine.scanned < engine.count());

    // Candidates added after the previous query are always scored.
    try engine.add(second);
    try engine.query("sctrl", 50);
    const appended = try freshOutput(allocator, &.{ first, second }, "sctrl", 50);
    defer allocator.free(appended);
    try std.testing.expectEqualSlices(u8, appended, engine.output.items);

    // Insertions anywhere keep the previous query as a subsequence.
    try engine.query("sXctrl", 50);
    const inserted = try freshOutput(allocator, &.{ first, second }, "sXctrl", 50);
    defer allocator.free(inserted);
    try std.testing.expectEqualSlices(u8, inserted, engine.output.items);

    // Shorter or unrelated queries scan everything again.
    for ([_][]const u8{ "sc", "日検", "", "B" }) |text| {
        try engine.query(text, 50);
        const expected = try freshOutput(allocator, &.{ first, second }, text, 50);
        defer allocator.free(expected);
        try std.testing.expectEqualSlices(u8, expected, engine.output.items);
        try std.testing.expectEqual(engine.count(), engine.scanned);
    }
}

test "case-folded queries narrow like the folded previous query" {
    const allocator = std.testing.allocator;
    var engine = fuzzy.Engine.init(allocator);
    defer engine.deinit();
    try engine.add("Search\x00xs\x00other\x00");
    try engine.query("S", 10);
    try engine.query("se", 10);
    try std.testing.expectEqual(@as(u64, 1), engine.total);
    try std.testing.expectEqual(@as(usize, 2), engine.scanned);
}

test "parallel scoring returns the same output as sequential scoring" {
    const allocator = std.testing.allocator;
    const first = try buildCandidates(allocator, 4000, 3);
    defer allocator.free(first);
    const second = try buildCandidates(allocator, 777, 4);
    defer allocator.free(second);
    var parallel = fuzzy.Engine.init(allocator);
    defer parallel.deinit();
    parallel.threads = 4;
    parallel.min_parallel = 0;
    try parallel.add(first);
    try parallel.add(second);
    const queries = [_][]const u8{ "", "s", "sc", "ctrl", "日検", "😀", "B", "zzzz", "lib/src" };
    for (queries) |text| {
        for ([_]usize{ 0, 1, 7, 1000, 10000 }) |limit| {
            try parallel.query(text, limit);
            const expected = try freshOutput(allocator, &.{ first, second }, text, limit);
            defer allocator.free(expected);
            try std.testing.expectEqualSlices(u8, expected, parallel.output.items);
        }
    }
}

test "candidate storage stays close to the UTF-8 size" {
    const allocator = std.testing.allocator;
    const batch = try buildCandidates(allocator, 2000, 5);
    defer allocator.free(batch);
    var engine = fuzzy.Engine.init(allocator);
    defer engine.deinit();
    try engine.add(batch);
    try engine.query("sc", 10);
    const text_bytes = batch.len - engine.count();
    // At most twice the text (list growth) plus a small fixed cost per candidate.
    try std.testing.expect(engine.storageBytes() <= text_bytes * 2 + engine.count() * 32);
}

test "position-limited queries rank identically and omit positions after the limit" {
    var full = fuzzy.Engine.init(std.testing.allocator);
    defer full.deinit();
    var limited = fuzzy.Engine.init(std.testing.allocator);
    defer limited.deinit();
    const batch = "src/search_controller.rb\x00lib/sc.rb\x00docs/s_c_notes.md\x00test/scope_check.rb\x00";
    try full.add(batch);
    try limited.add(batch);
    try full.query("sc", 10);
    try limited.queryPositions("sc", 10, 2);
    try std.testing.expectEqual(full.total, limited.total);
    try std.testing.expectEqualSlices(fuzzy.Match, full.matches.items, limited.matches.items);
    // Each record: id u64, score i64, count u32, positions; after 12 header bytes.
    var a: usize = 12;
    var b: usize = 12;
    for (0..full.matches.items.len) |rank| {
        const count = std.mem.readInt(u32, full.output.items[a + 16 ..][0..4], .little);
        const limited_count = std.mem.readInt(u32, limited.output.items[b + 16 ..][0..4], .little);
        try std.testing.expectEqualSlices(u8, full.output.items[a..][0..16], limited.output.items[b..][0..16]);
        if (rank < 2) {
            try std.testing.expectEqual(count, limited_count);
            try std.testing.expectEqualSlices(u8, full.output.items[a + 20 ..][0 .. count * 4], limited.output.items[b + 20 ..][0 .. count * 4]);
        } else {
            try std.testing.expectEqual(@as(u32, 0), limited_count);
        }
        a += 20 + count * 4;
        b += 20 + limited_count * 4;
    }
    try std.testing.expectEqual(full.output.items.len, a);
    try std.testing.expectEqual(limited.output.items.len, b);
}
