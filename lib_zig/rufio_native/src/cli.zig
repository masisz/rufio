//! ripgrep と同条件で比較するためのベンチマーク用 CLI。
//! 使い方: rufio_search [-j N] [-r N] QUERY DIR...
//! -r N: キャッシュを使って同じ検索を N 回繰り返し、各回の所要時間を標準エラーに出す（G mode の再検索を再現）
//! 出力は rg -n と同じ `path:line:text` 形式（text はマッチ周辺の最大 1KB）。
const std = @import("std");
const c = std.c;
const search = @import("search.zig");
const os = @import("os.zig");

fn writeAll(bytes: []const u8) void {
    os.writeAll(1, bytes);
}

pub fn main(init: std.process.Init.Minimal) !void {
    var args = try init.args.iterateAllocator(std.heap.c_allocator);
    defer args.deinit();
    _ = args.skip();
    var threads: usize = 0;
    var repeat: usize = 0;
    var query: ?[]const u8 = null;
    var roots: std.ArrayList(u8) = .empty;
    const alloc = std.heap.c_allocator;
    defer roots.deinit(alloc);

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-j")) {
            threads = try std.fmt.parseInt(usize, args.next() orelse return error.MissingValue, 10);
        } else if (std.mem.eql(u8, arg, "-r")) {
            repeat = try std.fmt.parseInt(usize, args.next() orelse return error.MissingValue, 10);
        } else if (query == null) {
            query = arg;
        } else {
            if (roots.items.len > 0) try roots.append(alloc, 0);
            try roots.appendSlice(alloc, std.mem.trimEnd(u8, arg, "/"));
        }
    }
    const q = query orelse {
        writeAll("usage: rufio_search [-j N] [-r N] QUERY DIR...\n");
        return;
    };
    if (roots.items.len == 0) try roots.append(alloc, '.');

    if (repeat > 0) {
        const cache = try search.Cache.create(256 * 1024 * 1024);
        defer cache.destroy();
        var i: usize = 0;
        while (i < repeat) : (i += 1) {
            const t0 = os.nowNs();
            const lines = try runSearch(roots.items, q, threads, cache, i + 1 == repeat);
            const ms = @as(f64, @floatFromInt(os.nowNs() - t0)) / 1e6;
            var msg: [128]u8 = undefined;
            os.writeAll(2, try std.fmt.bufPrint(&msg, "run {d}: {d:.1} ms, {d} lines, cache {d} MB\n", .{ i + 1, ms, lines, cache.cachedBytes() >> 20 }));
        }
        return;
    }
    _ = try runSearch(roots.items, q, threads, null, true);
}

fn runSearch(roots: []const u8, q: []const u8, threads: usize, cache: ?*search.Cache, print: bool) !usize {
    const alloc = std.heap.c_allocator;
    const s = try search.Search.create(roots, q, "", "", threads, cache);
    defer s.destroy();

    var lines: usize = 0;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    var line_buf: [24]u8 = undefined;
    while (true) {
        const state = s.getState();
        const data = s.drain();
        var pos: usize = 0;
        while (pos + search.RECORD_HEADER <= data.len) {
            const kind = data[pos];
            const line = std.mem.readInt(u64, data[pos + 5 ..][0..8], .little);
            const a_len = std.mem.readInt(u32, data[pos + 17 ..][0..4], .little);
            const b_len = std.mem.readInt(u32, data[pos + 21 ..][0..4], .little);
            const a = data[pos + search.RECORD_HEADER ..][0..a_len];
            const b = data[pos + search.RECORD_HEADER + a_len ..][0..b_len];
            pos += search.RECORD_HEADER + a_len + b_len;
            if (kind != @intFromEnum(search.Kind.match)) continue;
            lines += 1;
            if (!print) continue;
            try out.appendSlice(alloc, a);
            try out.appendSlice(alloc, try std.fmt.bufPrint(&line_buf, ":{d}:", .{line}));
            try out.appendSlice(alloc, std.mem.trimEnd(u8, b, "\r\n"));
            try out.append(alloc, '\n');
        }
        if (out.items.len >= 1 << 16) {
            writeAll(out.items);
            out.clearRetainingCapacity();
        }
        if (data.len == 0) {
            if (state != .scanning) break;
            os.sleepMicros(50);
        }
    }
    writeAll(out.items);
    return lines;
}
