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
    Cancelled,
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

const FAST_BITS = 10;
const FAST_SIZE = 1 << FAST_BITS;
/// 1 辺の最大ピクセル数（細工した極端な縦長・横長画像を拒否する）
const MAX_DIMENSION: u32 = 16384;
/// JPEG 規格上の 1 MCU あたり最大ブロック数（Σ h*v <= 10）
const MAX_MCU_BLOCKS: u32 = 10;

const HuffmanTable = struct {
    // 10bit 以下の符号はテーブル一発で復号する（99% 以上がここで終わる）
    fast_sym: [FAST_SIZE]u8 = @splat(0),
    fast_len: [FAST_SIZE]u8 = @splat(0),
    // 9..16bit の長符号用（JPEG 標準の復号手順）
    min_code: [17]i32 = @splat(0),
    max_code: [17]i32 = @splat(-1),
    value_index: [17]i32 = @splat(0),
    values: [256]u8 = @splat(0),
    defined: bool = false,

    fn build(self: *HuffmanTable, counts: []const u8, values: []const u8) Error!void {
        @memset(&self.fast_len, 0);
        var code: i32 = 0;
        var index: i32 = 0;
        var length: u8 = 1;
        while (length <= 16) : (length += 1) {
            const count = counts[length - 1];
            const limit: i32 = @as(i32, 1) << @intCast(length);
            // 符号長に対する最大符号数を超える不正 DHT による OOB 書き込みを防ぐ
            if (code + count > limit) return Error.InvalidJpeg;
            self.value_index[length] = index - code;
            self.min_code[length] = code;
            if (length <= FAST_BITS and count > 0) {
                const shift: u4 = @intCast(FAST_BITS - length);
                const span: usize = @as(usize, 1) << shift;
                var i: u8 = 0;
                while (i < count) : (i += 1) {
                    const sym = values[@intCast(index + i)];
                    const prefix: usize = @as(usize, @intCast(code + i)) << shift;
                    if (prefix + span > FAST_SIZE) return Error.InvalidJpeg;
                    @memset(self.fast_sym[prefix .. prefix + span], sym);
                    @memset(self.fast_len[prefix .. prefix + span], length);
                }
            }
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
    // 64bit ビットバッファ（上位ビットから詰める）
    bit_buffer: u64 = 0,
    bit_count: u8 = 0,
    marker_hit: bool = false,
    // EOF 後に連続で供給された 0 バイト数（細工した小ファイルでの空回し DoS を防ぐ）
    eof_zeros: u32 = 0,
    eof_overflow: bool = false,
    cancelled: ?*const std.atomic.Value(bool) = null,

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
        // 複数の SOF セグメントによるリーク・状態破壊を防ぐ
        if (self.component_count != 0) return Error.InvalidJpeg;
        const body = try self.segmentBody();
        if (body.len < 6) return Error.InvalidJpeg;
        if (body[0] != 8) return Error.UnsupportedJpeg; // 8bit 以外は非対応
        self.height = std.mem.readInt(u16, body[1..3], .big);
        self.width = std.mem.readInt(u16, body[3..5], .big);
        self.component_count = body[5];
        if (self.width == 0 or self.height == 0) return Error.InvalidJpeg;
        if (self.width > MAX_DIMENSION or self.height > MAX_DIMENSION) return Error.TooLarge;
        if (@as(u64, self.width) * self.height > max_pixels) return Error.TooLarge;
        if (self.component_count != 1 and self.component_count != 3) return Error.UnsupportedJpeg;
        if (body.len < 6 + @as(usize, self.component_count) * 3) return Error.InvalidJpeg;

        var mcu_blocks: u32 = 0;
        var i: u8 = 0;
        while (i < self.component_count) : (i += 1) {
            const base = 6 + @as(usize, i) * 3;
            var component = &self.components[i];
            component.id = body[base];
            // 成分 ID の重複を拒否する
            var prev: u8 = 0;
            while (prev < i) : (prev += 1) {
                if (self.components[prev].id == component.id) return Error.InvalidJpeg;
            }
            component.h = @intCast(body[base + 1] >> 4);
            component.v = @intCast(body[base + 1] & 0x0f);
            component.quant = body[base + 2];
            if (component.h == 0 or component.v == 0 or component.h > 4 or component.v > 4) return Error.InvalidJpeg;
            if (component.quant > 3) return Error.InvalidJpeg;
            mcu_blocks += @as(u32, component.h) * component.v;
            self.max_h = @max(self.max_h, component.h);
            self.max_v = @max(self.max_v, component.v);
        }
        if (mcu_blocks > MAX_MCU_BLOCKS) return Error.InvalidJpeg;

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
            const plane_size = std.math.mul(usize, component.stride, component.height) catch return Error.TooLarge;
            component.data = self.alloc.alloc(u8, plane_size) catch return Error.OutOfMemory;
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
                try self.dc_tables[index].build(counts, values);
            } else {
                try self.ac_tables[index].build(counts, values);
            }
            body = body[17 + total ..];
        }
    }

    fn readQuant(self: *Decoder) Error!void {
        var body = try self.segmentBody();
        while (body.len >= 1) {
            const precision = body[0] >> 4;
            const index = body[0] & 0x0f;
            if (precision > 1 or index > 3) return Error.InvalidJpeg;
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
        if (self.component_count == 0) return Error.InvalidJpeg;
        const body = try self.segmentBody();
        if (body.len < 1) return Error.InvalidJpeg;
        const count = body[0];
        if (count != self.component_count) return Error.UnsupportedJpeg; // 単一成分スキャンは非対応
        if (body.len < 1 + @as(usize, count) * 2) return Error.InvalidJpeg;

        var seen: [4]bool = @splat(false);
        var i: u8 = 0;
        while (i < count) : (i += 1) {
            const id = body[1 + @as(usize, i) * 2];
            const tables = body[2 + @as(usize, i) * 2];
            var found = false;
            var ci: u8 = 0;
            while (ci < self.component_count) : (ci += 1) {
                var component = &self.components[ci];
                if (component.id != id) continue;
                if (seen[ci]) return Error.InvalidJpeg;
                seen[ci] = true;
                component.dc_table = tables >> 4;
                component.ac_table = tables & 0x0f;
                if (component.dc_table > 3 or component.ac_table > 3) return Error.InvalidJpeg;
                if (!self.dc_tables[component.dc_table].defined or !self.ac_tables[component.ac_table].defined) {
                    return Error.InvalidJpeg;
                }
                found = true;
            }
            if (!found) return Error.InvalidJpeg;
        }

        try self.decodeScan();
    }

    // === ビット読み出し ===
    //
    // bit_buffer は上位ビットから詰める。bit_count は有効ビット数（最大 64）。
    // 0xff の後ろが 0x00 ならバイトスタッフィング、それ以外はマーカーなので、
    // それ以降は 0 を供給して走査を止める（末尾が切れた画像でも落ちない）。

    inline fn nextByte(self: *Decoder) u8 {
        if (self.marker_hit or self.offset >= self.data.len) {
            if (self.offset >= self.data.len) {
                self.eof_zeros +|= 1;
                if (self.eof_zeros > 64) self.eof_overflow = true;
            }
            return 0;
        }
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
        // 0xff を含まない通常ケースをまとめて 1 バイトずつ高速補充
        var buf = self.bit_buffer;
        var cnt = self.bit_count;
        var off = self.offset;
        const data = self.data;

        if (!self.marker_hit) {
            while (cnt <= 56 and off < data.len) {
                const byte = data[off];
                if (byte == 0xff) break;
                off += 1;
                const shift: u6 = @intCast(56 - cnt);
                buf |= @as(u64, byte) << shift;
                cnt += 8;
            }
            self.offset = off;
        }

        while (cnt <= 56) {
            const byte = self.nextByte();
            const shift: u6 = @intCast(56 - cnt);
            buf |= @as(u64, byte) << shift;
            cnt += 8;
        }

        self.bit_buffer = buf;
        self.bit_count = cnt;
    }

    inline fn getBits(self: *Decoder, count: u8) i32 {
        if (count == 0 or count > 16) return 0;
        if (self.bit_count < count) self.fillBits();
        const shift: u6 = @intCast(@as(u8, 64) - count);
        const value: u64 = self.bit_buffer >> shift;
        self.bit_buffer <<= @intCast(count);
        self.bit_count -= count;
        return @intCast(value);
    }

    inline fn decodeHuffman(self: *Decoder, table: *const HuffmanTable) Error!u8 {
        if (!table.defined) return Error.InvalidJpeg;
        if (self.bit_count < 16) self.fillBits();

        const peek: usize = @intCast(self.bit_buffer >> (64 - FAST_BITS));
        const fast_len = table.fast_len[peek];
        if (fast_len != 0) {
            self.bit_buffer <<= @intCast(fast_len);
            self.bit_count -= fast_len;
            return table.fast_sym[peek];
        }

        return self.decodeHuffmanSlow(table);
    }

    noinline fn decodeHuffmanSlow(self: *Decoder, table: *const HuffmanTable) Error!u8 {
        if (self.bit_count < 16) self.fillBits();
        const top16: u32 = @intCast(self.bit_buffer >> 48);
        var length: u8 = FAST_BITS + 1;
        while (length <= 16) : (length += 1) {
            const shift: u5 = @intCast(16 - length);
            const code: i32 = @intCast(top16 >> shift);
            if (table.max_code[length] >= code and code >= table.min_code[length]) {
                const index = table.value_index[length] + code;
                if (index < 0 or index >= 256) return Error.InvalidJpeg;
                self.bit_buffer <<= @intCast(length);
                self.bit_count -= length;
                return table.values[@intCast(index)];
            }
        }
        return Error.InvalidJpeg;
    }

    /// JPEG の可変長数値（符号付き）
    inline fn extend(value: i32, length: u8) i32 {
        if (length == 0) return 0;
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
                    self.eof_zeros = 0;
                    self.eof_overflow = false;
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
            if ((mcu & 0x3f) == 0) {
                if (self.cancelled) |flag| {
                    if (flag.load(.acquire)) return Error.Cancelled;
                }
            }
            if (self.eof_overflow) return Error.InvalidJpeg;
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
                        const dc_only = try self.decodeBlock(component, &block);
                        if (self.eof_overflow) return Error.InvalidJpeg;
                        const x = (mcu_x * @as(u32, component.h) + bx) * 8;
                        const y = (mcu_y * @as(u32, component.v) + by) * 8;
                        if (dc_only) {
                            fillDcBlock(block[0], component.data, component.stride, x, y);
                        } else {
                            idctBlock(&block, component.data, component.stride, x, y);
                        }
                    }
                }
            }
        }
    }

    /// 1 ブロック（8x8）を復号する。AC 係数がすべて 0 なら true を返す
    fn decodeBlock(self: *Decoder, component: *Component, block: *[64]i32) Error!bool {
        @memset(block, 0);
        const quant = &self.quant[component.quant];

        // DC（異常な連続差分で i32 が溢れないよう範囲内に収める）
        const dc_bits = try self.decodeHuffman(&self.dc_tables[component.dc_table]);
        if (dc_bits > 16) return Error.InvalidJpeg;
        const diff = if (dc_bits > 0) extend(self.getBits(dc_bits), dc_bits) else 0;
        component.dc_pred = @intCast(std.math.clamp(@as(i64, component.dc_pred) + diff, -32768, 32767));
        block[0] = @intCast(std.math.clamp(@as(i64, component.dc_pred) * quant[0], -1_000_000, 1_000_000));

        // AC
        const ac_table = &self.ac_tables[component.ac_table];
        var index: u8 = 1;
        var dc_only = true;
        while (index < 64) {
            const symbol = try self.decodeHuffman(ac_table);
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
            block[ZIGZAG[index]] = @intCast(std.math.clamp(@as(i64, value) * quant[index], -1_000_000, 1_000_000));
            dc_only = false;
            index += 1;
        }
        return dc_only;
    }
};

