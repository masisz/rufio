//! 画像プレビュー用のデコード・縮小・符号化。
//!
//! Ruby（ImagePreviewView / GraphicsLayer）が端末の対応判定・矩形・上限・フォールバックを
//! 決め、ここでは計算だけを行う:
//!   ファイルを読む → 形式を判定 → 画素に展開 → 指定ピクセルへ縮小 → 端末へ渡す形に符号化
//!   → Base64 化（Ruby で数 MB を符号化すると GVL を握るため、ここで済ませる）
//!
//! 読めない・非対応の形式は failed にするだけで、例外もログも出さない（Ruby 側が
//! 形式と寸法のテキスト表示に落とす）。
const std = @import("std");
const png = @import("image_png.zig");
const jpeg = @import("image_jpeg.zig");
const bmp = @import("image_bmp.zig");
const resize_mod = @import("image_resize.zig");
const os = @import("os.zig");

const alloc = std.heap.c_allocator;

/// 読み込むファイルサイズの上限（Ruby 側でも先に弾く）
pub const MAX_BYTES: usize = 32 * 1024 * 1024;
/// 展開を許す画素数の上限（細工した画像での巨大確保を防ぐ）
pub const MAX_PIXELS: u64 = 64_000_000;
const WORKER_STACK = 8 * 1024 * 1024;

pub const State = enum(u8) {
    running = 0,
    done = 1,
    failed = 2,
    cancelled = 3,
};

/// 端末へ渡す形
pub const Format = enum(u8) {
    png = 0, // PNG に符号化（f=100）
    rgb = 1, // 生 RGB（f=24）
    rgba = 2, // 生 RGBA（f=32）
};

pub const Kind = enum(u8) {
    png = 0,
    jpeg = 1,
    gif = 2,
    bmp = 3,
    unsupported = 255,
};

pub const Decoded = struct {
    width: u32,
    height: u32,
    channels: u8,
    pixels: []u8,
};

pub const Job = struct {
    mutex: os.Mutex = .{},
    thread: ?std.Thread = null,
    state: State = .running,
    cancelled: std.atomic.Value(bool) = .init(false),

    path: []u8,
    max_w: u32,
    max_h: u32,
    format: Format,

    kind: Kind = .unsupported,
    src_width: u32 = 0,
    src_height: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    channels: u8 = 0,
    payload: []u8 = &.{}, // Base64 済み

    fn create(path: []const u8, max_w: u32, max_h: u32, format: Format) !*Job {
        const self = try alloc.create(Job);
        errdefer alloc.destroy(self);
        const path_copy = try alloc.dupe(u8, path);
        self.* = .{ .path = path_copy, .max_w = max_w, .max_h = max_h, .format = format };
        return self;
    }

    fn destroy(self: *Job) void {
        if (self.thread) |thread| thread.join();
        alloc.free(self.path);
        if (self.payload.len > 0) alloc.free(self.payload);
        alloc.destroy(self);
    }

    fn finish(self: *Job, state: State) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.state == .running) self.state = state;
    }

    fn run(self: *Job) void {
        const ok = self.work() catch false;
        if (!ok) self.finish(.failed) else self.finish(.done);
    }

    fn work(self: *Job) !bool {
        const data = readFile(self.path) catch return false;
        defer alloc.free(data);
        if (self.cancelled.load(.acquire)) {
            self.finish(.cancelled);
            return true;
        }

        const kind = detect(data);
        self.mutex.lock();
        self.kind = kind;
        self.mutex.unlock();

        const image = decodeImage(kind, data) catch return false;
        defer alloc.free(image.pixels);

        if (self.cancelled.load(.acquire)) {
            self.finish(.cancelled);
            return true;
        }

        // ペインに収まるピクセルへ縮小する（拡大はしない）
        const target = resize_mod.fit(image.width, image.height, self.max_w, self.max_h);
        var out_pixels = image.pixels;
        var scaled: []u8 = &.{};
        defer if (scaled.len > 0) alloc.free(scaled);
        if (target[0] != image.width or target[1] != image.height) {
            scaled = try alloc.alloc(u8, @as(usize, target[0]) * target[1] * image.channels);
            resize_mod.resize(image.pixels, image.width, image.height, scaled, target[0], target[1], image.channels);
            out_pixels = scaled;
        }

        if (self.cancelled.load(.acquire)) {
            self.finish(.cancelled);
            return true;
        }

        const encoded = try encodePayload(self.format, out_pixels, target[0], target[1], image.channels);
        defer alloc.free(encoded);
        const base64 = try encodeBase64(encoded);

        self.mutex.lock();
        defer self.mutex.unlock();
        self.src_width = image.width;
        self.src_height = image.height;
        self.width = target[0];
        self.height = target[1];
        self.channels = if (self.format == .rgba) 4 else if (self.format == .rgb) 3 else image.channels;
        self.payload = base64;
        return true;
    }
};

