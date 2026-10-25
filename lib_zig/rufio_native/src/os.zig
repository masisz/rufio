//! 検索・スキャナーが使う OS 抽象層（macOS / Linux / Windows）。
//!
//! - macOS: getattrlistbulk で名前・種別・サイズ・mtime・inode を一括取得し、openat で開く
//! - Linux: getdents64 と statx を直接システムコールで呼ぶ（古い glibc でも動くよう libc を経由しない）
//! - Windows: FindFirstFileExW（LARGE_FETCH）で属性ごと列挙し、CreateFileW/ReadFile で読む
//!
//! パスは常に UTF-8・区切り文字 '/' で受け渡す（Ruby の File.join と同じ形）。
const std = @import("std");
const builtin = @import("builtin");
const c = std.c;
const linux = std.os.linux;

pub const is_windows = builtin.os.tag == .windows;
pub const is_darwin = builtin.os.tag.isDarwin();
pub const is_linux = builtin.os.tag == .linux;

/// キャッシュの有効性判定に使うファイル属性
pub const FileMeta = struct {
    mtime_sec: i64,
    mtime_nsec: i64,
    ino: u64,
    size: u64,

    pub fn eql(a: FileMeta, b: FileMeta) bool {
        return a.mtime_sec == b.mtime_sec and a.mtime_nsec == b.mtime_nsec and a.ino == b.ino and a.size == b.size;
    }
};

pub const DirKey = struct { dev: u64, ino: u64 };

pub const Kind = enum { file, dir, symlink, unknown, other };

pub const Entry = struct {
    name: [:0]const u8,
    kind: Kind,
    /// 通常ファイルで属性が取れた場合のみ
    meta: ?FileMeta,
};

/// stat 相当の情報（スキャナーとシンボリックリンク解決用）
pub const Info = struct {
    kind: Kind,
    size: u64,
    mtime_sec: i64,
    executable: bool,
};

// ============================================================
// 同期プリミティブ
// ============================================================

const win = struct {
    const INVALID_HANDLE: usize = std.math.maxInt(usize);
    const GENERIC_READ: u32 = 0x80000000;
    const FILE_READ_ATTRIBUTES: u32 = 0x80;
    const FILE_SHARE_ALL: u32 = 0x7;
    const OPEN_EXISTING: u32 = 3;
    const FILE_FLAG_BACKUP_SEMANTICS: u32 = 0x02000000;
    const FILE_FLAG_SEQUENTIAL_SCAN: u32 = 0x08000000;
    const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
    const FILE_ATTRIBUTE_DEVICE: u32 = 0x40;
    const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
    const FIND_EX_INFO_BASIC: c_int = 1;
    const FIND_FIRST_EX_LARGE_FETCH: u32 = 2;
    const ERROR_FILE_NOT_FOUND: u32 = 2;
    const ERROR_NO_MORE_FILES: u32 = 18;
    const INFINITE: u32 = 0xFFFFFFFF;

    const FILETIME = extern struct { low: u32, high: u32 };

    const FindData = extern struct {
        attributes: u32,
        creation: FILETIME,
        access: FILETIME,
        write: FILETIME,
        size_high: u32,
        size_low: u32,
        reserved0: u32,
        reserved1: u32,
        name: [260]u16,
        alt_name: [14]u16,
    };

    const ByHandleInfo = extern struct {
        attributes: u32,
        creation: FILETIME,
        access: FILETIME,
        write: FILETIME,
        volume_serial: u32,
        size_high: u32,
        size_low: u32,
        links: u32,
        index_high: u32,
        index_low: u32,
    };

    extern "kernel32" fn AcquireSRWLockExclusive(lock: *?*anyopaque) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(lock: *?*anyopaque) callconv(.winapi) void;
    extern "kernel32" fn SleepConditionVariableSRW(cv: *?*anyopaque, lock: *?*anyopaque, ms: u32, flags: u32) callconv(.winapi) c_int;
    extern "kernel32" fn WakeConditionVariable(cv: *?*anyopaque) callconv(.winapi) void;
    extern "kernel32" fn WakeAllConditionVariable(cv: *?*anyopaque) callconv(.winapi) void;
    extern "kernel32" fn FindFirstFileExW(name: [*:0]const u16, level: c_int, data: *FindData, op: c_int, filter: ?*anyopaque, flags: u32) callconv(.winapi) usize;
    extern "kernel32" fn FindNextFileW(handle: usize, data: *FindData) callconv(.winapi) c_int;
    extern "kernel32" fn FindClose(handle: usize) callconv(.winapi) c_int;
    extern "kernel32" fn CreateFileW(name: [*:0]const u16, access: u32, share: u32, security: ?*anyopaque, disposition: u32, flags: u32, template: ?*anyopaque) callconv(.winapi) usize;
    extern "kernel32" fn ReadFile(handle: usize, buf: [*]u8, len: u32, read: *u32, overlapped: ?*anyopaque) callconv(.winapi) c_int;
    extern "kernel32" fn CloseHandle(handle: usize) callconv(.winapi) c_int;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    extern "kernel32" fn GetFileInformationByHandle(handle: usize, info: *ByHandleInfo) callconv(.winapi) c_int;
    extern "kernel32" fn QueryPerformanceCounter(count: *i64) callconv(.winapi) c_int;
    extern "kernel32" fn QueryPerformanceFrequency(freq: *i64) callconv(.winapi) c_int;
    extern "kernel32" fn Sleep(ms: u32) callconv(.winapi) void;
    extern "kernel32" fn GetStdHandle(which: u32) callconv(.winapi) usize;
    extern "kernel32" fn WriteFile(handle: usize, buf: [*]const u8, len: u32, written: *u32, overlapped: ?*anyopaque) callconv(.winapi) c_int;

    fn ticks(ft: FILETIME) i64 {
        return @bitCast((@as(u64, ft.high) << 32) | ft.low);
    }

    /// FILETIME（1601 年起点・100ns 単位）を Unix 秒に変換
    fn unixSeconds(ft: FILETIME) i64 {
        return @divFloor(ticks(ft), 10_000_000) - 11_644_473_600;
    }
};