inline fn clampInt(value: i64) u8 {
    if (value <= 0) return 0;
    if (value >= 255) return 255;
    return @intCast(value);
}

/// AC 係数がすべて 0 のブロックは 64 画素すべて同じ値になる
fn fillDcBlock(dc: i32, out: []u8, stride: u32, x0: u32, y0: u32) void {
    if (x0 + 8 > stride or @as(usize, y0 + 8) * stride > out.len) return;
    const val = clampInt(((@as(i64, dc) + 4) >> 3) + 128);
    var y: u32 = 0;
    while (y < 8) : (y += 1) {
        const offset = @as(usize, y0 + y) * stride + x0;
        @memset(out[offset .. offset + 8], val);
    }
}

// Loeffler 12-bit 固定小数点 1D IDCT 定数（round(c * 4096)）
const C0_298631336: i64 = 1223;
const C0_390180644: i64 = 1598;
const C0_541196100: i64 = 2217;
const C0_765366865: i64 = 3135;
const C0_899976223: i64 = 3686;
const C1_175875602: i64 = 4816;
const C1_501321110: i64 = 6149;
const C1_847759065: i64 = 7568;
const C1_961570560: i64 = 8035;
const C2_053119869: i64 = 8410;
const C2_562915447: i64 = 10498;
const C3_072711026: i64 = 12586;

