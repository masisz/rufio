//! 画像デコード・縮小・符号化の単体テスト。
//! テスト画像は testdata/ に置いた小さな実ファイル（PNG は Ruby の zlib で、
//! JPEG と BMP はそこから sips で変換して作成）。
const std = @import("std");
const testing = std.testing;
const image = @import("image.zig");
const png = @import("image_png.zig");
const jpeg = @import("image_jpeg.zig");
const bmp = @import("image_bmp.zig");
const resize = @import("image_resize.zig");

const GRADIENT_PNG = @embedFile("testdata/gradient.png");
const ALPHA_PNG = @embedFile("testdata/alpha.png");
const GRADIENT_JPG = @embedFile("testdata/gradient.jpg");
const GRADIENT_BMP = @embedFile("testdata/gradient.bmp");

// gradient.png は 16x12 で、画素は (x*16, y*20, 128)
fn expectedGradient(x: u32, y: u32) [3]u8 {
    return .{ @intCast(x * 16), @intCast(y * 20), 128 };
}

test "形式はシグネチャで判定する" {
    try testing.expectEqual(image.Kind.png, image.detect(GRADIENT_PNG));
    try testing.expectEqual(image.Kind.jpeg, image.detect(GRADIENT_JPG));
    try testing.expectEqual(image.Kind.bmp, image.detect(GRADIENT_BMP));
    try testing.expectEqual(image.Kind.unsupported, image.detect("not an image"));
    try testing.expectEqual(image.Kind.unsupported, image.detect(""));
    try testing.expectEqual(image.Kind.gif, image.detect("GIF89a....."));
}

test "PNG の見出しから寸法を読む" {
    const size = try png.info(GRADIENT_PNG);
    try testing.expectEqual(@as(u32, 16), size[0]);
    try testing.expectEqual(@as(u32, 12), size[1]);
}

test "PNG を RGB に展開する" {
    var decoded = try png.decode(testing.allocator, GRADIENT_PNG, image.MAX_PIXELS);
    defer decoded.deinit(testing.allocator);

    try testing.expectEqual(@as(u32, 16), decoded.width);
    try testing.expectEqual(@as(u32, 12), decoded.height);
    try testing.expectEqual(@as(u8, 3), decoded.channels);

    var y: u32 = 0;
    while (y < decoded.height) : (y += 1) {
        var x: u32 = 0;
        while (x < decoded.width) : (x += 1) {
            const expected = expectedGradient(x, y);
            const offset = (y * decoded.width + x) * 3;
            try testing.expectEqualSlices(u8, &expected, decoded.pixels[offset .. offset + 3]);
        }
    }
}

test "アルファ付き PNG は RGBA になる" {
    var decoded = try png.decode(testing.allocator, ALPHA_PNG, image.MAX_PIXELS);
    defer decoded.deinit(testing.allocator);

    try testing.expectEqual(@as(u8, 4), decoded.channels);
    try testing.expectEqual(@as(u32, 8), decoded.width);
    // alpha.png は (255, 0, 0, x*32)
    try testing.expectEqual(@as(u8, 255), decoded.pixels[0]);
    try testing.expectEqual(@as(u8, 0), decoded.pixels[3]);
    try testing.expectEqual(@as(u8, 32), decoded.pixels[7]);
}

test "PNG を書いて読み戻すと同じ画素になる" {
    var decoded = try png.decode(testing.allocator, GRADIENT_PNG, image.MAX_PIXELS);
    defer decoded.deinit(testing.allocator);

    const encoded = try png.encode(testing.allocator, decoded.pixels, decoded.width, decoded.height, 3);
    defer testing.allocator.free(encoded);
    try testing.expect(std.mem.eql(u8, encoded[0..8], png.SIGNATURE));

    var again = try png.decode(testing.allocator, encoded, image.MAX_PIXELS);
    defer again.deinit(testing.allocator);
    try testing.expectEqual(decoded.width, again.width);
    try testing.expectEqual(decoded.height, again.height);
    try testing.expectEqualSlices(u8, decoded.pixels, again.pixels);
}

test "BMP を展開すると PNG と同じ画素になる" {
    var decoded = try bmp.decode(testing.allocator, GRADIENT_BMP, image.MAX_PIXELS);
    defer decoded.deinit(testing.allocator);

    try testing.expectEqual(@as(u32, 16), decoded.width);
    try testing.expectEqual(@as(u32, 12), decoded.height);
    try testing.expectEqual(@as(u8, 3), decoded.channels);

    var y: u32 = 0;
    while (y < decoded.height) : (y += 1) {
        var x: u32 = 0;
        while (x < decoded.width) : (x += 1) {
            const expected = expectedGradient(x, y);
            const offset = (y * decoded.width + x) * 3;
            try testing.expectEqualSlices(u8, &expected, decoded.pixels[offset .. offset + 3]);
        }
    }
}

