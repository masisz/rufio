const std = @import("std");
const search = @import("search.zig");
const Matcher = search.Matcher;

fn naiveFind(hay: []const u8, needle: []const u8) ?usize {
    if (needle.len > hay.len) return null;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var ok = true;
        for (needle, 0..) |n, j| {
            if (std.ascii.toLower(hay[i + j]) != std.ascii.toLower(n)) {
                ok = false;
                break;
            }
        }
        if (ok) return i;
    }
    return null;
}

test "finds ascii case-insensitively" {
    const m = Matcher.init("world");
    try std.testing.expectEqual(@as(?usize, 6), m.find("Hello WORLD"));
    try std.testing.expectEqual(@as(?usize, 0), m.find("wOrLd"));
    try std.testing.expectEqual(@as(?usize, null), m.find("worl"));
    try std.testing.expectEqual(@as(?usize, null), m.find(""));
}

test "does not fold non-letters" {
    const m = Matcher.init("[a]");
    try std.testing.expectEqual(@as(?usize, null), m.find("{A}"));
    try std.testing.expectEqual(@as(?usize, 3), m.find("{A}[A]"));
    const at = Matcher.init("@");
    try std.testing.expectEqual(@as(?usize, null), at.find("`````"));
}

test "finds utf-8 needles" {
    const m = Matcher.init("日本語");
    try std.testing.expectEqual(@as(?usize, 3), m.find("あ日本語の検索"));
    try std.testing.expectEqual(@as(?usize, null), m.find("日本の検索"));
}

test "single byte needle" {
    const m = Matcher.init("Q");
    var buf: [100]u8 = undefined;
    @memset(&buf, 'x');
    try std.testing.expectEqual(@as(?usize, null), m.find(&buf));
    buf[77] = 'q';
    try std.testing.expectEqual(@as(?usize, 77), m.find(&buf));
}

test "matches naive search on random input" {
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rand = prng.random();
    const alphabet = "abAB_ \n.xyz";
    var hay: [700]u8 = undefined;
    var needle: [9]u8 = undefined;
    var iter: usize = 0;
    while (iter < 20000) : (iter += 1) {
        const hay_len = rand.uintLessThan(usize, hay.len);
        const needle_len = 1 + rand.uintLessThan(usize, needle.len);
        for (hay[0..hay_len]) |*b| b.* = alphabet[rand.uintLessThan(usize, alphabet.len)];
        for (needle[0..needle_len]) |*b| b.* = alphabet[rand.uintLessThan(usize, 4)];
        const m = Matcher.init(needle[0..needle_len]);
        try std.testing.expectEqual(naiveFind(hay[0..hay_len], needle[0..needle_len]), m.find(hay[0..hay_len]));
    }
}

test "counts newlines" {
    var buf: [300]u8 = undefined;
    @memset(&buf, 'a');
    buf[0] = '\n';
    buf[31] = '\n';
    buf[32] = '\n';
    buf[299] = '\n';
    try std.testing.expectEqual(@as(usize, 4), search.countNewlines(&buf));
    try std.testing.expectEqual(@as(usize, 2), search.countNewlines(buf[1..33]));
    try std.testing.expectEqual(@as(usize, 0), search.countNewlines(buf[33..299]));
}

test "extension helpers follow Ruby semantics" {
    try std.testing.expect(search.hasSuffixIgnoreCase("archive.TAR.GZ", ".tar.gz"));
    try std.testing.expect(!search.hasSuffixIgnoreCase("catalog", ".log"));
    try std.testing.expectEqualStrings(".PDF", search.extname("report.PDF"));
    try std.testing.expectEqualStrings("", search.extname(".pdf"));
    try std.testing.expectEqualStrings("", search.extname("Makefile"));
    try std.testing.expectEqualStrings(".gz", search.extname("a.tar.gz"));
}
