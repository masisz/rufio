//! BMP（Windows ビットマップ）の読み。無圧縮の 24bit / 32bit と 8bit パレットだけを扱う。
//! RLE 圧縮・1/4bit・OS/2 形式は非対応で、呼び出し側がテキスト表示にフォールバックする。
const std = @import("std");

pub const Error = error{
    InvalidBmp,
    UnsupportedBmp,
    TooLarge,
    OutOfMemory,
};

pub const Image = struct {
    width: u32,
    height: u32,
    channels: u8,
    pixels: []u8,

    pub fn deinit(self: *Image, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
        self.pixels = &.{};
    }
};

pub fn info(data: []const u8) Error![2]u32 {
    if (data.len < 26 or data[0] != 'B' or data[1] != 'M') return Error.InvalidBmp;
    const width = std.mem.readInt(i32, data[18..22], .little);
    const height = std.mem.readInt(i32, data[22..26], .little);
    if (width <= 0 or height == 0) return Error.InvalidBmp;
    return .{ @intCast(width), @intCast(@abs(height)) };
}

pub fn decode(alloc: std.mem.Allocator, data: []const u8, max_pixels: u64) Error!Image {
    if (data.len < 54 or data[0] != 'B' or data[1] != 'M') return Error.InvalidBmp;

    const pixel_offset = std.mem.readInt(u32, data[10..14], .little);
    const header_size = std.mem.readInt(u32, data[14..18], .little);
    if (header_size < 40) return Error.UnsupportedBmp; // OS/2 形式は非対応

    const width_raw = std.mem.readInt(i32, data[18..22], .little);
    const height_raw = std.mem.readInt(i32, data[22..26], .little);
    const bits = std.mem.readInt(u16, data[28..30], .little);
    const compression = std.mem.readInt(u32, data[30..34], .little);
    if (compression != 0 and compression != 3) return Error.UnsupportedBmp; // RLE は非対応
    if (width_raw <= 0 or height_raw == 0) return Error.InvalidBmp;
    if (bits != 8 and bits != 24 and bits != 32) return Error.UnsupportedBmp;

    const width: u32 = @intCast(width_raw);
    const height: u32 = @intCast(@abs(height_raw));
    // 高さが正なら下から上へ並ぶ（bottom-up）
    const bottom_up = height_raw > 0;
    if (width > 16384 or height > 16384) return Error.TooLarge;
    if (@as(u64, width) * height > max_pixels) return Error.TooLarge;

    // header_size の加算オーバーフローを防ぐ
    if (header_size > data.len or data.len - header_size < 14) return Error.InvalidBmp;
    // 8bit はパレット（BGRA の並び）を見る
    const palette_offset: usize = 14 + @as(usize, header_size);
    const palette: []const u8 = if (bits == 8) blk: {
        if (palette_offset + 4 > data.len) return Error.InvalidBmp;
        const end = @min(@as(usize, pixel_offset), data.len);
        if (end <= palette_offset) return Error.InvalidBmp;
        break :blk data[palette_offset..end];
    } else &.{};

    const raw_row_bytes = std.math.mul(usize, width, bits / 8) catch return Error.TooLarge;
    const src_stride = (raw_row_bytes + 3) & ~@as(usize, 3); // 4 バイト境界
    const required_body = std.math.mul(usize, src_stride, height) catch return Error.TooLarge;
    if (pixel_offset >= data.len) return Error.InvalidBmp;
    const body = data[pixel_offset..];
    if (body.len < required_body) return Error.InvalidBmp;

    const channels: u8 = if (bits == 32) 4 else 3;
    const out_bytes = std.math.mul(usize, std.math.mul(usize, width, height) catch return Error.TooLarge, channels) catch return Error.TooLarge;
    const pixels = alloc.alloc(u8, out_bytes) catch return Error.OutOfMemory;
    errdefer alloc.free(pixels);

    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const src_y = if (bottom_up) height - 1 - y else y;
        const row = body[src_y * src_stride ..];
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const out = (@as(usize, y) * width + x) * channels;
            switch (bits) {
                8 => {
                    const index = @as(usize, row[x]) * 4;
                    if (index + 2 >= palette.len) return Error.InvalidBmp;
                    pixels[out] = palette[index + 2]; // R
                    pixels[out + 1] = palette[index + 1]; // G
                    pixels[out + 2] = palette[index]; // B
                },
                24 => {
                    const base = @as(usize, x) * 3;
                    pixels[out] = row[base + 2];
                    pixels[out + 1] = row[base + 1];
                    pixels[out + 2] = row[base];
                },
                32 => {
                    const base = @as(usize, x) * 4;
                    pixels[out] = row[base + 2];
                    pixels[out + 1] = row[base + 1];
                    pixels[out + 2] = row[base];
                    pixels[out + 3] = row[base + 3];
                },
                else => unreachable,
            }
        }
    }

    return .{ .width = width, .height = height, .channels = channels, .pixels = pixels };
}
