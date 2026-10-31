# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'open3'
require 'zlib'
require_relative 'support/zip_fixture'

class TestZipArchive < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('rufio-zip')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write(name, bytes)
    path = File.join(@dir, name)
    File.binwrite(path, bytes)
    path
  end

  def test_lists_stored_and_deflated_entries
    zip = ZipFixture.new
                    .add('docs/', '')
                    .add('docs/readme.txt', "hello\n")
                    .add('data.bin', 'a' * 1000, deflate: true)
    listing = Rufio::ZipArchive.list(write('sample.zip', zip.to_s(comment: 'built by test')))

    assert_equal 3, listing.total_entries
    assert_equal %w[docs/ docs/readme.txt data.bin], listing.entries.map(&:name)
    assert listing.entries[0].directory?
    assert_equal [0, 6, 1000], listing.entries.map(&:size)
    assert_equal 'Deflate', Rufio::ZipArchive.method_name(listing.entries[2].method)
    assert_operator listing.entries[2].compressed_size, :<, 1000
    assert_equal Zlib.crc32('a' * 1000), listing.entries[2].crc32
    assert_equal Time.new(2026, 10, 31, 12, 34, 56), listing.entries[1].mtime
    assert_equal 'built by test', listing.comment
    refute listing.zip64?
    refute listing.truncated?
  end

  def test_limit_reads_only_leading_entries
    zip = ZipFixture.new
    5.times { |i| zip.add("file#{i}.txt", i.to_s) }
    listing = Rufio::ZipArchive.list(write('many.zip', zip.to_s), limit: 2)

    assert_equal %w[file0.txt file1.txt], listing.entries.map(&:name)
    assert_equal 5, listing.total_entries
    assert listing.truncated?
  end

  def test_empty_archive
    listing = Rufio::ZipArchive.list(write('empty.zip', ZipFixture.new.to_s))

    assert_equal 0, listing.total_entries
    assert_empty listing.entries
  end

  def test_decodes_utf8_flag_and_cp932_names
    zip = ZipFixture.new
                    .add('日本語.txt', 'x', flags: Rufio::ZipArchive::FLAG_UTF8)
                    .add('資料.txt'.encode('Windows-31J'), 'y')
    names = Rufio::ZipArchive.list(write('ja.zip', zip.to_s)).entries.map(&:name)

    assert_equal %w[日本語.txt 資料.txt], names
    assert names.all? { |n| n.encoding == Encoding::UTF_8 && n.valid_encoding? }
  end

  def test_prefers_info_zip_unicode_path_extra
    raw = 'old.txt'
    extra_data = [1, Zlib.crc32(raw)].pack('CV') + 'ユニコード.txt'.b
    extra = [Rufio::ZipArchive::UNICODE_PATH_EXTRA_ID, extra_data.bytesize].pack('vv') + extra_data
    zip = ZipFixture.new.add(raw, 'z', extra: extra)

    assert_equal 'ユニコード.txt', Rufio::ZipArchive.list(write('u.zip', zip.to_s)).entries.first.name
  end

  def test_reads_zip64_end_of_central_directory_and_extra_field
    name = 'big.bin'.b
    zip64_extra = [Rufio::ZipArchive::ZIP64_EXTRA_ID, 16, 5_000_000_000, 4_000_000_000].pack('vvQ<Q<')
    central = [0x02014b50, 45, 45, 0, 8, 0, 0x5C21, 0, 0xFFFFFFFF, 0xFFFFFFFF,
               name.bytesize, zip64_extra.bytesize, 0, 0, 0, 0, 0].pack('VvvvvvvVVVvvvvvVV') + name + zip64_extra
    cd_offset = 0
    zip64_eocd_offset = central.bytesize
    zip64_eocd = [0x06064b50, 44, 45, 45, 0, 0, 1, 1, central.bytesize, cd_offset].pack('VQ<vvVVQ<Q<Q<Q<')
    locator = [0x07064b50, 0, zip64_eocd_offset, 1].pack('VVQ<V')
    eocd = [0x06054b50, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0].pack('VvvvvVVv')

    listing = Rufio::ZipArchive.list(write('z64.zip', central + zip64_eocd + locator + eocd))

    assert listing.zip64?
    assert_equal 1, listing.total_entries
    entry = listing.entries.first
    assert_equal 5_000_000_000, entry.size
    assert_equal 4_000_000_000, entry.compressed_size
  end

  def test_ignores_signature_like_bytes_inside_comment
    fake_eocd = [0x06054b50, 0, 0, 9, 9, 0, 0, 0].pack('VvvvvVVv')
    zip = ZipFixture.new.add('a.txt', 'a')
    listing = Rufio::ZipArchive.list(write('c.zip', zip.to_s(comment: fake_eocd)))

    assert_equal ['a.txt'], listing.entries.map(&:name)
  end

  def test_rejects_non_zip_and_truncated_files
    assert_raises(Rufio::ZipArchive::FormatError) { Rufio::ZipArchive.list(write('text.zip', 'not a zip file at all, really')) }

    bytes = ZipFixture.new.add('a.txt', 'abc').to_s
    broken = bytes.dup
    broken[-6, 4] = [0x7FFFFFFF].pack('V') # cd_offset をファイル外に向ける
    assert_raises(Rufio::ZipArchive::FormatError) { Rufio::ZipArchive.list(write('broken.zip', broken)) }
  end

  def test_matches_unzip_listing_when_available
    _, status = Open3.capture2e('zip', '-v')
    skip 'zip/unzip command not available' unless status.success?

    src = File.join(@dir, 'src')
    FileUtils.mkdir_p(File.join(src, 'nested'))
    File.write(File.join(src, 'a.txt'), 'alpha' * 100)
    File.write(File.join(src, 'nested', 'b.rb'), "puts 1\n")
    archive = File.join(@dir, 'real.zip')
    _, status = Open3.capture2e('zip', '-qr', archive, '.', chdir: src)
    assert status.success?

    expected, = Open3.capture2('unzip', '-Z1', archive)
    assert_equal expected.lines.map(&:chomp), Rufio::ZipArchive.list(archive).entries.map(&:name)
  end

  def test_file_preview_shows_archive_listing
    zip = ZipFixture.new.add('docs/', '').add('docs/readme.txt', "hello\n")
    preview = Rufio::FilePreview.new.preview_file(write('preview.zip', zip.to_s))

    assert_equal 'archive', preview[:type]
    assert_equal 'ZIP archive: 2 entries', preview[:lines].first
    assert(preview[:lines].any? { |l| l.include?('docs/readme.txt') && l.include?('Stored') })
    assert(preview[:lines].any? { |l| l.match?(/\s6\s+1 files|\s6\s+2 files/) })
  end

  def test_file_preview_reports_invalid_zip
    preview = Rufio::FilePreview.new.preview_file(write('bad.zip', "PK\x03\x04garbage".b))

    assert_equal 'error', preview[:type]
    assert_match(/Invalid ZIP archive/, preview[:message])
  end
end