test "baseline JPEG を展開すると元の絵に近い画素になる" {
    const size = try jpeg.info(GRADIENT_JPG);
    try testing.expectEqual(@as(u32, 16), size[0]);
    try testing.expectEqual(@as(u32, 12), size[1]);

    var decoded = try jpeg.decode(testing.allocator, GRADIENT_JPG, image.MAX_PIXELS);
    defer decoded.deinit(testing.allocator);

    try testing.expectEqual(@as(u32, 16), decoded.width);
    try testing.expectEqual(@as(u32, 12), decoded.height);
    try testing.expectEqual(@as(u8, 3), decoded.channels);

    // 非可逆なので、各画素が期待値から大きく外れていないことだけを見る
    var max_error: i32 = 0;
    var y: u32 = 0;
    while (y < decoded.height) : (y += 1) {
        var x: u32 = 0;
        while (x < decoded.width) : (x += 1) {
            const expected = expectedGradient(x, y);
            const offset = (y * decoded.width + x) * 3;
            var c: usize = 0;
            while (c < 3) : (c += 1) {
                const diff = @as(i32, decoded.pixels[offset + c]) - @as(i32, expected[c]);
                max_error = @max(max_error, @as(i32, @intCast(@abs(diff))));
            }
        }
    }
    try testing.expect(max_error <= 32);
}

test "プログレッシブ JPEG は非対応として断る" {
    // SOF2（プログレッシブ）の見出しだけを組み立てる
    var data: [24]u8 = @splat(0);
    data[0] = 0xff;
    data[1] = 0xd8;
    data[2] = 0xff;
    data[3] = 0xc2; // SOF2
    data[4] = 0x00;
    data[5] = 0x11; // length = 17
    data[6] = 8; // precision
    data[7] = 0;
    data[8] = 16; // height
    data[9] = 0;
    data[10] = 16; // width
    data[11] = 3; // components
    try testing.expectError(jpeg.Error.UnsupportedJpeg, jpeg.decode(testing.allocator, &data, image.MAX_PIXELS));
}

test "壊れた入力でも落ちずにエラーを返す" {
    try testing.expectError(png.Error.InvalidPng, png.decode(testing.allocator, "not a png at all", image.MAX_PIXELS));
    try testing.expectError(bmp.Error.InvalidBmp, bmp.decode(testing.allocator, "BM", image.MAX_PIXELS));
    try testing.expectError(jpeg.Error.InvalidJpeg, jpeg.decode(testing.allocator, "\xff\xd8\xff", image.MAX_PIXELS));

    // 途中で切れた PNG
    try testing.expectError(png.Error.InvalidPng, png.decode(testing.allocator, GRADIENT_PNG[0..40], image.MAX_PIXELS));
}

test "画素数の上限を超える画像は断る" {
    // IHDR だけを書き換えて巨大な寸法を名乗る PNG を作る
    var data = try testing.allocator.dupe(u8, GRADIENT_PNG);
    defer testing.allocator.free(data);
    std.mem.writeInt(u32, data[16..20], 40000, .big);
    std.mem.writeInt(u32, data[20..24], 40000, .big); // 16 億画素

    try testing.expectError(png.Error.TooLarge, png.decode(testing.allocator, data, image.MAX_PIXELS));
}

test "縮小後の寸法は比を保ち、拡大はしない" {
    try testing.expectEqual([2]u32{ 100, 50 }, resize.fit(200, 100, 100, 100));
    try testing.expectEqual([2]u32{ 50, 100 }, resize.fit(100, 200, 100, 100));
    try testing.expectEqual([2]u32{ 40, 30 }, resize.fit(40, 30, 100, 100)); // 小さい画像はそのまま
    try testing.expectEqual([2]u32{ 1, 1 }, resize.fit(1000, 1, 1, 1));
    try testing.expectEqual([2]u32{ 0, 0 }, resize.fit(0, 0, 10, 10));
}

