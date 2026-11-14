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
    try std.testing.expectEqual(@as(usize, 0), engine.candidates.items.len);
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
    try engine.query("", 1);
}
