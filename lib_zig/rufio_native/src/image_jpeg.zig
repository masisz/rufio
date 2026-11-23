//! baseline JPEG（SOF0 / ハフマン符号 / 8bit）の読み。プレビューに出すためだけの実装で、
//! 書き出しは行わない。
//!
//! 対応: グレースケール（1 成分）と YCbCr（3 成分）、4:4:4 / 4:2:2 / 4:2:0 などの間引き、
//!       リスタートマーカー、複数のハフマン表・量子化表。
//! 非対応: プログレッシブ（SOF2）・算術符号・12bit・CMYK（4 成分）。
//!       呼び出し側はテキスト表示にフォールバックする。
const std = @import("std");

pub const Error = error{
    InvalidJpeg,
    UnsupportedJpeg,
    TooLarge,
    OutOfMemory,
};

pub const Image = struct {
    width: u32,
    height: u32,
    channels: u8, // 常に 3（RGB）
    pixels: []u8,

    pub fn deinit(self: *Image, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
        self.pixels = &.{};
    }
};

const ZIGZAG = [64]u8{
    0,  1,  8,  16, 9,  2,  3,  10,
    17, 24, 32, 25, 18, 11, 4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13, 6,  7,  14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
};

const HuffmanTable = struct {
    // 符号長ごとの最小・最大コードと、値表への添字（JPEG 標準の復号手順）
    min_code: [17]i32 = @splat(0),
    max_code: [17]i32 = @splat(-1),
    value_index: [17]i32 = @splat(0),
    values: [256]u8 = @splat(0),
    defined: bool = false,

    fn build(self: *HuffmanTable, counts: []const u8, values: []const u8) void {
        var code: i32 = 0;
        var index: i32 = 0;
        var length: u8 = 1;
        while (length <= 16) : (length += 1) {
            const count = counts[length - 1];
            self.value_index[length] = index - code;
            self.min_code[length] = code;
            code += count;
            index += count;
            self.max_code[length] = if (count == 0) -1 else code - 1;
            code <<= 1;
        }
        @memcpy(self.values[0..values.len], values);
        self.defined = true;
    }
};

const Component = struct {
    id: u8 = 0,
    h: u8 = 1,
    v: u8 = 1,
    quant: u8 = 0,
    dc_table: u8 = 0,
    ac_table: u8 = 0,
    dc_pred: i32 = 0,
    // 成分ごとの画素面（間引き後の寸法）
    data: []u8 = &.{},
    width: u32 = 0,
    height: u32 = 0,
    stride: u32 = 0,
};

/// 見出し（SOFn）だけを読んで寸法を返す
pub fn info(data: []const u8) Error![2]u32 {
    var offset: usize = 2;
    if (data.len < 4 or data[0] != 0xff or data[1] != 0xd8) return Error.InvalidJpeg;
    while (offset + 4 <= data.len) {
        if (data[offset] != 0xff) {
            offset += 1;
            continue;
        }
        const marker = data[offset + 1];
        if (marker == 0xff) {
            offset += 1;
            continue;
        }
        if (marker == 0xd8 or (marker >= 0xd0 and marker <= 0xd9)) {
            offset += 2;
            continue;
        }
        const length = std.mem.readInt(u16, data[offset + 2 ..][0..2], .big);
        if (length < 2) return Error.InvalidJpeg;
        if (isFrameMarker(marker)) {
            if (offset + 9 > data.len) return Error.InvalidJpeg;
            const height = std.mem.readInt(u16, data[offset + 5 ..][0..2], .big);
            const width = std.mem.readInt(u16, data[offset + 7 ..][0..2], .big);
            if (width == 0 or height == 0) return Error.InvalidJpeg;
            return .{ width, height };
        }
        offset += 2 + length;
    }
    return Error.InvalidJpeg;
}

fn isFrameMarker(marker: u8) bool {
    return switch (marker) {
        0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf => true,
        else => false,
    };
}

