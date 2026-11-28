//! PNG の読み書き。zlib は Zig 標準ライブラリ（std.compress.flate）を使う。
//!
//! 読み: 8bit / 16bit（上位 8bit だけ使う）の グレースケール・RGB・パレット・アルファ付きを
//! RGB か RGBA の生画素に展開する。インターレース（Adam7）は非対応で、呼び出し側が
//! テキスト表示にフォールバックする。
//! 書き: フィルタ 0（None）・高速圧縮（.fastest）で zlib 圧縮する。端末へ渡すだけなので圧縮率より速さを採る。
const std = @import("std");
const flate = std.compress.flate;
const Crc32 = std.hash.Crc32;

pub const SIGNATURE = "\x89PNG\r\n\x1a\n";
/// 1 辺の最大ピクセル数（細工した極端な縦長・横長画像を拒否する）
const MAX_DIMENSION: u32 = 16384;
/// 伸長後の生データ（フィルタバイト込み）の上限（decompression bomb 対策）
const MAX_DECODED_BYTES: usize = 256 * 1024 * 1024;

pub const Error = error{
    InvalidPng,
    UnsupportedPng,
    TooLarge,
    OutOfMemory,
    Cancelled,
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

pub const Meta = struct {
    width: u32,
    height: u32,
    channels: u8,
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

/// 画素を展開せずにチャンク構造・寸法・チャンネル数を検査する（軽量メタ検証用）
pub fn inspect(data: []const u8, max_pixels: u64) Error!Meta {
    return inspectInternal(null, data, max_pixels, null, false);
}

/// チャンク構造に加えて IDAT の伸長サイズ（decompression bomb 等）も検証する（縮小不要 PNG の直送判定用）
pub fn inspectVerified(
    alloc: std.mem.Allocator,
    data: []const u8,
    max_pixels: u64,
    cancelled: ?*const std.atomic.Value(bool),
) Error!Meta {
    return inspectInternal(alloc, data, max_pixels, cancelled, true);
}

fn inspectInternal(
    maybe_alloc: ?std.mem.Allocator,
    data: []const u8,
    max_pixels: u64,
    cancelled: ?*const std.atomic.Value(bool),
    verify_idat: bool,
) Error!Meta {
    if (data.len < 8 or !std.mem.eql(u8, data[0..8], SIGNATURE)) return Error.InvalidPng;

    var width: u32 = 0;
    var height: u32 = 0;
    var bit_depth: u8 = 0;
    var color_type: ColorType = .rgb;
    var palette_alpha_len: usize = 0;
    var seen_ihdr = false;
    var seen_plte = false;
    var seen_idat = false;
    var seen_iend = false;

    var idat: std.ArrayList(u8) = .empty;
    defer if (maybe_alloc) |a| idat.deinit(a);

    var offset: usize = 8;
    while (offset + 8 <= data.len) {
        const length = std.mem.readInt(u32, data[offset..][0..4], .big);
        const kind = data[offset + 4 ..][0..4];
        const body_start = offset + 8;
        // 32bit 加算オーバーフローを避けて減算で境界検証する
        if (data.len - body_start < 4 or length > data.len - body_start - 4) return Error.InvalidPng;
        const body = data[body_start .. body_start + length];

        if (std.mem.eql(u8, kind, "IHDR")) {
            if (seen_ihdr or offset != 8 or length != 13) return Error.InvalidPng;
            width = std.mem.readInt(u32, body[0..4], .big);
            height = std.mem.readInt(u32, body[4..8], .big);
            bit_depth = body[8];
            color_type = std.enums.fromInt(ColorType, body[9]) orelse return Error.UnsupportedPng;
            if (body[10] != 0 or body[11] != 0 or body[12] != 0) return Error.UnsupportedPng;
            if (bit_depth != 8 and bit_depth != 16) return Error.UnsupportedPng;
            if (color_type == .palette and bit_depth != 8) return Error.InvalidPng;
            if (width == 0 or height == 0) return Error.InvalidPng;
            if (width > MAX_DIMENSION or height > MAX_DIMENSION) return Error.TooLarge;
            if (@as(u64, width) * height > max_pixels) return Error.TooLarge;
            seen_ihdr = true;
        } else if (std.mem.eql(u8, kind, "PLTE")) {
            if (seen_plte or length == 0 or length > 768 or length % 3 != 0) return Error.InvalidPng;
            seen_plte = true;
        } else if (std.mem.eql(u8, kind, "tRNS")) {
            if (color_type == .palette) {
                if (length > 256) return Error.InvalidPng;
                palette_alpha_len = length;
            }
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            if (length > 0) {
                seen_idat = true;
                if (verify_idat) {
                    try idat.appendSlice(maybe_alloc.?, body);
                }
            }
        } else if (std.mem.eql(u8, kind, "IEND")) {
            // IEND は長さ 0 かつ末尾チャンクでなければならない（末尾余剰データの直送を防ぐ）
            if (length != 0 or body_start + 4 != data.len) return Error.InvalidPng;
            seen_iend = true;
            break;
        }

        offset = body_start + length + 4;
    }

    if (!seen_ihdr or !seen_idat or !seen_iend) return Error.InvalidPng;
    if (color_type == .palette and !seen_plte) return Error.InvalidPng;

    if (verify_idat) {
        const samples = samplesPerPixel(color_type);
        const bytes_per_sample: u8 = if (bit_depth == 16) 2 else 1;
        const bytes_per_pixel: usize = @as(usize, samples) * bytes_per_sample;
        const stride = std.math.mul(usize, width, bytes_per_pixel) catch return Error.TooLarge;
        const row_bytes = std.math.add(usize, stride, 1) catch return Error.TooLarge;
        const expected = std.math.mul(usize, row_bytes, height) catch return Error.TooLarge;
        if (expected > MAX_DECODED_BYTES) return Error.TooLarge;
        try verifyInflate(maybe_alloc.?, idat.items, expected, cancelled);
    }

    const channels: u8 = if (hasAlpha(color_type, palette_alpha_len)) 4 else 3;
    return .{ .width = width, .height = height, .channels = channels };
}

/// PNG を RGB / RGBA の生画素に展開する
pub fn decode(alloc: std.mem.Allocator, data: []const u8, max_pixels: u64) Error!Image {
    return decodeCancelable(alloc, data, max_pixels, null);
}

/// キャンセルフラグを監視しながら PNG を RGB / RGBA の生画素に展開する
pub fn decodeCancelable(
    alloc: std.mem.Allocator,
    data: []const u8,
    max_pixels: u64,
    cancelled: ?*const std.atomic.Value(bool),
) Error!Image {
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
    var seen_plte = false;
    while (offset + 8 <= data.len) {
        const length = std.mem.readInt(u32, data[offset..][0..4], .big);
        const kind = data[offset + 4 ..][0..4];
        const body_start = offset + 8;
        if (data.len - body_start < 4 or length > data.len - body_start - 4) return Error.InvalidPng;
        const body = data[body_start .. body_start + length];

        if (std.mem.eql(u8, kind, "IHDR")) {
            if (seen_ihdr or offset != 8 or length != 13) return Error.InvalidPng;
            width = std.mem.readInt(u32, body[0..4], .big);
            height = std.mem.readInt(u32, body[4..8], .big);
            bit_depth = body[8];
            color_type = std.enums.fromInt(ColorType, body[9]) orelse return Error.UnsupportedPng;
            if (body[10] != 0 or body[11] != 0 or body[12] != 0) return Error.UnsupportedPng; // インターレース・未知圧縮/フィルタは非対応
            if (bit_depth != 8 and bit_depth != 16) return Error.UnsupportedPng;
            if (color_type == .palette and bit_depth != 8) return Error.InvalidPng;
            if (width == 0 or height == 0) return Error.InvalidPng;
            if (width > MAX_DIMENSION or height > MAX_DIMENSION) return Error.TooLarge;
            if (@as(u64, width) * height > max_pixels) return Error.TooLarge;
            seen_ihdr = true;
        } else if (std.mem.eql(u8, kind, "PLTE")) {
            if (seen_plte or length == 0 or length > 768 or length % 3 != 0) return Error.InvalidPng;
            palette = try alloc.realloc(palette, length);
            @memcpy(palette, body);
            seen_plte = true;
        } else if (std.mem.eql(u8, kind, "tRNS")) {
            if (color_type == .palette) {
                if (length > 256) return Error.InvalidPng;
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
    if (color_type == .palette and !seen_plte) return Error.InvalidPng;

    const samples = samplesPerPixel(color_type);
    const bytes_per_sample: u8 = if (bit_depth == 16) 2 else 1;
    const bytes_per_pixel: usize = @as(usize, samples) * bytes_per_sample;
    const stride = std.math.mul(usize, width, bytes_per_pixel) catch return Error.TooLarge;
    const row_bytes = std.math.add(usize, stride, 1) catch return Error.TooLarge;
    const expected = std.math.mul(usize, row_bytes, height) catch return Error.TooLarge;
    if (expected > MAX_DECODED_BYTES) return Error.TooLarge;

    const raw = try inflate(alloc, idat.items, expected, cancelled);
    defer alloc.free(raw);
    if (raw.len != expected) return Error.InvalidPng;
    if (cancelled) |flag| {
        if (flag.load(.acquire)) return Error.Cancelled;
    }

    unfilter(raw, width, height, stride, bytes_per_pixel);

    const out_channels: u8 = if (hasAlpha(color_type, palette_alpha.len)) 4 else 3;
    const pixel_bytes = std.math.mul(usize, std.math.mul(usize, width, height) catch return Error.TooLarge, out_channels) catch return Error.TooLarge;
    const pixels = try alloc.alloc(u8, pixel_bytes);
    errdefer alloc.free(pixels);
    try expand(raw, pixels, width, height, stride, color_type, bit_depth, out_channels, palette, palette_alpha);

    return .{ .width = width, .height = height, .channels = out_channels, .pixels = pixels };
}

/// RGB / RGBA の生画素を PNG にする（フィルタなし・高速 zlib 圧縮）
pub fn encode(alloc: std.mem.Allocator, pixels: []const u8, width: u32, height: u32, channels: u8) Error![]u8 {
    std.debug.assert(channels == 3 or channels == 4);
    const stride = @as(usize, width) * channels;
    if (pixels.len < stride * height) return Error.InvalidPng;

    // フィルタ種別 0 を各行の先頭に付けて高速 zlib 圧縮（level_1）する。端末送信用のため速度と転送量のバランスを採る
    var compressed = std.Io.Writer.Allocating.initCapacity(alloc, @max(@as(usize, 64 * 1024), stride * height / 4)) catch
        return Error.OutOfMemory;
    defer compressed.deinit();
    const window = alloc.alloc(u8, flate.max_window_len) catch return Error.OutOfMemory;
    defer alloc.free(window);
    var deflate = flate.Compress.init(&compressed.writer, window, .zlib, .fastest) catch return Error.OutOfMemory;
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
    try out.ensureTotalCapacity(alloc, SIGNATURE.len + 25 + 12 + body.len + 12);
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

fn inflate(
    alloc: std.mem.Allocator,
    zlib_data: []const u8,
    expected: usize,
    cancelled: ?*const std.atomic.Value(bool),
) Error![]u8 {
    var reader: std.Io.Reader = .fixed(zlib_data);
    var out = std.Io.Writer.Allocating.initCapacity(alloc, @min(expected + 16, 32 * 1024 * 1024)) catch
        return Error.OutOfMemory;
    errdefer out.deinit();
    const window = alloc.alloc(u8, flate.max_window_len) catch return Error.OutOfMemory;
    defer alloc.free(window);
    var decompress: flate.Decompress = .init(&reader, .zlib, window);

    // 展開サイズが expected を 1 バイトでも超えたら即座に打ち切る（decompression bomb 対策）。
    // 64KB ごとにキャンセルも確認する
    var total: usize = 0;
    const limit = std.math.add(usize, expected, 1) catch return Error.TooLarge;
    while (total < limit) {
        if (cancelled) |flag| {
            if (flag.load(.acquire)) return Error.Cancelled;
        }
        const step = @min(limit - total, 64 * 1024);
        const n = decompress.reader.stream(&out.writer, .limited(step)) catch |err| switch (err) {
            error.EndOfStream => break,
            error.WriteFailed => return Error.OutOfMemory,
            else => return Error.InvalidPng,
        };
        total += n;
    }
    if (total > expected) return Error.InvalidPng;

    out.writer.flush() catch return Error.OutOfMemory;
    // バッファを丸ごと再コピーせず、そのまま所有権を返す
    return out.toOwnedSlice() catch return Error.OutOfMemory;
}

/// 画素バッファを確保せず IDAT を固定スクラッチへ伸長し、展開サイズが expected と一致するかだけ検証する
fn verifyInflate(
    alloc: std.mem.Allocator,
    zlib_data: []const u8,
    expected: usize,
    cancelled: ?*const std.atomic.Value(bool),
) Error!void {
    var reader: std.Io.Reader = .fixed(zlib_data);
    const window = alloc.alloc(u8, flate.max_window_len) catch return Error.OutOfMemory;
    defer alloc.free(window);
    var decompress: flate.Decompress = .init(&reader, .zlib, window);

    var scratch: [16 * 1024]u8 = undefined;
    var total: usize = 0;
    const limit = std.math.add(usize, expected, 1) catch return Error.TooLarge;
    while (total < limit) {
        if (cancelled) |flag| {
            if (flag.load(.acquire)) return Error.Cancelled;
        }
        const step = @min(limit - total, scratch.len);
        var sink: std.Io.Writer = .fixed(&scratch);
        const n = decompress.reader.stream(&sink, .limited(step)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return Error.InvalidPng,
        };
        total += n;
    }
    if (total != expected) return Error.InvalidPng;
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
        const row_start = @as(usize, y) * (stride + 1);
        const filter = raw[row_start];
        const row = raw[row_start + 1 ..][0..stride];
        const prev: ?[]const u8 = if (y == 0) null else raw[@as(usize, y - 1) * (stride + 1) + 1 ..][0..stride];

        switch (filter) {
            0 => {},
            1 => { // Sub
                var i = bpp;
                while (i < stride) : (i += 1) row[i] +%= row[i - bpp];
            },
            2 => { // Up
                if (prev) |up| {
                    var i: usize = 0;
                    while (i < stride) : (i += 1) row[i] +%= up[i];
                }
            },
            3 => { // Average
                if (prev) |up| {
                    var i: usize = 0;
                    while (i < bpp) : (i += 1) row[i] +%= up[i] >> 1;
                    while (i < stride) : (i += 1) {
                        const sum: u16 = @as(u16, row[i - bpp]) + @as(u16, up[i]);
                        row[i] +%= @intCast(sum >> 1);
                    }
                } else {
                    var i = bpp;
                    while (i < stride) : (i += 1) row[i] +%= row[i - bpp] >> 1;
                }
            },
            4 => { // Paeth
                if (prev) |up| {
                    var i: usize = 0;
                    while (i < bpp) : (i += 1) row[i] +%= up[i];
                    while (i < stride) : (i += 1) {
                        const a: i16 = row[i - bpp];
                        const b: i16 = up[i];
                        const c: i16 = up[i - bpp];
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
                        row[i] +%= pred;
                    }
                } else {
                    var i = bpp;
                    while (i < stride) : (i += 1) row[i] +%= row[i - bpp];
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
    const out_stride = @as(usize, width) * out_channels;

    // 8bit RGB / RGBA は最も頻度が高く、そのまま行コピーできる
    if (bit_depth == 8 and ((color_type == .rgb and out_channels == 3) or
        (color_type == .rgba and out_channels == 4)))
    {
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            const src_row = raw[@as(usize, y) * (stride + 1) + 1 ..][0..out_stride];
            const dst_row = out[@as(usize, y) * out_stride ..][0..out_stride];
            @memcpy(dst_row, src_row);
        }
        return;
    }

    const step: usize = if (bit_depth == 16) 2 else 1;
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const row = raw[@as(usize, y) * (stride + 1) + 1 ..][0..stride];
        const dst_row = out[@as(usize, y) * out_stride ..][0..out_stride];
        switch (color_type) {
            .gray => {
                var x: usize = 0;
                while (x < width) : (x += 1) {
                    const value = row[x * step];
                    const off = x * 3;
                    dst_row[off] = value;
                    dst_row[off + 1] = value;
                    dst_row[off + 2] = value;
                }
            },
            .gray_alpha => {
                var x: usize = 0;
                while (x < width) : (x += 1) {
                    const value = row[x * 2 * step];
                    const off = x * 4;
                    dst_row[off] = value;
                    dst_row[off + 1] = value;
                    dst_row[off + 2] = value;
                    dst_row[off + 3] = row[x * 2 * step + step];
                }
            },
            .rgb => {
                var x: usize = 0;
                while (x < width) : (x += 1) {
                    const base = x * 3 * step;
                    const off = x * 3;
                    dst_row[off] = row[base];
                    dst_row[off + 1] = row[base + step];
                    dst_row[off + 2] = row[base + 2 * step];
                }
            },
            .rgba => {
                var x: usize = 0;
                while (x < width) : (x += 1) {
                    const base = x * 4 * step;
                    const off = x * 4;
                    dst_row[off] = row[base];
                    dst_row[off + 1] = row[base + step];
                    dst_row[off + 2] = row[base + 2 * step];
                    dst_row[off + 3] = row[base + 3 * step];
                }
            },
            .palette => {
                var x: usize = 0;
                while (x < width) : (x += 1) {
                    const index = row[x];
                    const base = @as(usize, index) * 3;
                    if (base + 2 >= palette.len) return Error.InvalidPng;
                    const off = x * out_channels;
                    dst_row[off] = palette[base];
                    dst_row[off + 1] = palette[base + 1];
                    dst_row[off + 2] = palette[base + 2];
                    if (out_channels == 4) {
                        dst_row[off + 3] = if (index < palette_alpha.len) palette_alpha[index] else 255;
                    }
                }
            },
        }
    }
}
