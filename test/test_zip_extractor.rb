# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'open3'
require 'zlib'
require_relative 'support/zip_fixture'

class TestZipExtractor < Minitest::Test
  Extractor = Rufio::ZipExtractor

  def setup
    @dir = Dir.mktmpdir('rufio-unzip')
    @dest = File.join(@dir, 'out')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write_zip(fixture, name = 'a.zip')
    path = File.join(@dir, name)
    File.binwrite(path, fixture.to_s)
    path
  end

  # Ruby 実装で実行する。TestZipExtractorNative は同じテストを Zig 実装で実行する
  def native?
    false
  end

  def extract(zip, **options)
    Extractor.new(zip, @dest, native: native?, **options).extract
  end

  def assert_nothing_written
    assert(!Dir.exist?(@dest) || Dir.empty?(@dest), "expected nothing extracted, got #{Dir.glob("#{@dest}/**/*")}")
  end

  def test_extracts_stored_and_deflated_files_with_mtime
    zip = write_zip(ZipFixture.new.add('docs/', '').add('docs/a.txt', "hello\n").add('b.bin', 'x' * 5000, deflate: true))
    result = extract(zip)

    assert_equal "hello\n", File.read(File.join(@dest, 'docs/a.txt'))
    assert_equal 'x' * 5000, File.read(File.join(@dest, 'b.bin'))
    assert_equal Time.new(2026, 10, 31, 12, 34, 56), File.mtime(File.join(@dest, 'docs/a.txt'))
    assert_equal %w[docs docs/a.txt b.bin], result.extracted
    assert_equal 5006, result.bytes_written
  end

  def test_normalize_entry_name
    assert_equal 'a/b.txt', Extractor.normalize_entry_name('a/./b.txt')
    assert_equal 'a/b.txt', Extractor.normalize_entry_name('a\\b.txt')
    ['../evil', 'a/../../evil', '/etc/passwd', 'C:/evil', 'c:evil', '..\\evil', "a\0b", ''].each do |name|
      assert_raises(Extractor::UnsafeEntryError, name.inspect) { Extractor.normalize_entry_name(name) }
    end
  end

  def test_rejects_zip_slip_without_writing_anything
    zip = write_zip(ZipFixture.new.add('ok.txt', 'ok').add('../../evil.txt', 'evil'))

    assert_raises(Extractor::UnsafeEntryError) { extract(zip) }
    assert_nothing_written
    refute File.exist?(File.join(@dir, 'evil.txt'))
  end

  def test_skips_symlink_entries
    zip = write_zip(ZipFixture.new.add('link', '/etc', unix_mode: 0o120777).add('file.txt', 'data', unix_mode: 0o100644))
    result = extract(zip)

    refute File.exist?(File.join(@dest, 'link'))
    refute File.symlink?(File.join(@dest, 'link'))
    assert_equal [{ name: 'link', reason: 'symlink' }], result.skipped
    assert_equal 'data', File.read(File.join(@dest, 'file.txt'))
  end

  def test_does_not_follow_existing_symlink_in_destination
    skip 'symlink not supported' if Gem.win_platform?

    outside = File.join(@dir, 'outside')
    FileUtils.mkdir_p([outside, @dest])
    File.symlink(outside, File.join(@dest, 'sub'))
    zip = write_zip(ZipFixture.new.add('sub/evil.txt', 'evil'))

    assert_raises(Extractor::Error) { extract(zip) }
    refute File.exist?(File.join(outside, 'evil.txt'))
  end

  def test_refuses_to_overwrite_existing_files_unless_requested
    FileUtils.mkdir_p(@dest)
    File.write(File.join(@dest, 'a.txt'), 'original')
    zip = write_zip(ZipFixture.new.add('a.txt', 'new'))

    assert_raises(Extractor::ConflictError) { extract(zip) }
    assert_equal 'original', File.read(File.join(@dest, 'a.txt'))

    extract(zip, overwrite: true)
    assert_equal 'new', File.read(File.join(@dest, 'a.txt'))
  end

  def test_crc_mismatch_leaves_no_file
    zip = write_zip(ZipFixture.new.add('a.txt', 'data', crc: 12_345))

    assert_raises(Extractor::CorruptEntryError) { extract(zip) }
    assert_empty Dir.children(@dest)
  end

  def test_stops_when_data_exceeds_declared_size
    zip = write_zip(ZipFixture.new.add('bomb.bin', 'a' * 100_000, deflate: true, size: 10))

    error = assert_raises(Extractor::CorruptEntryError) { extract(zip) }
    assert_match(/larger than declared/, error.message)
    assert_empty Dir.children(@dest)
  end

  def test_rejects_corrupt_deflate_data
    payload = "\xFF".b * 64
    fixture = ZipFixture.new.add('bad.bin', 'x' * 64, deflate: true)
    bytes = fixture.to_s.b
    start = 30 + 'bad.bin'.bytesize
    compressed_size = bytes.byteslice(18, 4).unpack1('V')
    bytes[start, compressed_size] = payload.byteslice(0, compressed_size)
    File.binwrite(File.join(@dir, 'bad.zip'), bytes)

    assert_raises(Extractor::CorruptEntryError) { extract(File.join(@dir, 'bad.zip')) }
    assert_empty Dir.children(@dest)
  end

  def test_extracts_many_entries_identically
    fixture = ZipFixture.new
    random = Random.new(7)
    contents = 300.times.to_h do |i|
      data = i.even? ? random.bytes(random.rand(0..5000)) : ("line #{i}\n" * random.rand(1..400))
      fixture.add("dir#{i % 7}/file#{i}.bin", data, deflate: i % 3 != 0)
      ["dir#{i % 7}/file#{i}.bin", data]
    end
    result = extract(write_zip(fixture))

    assert_equal 300, result.extracted.length
    contents.each { |name, data| assert_equal data.b, File.binread(File.join(@dest, name)), name }
  end

  def test_enforces_total_size_entry_count_and_ratio_limits
    zip = write_zip(ZipFixture.new.add('a.txt', 'a' * 100).add('b.txt', 'b' * 100))
    assert_raises(Extractor::LimitExceededError) { extract(zip, max_total_size: 150) }
    assert_raises(Extractor::LimitExceededError) { extract(zip, max_entries: 1) }

    bomb = write_zip(ZipFixture.new.add('zeros.bin', "\0" * (2 * 1024 * 1024), deflate: true), 'bomb.zip')
    assert_raises(Extractor::LimitExceededError) { extract(bomb, max_ratio: 100) }
    assert_nothing_written
  end

  def test_rejects_overlapping_entries
    fixture = ZipFixture.new.add('a.txt', 'a' * 50).add('b.txt', 'a' * 50, local_offset: 0)

    assert_raises(Extractor::UnsafeEntryError) { extract(write_zip(fixture)) }
    assert_nothing_written
  end

  def test_skips_encrypted_entries
    result = extract(write_zip(ZipFixture.new.add('secret.txt', 'xx', flags: 1).add('plain.txt', 'p')))

    assert_equal [{ name: 'secret.txt', reason: 'encrypted' }], result.skipped
    assert File.exist?(File.join(@dest, 'plain.txt'))
  end

  def test_preserves_only_executable_bit
    skip 'file modes not supported' if Gem.win_platform?

    zip = write_zip(ZipFixture.new.add('run.sh', 'echo', unix_mode: 0o104777).add('data.txt', 'd', unix_mode: 0o100666))
    extract(zip)

    run_mode = File.stat(File.join(@dest, 'run.sh')).mode & 0o7777
    data_mode = File.stat(File.join(@dest, 'data.txt')).mode & 0o7777
    assert_equal 0, run_mode & 0o7022, format('unexpected mode %o', run_mode)
    refute_equal 0, run_mode & 0o100
    assert_equal 0, data_mode & 0o111
  end

  def test_cancellation_and_progress
    zip = write_zip(ZipFixture.new.add('a.txt', 'a' * 10).add('b.txt', 'b' * 10))
    seen = []
    extract(zip, progress: ->(done, total) { seen << [done, total] })
    assert_equal [20, 20], seen.last
    assert(seen.each_cons(2).all? { |(a, _), (b, _)| a <= b })
    assert(seen.all? { |_, total| total == 20 })

    FileUtils.rm_rf(@dest)
    calls = 0
    assert_raises(Extractor::CancelledError) { extract(zip, cancelled: -> { (calls += 1) > 1 }) }
  end

  # zip コマンドの通常出力と、標準入力から作るデータディスクリプタ付きの出力を展開できること
  def test_extracts_archives_made_by_zip_command
    _, status = Open3.capture2e('zip', '-v')
    skip 'zip command not available' unless status.success?

    src = File.join(@dir, 'src')
    FileUtils.mkdir_p(File.join(src, 'sub'))
    File.write(File.join(src, 'sub', 'a.txt'), 'alpha' * 2000)
    Open3.capture2e('zip', '-qr', File.join(@dir, 'r.zip'), '.', chdir: src)
    Open3.capture2e('zip', '-q', File.join(@dir, 's.zip'), '-', stdin_data: 'streamed' * 100)

    extract(File.join(@dir, 'r.zip'))
    assert_equal 'alpha' * 2000, File.read(File.join(@dest, 'sub', 'a.txt'))
    extract(File.join(@dir, 's.zip'))
    assert_equal 'streamed' * 100, File.read(File.join(@dest, '-'))
  end
end

class TestZipExtractorNative < TestZipExtractor
  def setup
    skip 'Zig ZIP engine is not available' unless Rufio::NativeZip.available?
    super
  end

  def native?
    true
  end
end
