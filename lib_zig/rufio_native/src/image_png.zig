//! PNG の読み書き。zlib は Zig 標準ライブラリ（std.compress.flate）を使う。
//!
//! 読み: 8bit / 16bit（上位 8bit だけ使う）の グレースケール・RGB・パレット・アルファ付きを
//! RGB か RGBA の生画素に展開する。インターレース（Adam7）は非対応で、呼び出し側が
//! テキスト表示にフォールバックする。
//! 書き: フィルタ 0（None）固定で zlib 圧縮する。端末へ渡すだけなので圧縮率より速さを採る。
const std = @import("std");
const flate = std.compress.flate;
const Crc32 = std.hash.Crc32;

pub const SIGNATURE = "\x89PNG\r\n\x1a\n";

pub const Error = error{
    InvalidPng,
    UnsupportedPng,
    TooLarge,
    OutOfMemory,
};

pub const Image = struct {
    width: u32,
    height: u32,
    channels: u8, // 3 = RGB / 4 = RGBA
    pixels: []u8,

    pub fn deinit(self: *Image, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
        self.pixels = &.{};
    }
};

const ColorType = enum(u8) {
    gray = 0,
    rgb = 2,
    palette = 3,
    gray_alpha = 4,
    rgba = 6,
};

/// 見出しだけを読んで寸法を返す（画素は展開しない）
pub fn info(data: []const u8) Error![2]u32 {
    if (data.len < 24) return Error.InvalidPng;
    if (!std.mem.eql(u8, data[0..8], SIGNATURE)) return Error.InvalidPng;
    if (!std.mem.eql(u8, data[12..16], "IHDR")) return Error.InvalidPng;
    const width = std.mem.readInt(u32, data[16..20], .big);
    const height = std.mem.readInt(u32, data[20..24], .big);
    if (width == 0 or height == 0) return Error.InvalidPng;
    return .{ width, height };
}

/// PNG を RGB / RGBA の生画素に展開する
pub fn decode(alloc: std.mem.Allocator, data: []const u8, max_pixels: u64) Error!Image {
    if (data.len < 8 or !std.mem.eql(u8, data[0..8], SIGNATURE)) return Error.InvalidPng;

    var width: u32 = 0;
    var height: u32 = 0;
    var bit_depth: u8 = 0;
    var color_type: ColorType = .rgb;
    var palette: []u8 = &.{};
    var palette_alpha: []u8 = &.{};
    defer alloc.free(palette);
    defer alloc.free(palette_alpha);

    // IDAT はファイル内で分割されていることがあるので、まとめてから伸長する
    var idat: std.ArrayList(u8) = .empty;
    defer idat.deinit(alloc);

    var offset: usize = 8;
    var seen_ihdr = false;
    while (offset + 8 <= data.len) {
        const length = std.mem.readInt(u32, data[offset..][0..4], .big);
        const kind = data[offset + 4 ..][0..4];
        const body_start = offset + 8;
        if (length > data.len or body_start + length + 4 > data.len) return Error.InvalidPng;
        const body = data[body_start .. body_start + length];

        if (std.mem.eql(u8, kind, "IHDR")) {
            if (length < 13) return Error.InvalidPng;
            width = std.mem.readInt(u32, body[0..4], .big);
            height = std.mem.readInt(u32, body[4..8], .big);
            bit_depth = body[8];
            color_type = std.enums.fromInt(ColorType, body[9]) orelse return Error.UnsupportedPng;
            if (body[12] != 0) return Error.UnsupportedPng; // インターレースは非対応
            if (bit_depth != 8 and bit_depth != 16) return Error.UnsupportedPng;
            if (width == 0 or height == 0) return Error.InvalidPng;
            if (@as(u64, width) * height > max_pixels) return Error.TooLarge;
            seen_ihdr = true;
        } else if (std.mem.eql(u8, kind, "PLTE")) {
            palette = try alloc.realloc(palette, length);
            @memcpy(palette, body);
        } else if (std.mem.eql(u8, kind, "tRNS")) {
            if (color_type == .palette) {
                palette_alpha = try alloc.realloc(palette_alpha, length);
                @memcpy(palette_alpha, body);
            }
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            try idat.appendSlice(alloc, body);
        } else if (std.mem.eql(u8, kind, "IEND")) {
            break;
        }

        offset = body_start + length + 4; // CRC は読み飛ばす（端末に出すだけなので検証しない）
    }
    if (!seen_ihdr or idat.items.len == 0) return Error.InvalidPng;

    const samples = samplesPerPixel(color_type);
    const bytes_per_sample: u8 = if (bit_depth == 16) 2 else 1;
    const bytes_per_pixel: usize = @as(usize, samples) * bytes_per_sample;
    const stride = @as(usize, width) * bytes_per_pixel;
    const expected = (stride + 1) * height; // 各行の先頭にフィルタ種別が 1 バイト付く

    const raw = try inflate(alloc, idat.items, expected);
    defer alloc.free(raw);
    if (raw.len < expected) return Error.InvalidPng;

    unfilter(raw, width, height, stride, bytes_per_pixel);

    const out_channels: u8 = if (hasAlpha(color_type, palette_alpha.len)) 4 else 3;
    const pixels = try alloc.alloc(u8, @as(usize, width) * height * out_channels);
    errdefer alloc.free(pixels);
    try expand(raw, pixels, width, height, stride, color_type, bit_depth, out_channels, palette, palette_alpha);

    return .{ .width = width, .height = height, .channels = out_channels, .pixels = pixels };
}