const Decoder = struct {
    alloc: std.mem.Allocator,
    data: []const u8,
    offset: usize = 2,
    width: u32 = 0,
    height: u32 = 0,
    components: [4]Component = .{ .{}, .{}, .{}, .{} },
    component_count: u8 = 0,
    quant: [4][64]u16 = @splat(@splat(0)),
    dc_tables: [4]HuffmanTable = @splat(.{}),
    ac_tables: [4]HuffmanTable = @splat(.{}),
    restart_interval: u32 = 0,
    max_h: u8 = 1,
    max_v: u8 = 1,
    // ビット読み出しの状態
    bit_buffer: u32 = 0,
    bit_count: u8 = 0,
    marker_hit: bool = false,

    fn deinit(self: *Decoder) void {
        for (&self.components) |*component| {
            if (component.data.len > 0) self.alloc.free(component.data);
            component.data = &.{};
        }
    }

    fn readSegments(self: *Decoder, max_pixels: u64) Error!void {
        while (self.offset + 2 <= self.data.len) {
            if (self.data[self.offset] != 0xff) {
                self.offset += 1;
                continue;
            }
            const marker = self.data[self.offset + 1];
            self.offset += 2;
            switch (marker) {
                0xd8, 0x01 => {},
                0xd9 => return,
                0xc0, 0xc1 => try self.readFrame(max_pixels),
                0xc4 => try self.readHuffman(),
                0xdb => try self.readQuant(),
                0xdd => try self.readRestart(),
                0xda => {
                    try self.readScan();
                    return;
                },
                0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf =>
                    return Error.UnsupportedJpeg, // プログレッシブ・算術符号など
                else => try self.skipSegment(),
            }
        }
    }

    fn segmentBody(self: *Decoder) Error![]const u8 {
        if (self.offset + 2 > self.data.len) return Error.InvalidJpeg;
        const length = std.mem.readInt(u16, self.data[self.offset..][0..2], .big);
        if (length < 2 or self.offset + length > self.data.len) return Error.InvalidJpeg;
        const body = self.data[self.offset + 2 .. self.offset + length];
        self.offset += length;
        return body;
    }

    fn skipSegment(self: *Decoder) Error!void {
        _ = try self.segmentBody();
    }

    fn readFrame(self: *Decoder, max_pixels: u64) Error!void {
        const body = try self.segmentBody();
        if (body.len < 6) return Error.InvalidJpeg;
        if (body[0] != 8) return Error.UnsupportedJpeg; // 8bit 以外は非対応
        self.height = std.mem.readInt(u16, body[1..3], .big);
        self.width = std.mem.readInt(u16, body[3..5], .big);
        self.component_count = body[5];
        if (self.width == 0 or self.height == 0) return Error.InvalidJpeg;
        if (@as(u64, self.width) * self.height > max_pixels) return Error.TooLarge;
        if (self.component_count != 1 and self.component_count != 3) return Error.UnsupportedJpeg;
        if (body.len < 6 + @as(usize, self.component_count) * 3) return Error.InvalidJpeg;

        var i: u8 = 0;
        while (i < self.component_count) : (i += 1) {
            const base = 6 + @as(usize, i) * 3;
            var component = &self.components[i];
            component.id = body[base];
            component.h = @intCast(body[base + 1] >> 4);
            component.v = @intCast(body[base + 1] & 0x0f);
            component.quant = body[base + 2];
            if (component.h == 0 or component.v == 0 or component.h > 4 or component.v > 4) return Error.InvalidJpeg;
            if (component.quant > 3) return Error.InvalidJpeg;
            self.max_h = @max(self.max_h, component.h);
            self.max_v = @max(self.max_v, component.v);
        }

        // 成分ごとの面を確保する（MCU 単位に切り上げ）
        const mcu_w = @as(u32, self.max_h) * 8;
        const mcu_h = @as(u32, self.max_v) * 8;
        const mcus_x = (self.width + mcu_w - 1) / mcu_w;
        const mcus_y = (self.height + mcu_h - 1) / mcu_h;
        i = 0;
        while (i < self.component_count) : (i += 1) {
            var component = &self.components[i];
            component.stride = mcus_x * @as(u32, component.h) * 8;
            component.height = mcus_y * @as(u32, component.v) * 8;
            component.width = component.stride;
            component.data = self.alloc.alloc(u8, @as(usize, component.stride) * component.height) catch
                return Error.OutOfMemory;
            @memset(component.data, 128);
        }
    }

    fn readHuffman(self: *Decoder) Error!void {
        var body = try self.segmentBody();
        while (body.len >= 17) {
            const class = body[0] >> 4;
            const index = body[0] & 0x0f;
            if (index > 3 or class > 1) return Error.InvalidJpeg;
            const counts = body[1..17];
            var total: usize = 0;
            for (counts) |count| total += count;
            if (total > 256 or body.len < 17 + total) return Error.InvalidJpeg;
            const values = body[17 .. 17 + total];
            if (class == 0) {
                self.dc_tables[index].build(counts, values);
            } else {
                self.ac_tables[index].build(counts, values);
            }
            body = body[17 + total ..];
        }
    }

    fn readQuant(self: *Decoder) Error!void {
        var body = try self.segmentBody();
        while (body.len >= 1) {
            const precision = body[0] >> 4;
            const index = body[0] & 0x0f;
            if (index > 3) return Error.InvalidJpeg;
            const count: usize = if (precision == 0) 64 else 128;
            if (body.len < 1 + count) return Error.InvalidJpeg;
            var i: usize = 0;
            while (i < 64) : (i += 1) {
                self.quant[index][i] = if (precision == 0)
                    body[1 + i]
                else
                    std.mem.readInt(u16, body[1 + i * 2 ..][0..2], .big);
            }
            body = body[1 + count ..];
        }
    }

    fn readRestart(self: *Decoder) Error!void {
        const body = try self.segmentBody();
        if (body.len < 2) return Error.InvalidJpeg;
        self.restart_interval = std.mem.readInt(u16, body[0..2], .big);
    }

    fn readScan(self: *Decoder) Error!void {
        const body = try self.segmentBody();
        if (body.len < 1) return Error.InvalidJpeg;
        const count = body[0];
        if (count != self.component_count) return Error.UnsupportedJpeg; // 単一成分スキャンは非対応
        if (body.len < 1 + @as(usize, count) * 2) return Error.InvalidJpeg;

        var i: u8 = 0;
        while (i < count) : (i += 1) {
            const id = body[1 + @as(usize, i) * 2];
            const tables = body[2 + @as(usize, i) * 2];
            var found = false;
            for (self.components[0..self.component_count]) |*component| {
                if (component.id != id) continue;
                component.dc_table = tables >> 4;
                component.ac_table = tables & 0x0f;
                if (component.dc_table > 3 or component.ac_table > 3) return Error.InvalidJpeg;
                found = true;
            }
            if (!found) return Error.InvalidJpeg;
        }

        try self.decodeScan();
    }

    // === ビット読み出し ===
    //
    // bit_buffer は上位ビットから詰める。bit_count は有効ビット数（最大 32）。
    // 0xff の後ろが 0x00 ならバイトスタッフィング、それ以外はマーカーなので、
    // それ以降は 0 を供給して走査を止める（末尾が切れた画像でも落ちない）。

    fn nextByte(self: *Decoder) u8 {
        if (self.marker_hit or self.offset >= self.data.len) return 0;
        const byte = self.data[self.offset];
        if (byte != 0xff) {
            self.offset += 1;
            return byte;
        }
        const next = if (self.offset + 1 < self.data.len) self.data[self.offset + 1] else 0xd9;
        if (next == 0x00) {
            self.offset += 2;
            return 0xff;
        }
        self.marker_hit = true; // マーカーは restart() / 呼び出し側が処理する
        return 0;
    }

    fn fillBits(self: *Decoder) void {
        while (self.bit_count <= 24) {
            const byte = self.nextByte();
            const shift: u5 = @intCast(24 - self.bit_count);
            self.bit_buffer |= @as(u32, byte) << shift;
            self.bit_count += 8;
        }
    }

    fn getBits(self: *Decoder, count: u8) i32 {
        if (count == 0 or count > 16) return 0;
        self.fillBits();
        const shift: u5 = @intCast(32 - @as(u6, @intCast(count)));
        const value: u32 = self.bit_buffer >> shift;
        self.bit_buffer <<= @intCast(count);
        self.bit_count -= count;
        return @intCast(value);
    }

    fn decodeHuffman(self: *Decoder, table: *const HuffmanTable) Error!u8 {
        if (!table.defined) return Error.InvalidJpeg;
        self.fillBits();
        var code: i32 = 0;
        var length: u8 = 1;
        while (length <= 16) : (length += 1) {
            code = (code << 1) | self.getBits(1);
            if (table.max_code[length] >= code and code >= table.min_code[length]) {
                const index = table.value_index[length] + code;
                if (index < 0 or index >= 256) return Error.InvalidJpeg;
                return table.values[@intCast(index)];
            }
        }
        return Error.InvalidJpeg;
    }

    /// JPEG の可変長数値（符号付き）
    fn extend(value: i32, length: u8) i32 {
        if (length == 0 or length > 16) return 0;
        const shift: u5 = @intCast(length);
        const threshold = @as(i32, 1) << (shift - 1);
        return if (value < threshold) value - (@as(i32, 1) << shift) + 1 else value;
    }

    fn resetBits(self: *Decoder) void {
        self.bit_buffer = 0;
        self.bit_count = 0;
        self.marker_hit = false;
    }

    /// リスタートマーカーを読み飛ばし、DC 予測値を戻す
    fn restart(self: *Decoder) void {
        self.resetBits();
        while (self.offset + 1 < self.data.len) {
            if (self.data[self.offset] == 0xff) {
                const marker = self.data[self.offset + 1];
                if (marker >= 0xd0 and marker <= 0xd7) {
                    self.offset += 2;
                    break;
                }
                if (marker == 0xd9) break; // EOI
            }
            self.offset += 1;
        }
        for (&self.components) |*component| component.dc_pred = 0;
    }

    fn decodeScan(self: *Decoder) Error!void {
        const mcus_x = (self.width + @as(u32, self.max_h) * 8 - 1) / (@as(u32, self.max_h) * 8);
        const mcus_y = (self.height + @as(u32, self.max_v) * 8 - 1) / (@as(u32, self.max_v) * 8);
        var block: [64]i32 = undefined;
        var mcu: u32 = 0;
        const total = mcus_x * mcus_y;

        while (mcu < total) : (mcu += 1) {
            if (self.restart_interval > 0 and mcu > 0 and mcu % self.restart_interval == 0) self.restart();

            const mcu_x = mcu % mcus_x;
            const mcu_y = mcu / mcus_x;
            var ci: u8 = 0;
            while (ci < self.component_count) : (ci += 1) {
                const component = &self.components[ci];
                var by: u8 = 0;
                while (by < component.v) : (by += 1) {
                    var bx: u8 = 0;
                    while (bx < component.h) : (bx += 1) {
                        try self.decodeBlock(component, &block);
                        const x = (mcu_x * @as(u32, component.h) + bx) * 8;
                        const y = (mcu_y * @as(u32, component.v) + by) * 8;
                        idctBlock(&block, component.data, component.stride, x, y);
                    }
                }
            }
        }
    }

    fn decodeBlock(self: *Decoder, component: *Component, block: *[64]i32) Error!void {
        @memset(block, 0);
        const quant = &self.quant[component.quant];

        // DC
        const dc_bits = try self.decodeHuffman(&self.dc_tables[component.dc_table]);
        if (dc_bits > 16) return Error.InvalidJpeg;
        const diff = extend(self.getBits(dc_bits), dc_bits);
        component.dc_pred += diff;
        block[0] = component.dc_pred * @as(i32, quant[0]);

        // AC
        var index: u8 = 1;
        while (index < 64) {
            const symbol = try self.decodeHuffman(&self.ac_tables[component.ac_table]);
            const run = symbol >> 4;
            const size = symbol & 0x0f;
            if (size == 0) {
                if (run != 15) break; // EOB
                index += 16;
                continue;
            }
            index += run;
            if (index >= 64) break;
            const value = extend(self.getBits(size), size);
            block[ZIGZAG[index]] = value * @as(i32, quant[index]);
            index += 1;
        }
    }
};