pub const Mutex = if (is_windows) struct {
    srw: ?*anyopaque = null,

    pub fn lock(self: *@This()) void {
        win.AcquireSRWLockExclusive(&self.srw);
    }
    pub fn unlock(self: *@This()) void {
        win.ReleaseSRWLockExclusive(&self.srw);
    }
} else struct {
    inner: c.pthread_mutex_t = .{},

    pub fn lock(self: *@This()) void {
        _ = c.pthread_mutex_lock(&self.inner);
    }
    pub fn unlock(self: *@This()) void {
        _ = c.pthread_mutex_unlock(&self.inner);
    }
};

pub const Cond = if (is_windows) struct {
    cv: ?*anyopaque = null,

    pub fn wait(self: *@This(), mutex: *Mutex) void {
        _ = win.SleepConditionVariableSRW(&self.cv, &mutex.srw, win.INFINITE, 0);
    }
    pub fn signal(self: *@This()) void {
        win.WakeConditionVariable(&self.cv);
    }
    pub fn broadcast(self: *@This()) void {
        win.WakeAllConditionVariable(&self.cv);
    }
} else struct {
    inner: c.pthread_cond_t = .{},

    pub fn wait(self: *@This(), mutex: *Mutex) void {
        _ = c.pthread_cond_wait(&self.inner, &mutex.inner);
    }
    pub fn signal(self: *@This()) void {
        _ = c.pthread_cond_signal(&self.inner);
    }
    pub fn broadcast(self: *@This()) void {
        _ = c.pthread_cond_broadcast(&self.inner);
    }
};

// ============================================================
// エラー
// ============================================================

extern "c" fn strerror(errnum: c_int) [*:0]const u8;

/// 直前に失敗した操作のエラーコード
pub const ErrorCode = u32;

threadlocal var last_error: ErrorCode = 0;

fn setPosixError(rc: usize) void {
    last_error = @intFromEnum(linux.errno(rc));
}

fn captureError() void {
    if (is_windows) {
        last_error = win.GetLastError();
    } else if (!is_linux) {
        last_error = @intCast(@intFromEnum(c.errno(-1)));
    }
}

/// Ruby 側のエラー表示用メッセージ
pub fn lastErrorMessage() []const u8 {
    if (is_windows) {
        return switch (last_error) {
            2, 3 => "No such file or directory",
            5 => "Permission denied",
            32, 33 => "Device or resource busy",
            else => "Windows error",
        };
    }
    return std.mem.span(strerror(@intCast(last_error)));
}