/// RGB / RGBA の生画素を PNG にする（フィルタなし・zlib 圧縮）
pub fn encode(alloc: std.mem.Allocator, pixels: []const u8, width: u32, height: u32, channels: u8) Error![]u8 {
    std.debug.assert(channels == 3 or channels == 4);
    const stride = @as(usize, width) * channels;
    if (pixels.len < stride * height) return Error.InvalidPng;

    // フィルタ種別 0 を各行の先頭に付けて zlib 圧縮する
    var compressed = std.Io.Writer.Allocating.initCapacity(alloc, 64 * 1024) catch return Error.OutOfMemory;
    defer compressed.deinit();
    const window = alloc.alloc(u8, flate.max_window_len) catch return Error.OutOfMemory;
    defer alloc.free(window);
    var deflate = flate.Compress.init(&compressed.writer, window, .zlib, .default) catch return Error.OutOfMemory;
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        deflate.writer.writeAll(&.{0}) catch return Error.OutOfMemory;
        deflate.writer.writeAll(pixels[@as(usize, y) * stride ..][0..stride]) catch return Error.OutOfMemory;
    }
    deflate.finish() catch return Error.OutOfMemory;
    compressed.writer.flush() catch return Error.OutOfMemory;
    const body = compressed.written();

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    try out.appendSlice(alloc, SIGNATURE);

    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], width, .big);
    std.mem.writeInt(u32, ihdr[4..8], height, .big);
    ihdr[8] = 8; // bit depth
    ihdr[9] = if (channels == 4) 6 else 2; // RGBA / RGB
    ihdr[10] = 0; // compression
    ihdr[11] = 0; // filter
    ihdr[12] = 0; // interlace
    try writeChunk(alloc, &out, "IHDR", &ihdr);
    try writeChunk(alloc, &out, "IDAT", body);
    try writeChunk(alloc, &out, "IEND", &.{});
    return out.toOwnedSlice(alloc);
}

fn writeChunk(alloc: std.mem.Allocator, out: *std.ArrayList(u8), kind: []const u8, body: []const u8) Error!void {
    var length: [4]u8 = undefined;
    std.mem.writeInt(u32, &length, @intCast(body.len), .big);
    try out.appendSlice(alloc, &length);
    try out.appendSlice(alloc, kind);
    try out.appendSlice(alloc, body);

    var crc: Crc32 = .init();
    crc.update(kind);
    crc.update(body);
    var checksum: [4]u8 = undefined;
    std.mem.writeInt(u32, &checksum, crc.final(), .big);
    try out.appendSlice(alloc, &checksum);
}

fn inflate(alloc: std.mem.Allocator, zlib_data: []const u8, expected: usize) Error![]u8 {
    var reader: std.Io.Reader = .fixed(zlib_data);
    var out = std.Io.Writer.Allocating.initCapacity(alloc, @min(expected + 1024, 8 * 1024 * 1024)) catch
        return Error.OutOfMemory;
    defer out.deinit();
    const window = alloc.alloc(u8, flate.max_window_len) catch return Error.OutOfMemory;
    defer alloc.free(window);
    var decompress: flate.Decompress = .init(&reader, .zlib, window);
    _ = decompress.reader.streamRemaining(&out.writer) catch return Error.InvalidPng;
    out.writer.flush() catch return Error.OutOfMemory;
    return alloc.dupe(u8, out.written()) catch return Error.OutOfMemory;
}