/// 8x8 の逆 DCT（分離型・整数近似）。結果は 0..255 に丸めて面へ書く
fn idctBlock(block: *const [64]i32, out: []u8, stride: u32, x0: u32, y0: u32) void {
    var tmp: [64]f32 = undefined;

    // 行方向
    var y: usize = 0;
    while (y < 8) : (y += 1) {
        var x: usize = 0;
        while (x < 8) : (x += 1) {
            var sum: f32 = 0;
            var u: usize = 0;
            while (u < 8) : (u += 1) {
                const coefficient = block[y * 8 + u];
                if (coefficient == 0) continue;
                sum += @as(f32, @floatFromInt(coefficient)) * COS_TABLE[u][x];
            }
            tmp[y * 8 + x] = sum;
        }
    }

    // 列方向
    var x: usize = 0;
    while (x < 8) : (x += 1) {
        var out_y: usize = 0;
        while (out_y < 8) : (out_y += 1) {
            var sum: f32 = 0;
            var v: usize = 0;
            while (v < 8) : (v += 1) {
                sum += tmp[v * 8 + x] * COS_TABLE[v][out_y];
            }
            const value = sum / 4.0 + 128.0;
            const clamped: u8 = if (value <= 0) 0 else if (value >= 255) 255 else @intFromFloat(value);
            const py = y0 + out_y;
            const px = x0 + x;
            const offset = @as(usize, py) * stride + px;
            if (offset < out.len) out[offset] = clamped;
        }
    }
}

