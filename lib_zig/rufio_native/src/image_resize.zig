//! 画像の縮小。プレビューはペインに収める用途しかないので、拡大は行わない。
//!
//! 面積平均（box filter）で縮小する。チャンネル数（3 = RGB / 4 = RGBA）はそのまま保つ。
const std = @import("std");

/// 縮小後の寸法を決める。元より大きくはしない（拡大は端末側の仕事）
pub fn fit(src_w: u32, src_h: u32, max_w: u32, max_h: u32) [2]u32 {
    if (src_w == 0 or src_h == 0) return .{ 0, 0 };
    if (max_w == 0 or max_h == 0) return .{ src_w, src_h };
    if (src_w <= max_w and src_h <= max_h) return .{ src_w, src_h };

    // 幅・高さのどちらも収まる倍率を選ぶ（アスペクト比を保つ）
    const scale_w = @as(f64, @floatFromInt(max_w)) / @as(f64, @floatFromInt(src_w));
    const scale_h = @as(f64, @floatFromInt(max_h)) / @as(f64, @floatFromInt(src_h));
    const scale = @min(scale_w, scale_h);
    const w: u32 = @max(1, @as(u32, @intFromFloat(@round(@as(f64, @floatFromInt(src_w)) * scale))));
    const h: u32 = @max(1, @as(u32, @intFromFloat(@round(@as(f64, @floatFromInt(src_h)) * scale))));
    return .{ @min(w, max_w), @min(h, max_h) };
}

pub const CancelError = error{Cancelled};

/// src（src_w x src_h x channels）を dst（dst_w x dst_h x channels）へ面積平均で縮小する。
/// dst は呼び出し側が確保する。dst が src より大きい場合は最近傍で埋める（拡大はしない前提）。
pub fn resize(
    src: []const u8,
    src_w: u32,
    src_h: u32,
    dst: []u8,
    dst_w: u32,
    dst_h: u32,
    channels: u8,
) void {
    resizeCancelable(src, src_w, src_h, dst, dst_w, dst_h, channels, null) catch unreachable;
}

/// キャンセルフラグを監視しながら縮小する。中断されたら error.Cancelled を返す。
pub fn resizeCancelable(
    src: []const u8,
    src_w: u32,
    src_h: u32,
    dst: []u8,
    dst_w: u32,
    dst_h: u32,
    channels: u8,
    cancelled: ?*const std.atomic.Value(bool),
) CancelError!void {
    std.debug.assert(src.len >= @as(usize, src_w) * src_h * channels);
    std.debug.assert(dst.len >= @as(usize, dst_w) * dst_h * channels);
    if (dst_w == 0 or dst_h == 0 or src_w == 0 or src_h == 0) return;

    if (dst_w == src_w and dst_h == src_h) {
        @memcpy(dst[0 .. @as(usize, src_w) * src_h * channels], src[0 .. @as(usize, src_w) * src_h * channels]);
        return;
    }

    if (channels == 3) {
        try resizeImpl(3, src, src_w, src_h, dst, dst_w, dst_h, cancelled);
    } else if (channels == 4) {
        try resizeImpl(4, src, src_w, src_h, dst, dst_w, dst_h, cancelled);
    } else {
        try resizeGeneric(src, src_w, src_h, dst, dst_w, dst_h, channels, cancelled);
    }
}