/// シグネチャで形式を判定する（拡張子は見ない）
pub fn detect(data: []const u8) Kind {
    if (data.len >= 8 and std.mem.eql(u8, data[0..8], png.SIGNATURE)) return .png;
    if (data.len >= 3 and data[0] == 0xff and data[1] == 0xd8 and data[2] == 0xff) return .jpeg;
    if (data.len >= 4 and std.mem.eql(u8, data[0..4], "GIF8")) return .gif;
    if (data.len >= 2 and data[0] == 'B' and data[1] == 'M') return .bmp;
    return .unsupported;
}

pub fn decodeImage(kind: Kind, data: []const u8) !Decoded {
    return switch (kind) {
        .png => blk: {
            const image = try png.decode(alloc, data, MAX_PIXELS);
            break :blk Decoded{
                .width = image.width,
                .height = image.height,
                .channels = image.channels,
                .pixels = image.pixels,
            };
        },
        .jpeg => blk: {
            const image = try jpeg.decode(alloc, data, MAX_PIXELS);
            break :blk Decoded{
                .width = image.width,
                .height = image.height,
                .channels = image.channels,
                .pixels = image.pixels,
            };
        },
        .bmp => blk: {
            const image = try bmp.decode(alloc, data, MAX_PIXELS);
            break :blk Decoded{
                .width = image.width,
                .height = image.height,
                .channels = image.channels,
                .pixels = image.pixels,
            };
        },
        // GIF は LZW が必要で未対応。Ruby 側がテキスト表示に落とす
        .gif, .unsupported => error.UnsupportedFormat,
    };
}

fn encodePayload(format: Format, pixels: []const u8, width: u32, height: u32, channels: u8) ![]u8 {
    return switch (format) {
        .png => try png.encode(alloc, pixels, width, height, channels),
        .rgb => if (channels == 3) try alloc.dupe(u8, pixels) else try dropAlpha(pixels, width, height),
        .rgba => if (channels == 4) try alloc.dupe(u8, pixels) else try addAlpha(pixels, width, height),
    };
}

fn dropAlpha(pixels: []const u8, width: u32, height: u32) ![]u8 {
    const count = @as(usize, width) * height;
    const out = try alloc.alloc(u8, count * 3);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        out[i * 3] = pixels[i * 4];
        out[i * 3 + 1] = pixels[i * 4 + 1];
        out[i * 3 + 2] = pixels[i * 4 + 2];
    }
    return out;
}

fn addAlpha(pixels: []const u8, width: u32, height: u32) ![]u8 {
    const count = @as(usize, width) * height;
    const out = try alloc.alloc(u8, count * 4);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        out[i * 4] = pixels[i * 3];
        out[i * 4 + 1] = pixels[i * 3 + 1];
        out[i * 4 + 2] = pixels[i * 3 + 2];
        out[i * 4 + 3] = 255;
    }
    return out;
}

fn encodeBase64(data: []const u8) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const out = try alloc.alloc(u8, encoder.calcSize(data.len));
    _ = encoder.encode(out, data);
    return out;
}

/// ファイルを丸ごと読む（os.zig の読み取り口を使うので Windows でも同じ経路）
fn readFile(path: []const u8) ![]u8 {
    var scratch: os.Scratch = .{};
    try scratch.init();
    defer scratch.deinit();

    // os.openRead は NUL 終端のパスを取る
    const path_z = try alloc.allocSentinel(u8, path.len, 0);
    defer alloc.free(path_z);
    @memcpy(path_z[0..path.len], path);

    const file = os.openRead(path_z, &scratch) orelse return error.OpenFailed;
    defer file.close();

    var buffer = try alloc.alloc(u8, 256 * 1024);
    errdefer alloc.free(buffer);
    var read: usize = 0;
    while (true) {
        if (read == buffer.len) {
            if (buffer.len >= MAX_BYTES) return error.TooLarge;
            buffer = try alloc.realloc(buffer, @min(buffer.len * 2, MAX_BYTES));
        }
        const n = file.pread(buffer[read..], read) orelse return error.ReadFailed;
        if (n == 0) break;
        read += n;
    }
    if (read == 0) return error.Empty;
    return try alloc.realloc(buffer, read);
}