test "縮小は面積平均で行う" {
    // 2x2 の 1 色ずつを 1x1 にすると平均になる
    const src = [_]u8{
        0,   0,   0,   255, 255, 255,
        255, 255, 255, 0,   0,   0,
    };
    var dst: [3]u8 = @splat(0);
    resize.resize(&src, 2, 2, &dst, 1, 1, 3);
    try testing.expectEqual(@as(u8, 128), dst[0]);
    try testing.expectEqual(@as(u8, 128), dst[1]);
    try testing.expectEqual(@as(u8, 128), dst[2]);
}

test "縮小しても端の画素は元の色に近い" {
    var decoded = try png.decode(testing.allocator, GRADIENT_PNG, image.MAX_PIXELS);
    defer decoded.deinit(testing.allocator);

    const target = resize.fit(decoded.width, decoded.height, 8, 8);
    try testing.expectEqual([2]u32{ 8, 6 }, target);
    const scaled = try testing.allocator.alloc(u8, @as(usize, target[0]) * target[1] * 3);
    defer testing.allocator.free(scaled);
    resize.resize(decoded.pixels, decoded.width, decoded.height, scaled, target[0], target[1], 3);

    // 左上は元の左上（0, 0, 128）の近く、右下は右下（240, 220, 128）の近く
    try testing.expect(scaled[0] < 40);
    try testing.expectEqual(@as(u8, 128), scaled[2]);
    const last = (@as(usize, target[1] - 1) * target[0] + target[0] - 1) * 3;
    try testing.expect(scaled[last] > 200);
}

test "PNG の高速検査は寸法とチャンネル数を返し、壊れた入力を断る" {
    const rgb = try png.inspect(GRADIENT_PNG, image.MAX_PIXELS);
    try testing.expectEqual(@as(u32, 16), rgb.width);
    try testing.expectEqual(@as(u32, 12), rgb.height);
    try testing.expectEqual(@as(u8, 3), rgb.channels);

    const rgba = try png.inspect(ALPHA_PNG, image.MAX_PIXELS);
    try testing.expectEqual(@as(u32, 8), rgba.width);
    try testing.expectEqual(@as(u32, 8), rgba.height);
    try testing.expectEqual(@as(u8, 4), rgba.channels);

    // 途中で切れた PNG（IEND が無い）はエラーになる
    try testing.expectError(png.Error.InvalidPng, png.inspect(GRADIENT_PNG[0..40], image.MAX_PIXELS));
}

test "セキュリティ: 不正な JPEG ハフマン表（符号数オーバーフロー）を安全に拒否する" {
    // 長さ 1bit の符号を 5 個宣言する悪意ある DHT（本来は最大 2 個）
    var data = [_]u8{
        0xff, 0xd8, // SOI
        0xff, 0xc4, 0x00, 0x18, // DHT, len=24 (1 + 16 + 5 + 2)
        0x00, // class=0 (DC), index=0
        5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // counts: len1 = 5 (不正)
        0, 1, 2, 3, 4, // values
        0xff, 0xd9, // EOI
    };
    try testing.expectError(jpeg.Error.InvalidJpeg, jpeg.decode(testing.allocator, &data, image.MAX_PIXELS));
}

test "セキュリティ: JPEG の SOF 重複・SOF 前 SOS・規格外 MCU ブロック数を拒否する" {
    // SOF 前に SOS が来る不正 JPEG
    const sos_before_sof = [_]u8{
        0xff, 0xd8,
        0xff, 0xda, 0x00, 0x03, 0x00,
        0xff, 0xd9,
    };
    try testing.expectError(jpeg.Error.InvalidJpeg, jpeg.decode(testing.allocator, &sos_before_sof, image.MAX_PIXELS));

    // 3 成分すべて h=4, v=4（Σ h*v = 48 > 規格上限 10）の MCU 爆弾
    const huge_mcu = [_]u8{
        0xff, 0xd8,
        0xff, 0xc0, 0x00, 0x11, 8, 0, 16, 0, 16, 3,
        1, 0x44, 0,
        2, 0x44, 0,
        3, 0x44, 0,
        0xff, 0xd9,
    };
    try testing.expectError(jpeg.Error.InvalidJpeg, jpeg.decode(testing.allocator, &huge_mcu, image.MAX_PIXELS));
}

