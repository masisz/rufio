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