fn resizeImpl(
    comptime ch: usize,
    src: []const u8,
    src_w: u32,
    src_h: u32,
    dst: []u8,
    dst_w: u32,
    dst_h: u32,
    cancelled: ?*const std.atomic.Value(bool),
) CancelError!void {
    // 整数演算で各出力ピクセルの入力範囲を求める（内側ループから f64 を排除）
    const src_stride = @as(usize, src_w) * ch;
    const dst_stride = @as(usize, dst_w) * ch;

    var out_y: u32 = 0;
    while (out_y < dst_h) : (out_y += 1) {
        if (cancelled) |flag| {
            if (flag.load(.acquire)) return error.Cancelled;
        }
        const y0: u32 = @intCast((@as(u64, out_y) * src_h) / dst_h);
        const y1_raw: u32 = @intCast((@as(u64, out_y + 1) * src_h + dst_h - 1) / dst_h);
        const y1: u32 = @min(src_h, @max(y0 + 1, y1_raw));
        const y_span: u64 = y1 - y0;

        const dst_row = dst[@as(usize, out_y) * dst_stride ..];
        var out_x: u32 = 0;
        while (out_x < dst_w) : (out_x += 1) {
            const x0: u32 = @intCast((@as(u64, out_x) * src_w) / dst_w);
            const x1_raw: u32 = @intCast((@as(u64, out_x + 1) * src_w + dst_w - 1) / dst_w);
            const x1: u32 = @min(src_w, @max(x0 + 1, x1_raw));
            // 大きな画像を極小サイズへ縮小しても合計値が溢れないよう u64 を使う
            const count: u64 = y_span * @as(u64, x1 - x0);
            const half: u64 = count >> 1;

            var s0: u64 = 0;
            var s1: u64 = 0;
            var s2: u64 = 0;
            var s3: u64 = 0;

            var y = y0;
            while (y < y1) : (y += 1) {
                var offset = @as(usize, y) * src_stride + @as(usize, x0) * ch;
                var x = x0;
                while (x < x1) : (x += 1) {
                    s0 += src[offset];
                    s1 += src[offset + 1];
                    s2 += src[offset + 2];
                    if (ch == 4) s3 += src[offset + 3];
                    offset += ch;
                }
            }

            const out_offset = @as(usize, out_x) * ch;
            dst_row[out_offset] = @intCast((s0 + half) / count);
            dst_row[out_offset + 1] = @intCast((s1 + half) / count);
            dst_row[out_offset + 2] = @intCast((s2 + half) / count);
            if (ch == 4) dst_row[out_offset + 3] = @intCast((s3 + half) / count);
        }
    }
}

fn resizeGeneric(
    src: []const u8,
    src_w: u32,
    src_h: u32,
    dst: []u8,
    dst_w: u32,
    dst_h: u32,
    channels: u8,
    cancelled: ?*const std.atomic.Value(bool),
) CancelError!void {
    std.debug.assert(channels <= 4);
    var out_y: u32 = 0;
    while (out_y < dst_h) : (out_y += 1) {
        if (cancelled) |flag| {
            if (flag.load(.acquire)) return error.Cancelled;
        }
        const y0: u32 = @intCast((@as(u64, out_y) * src_h) / dst_h);
        const y1: u32 = @min(src_h, @max(y0 + 1, @as(u32, @intCast((@as(u64, out_y + 1) * src_h + dst_h - 1) / dst_h))));

        var out_x: u32 = 0;
        while (out_x < dst_w) : (out_x += 1) {
            const x0: u32 = @intCast((@as(u64, out_x) * src_w) / dst_w);
            const x1: u32 = @min(src_w, @max(x0 + 1, @as(u32, @intCast((@as(u64, out_x + 1) * src_w + dst_w - 1) / dst_w))));

            var sums: [4]u64 = .{ 0, 0, 0, 0 };
            const count: u64 = @as(u64, y1 - y0) * @as(u64, x1 - x0);
            var y = y0;
            while (y < y1) : (y += 1) {
                var x = x0;
                while (x < x1) : (x += 1) {
                    const offset = (@as(usize, y) * src_w + x) * channels;
                    var c: u8 = 0;
                    while (c < channels) : (c += 1) sums[c] += src[offset + c];
                }
            }

            const out_offset = (@as(usize, out_y) * dst_w + out_x) * channels;
            var c: u8 = 0;
            while (c < channels) : (c += 1) {
                dst[out_offset + c] = @intCast((sums[c] + count / 2) / count);
            }
        }
    }
}