/// cos((2x+1)uπ/16) * C(u)（C(0)=1/√2, それ以外 1）
const COS_TABLE: [8][8]f32 = blk: {
    @setEvalBranchQuota(10000);
    var table: [8][8]f32 = undefined;
    var u: usize = 0;
    while (u < 8) : (u += 1) {
        var x: usize = 0;
        while (x < 8) : (x += 1) {
            const cu: f32 = if (u == 0) 0.70710678118654752 else 1.0;
            const angle = (2.0 * @as(f64, @floatFromInt(x)) + 1.0) * @as(f64, @floatFromInt(u)) *
                std.math.pi / 16.0;
            table[u][x] = cu * @as(f32, @floatCast(@cos(angle)));
        }
    }
    break :blk table;
};

/// JPEG を RGB の生画素に展開する
pub fn decode(alloc: std.mem.Allocator, data: []const u8, max_pixels: u64) Error!Image {
    if (data.len < 4 or data[0] != 0xff or data[1] != 0xd8) return Error.InvalidJpeg;

    var decoder = Decoder{ .alloc = alloc, .data = data };
    defer decoder.deinit();
    try decoder.readSegments(max_pixels);
    if (decoder.width == 0 or decoder.height == 0 or decoder.component_count == 0) return Error.InvalidJpeg;

    const width = decoder.width;
    const height = decoder.height;
    const pixels = alloc.alloc(u8, @as(usize, width) * height * 3) catch return Error.OutOfMemory;
    errdefer alloc.free(pixels);

    if (decoder.component_count == 1) {
        const component = &decoder.components[0];
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const value = sample(component, x, y, decoder.max_h, decoder.max_v);
                const out = (@as(usize, y) * width + x) * 3;
                pixels[out] = value;
                pixels[out + 1] = value;
                pixels[out + 2] = value;
            }
        }
        return .{ .width = width, .height = height, .channels = 3, .pixels = pixels };
    }

    const luma = &decoder.components[0];
    const cb = &decoder.components[1];
    const cr = &decoder.components[2];
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const yy = @as(f32, @floatFromInt(sample(luma, x, y, decoder.max_h, decoder.max_v)));
            const cb_value = @as(f32, @floatFromInt(sample(cb, x, y, decoder.max_h, decoder.max_v))) - 128.0;
            const cr_value = @as(f32, @floatFromInt(sample(cr, x, y, decoder.max_h, decoder.max_v))) - 128.0;
            const out = (@as(usize, y) * width + x) * 3;
            pixels[out] = clamp(yy + 1.402 * cr_value);
            pixels[out + 1] = clamp(yy - 0.344136 * cb_value - 0.714136 * cr_value);
            pixels[out + 2] = clamp(yy + 1.772 * cb_value);
        }
    }

    return .{ .width = width, .height = height, .channels = 3, .pixels = pixels };
}

/// 間引かれた成分から、画像座標 (x, y) に対応する値を取る（最近傍）
fn sample(component: *const Component, x: u32, y: u32, max_h: u8, max_v: u8) u8 {
    const sx = x * component.h / max_h;
    const sy = y * component.v / max_v;
    const cx = @min(sx, component.stride - 1);
    const cy = @min(sy, component.height - 1);
    const offset = @as(usize, cy) * component.stride + cx;
    return if (offset < component.data.len) component.data[offset] else 128;
}

fn clamp(value: f32) u8 {
    if (value <= 0) return 0;
    if (value >= 255) return 255;
    return @intFromFloat(value);
}