test "セキュリティ: PNG の decompression bomb（展開サイズが寸法を超過）を拒否する" {
    // 1x1 RGB PNG（期待展開サイズは 4 バイト）だが、IDAT に大量の 0 を圧縮して仕込む
    const flate = std.compress.flate;
    var zbuf = try std.Io.Writer.Allocating.initCapacity(testing.allocator, 4096);
    defer zbuf.deinit();
    const window = try testing.allocator.alloc(u8, flate.max_window_len);
    defer testing.allocator.free(window);
    var comp = try flate.Compress.init(&zbuf.writer, window, .zlib, .fastest);
    var zeros: [4096]u8 = @splat(0);
    // 64KB 分のゼロを圧縮（1x1 の期待サイズ 4 バイトを遥かに超える）
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        try comp.writer.writeAll(&zeros);
    }
    try comp.finish();
    try zbuf.writer.flush();
    const idat_body = zbuf.written();

    var bomb: std.ArrayList(u8) = .empty;
    defer bomb.deinit(testing.allocator);
    try bomb.appendSlice(testing.allocator, png.SIGNATURE);
    // IHDR: 1x1, 8bit RGB
    var ihdr = [_]u8{ 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0 };
    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, 13, .big);
    try bomb.appendSlice(testing.allocator, &len_buf);
    try bomb.appendSlice(testing.allocator, "IHDR");
    try bomb.appendSlice(testing.allocator, &ihdr);
    try bomb.appendSlice(testing.allocator, &[_]u8{ 0, 0, 0, 0 });
    // IDAT
    std.mem.writeInt(u32, &len_buf, @intCast(idat_body.len), .big);
    try bomb.appendSlice(testing.allocator, &len_buf);
    try bomb.appendSlice(testing.allocator, "IDAT");
    try bomb.appendSlice(testing.allocator, idat_body);
    try bomb.appendSlice(testing.allocator, &[_]u8{ 0, 0, 0, 0 });
    // IEND
    try bomb.appendSlice(testing.allocator, &[_]u8{ 0, 0, 0, 0, 'I', 'E', 'N', 'D', 0, 0, 0, 0 });

    try testing.expectError(png.Error.InvalidPng, png.decode(testing.allocator, bomb.items, image.MAX_PIXELS));
}

test "セキュリティ: BMP の header_size オーバーフローを安全に拒否する" {
    var bad_bmp: [64]u8 = @splat(0);
    bad_bmp[0] = 'B';
    bad_bmp[1] = 'M';
    std.mem.writeInt(u32, bad_bmp[10..14], 54, .little); // pixel_offset
    std.mem.writeInt(u32, bad_bmp[14..18], 0xffff_fff5, .little); // 14 + header_size が u32 オーバーフロー
    std.mem.writeInt(i32, bad_bmp[18..22], 1, .little);
    std.mem.writeInt(i32, bad_bmp[22..26], 1, .little);
    std.mem.writeInt(u16, bad_bmp[28..30], 8, .little);
    try testing.expectError(bmp.Error.InvalidBmp, bmp.decode(testing.allocator, &bad_bmp, image.MAX_PIXELS));
}

test "セキュリティ: パスに NUL バイトを含む要求は拒否する" {
    const path = "/tmp/foo\x00bar.png";
    try testing.expectEqual(@as(u64, 0), image.core_image_create(path.ptr, path.len, 100, 100, 0));
}

test "セキュリティ: 縮小時の画素合計が u32 上限を超えてもオーバーフローしない" {
    // 4100x4100 = 16,810,000 画素、4200x4200 = 17,640,000 画素（x 255 = 4,498,200,000 > u32 最大値）
    const w: u32 = 4200;
    const h: u32 = 4200;
    const src = try testing.allocator.alloc(u8, @as(usize, w) * h * 3);
    defer testing.allocator.free(src);
    @memset(src, 255);

    var dst: [3]u8 = @splat(0);
    resize.resize(src, w, h, &dst, 1, 1, 3);
    try testing.expectEqualSlices(u8, &[_]u8{ 255, 255, 255 }, &dst);
}