// ============================================================
// macOS: getattrlistbulk
// ============================================================

extern "c" fn getattrlistbulk(dirfd: c_int, attr_list: *const AttrList, buf: [*]u8, size: usize, options: u64) c_int;

const AttrList = extern struct {
    bitmapcount: u16 = 5,
    reserved: u16 = 0,
    commonattr: u32 = 0,
    volattr: u32 = 0,
    dirattr: u32 = 0,
    fileattr: u32 = 0,
    forkattr: u32 = 0,
};

const ATTR_CMN_NAME: u32 = 0x00000001;
const ATTR_CMN_OBJTYPE: u32 = 0x00000008;
const ATTR_CMN_MODTIME: u32 = 0x00000400;
const ATTR_CMN_FILEID: u32 = 0x02000000;
const ATTR_CMN_RETURNED_ATTRS: u32 = 0x80000000;
const ATTR_FILE_DATALENGTH: u32 = 0x00000200;
const FSOPT_PACK_INVAL_ATTRS: u64 = 0x00000008;
const VREG: u32 = 1;
const VDIR: u32 = 2;
const VLNK: u32 = 5;

const bulk_attrs = AttrList{
    .commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME | ATTR_CMN_FILEID,
    .fileattr = ATTR_FILE_DATALENGTH,
};

// ============================================================
// ディレクトリ
// ============================================================

/// ディレクトリ読み込み用の作業領域（スレッドごとに 1 つ）
pub const Scratch = struct {
    pub const DIR_BUFFER = 64 * 1024;
    /// Windows の長いパス（\\?\ 形式）にも足りる UTF-16 バッファ
    const WIDE_LEN = 32 * 1024;

    buf: []u8 = &.{},
    wide: []u16 = &.{},
    name: []u8 = &.{},

    pub fn init(self: *Scratch) !void {
        const alloc = std.heap.c_allocator;
        self.buf = try alloc.alloc(u8, DIR_BUFFER);
        if (is_windows) {
            self.wide = try alloc.alloc(u16, WIDE_LEN);
            self.name = try alloc.alloc(u8, 260 * 3 + 1);
        }
    }

    pub fn deinit(self: *Scratch) void {
        const alloc = std.heap.c_allocator;
        if (self.buf.len > 0) alloc.free(self.buf);
        if (self.wide.len > 0) alloc.free(self.wide);
        if (self.name.len > 0) alloc.free(self.name);
        self.* = .{};
    }

    /// UTF-8 のパス（dir と name を '/' で連結）を Win32 用の UTF-16 に変換する
    fn widePath(self: *Scratch, dir: []const u8, name: []const u8) ?[*:0]const u16 {
        const total = dir.len + 1 + name.len;
        // 260 文字制限を超えるパスは \\?\ 形式（区切りは '\' 必須）にする
        const long = total >= 248;
        var w: usize = 0;
        if (long) {
            const prefix = if (std.mem.startsWith(u8, dir, "//")) "\\\\?\\UNC\\" else "\\\\?\\";
            for (prefix) |ch| {
                self.wide[w] = ch;
                w += 1;
            }
        }
        const dir_part = if (long and std.mem.startsWith(u8, dir, "//")) dir[2..] else dir;
        w += appendWide(self.wide[w..], dir_part, long) orelse return null;
        if (name.len > 0) {
            if (w + 1 >= self.wide.len) return null;
            self.wide[w] = if (long) '\\' else '/';
            w += 1;
            w += appendWide(self.wide[w..], name, long) orelse return null;
        }
        if (w >= self.wide.len) return null;
        self.wide[w] = 0;
        return self.wide[0..w :0].ptr;
    }

    fn appendWide(dst: []u16, utf8: []const u8, backslash: bool) ?usize {
        const need = std.unicode.calcWtf16LeLen(utf8) catch return null;
        if (need + 1 > dst.len) return null;
        const n = std.unicode.wtf8ToWtf16Le(dst, utf8) catch return null;
        if (backslash) {
            for (dst[0..n]) |*ch| {
                if (ch.* == '/') ch.* = '\\';
            }
        }
        return n;
    }
};