fn samplesPerPixel(color_type: ColorType) u8 {
    return switch (color_type) {
        .gray => 1,
        .rgb => 3,
        .palette => 1,
        .gray_alpha => 2,
        .rgba => 4,
    };
}

fn hasAlpha(color_type: ColorType, palette_alpha_len: usize) bool {
    return switch (color_type) {
        .rgba, .gray_alpha => true,
        .palette => palette_alpha_len > 0,
        else => false,
    };
}

/// PNG の行フィルタを戻す（raw は [フィルタ種別][行データ] の繰り返し）
fn unfilter(raw: []u8, width: u32, height: u32, stride: usize, bpp: usize) void {
    _ = width;
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const row_start = y * (stride + 1);
        const filter = raw[row_start];
        const row = raw[row_start + 1 ..][0..stride];
        const prev: ?[]const u8 = if (y == 0) null else raw[(y - 1) * (stride + 1) + 1 ..][0..stride];

        switch (filter) {
            0 => {},
            1 => { // Sub
                var i = bpp;
                while (i < stride) : (i += 1) row[i] = row[i] +% row[i - bpp];
            },
            2 => { // Up
                if (prev) |up| {
                    var i: usize = 0;
                    while (i < stride) : (i += 1) row[i] = row[i] +% up[i];
                }
            },
            3 => { // Average
                var i: usize = 0;
                while (i < stride) : (i += 1) {
                    const left: u16 = if (i >= bpp) row[i - bpp] else 0;
                    const up: u16 = if (prev) |p| p[i] else 0;
                    row[i] = row[i] +% @as(u8, @intCast((left + up) / 2));
                }
            },
            4 => { // Paeth
                var i: usize = 0;
                while (i < stride) : (i += 1) {
                    const a: i16 = if (i >= bpp) row[i - bpp] else 0;
                    const b: i16 = if (prev) |p| p[i] else 0;
                    const c: i16 = if (i >= bpp and prev != null) prev.?[i - bpp] else 0;
                    const p = a + b - c;
                    const pa = @abs(p - a);
                    const pb = @abs(p - b);
                    const pc = @abs(p - c);
                    const pred: u8 = if (pa <= pb and pa <= pc)
                        @intCast(a)
                    else if (pb <= pc)
                        @intCast(b)
                    else
                        @intCast(c);
                    row[i] = row[i] +% pred;
                }
            },
            else => {}, // 未知のフィルタは素通し（壊れた画像でも落ちない）
        }
    }
}

/// フィルタを戻した行を RGB / RGBA に並べ替える
fn expand(
    raw: []const u8,
    out: []u8,
    width: u32,
    height: u32,
    stride: usize,
    color_type: ColorType,
    bit_depth: u8,
    out_channels: u8,
    palette: []const u8,
    palette_alpha: []const u8,
) Error!void {
    const step: usize = if (bit_depth == 16) 2 else 1;
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const row = raw[y * (stride + 1) + 1 ..][0..stride];
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const out_offset = (@as(usize, y) * width + x) * out_channels;
            switch (color_type) {
                .gray => {
                    const value = row[x * step];
                    out[out_offset] = value;
                    out[out_offset + 1] = value;
                    out[out_offset + 2] = value;
                },
                .gray_alpha => {
                    const value = row[x * 2 * step];
                    out[out_offset] = value;
                    out[out_offset + 1] = value;
                    out[out_offset + 2] = value;
                    out[out_offset + 3] = row[x * 2 * step + step];
                },
                .rgb => {
                    const base = x * 3 * step;
                    out[out_offset] = row[base];
                    out[out_offset + 1] = row[base + step];
                    out[out_offset + 2] = row[base + 2 * step];
                },
                .rgba => {
                    const base = x * 4 * step;
                    out[out_offset] = row[base];
                    out[out_offset + 1] = row[base + step];
                    out[out_offset + 2] = row[base + 2 * step];
                    out[out_offset + 3] = row[base + 3 * step];
                },
                .palette => {
                    const index = row[x];
                    const base = @as(usize, index) * 3;
                    if (base + 2 >= palette.len) return Error.InvalidPng;
                    out[out_offset] = palette[base];
                    out[out_offset + 1] = palette[base + 1];
                    out[out_offset + 2] = palette[base + 2];
                    if (out_channels == 4) {
                        out[out_offset + 3] = if (index < palette_alpha.len) palette_alpha[index] else 255;
                    }
                },
            }
        }
    }
}