test "セキュリティ: PNG 直送検証は decompression bomb・末尾ゴミ・不正パレット深度を拒否する" {
    // 正常な PNG は inspectVerified を通過する
    const ok = try png.inspectVerified(testing.allocator, GRADIENT_PNG, image.MAX_PIXELS, null);
    try testing.expectEqual(@as(u32, 16), ok.width);

    // IEND の後ろに余剰データが付いた PNG は直送検証で拒否する
    var trailing = try testing.allocator.alloc(u8, GRADIENT_PNG.len + 16);
    defer testing.allocator.free(trailing);
    @memcpy(trailing[0..GRADIENT_PNG.len], GRADIENT_PNG);
    @memset(trailing[GRADIENT_PNG.len..], 'X');
    try testing.expectError(png.Error.InvalidPng, png.inspectVerified(testing.allocator, trailing, image.MAX_PIXELS, null));

    // palette(3) + bit_depth(16) は PNG 規格違反のため拒否する
    var bad_palette = try testing.allocator.dupe(u8, GRADIENT_PNG);
    defer testing.allocator.free(bad_palette);
    bad_palette[24] = 16; // bit_depth
    bad_palette[25] = 3; // color_type = palette
    try testing.expectError(png.Error.InvalidPng, png.inspect(bad_palette, image.MAX_PIXELS));
    try testing.expectError(png.Error.InvalidPng, png.decode(testing.allocator, bad_palette, image.MAX_PIXELS));

    // 1x1 RGB なのに IDAT が 64KB 展開する bomb PNG は inspectVerified でも拒否する
    const flate = std.compress.flate;
    var zbuf = try std.Io.Writer.Allocating.initCapacity(testing.allocator, 4096);
    defer zbuf.deinit();
    const window = try testing.allocator.alloc(u8, flate.max_window_len);
    defer testing.allocator.free(window);
    var comp = try flate.Compress.init(&zbuf.writer, window, .zlib, .fastest);
    var zeros: [4096]u8 = @splat(0);
    var i: usize = 0;
    while (i < 16) : (i += 1) try comp.writer.writeAll(&zeros);
    try comp.finish();
    try zbuf.writer.flush();
    const idat_body = zbuf.written();

    var bomb: std.ArrayList(u8) = .empty;
    defer bomb.deinit(testing.allocator);
    try bomb.appendSlice(testing.allocator, png.SIGNATURE);
    var ihdr = [_]u8{ 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0 };
    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, 13, .big);
    try bomb.appendSlice(testing.allocator, &len_buf);
    try bomb.appendSlice(testing.allocator, "IHDR");
    try bomb.appendSlice(testing.allocator, &ihdr);
    try bomb.appendSlice(testing.allocator, &[_]u8{ 0, 0, 0, 0 });
    std.mem.writeInt(u32, &len_buf, @intCast(idat_body.len), .big);
    try bomb.appendSlice(testing.allocator, &len_buf);
    try bomb.appendSlice(testing.allocator, "IDAT");
    try bomb.appendSlice(testing.allocator, idat_body);
    try bomb.appendSlice(testing.allocator, &[_]u8{ 0, 0, 0, 0 });
    try bomb.appendSlice(testing.allocator, &[_]u8{ 0, 0, 0, 0, 'I', 'E', 'N', 'D', 0, 0, 0, 0 });

    try testing.expectError(png.Error.InvalidPng, png.inspectVerified(testing.allocator, bomb.items, image.MAX_PIXELS, null));
}

test "セキュリティ: 切れた小ファイルで巨大寸法を名乗る JPEG の空回し DoS を打ち切る" {
    // 2000x2000 1成分、DC/AC ともに符号 0 (1bit) = 0x00 を定義し、SOS 直後に EOF にする
    const crafted = [_]u8{
        0xff, 0xd8, // SOI
        0xff, 0xc0, 0x00, 0x0b, 8, 0x07, 0xd0, 0x07, 0xd0, 1, 1, 0x11, 0, // SOF0: 2000x2000, 1comp
        0xff, 0xc4, 0x00, 0x14, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x00, // DHT DC0
        0xff, 0xc4, 0x00, 0x14, 0x10, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x00, // DHT AC0
        0xff, 0xda, 0x00, 0x08, 1, 1, 0x00, 0, 63, 0, // SOS (直後に EOF)
    };
    try testing.expectError(jpeg.Error.InvalidJpeg, jpeg.decode(testing.allocator, &crafted, image.MAX_PIXELS));
}

test "セキュリティ: デコードと縮小はキャンセルフラグで即中断できる" {
    var flag = std.atomic.Value(bool).init(true);
    try testing.expectError(png.Error.Cancelled, png.decodeCancelable(testing.allocator, GRADIENT_PNG, image.MAX_PIXELS, &flag));
    try testing.expectError(jpeg.Error.Cancelled, jpeg.decodeCancelable(testing.allocator, GRADIENT_JPG, image.MAX_PIXELS, &flag));

    const src: [4 * 4 * 3]u8 = @splat(0);
    var dst: [2 * 2 * 3]u8 = @splat(0);
    try testing.expectError(error.Cancelled, resize.resizeCancelable(&src, 4, 4, &dst, 2, 2, 3, &flag));
}