pub const Dir = struct {
    scratch: *Scratch,
    path: []const u8,
    // POSIX
    fd: c_int = -1,
    used: usize = 0,
    offset: usize = 0,
    remaining: c_int = 0,
    // Windows
    find: usize = win.INVALID_HANDLE,
    find_data: if (is_windows) win.FindData else void = undefined,
    pending: bool = false,

    /// path は NUL 終端の UTF-8（'/' 区切り）
    pub fn open(path: [:0]const u8, scratch: *Scratch) ?Dir {
        var self = Dir{ .scratch = scratch, .path = path };
        if (is_windows) {
            const pattern = scratch.widePath(path, "*") orelse {
                last_error = 3;
                return null;
            };
            self.find = win.FindFirstFileExW(pattern, win.FIND_EX_INFO_BASIC, &self.find_data, 0, null, win.FIND_FIRST_EX_LARGE_FETCH);
            if (self.find == win.INVALID_HANDLE) {
                captureError();
                // 空のドライブ直下などは「エントリなし」として扱う
                if (last_error == win.ERROR_FILE_NOT_FOUND) return self;
                return null;
            }
            self.pending = true;
            return self;
        }
        if (is_linux) {
            const rc = linux.openat(linux.AT.FDCWD, path.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
            if (linux.errno(rc) != .SUCCESS) {
                setPosixError(rc);
                return null;
            }
            self.fd = @intCast(rc);
            return self;
        }
        self.fd = c.open(path.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true });
        if (self.fd < 0) {
            captureError();
            return null;
        }
        return self;
    }

    pub fn close(self: *Dir) void {
        if (is_windows) {
            if (self.find != win.INVALID_HANDLE) _ = win.FindClose(self.find);
            self.find = win.INVALID_HANDLE;
        } else if (is_linux) {
            if (self.fd >= 0) _ = linux.close(self.fd);
        } else {
            if (self.fd >= 0) _ = c.close(self.fd);
        }
        self.fd = -1;
    }

    /// 重複走査の判定用 ID（取得できなければ null）
    pub fn identity(self: *Dir) ?DirKey {
        if (is_windows) {
            const wide = self.scratch.widePath(self.path, "") orelse return null;
            const h = win.CreateFileW(wide, win.FILE_READ_ATTRIBUTES, win.FILE_SHARE_ALL, null, win.OPEN_EXISTING, win.FILE_FLAG_BACKUP_SEMANTICS, null);
            if (h == win.INVALID_HANDLE) return null;
            defer _ = win.CloseHandle(h);
            var info: win.ByHandleInfo = undefined;
            if (win.GetFileInformationByHandle(h, &info) == 0) return null;
            return .{ .dev = info.volume_serial, .ino = (@as(u64, info.index_high) << 32) | info.index_low };
        }
        if (is_linux) {
            var stx: linux.Statx = undefined;
            const rc = linux.statx(self.fd, "", linux.AT.EMPTY_PATH, .{ .INO = true }, &stx);
            if (linux.errno(rc) != .SUCCESS) return null;
            return .{ .dev = (@as(u64, stx.dev_major) << 32) | stx.dev_minor, .ino = stx.ino };
        }
        var st: c.Stat = undefined;
        if (c.fstat(self.fd, &st) != 0) return null;
        return .{ .dev = @bitCast(@as(i64, st.dev)), .ino = st.ino };
    }

    /// 次のエントリ。終端は null、読み込みエラーは error.ReadFailed
    pub fn next(self: *Dir) error{ReadFailed}!?Entry {
        if (is_windows) return self.nextWindows();
        if (is_linux) return self.nextLinux();
        return self.nextDarwin();
    }

    fn nextDarwin(self: *Dir) error{ReadFailed}!?Entry {
        const buf = self.scratch.buf;
        while (true) {
            if (self.remaining == 0) {
                const n = getattrlistbulk(self.fd, &bulk_attrs, buf.ptr, buf.len, FSOPT_PACK_INVAL_ATTRS);
                if (n < 0) {
                    captureError();
                    if (c.errno(-1) == .INTR) continue;
                    return error.ReadFailed;
                }
                if (n == 0) return null;
                self.remaining = n;
                self.offset = 0;
            }
            self.remaining -= 1;
            // レイアウト: length, returned_attrs[5], name_ref{off,len}, objtype, modtime, fileid, datalength
            const entry = buf.ptr + self.offset;
            const length = std.mem.readInt(u32, entry[0..4], .little);
            self.offset += length;
            const returned_common = std.mem.readInt(u32, entry[4..8], .little);
            const returned_file = std.mem.readInt(u32, entry[16..20], .little);
            const name_ref = entry + 24;
            const name_off = std.mem.readInt(i32, name_ref[0..4], .little);
            const name_len = std.mem.readInt(u32, name_ref[4..8], .little);
            const objtype = std.mem.readInt(u32, entry[32..36], .little);
            if (name_len <= 1) continue;
            // name_len は終端 NUL を含む
            const name_ptr: [*:0]const u8 = @ptrCast(name_ref + @as(usize, @intCast(name_off)));
            const name = name_ptr[0 .. name_len - 1 :0];
            const has_meta = returned_file & ATTR_FILE_DATALENGTH != 0 and
                returned_common & (ATTR_CMN_MODTIME | ATTR_CMN_FILEID) == (ATTR_CMN_MODTIME | ATTR_CMN_FILEID);
            const kind: Kind = switch (objtype) {
                VREG => .file,
                VDIR => .dir,
                VLNK => .symlink,
                else => .other,
            };
            const meta: ?FileMeta = if (kind == .file and has_meta) .{
                .mtime_sec = std.mem.readInt(i64, entry[36..44], .little),
                .mtime_nsec = std.mem.readInt(i64, entry[44..52], .little),
                .ino = std.mem.readInt(u64, entry[52..60], .little),
                .size = std.mem.readInt(u64, entry[60..68], .little),
            } else null;
            return .{ .name = name, .kind = kind, .meta = meta };
        }
    }

    fn nextLinux(self: *Dir) error{ReadFailed}!?Entry {
        const buf = self.scratch.buf;
        while (true) {
            if (self.offset >= self.used) {
                const rc = linux.getdents64(self.fd, buf.ptr, @intCast(buf.len));
                switch (linux.errno(rc)) {
                    .SUCCESS => {},
                    .INTR => continue,
                    else => {
                        setPosixError(rc);
                        return error.ReadFailed;
                    },
                }
                if (rc == 0) return null;
                self.used = rc;
                self.offset = 0;
            }
            const ent: *align(1) const linux.dirent64 = @ptrCast(buf.ptr + self.offset);
            self.offset += ent.reclen;
            const name_ptr: [*:0]const u8 = @ptrCast(&ent.name);
            const name = std.mem.span(name_ptr);
            if (isDotEntry(name)) continue;
            var kind: Kind = switch (ent.type) {
                linux.DT.REG => .file,
                linux.DT.DIR => .dir,
                linux.DT.LNK => .symlink,
                linux.DT.UNKNOWN => .unknown,
                else => .other,
            };
            var meta: ?FileMeta = null;
            if (kind == .file or kind == .unknown) {
                if (self.statLinux(name, false)) |stx| {
                    kind = kindFromMode(stx.mode);
                    if (kind == .file) meta = metaFromStatx(&stx);
                }
            }
            return .{ .name = name, .kind = kind, .meta = meta };
        }
    }

    fn nextWindows(self: *Dir) error{ReadFailed}!?Entry {
        while (true) {
            if (self.find == win.INVALID_HANDLE) return null;
            if (!self.pending) {
                if (win.FindNextFileW(self.find, &self.find_data) == 0) {
                    captureError();
                    if (last_error == win.ERROR_NO_MORE_FILES) return null;
                    return error.ReadFailed;
                }
            }
            self.pending = false;
            const data = &self.find_data;
            const wide = std.mem.sliceTo(&data.name, 0);
            const n = std.unicode.wtf16LeToWtf8(self.scratch.name, wide);
            self.scratch.name[n] = 0;
            const name = self.scratch.name[0..n :0];
            if (isDotEntry(name)) continue;
            const attrs = data.attributes;
            const kind: Kind = if (attrs & win.FILE_ATTRIBUTE_REPARSE_POINT != 0)
                .symlink
            else if (attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0)
                .dir
            else if (attrs & win.FILE_ATTRIBUTE_DEVICE != 0)
                .other
            else
                .file;
            const meta: ?FileMeta = if (kind == .file) .{
                .mtime_sec = win.ticks(data.write),
                .mtime_nsec = 0,
                .ino = 0,
                .size = (@as(u64, data.size_high) << 32) | data.size_low,
            } else null;
            return .{ .name = name, .kind = kind, .meta = meta };
        }
    }

    fn statLinux(self: *Dir, name: [*:0]const u8, follow: bool) ?linux.Statx {
        var stx: linux.Statx = undefined;
        const flags: u32 = if (follow) 0 else linux.AT.SYMLINK_NOFOLLOW;
        const rc = linux.statx(self.fd, name, flags, .{ .TYPE = true, .MODE = true, .MTIME = true, .INO = true, .SIZE = true }, &stx);
        if (linux.errno(rc) != .SUCCESS) return null;
        return stx;
    }

    /// エントリの stat（follow=true でシンボリックリンクを辿る）
    pub fn stat(self: *Dir, name: [:0]const u8, follow: bool) ?Info {
        if (is_windows) {
            const wide = self.scratch.widePath(self.path, name) orelse return null;
            const flags = win.FILE_FLAG_BACKUP_SEMANTICS | (if (follow) 0 else @as(u32, 0x00200000)); // OPEN_REPARSE_POINT
            const h = win.CreateFileW(wide, win.FILE_READ_ATTRIBUTES, win.FILE_SHARE_ALL, null, win.OPEN_EXISTING, flags, null);
            if (h == win.INVALID_HANDLE) return null;
            defer _ = win.CloseHandle(h);
            var info: win.ByHandleInfo = undefined;
            if (win.GetFileInformationByHandle(h, &info) == 0) return null;
            const attrs = info.attributes;
            return .{
                .kind = if (!follow and attrs & win.FILE_ATTRIBUTE_REPARSE_POINT != 0)
                    .symlink
                else if (attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0)
                    .dir
                else
                    .file,
                .size = (@as(u64, info.size_high) << 32) | info.size_low,
                .mtime_sec = win.unixSeconds(info.write),
                .executable = isWindowsExecutable(name),
            };
        }
        if (is_linux) {
            const stx = self.statLinux(name.ptr, follow) orelse return null;
            return .{
                .kind = kindFromMode(stx.mode),
                .size = stx.size,
                .mtime_sec = stx.mtime.sec,
                .executable = stx.mode & 0o100 != 0,
            };
        }
        var st: c.Stat = undefined;
        if (c.fstatat(self.fd, name.ptr, &st, if (follow) 0 else c.AT.SYMLINK_NOFOLLOW) != 0) return null;
        return .{
            .kind = kindFromMode(st.mode),
            .size = @intCast(st.size),
            .mtime_sec = @intCast(st.mtime().sec),
            .executable = st.mode & c.S.IXUSR != 0,
        };
    }

    /// 現在のエントリのスキャナー用情報（Windows は列挙結果をそのまま使う）
    pub fn currentInfo(self: *Dir, entry: Entry) ?Info {
        if (is_windows) {
            const data = &self.find_data;
            return .{
                .kind = entry.kind,
                .size = (@as(u64, data.size_high) << 32) | data.size_low,
                .mtime_sec = win.unixSeconds(data.write),
                .executable = isWindowsExecutable(entry.name),
            };
        }
        return self.stat(entry.name, false);
    }

    pub fn openFile(self: *Dir, name: [:0]const u8) ?File {
        if (is_windows) {
            const wide = self.scratch.widePath(self.path, name) orelse {
                last_error = 3;
                return null;
            };
            const h = win.CreateFileW(wide, win.GENERIC_READ, win.FILE_SHARE_ALL, null, win.OPEN_EXISTING, win.FILE_FLAG_SEQUENTIAL_SCAN, null);
            if (h == win.INVALID_HANDLE) {
                captureError();
                return null;
            }
            return .{ .handle = h };
        }
        if (is_linux) {
            const rc = linux.openat(self.fd, name.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
            if (linux.errno(rc) != .SUCCESS) {
                setPosixError(rc);
                return null;
            }
            return .{ .handle = rc };
        }
        const fd = c.openat(self.fd, name.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true });
        if (fd < 0) {
            captureError();
            return null;
        }
        return .{ .handle = @intCast(fd) };
    }
};

