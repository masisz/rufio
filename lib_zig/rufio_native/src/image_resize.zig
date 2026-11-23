//! 画像の縮小。プレビューはペインに収める用途しかないので、拡大は行わない。
//!
//! 面積平均（box filter）で縮小する。整数比でなくても境界の画素を部分的に重み付けするため、
//! 単純な間引きと違ってモアレが出にくい。チャンネル数（3 = RGB / 4 = RGBA）はそのまま保つ。
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
    std.debug.assert(src.len >= @as(usize, src_w) * src_h * channels);
    std.debug.assert(dst.len >= @as(usize, dst_w) * dst_h * channels);
    if (dst_w == 0 or dst_h == 0 or src_w == 0 or src_h == 0) return;

    if (dst_w == src_w and dst_h == src_h) {
        @memcpy(dst[0 .. @as(usize, src_w) * src_h * channels], src[0 .. @as(usize, src_w) * src_h * channels]);
        return;
    }

    const x_ratio = @as(f64, @floatFromInt(src_w)) / @as(f64, @floatFromInt(dst_w));
    const y_ratio = @as(f64, @floatFromInt(src_h)) / @as(f64, @floatFromInt(dst_h));

    var out_y: u32 = 0;
    while (out_y < dst_h) : (out_y += 1) {
        // この出力行が対応する入力行の範囲（半開区間）
        const y0f = @as(f64, @floatFromInt(out_y)) * y_ratio;
        const y1f = y0f + y_ratio;
        const y0: u32 = @min(src_h - 1, @as(u32, @intFromFloat(@floor(y0f))));
        const y1: u32 = @min(src_h, @max(y0 + 1, @as(u32, @intFromFloat(@ceil(y1f)))));

        var out_x: u32 = 0;
        while (out_x < dst_w) : (out_x += 1) {
            const x0f = @as(f64, @floatFromInt(out_x)) * x_ratio;
            const x1f = x0f + x_ratio;
            const x0: u32 = @min(src_w - 1, @as(u32, @intFromFloat(@floor(x0f))));
            const x1: u32 = @min(src_w, @max(x0 + 1, @as(u32, @intFromFloat(@ceil(x1f)))));

            var sums: [4]u32 = .{ 0, 0, 0, 0 };
            var count: u32 = 0;
            var y = y0;
            while (y < y1) : (y += 1) {
                var x = x0;
                while (x < x1) : (x += 1) {
                    const offset = (@as(usize, y) * src_w + x) * channels;
                    var c: u8 = 0;
                    while (c < channels) : (c += 1) sums[c] += src[offset + c];
                    count += 1;
                }
            }
            if (count == 0) count = 1;

            const out_offset = (@as(usize, out_y) * dst_w + out_x) * channels;
            var c: u8 = 0;
            while (c < channels) : (c += 1) {
                dst[out_offset + c] = @intCast((sums[c] + count / 2) / count);
            }
        }
    }
}
