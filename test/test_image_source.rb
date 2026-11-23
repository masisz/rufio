# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/rufio'

# 画像の形式判定と寸法読み取り。拡張子ではなくファイル先頭のシグネチャで判定する。
# 本文は読まないので、見出しだけを組み立てたファイルで検証できる。
class TestImageSource < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('rufio_image_source')
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def write(name, bytes)
    path = File.join(@dir, name)
    File.binwrite(path, bytes)
    path
  end

  # PNG: シグネチャ + IHDR（幅・高さはビッグエンディアン）
  def png(width, height, name: 'a.png')
    header = "\x89PNG\r\n\x1a\n".b
    ihdr = [13].pack('N') + 'IHDR' + [width, height].pack('NN') + "\x08\x06\x00\x00\x00".b + [0].pack('N')
    write(name, header + ihdr + ('\x00'.b * 16))
  end

  # JPEG: SOI + APP0 + SOF0（高さ・幅の順、ビッグエンディアン）
  def jpeg(width, height, name: 'a.jpg')
    app0 = "\xff\xe0".b + [16].pack('n') + "JFIF\x00".b + ("\x00".b * 9)
    sof0 = "\xff\xc0".b + [17].pack('n') + "\x08".b + [height, width].pack('nn') + "\x03".b + ("\x00".b * 9)
    write(name, "\xff\xd8".b + app0 + sof0 + "\xff\xd9".b)
  end

  # GIF: "GIF89a" + 論理画面（リトルエンディアン）
  def gif(width, height, name: 'a.gif')
    write(name, 'GIF89a'.b + [width, height].pack('vv') + ("\x00".b * 7))
  end

  # BMP: "BM" + ファイルヘッダ + DIB（幅・高さはリトルエンディアン 32bit）
  def bmp(width, height, name: 'a.bmp')
    file_header = 'BM'.b + [0, 0, 0, 54].pack('Vv2V')
    dib = [40, width, height].pack('Vl<l<') + ("\x00".b * 28)
    write(name, file_header + dib)
  end

  # === 形式判定 ===

  def test_each_format_is_recognised_by_its_signature
    assert_equal :png, Rufio::ImageSource.kind(png(1, 1))
    assert_equal :jpeg, Rufio::ImageSource.kind(jpeg(1, 1))
    assert_equal :gif, Rufio::ImageSource.kind(gif(1, 1))
    assert_equal :bmp, Rufio::ImageSource.kind(bmp(1, 1))
  end

  def test_the_extension_is_not_trusted
    path = png(4, 3, name: 'photo.jpg')

    assert_equal :png, Rufio::ImageSource.kind(path), '中身が PNG なら PNG として扱うこと'
    assert Rufio::ImageSource.supports?(path)
  end

  def test_other_files_are_not_images
    text = write('notes.txt', "hello\n")
    liar = write('fake.png', 'this is not a png')

    refute Rufio::ImageSource.supports?(text)
    refute Rufio::ImageSource.supports?(liar)
    refute Rufio::ImageSource.supports?(File.join(@dir, 'missing.png'))
    assert_nil Rufio::ImageSource.kind(text)
  end

  def test_an_empty_file_is_not_an_image
    refute Rufio::ImageSource.supports?(write('empty.png', ''))
  end

  # === 寸法 ===

  def test_dimensions_are_read_from_the_header
    { png(1920, 1080) => :png, jpeg(640, 480) => :jpeg,
      gif(320, 200) => :gif, bmp(64, 48) => :bmp }.each do |path, kind|
      info = Rufio::ImageSource.read(path)
      refute_nil info, path
      assert_equal kind, info.kind, path
      assert info.dimensions?, path
    end

    assert_equal [1920, 1080], Rufio::ImageSource.read(png(1920, 1080, name: 'big.png')).then { |i| [i.width, i.height] }
    assert_equal [640, 480], Rufio::ImageSource.read(jpeg(640, 480, name: 'b.jpg')).then { |i| [i.width, i.height] }
    assert_equal [320, 200], Rufio::ImageSource.read(gif(320, 200, name: 'b.gif')).then { |i| [i.width, i.height] }
    assert_equal [64, 48], Rufio::ImageSource.read(bmp(64, 48, name: 'b.bmp')).then { |i| [i.width, i.height] }
  end

  def test_a_bottom_up_bmp_reports_a_positive_height
    # BMP は高さが負（上から下へ並ぶ画像）でも、寸法としては正の値を返す
    path = bmp(10, -20, name: 'topdown.bmp')
    info = Rufio::ImageSource.read(path)

    assert_equal [10, 20], [info.width, info.height]
  end

  def test_the_size_and_path_are_reported
    path = png(8, 8)
    info = Rufio::ImageSource.read(path)

    assert_equal File.size(path), info.bytes
    assert_equal path, info.path
    assert_equal 'PNG', info.label
  end

  def test_a_jpeg_without_a_frame_header_has_no_dimensions
    path = write('broken.jpg', "\xff\xd8".b + ("\x00".b * 32))
    info = Rufio::ImageSource.read(path)

    refute_nil info, '形式だけは分かるので情報は返すこと'
    assert_equal :jpeg, info.kind
    refute info.dimensions?
  end

  def test_reading_a_file_that_is_not_an_image_returns_nil
    assert_nil Rufio::ImageSource.read(write('notes.txt', 'hello'))
  end

  # === 直送できる形式 ===

  def test_only_png_can_be_sent_to_the_terminal_as_is
    assert Rufio::ImageSource.direct?(Rufio::ImageSource.read(png(2, 2)))
    refute Rufio::ImageSource.direct?(Rufio::ImageSource.read(jpeg(2, 2)))
    refute Rufio::ImageSource.direct?(nil)
  end
end
