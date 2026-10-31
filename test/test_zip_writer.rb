# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'open3'
require 'zip'

class TestZipWriter < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('rufio-zipw')
    @src = File.join(@dir, 'src')
    FileUtils.mkdir_p(File.join(@src, 'nested', 'empty'))
    File.write(File.join(@src, 'a.txt'), 'alpha' * 1000)
    File.write(File.join(@src, '日本語.txt'), 'にほんご')
    File.binwrite(File.join(@src, 'nested', 'random.bin'), Random.new(1).bytes(4096))
    File.write(File.join(@src, 'nested', 'empty.txt'), '')
    @zip = File.join(@dir, 'out.zip')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Ruby 実装で実行する。TestZipWriterNative は同じテストを Zig 実装で実行する
  def native?
    false
  end

  def create(paths = %w[a.txt 日本語.txt nested], **options)
    Rufio::ZipWriter.new(@zip, @src, paths, native: native?, **options).write
  end

  def test_round_trip_through_extractor
    result = create
    dest = File.join(@dir, 'dest')
    Rufio::ZipExtractor.new(@zip, dest, native: native?).extract

    %w[a.txt 日本語.txt nested/random.bin nested/empty.txt].each do |name|
      assert_equal File.binread(File.join(@src, name)), File.binread(File.join(dest, name)), name
    end
    assert Dir.exist?(File.join(dest, 'nested', 'empty'))
    assert_includes result.added, 'nested/empty/'
  end

  # 1MiB 以上のファイルは Zig 実装が使える環境では並列圧縮の経路を通る
  def test_round_trip_large_files
    big = File.join(@src, 'big')
    FileUtils.mkdir_p(big)
    File.write(File.join(big, 'text.txt'), "rufio zip engine line\n" * 100_000)
    File.binwrite(File.join(big, 'random.bin'), Random.new(3).bytes(1_500_000))
    create(['big'])

    entries = Rufio::ZipArchive.list(@zip).entries.to_h { |e| [e.name, e] }
    assert_equal 8, entries['big/text.txt'].method
    assert_equal 0, entries['big/random.bin'].method
    dest = File.join(@dir, 'dest')
    Rufio::ZipExtractor.new(@zip, dest, native: native?).extract
    %w[text.txt random.bin].each do |name|
      assert_equal File.binread(File.join(big, name)), File.binread(File.join(dest, 'big', name)), name
    end
    if system('unzip', '-v', out: File::NULL, err: File::NULL)
      output, status = Open3.capture2e('unzip', '-t', @zip)
      assert status.success?, output
    end
  end

  def test_chooses_method_per_file_and_uses_utf8_names
    create
    entries = Rufio::ZipArchive.list(@zip).entries.to_h { |e| [e.name, e] }

    assert_equal 8, entries['a.txt'].method
    assert_equal 0, entries['nested/random.bin'].method, 'incompressible data is stored'
    assert_equal 0, entries['nested/empty.txt'].method
    assert(entries.values.all? { |e| (e.flags & Rufio::ZipArchive::FLAG_UTF8).nonzero? })
    assert entries['日本語.txt']
  end

  def test_readable_by_rubyzip
    create
    Zip::File.open(@zip) do |zip|
      assert_equal 'alpha' * 1000, zip.read('a.txt')
      # rubyzip 2.4 は名前を ASCII-8BIT で保持するため、バイト列で引く
      assert_equal 'にほんご', zip.read('日本語.txt'.b).force_encoding('UTF-8')
      assert_equal File.binread(File.join(@src, 'nested', 'random.bin')), zip.read('nested/random.bin')
    end
  end

  def test_passes_unzip_integrity_test_when_available
    _, status = Open3.capture2e('unzip', '-v')
    skip 'unzip command not available' unless status.success?

    create
    output, status = Open3.capture2e('unzip', '-t', @zip)
    assert status.success?, output
  end

  def test_skips_symlinks_and_output_archive
    skip 'symlink not supported' if Gem.win_platform?

    File.symlink('/etc/passwd', File.join(@src, 'link'))
    zip_inside = File.join(@src, 'self.zip')
    File.write(zip_inside, 'old')
    result = Rufio::ZipWriter.new(zip_inside, @src, %w[a.txt link self.zip], overwrite: true, native: native?).write

    assert_equal ['a.txt'], result.added
    assert_equal [{ name: 'link', reason: 'symlink' }, { name: 'self.zip', reason: 'output archive' }], result.skipped
  end

  def test_refuses_existing_archive_and_paths_outside_base
    File.write(@zip, 'existing')
    assert_raises(Rufio::ZipWriter::ConflictError) { create }
    assert_equal 'existing', File.read(@zip)

    assert_raises(Rufio::ZipWriter::Error) { create(['../outside'], overwrite: true) }
    assert_equal 'existing', File.read(@zip)
  end

  def test_cancel_leaves_no_partial_archive
    assert_raises(Rufio::ZipWriter::CancelledError) { create(cancelled: -> { true }) }
    refute File.exist?(@zip)
    assert_equal ['src'], Dir.children(@dir)
  end

  def test_uses_zip64_end_records_for_many_entries
    many = File.join(@src, 'many')
    FileUtils.mkdir_p(many)
    70_000.times { |i| File.write(File.join(many, i.to_s), '') }
    create(['many'])

    listing = Rufio::ZipArchive.list(@zip, limit: 1)
    assert listing.zip64?
    assert_equal 70_001, listing.total_entries
  end
end

class TestZipWriterNative < TestZipWriter
  def setup
    skip 'Zig ZIP engine is not available' unless Rufio::NativeZip.available?
    super
  end

  def native?
    true
  end
end