pub const File = struct {
    handle: usize,

    /// 読めたバイト数（0 は EOF）。エラー時は null
    pub fn read(self: File, dst: []u8) ?usize {
        if (is_windows) {
            var got: u32 = 0;
            const len: u32 = @intCast(@min(dst.len, std.math.maxInt(u32)));
            if (win.ReadFile(self.handle, dst.ptr, len, &got, null) == 0) {
                captureError();
                return null;
            }
            return got;
        }
        while (true) {
            if (is_linux) {
                const rc = linux.read(@intCast(self.handle), dst.ptr, dst.len);
                switch (linux.errno(rc)) {
                    .SUCCESS => return rc,
                    .INTR => continue,
                    else => {
                        setPosixError(rc);
                        return null;
                    },
                }
            }
            const n = c.read(@intCast(self.handle), dst.ptr, dst.len);
            if (n >= 0) return @intCast(n);
            captureError();
            if (c.errno(-1) == .INTR) continue;
            return null;
        }
    }

    pub fn close(self: File) void {
        if (is_windows) {
            _ = win.CloseHandle(self.handle);
        } else if (is_linux) {
            _ = linux.close(@intCast(self.handle));
        } else {
            _ = c.close(@intCast(self.handle));
        }
    }
};

fn isDotEntry(name: []const u8) bool {
    return name.len == 0 or (name[0] == '.' and (name.len == 1 or (name.len == 2 and name[1] == '.')));
}