/// 8x8 の高速整数逆 DCT（Loeffler 分離型・12bit 固定小数点）。結果は 0..255 に丸めて面へ書く
fn idctBlock(block: *const [64]i32, out: []u8, stride: u32, x0: u32, y0: u32) void {
    if (x0 + 8 > stride or @as(usize, y0 + 8) * stride > out.len) return;
    var ws: [64]i64 = undefined;

    // Pass 1: 行方向（出力は 2bit 余剰精度 = 4 倍スケール）
    var row: usize = 0;
    while (row < 8) : (row += 1) {
        const b = block[row * 8 ..][0..8];
        const w = ws[row * 8 ..][0..8];

        // 行の AC 係数がすべて 0 ならコピーだけで終わる
        if ((b[1] | b[2] | b[3] | b[4] | b[5] | b[6] | b[7]) == 0) {
            const dcval = @as(i64, b[0]) << 2;
            @memset(w, dcval);
            continue;
        }

        const d0: i64 = b[0];
        const d1: i64 = b[1];
        const d2: i64 = b[2];
        const d3: i64 = b[3];
        const d4: i64 = b[4];
        const d5: i64 = b[5];
        const d6: i64 = b[6];
        const d7: i64 = b[7];

        // 偶数部
        const ez1 = (d2 + d6) * C0_541196100;
        const etmp2 = ez1 + d6 * (-C1_847759065);
        const etmp3 = ez1 + d2 * C0_765366865;
        const etmp0 = (d0 + d4) << 12;
        const etmp1 = (d0 - d4) << 12;
        const tmp10 = etmp0 + etmp3;
        const tmp13 = etmp0 - etmp3;
        const tmp11 = etmp1 + etmp2;
        const tmp12 = etmp1 - etmp2;

        // 奇数部
        var z1 = d7 + d1;
        var z2 = d5 + d3;
        var z3 = d7 + d3;
        var z4 = d5 + d1;
        const z5 = (z3 + z4) * C1_175875602;

        var otmp0 = d7 * C0_298631336;
        var otmp1 = d5 * C2_053119869;
        var otmp2 = d3 * C3_072711026;
        var otmp3 = d1 * C1_501321110;

        z1 = z1 * (-C0_899976223);
        z2 = z2 * (-C2_562915447);
        z3 = z3 * (-C1_961570560) + z5;
        z4 = z4 * (-C0_390180644) + z5;

        otmp0 += z1 + z3;
        otmp1 += z2 + z4;
        otmp2 += z2 + z3;
        otmp3 += z1 + z4;

        w[0] = (tmp10 + otmp3 + 512) >> 10;
        w[7] = (tmp10 - otmp3 + 512) >> 10;
        w[1] = (tmp11 + otmp2 + 512) >> 10;
        w[6] = (tmp11 - otmp2 + 512) >> 10;
        w[2] = (tmp12 + otmp1 + 512) >> 10;
        w[5] = (tmp12 - otmp1 + 512) >> 10;
        w[3] = (tmp13 + otmp0 + 512) >> 10;
        w[4] = (tmp13 - otmp0 + 512) >> 10;
    }

    // Pass 2: 列方向（最終シフト 12 + 2 + 3 = 17bit）
    var col: usize = 0;
    while (col < 8) : (col += 1) {
        const d0: i64 = ws[col];
        const d1: i64 = ws[8 + col];
        const d2: i64 = ws[16 + col];
        const d3: i64 = ws[24 + col];
        const d4: i64 = ws[32 + col];
        const d5: i64 = ws[40 + col];
        const d6: i64 = ws[48 + col];
        const d7: i64 = ws[56 + col];

        const base = @as(usize, y0) * stride + x0 + col;
        if ((d1 | d2 | d3 | d4 | d5 | d6 | d7) == 0) {
            const val = clampInt(((d0 + 16) >> 5) + 128);
            var y: usize = 0;
            while (y < 8) : (y += 1) {
                out[base + y * stride] = val;
            }
            continue;
        }

        // 偶数部
        const ez1 = (d2 + d6) * C0_541196100;
        const etmp2 = ez1 + d6 * (-C1_847759065);
        const etmp3 = ez1 + d2 * C0_765366865;
        const etmp0 = (d0 + d4) << 12;
        const etmp1 = (d0 - d4) << 12;
        const tmp10 = etmp0 + etmp3;
        const tmp13 = etmp0 - etmp3;
        const tmp11 = etmp1 + etmp2;
        const tmp12 = etmp1 - etmp2;

        // 奇数部
        var z1 = d7 + d1;
        var z2 = d5 + d3;
        var z3 = d7 + d3;
        var z4 = d5 + d1;
        const z5 = (z3 + z4) * C1_175875602;

        var otmp0 = d7 * C0_298631336;
        var otmp1 = d5 * C2_053119869;
        var otmp2 = d3 * C3_072711026;
        var otmp3 = d1 * C1_501321110;

        z1 = z1 * (-C0_899976223);
        z2 = z2 * (-C2_562915447);
        z3 = z3 * (-C1_961570560) + z5;
        z4 = z4 * (-C0_390180644) + z5;

        otmp0 += z1 + z3;
        otmp1 += z2 + z4;
        otmp2 += z2 + z3;
        otmp3 += z1 + z4;

        const round: i64 = 1 << 16;
        out[base] = clampInt(((tmp10 + otmp3 + round) >> 17) + 128);
        out[base + 7 * stride] = clampInt(((tmp10 - otmp3 + round) >> 17) + 128);
        out[base + 1 * stride] = clampInt(((tmp11 + otmp2 + round) >> 17) + 128);
        out[base + 6 * stride] = clampInt(((tmp11 - otmp2 + round) >> 17) + 128);
        out[base + 2 * stride] = clampInt(((tmp12 + otmp1 + round) >> 17) + 128);
        out[base + 5 * stride] = clampInt(((tmp12 - otmp1 + round) >> 17) + 128);
        out[base + 3 * stride] = clampInt(((tmp13 + otmp0 + round) >> 17) + 128);
        out[base + 4 * stride] = clampInt(((tmp13 - otmp0 + round) >> 17) + 128);
    }
}