// ============================================================
// C ABI（Ruby からは Fiddle でハンドル（u64）だけを扱う）
// ============================================================

/// API の世代。Ruby 側が機能の有無を判断する
export fn core_image_version() [*:0]const u8 {
    return "1";
}

/// 1 セルのピクセル寸法（端末が報告しない場合は -1）
export fn core_image_cell_pixels(width: *u32, height: *u32) i32 {
    const size = cellPixels() orelse return -1;
    width.* = size[0];
    height.* = size[1];
    return 0;
}

fn cellPixels() ?[2]u32 {
    const builtin = @import("builtin");
    if (builtin.os.tag == .windows) return null;

    const Winsize = extern struct {
        rows: u16 = 0,
        cols: u16 = 0,
        xpixel: u16 = 0,
        ypixel: u16 = 0,
    };
    var size: Winsize = .{};
    // TIOCGWINSZ（OS ごとに番号が違う）
    const request: u32 = switch (builtin.os.tag) {
        .linux => 0x5413,
        .macos => 0x40087468,
        else => return null,
    };
    if (std.c.ioctl(1, @bitCast(request), @intFromPtr(&size)) != 0) return null;
    if (size.cols == 0 or size.rows == 0 or size.xpixel == 0 or size.ypixel == 0) return null;
    return .{ size.xpixel / size.cols, size.ypixel / size.rows };
}

/// デコードを別スレッドで始める。戻り値はハンドル（0 は失敗）
export fn core_image_create(
    path_ptr: [*]const u8,
    path_len: usize,
    max_w: u32,
    max_h: u32,
    format: u8,
) u64 {
    if (path_len == 0 or path_len > 4096) return 0;
    const kind = std.enums.fromInt(Format, format) orelse return 0;
    const job = Job.create(path_ptr[0..path_len], max_w, max_h, kind) catch return 0;
    job.thread = std.Thread.spawn(.{ .stack_size = WORKER_STACK }, Job.run, .{job}) catch {
        job.destroy();
        return 0;
    };
    return @intFromPtr(job);
}

fn handleToJob(handle: u64) ?*Job {
    if (handle == 0) return null;
    return @ptrFromInt(handle);
}

export fn core_image_state(handle: u64) u8 {
    const job = handleToJob(handle) orelse return @intFromEnum(State.failed);
    job.mutex.lock();
    defer job.mutex.unlock();
    return @intFromEnum(job.state);
}

/// 結果の寸法と形式を取り出す（done 以外では -1。kind は常に入る）
export fn core_image_info(
    handle: u64,
    width: *u32,
    height: *u32,
    src_width: *u32,
    src_height: *u32,
    channels: *u8,
    kind: *u8,
) i32 {
    const job = handleToJob(handle) orelse return -1;
    job.mutex.lock();
    defer job.mutex.unlock();
    kind.* = @intFromEnum(job.kind);
    if (job.state != .done) return -1;
    width.* = job.width;
    height.* = job.height;
    src_width.* = job.src_width;
    src_height.* = job.src_height;
    channels.* = job.channels;
    return 0;
}

/// Base64 済みのペイロード（done 以外では null）
export fn core_image_payload(handle: u64, len: *usize) ?[*]const u8 {
    const job = handleToJob(handle) orelse return null;
    job.mutex.lock();
    defer job.mutex.unlock();
    if (job.state != .done or job.payload.len == 0) return null;
    len.* = job.payload.len;
    return job.payload.ptr;
}

export fn core_image_cancel(handle: u64) void {
    const job = handleToJob(handle) orelse return;
    job.cancelled.store(true, .release);
}

export fn core_image_destroy(handle: u64) void {
    const job = handleToJob(handle) orelse return;
    job.cancelled.store(true, .release);
    job.destroy();
}