fn kindFromMode(mode: anytype) Kind {
    const m: u32 = @intCast(mode);
    return switch (m & 0o170000) {
        0o100000 => .file,
        0o040000 => .dir,
        0o120000 => .symlink,
        else => .other,
    };
}

fn metaFromStatx(stx: *const linux.Statx) FileMeta {
    return .{ .mtime_sec = stx.mtime.sec, .mtime_nsec = stx.mtime.nsec, .ino = stx.ino, .size = stx.size };
}

/// Ruby の File.executable? と同様、Windows では拡張子で判定する
fn isWindowsExecutable(name: []const u8) bool {
    const exts = [_][]const u8{ ".exe", ".com", ".bat", ".cmd" };
    for (exts) |ext| {
        if (name.len >= ext.len and std.ascii.eqlIgnoreCase(name[name.len - ext.len ..], ext)) return true;
    }
    return false;
}

/// 既定のスレッド数。macOS は性能コア数が最速（効率コアまで使うとカーネル内の競合で逆に遅くなる）
pub fn defaultThreads() usize {
    if (is_darwin) {
        var value: c_int = 0;
        var len: usize = @sizeOf(c_int);
        if (c.sysctlbyname("hw.perflevel0.physicalcpu", &value, &len, null, 0) == 0 and value > 0) {
            return @intCast(value);
        }
    }
    return std.Thread.getCpuCount() catch 4;
}