/// 16bit 固定小数点で YCbCr → RGB 変換する
inline fn writeYCbCr(dst: []u8, y_val: u8, cb_raw: u8, cr_raw: u8) void {
    const yy: i32 = y_val;
    const cb: i32 = @as(i32, cb_raw) - 128;
    const cr: i32 = @as(i32, cr_raw) - 128;

    const r = yy + ((91881 * cr + 32768) >> 16);
    const g = yy + ((-22554 * cb - 46802 * cr + 32768) >> 16);
    const b = yy + ((116130 * cb + 32768) >> 16);

    dst[0] = clampI32(r);
    dst[1] = clampI32(g);
    dst[2] = clampI32(b);
}

inline fn clampI32(value: i32) u8 {
    if (value <= 0) return 0;
    if (value >= 255) return 255;
    return @intCast(value);
}

/// JPEG を RGB の生画素に展開する
pub fn decode(alloc: std.mem.Allocator, data: []const u8, max_pixels: u64) Error!Image {
    return decodeCancelable(alloc, data, max_pixels, null);
}

/// キャンセルフラグを監視しながら JPEG を RGB の生画素に展開する
pub fn decodeCancelable(
    alloc: std.mem.Allocator,
    data: []const u8,
    max_pixels: u64,
    cancelled: ?*const std.atomic.Value(bool),
) Error!Image {
    if (data.len < 4 or data[0] != 0xff or data[1] != 0xd8) return Error.InvalidJpeg;

    var decoder = Decoder{ .alloc = alloc, .data = data, .cancelled = cancelled };
    defer decoder.deinit();
    try decoder.readSegments(max_pixels);
    if (decoder.width == 0 or decoder.height == 0 or decoder.component_count == 0) return Error.InvalidJpeg;
    if (cancelled) |flag| {
        if (flag.load(.acquire)) return Error.Cancelled;
    }

    const width = decoder.width;
    const height = decoder.height;
    const pixels = alloc.alloc(u8, @as(usize, width) * height * 3) catch return Error.OutOfMemory;
    errdefer alloc.free(pixels);

    if (decoder.component_count == 1) {
        const component = &decoder.components[0];
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            const src_row = component.data[@as(usize, y) * component.stride ..];
            var out_offset = @as(usize, y) * width * 3;
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const value = src_row[x];
                pixels[out_offset] = value;
                pixels[out_offset + 1] = value;
                pixels[out_offset + 2] = value;
                out_offset += 3;
            }
        }
        return .{ .width = width, .height = height, .channels = 3, .pixels = pixels };
    }

    const luma = &decoder.components[0];
    const cb = &decoder.components[1];
    const cr = &decoder.components[2];

    // よく使う間引き形式はビットシフトだけで参照し、毎ピクセルの除算を省く
    if (decoder.max_h == 2 and decoder.max_v == 2 and
        luma.h == 2 and luma.v == 2 and
        cb.h == 1 and cb.v == 1 and cr.h == 1 and cr.v == 1)
    {
        // 4:2:0（最も一般的）
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            const y_row = luma.data[@as(usize, y) * luma.stride ..];
            const cy = y >> 1;
            const cb_row = cb.data[@as(usize, cy) * cb.stride ..];
            const cr_row = cr.data[@as(usize, cy) * cr.stride ..];
            var out_offset = @as(usize, y) * width * 3;
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const cx = x >> 1;
                writeYCbCr(pixels[out_offset .. out_offset + 3], y_row[x], cb_row[cx], cr_row[cx]);
                out_offset += 3;
            }
        }
    } else if (decoder.max_h == 1 and decoder.max_v == 1) {
        // 4:4:4
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            const y_row = luma.data[@as(usize, y) * luma.stride ..];
            const cb_row = cb.data[@as(usize, y) * cb.stride ..];
            const cr_row = cr.data[@as(usize, y) * cr.stride ..];
            var out_offset = @as(usize, y) * width * 3;
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                writeYCbCr(pixels[out_offset .. out_offset + 3], y_row[x], cb_row[x], cr_row[x]);
                out_offset += 3;
            }
        }
    } else if (decoder.max_h == 2 and decoder.max_v == 1 and
        luma.h == 2 and luma.v == 1 and
        cb.h == 1 and cb.v == 1 and cr.h == 1 and cr.v == 1)
    {
        // 4:2:2
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            const y_row = luma.data[@as(usize, y) * luma.stride ..];
            const cb_row = cb.data[@as(usize, y) * cb.stride ..];
            const cr_row = cr.data[@as(usize, y) * cr.stride ..];
            var out_offset = @as(usize, y) * width * 3;
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const cx = x >> 1;
                writeYCbCr(pixels[out_offset .. out_offset + 3], y_row[x], cb_row[cx], cr_row[cx]);
                out_offset += 3;
            }
        }
    } else {
        // その他の間引き比（汎用パス）
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            var out_offset = @as(usize, y) * width * 3;
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                writeYCbCr(
                    pixels[out_offset .. out_offset + 3],
                    sample(luma, x, y, decoder.max_h, decoder.max_v),
                    sample(cb, x, y, decoder.max_h, decoder.max_v),
                    sample(cr, x, y, decoder.max_h, decoder.max_v),
                );
                out_offset += 3;
            }
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