// ============================================================
// ベンチマーク CLI 用ユーティリティ
// ============================================================

/// 単調増加時計（ナノ秒）
pub fn nowNs() u64 {
    if (is_windows) {
        var count: i64 = 0;
        var freq: i64 = 1;
        _ = win.QueryPerformanceCounter(&count);
        _ = win.QueryPerformanceFrequency(&freq);
        return @intCast(@divFloor(@as(i128, count) * 1_000_000_000, freq));
    }
    var ts: c.timespec = undefined;
    _ = c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

pub fn sleepMicros(us: u32) void {
    if (is_windows) {
        win.Sleep(@max(us / 1000, 1));
        return;
    }
    const ts: c.timespec = .{ .sec = 0, .nsec = @as(c_long, us) * 1000 };
    _ = c.nanosleep(&ts, null);
}

/// fd: 1=標準出力, 2=標準エラー
pub fn writeAll(fd: u8, bytes: []const u8) void {
    var rest = bytes;
    while (rest.len > 0) {
        var n: usize = 0;
        if (is_windows) {
            const handle = win.GetStdHandle(if (fd == 2) @as(u32, @bitCast(@as(i32, -12))) else @as(u32, @bitCast(@as(i32, -11))));
            var written: u32 = 0;
            const len: u32 = @intCast(@min(rest.len, 1 << 30));
            if (win.WriteFile(handle, rest.ptr, len, &written, null) == 0) return;
            n = written;
        } else {
            const rc = c.write(fd, rest.ptr, rest.len);
            if (rc <= 0) return;
            n = @intCast(rc);
        }
        if (n == 0) return;
        rest = rest[n..];
    }
}
