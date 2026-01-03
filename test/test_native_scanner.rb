# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio'

class TestNativeScanner < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir('rufio_native_scanner_test')
    # テスト用のファイルとディレクトリを作成
    FileUtils.touch(File.join(@test_dir, 'file1.txt'))
    FileUtils.touch(File.join(@test_dir, 'file2.rb'))
    FileUtils.mkdir(File.join(@test_dir, 'subdir'))
    FileUtils.touch(File.join(@test_dir, 'subdir', 'file3.md'))
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  def test_mode_setting
    # モードを設定できることを確認
    available = Rufio::NativeScanner.available_libraries

    # Rustライブラリが利用可能な場合のみテスト
    if available[:rust]
      Rufio::NativeScanner.mode = 'rust'
      assert_equal 'rust', Rufio::NativeScanner.mode
    end

    # Goライブラリが利用可能な場合のみテスト
    if available[:go]
      Rufio::NativeScanner.mode = 'go'
      assert_equal 'go', Rufio::NativeScanner.mode
    end

    # Rubyモードは常にテスト
    Rufio::NativeScanner.mode = 'ruby'
    assert_equal 'ruby', Rufio::NativeScanner.mode

    # autoモードは利用可能なライブラリにフォールバック
    Rufio::NativeScanner.mode = 'auto'
    assert_includes ['magnus', 'zig', 'rust', 'go', 'ruby'], Rufio::NativeScanner.mode
  end

  def test_invalid_mode
    # 無効なモードを設定した場合はrubyにフォールバック
    Rufio::NativeScanner.mode = 'invalid'
    assert_equal 'ruby', Rufio::NativeScanner.mode
  end

  def test_scan_directory_with_ruby_mode
    # Rubyモードでディレクトリスキャンできることを確認
    Rufio::NativeScanner.mode = 'ruby'
    entries = Rufio::NativeScanner.scan_directory(@test_dir)

    assert_kind_of Array, entries
    assert entries.length >= 3, "Expected at least 3 entries, got #{entries.length}"

    # エントリの構造を確認
    entry = entries.find { |e| e[:name] == 'file1.txt' }
    assert entry, "file1.txt not found in entries"
    assert_equal 'file', entry[:type]
    assert entry.key?(:size)
    assert entry.key?(:mtime)
  end

  def test_scan_directory_with_native_mode
    # ネイティブモード（rust/go）でディレクトリスキャンできることを確認
    # 利用可能なネイティブライブラリがあれば使用
    Rufio::NativeScanner.mode = 'auto'

    # autoモードで実際に使われているモードを取得
    actual_mode = Rufio::NativeScanner.mode

    entries = Rufio::NativeScanner.scan_directory(@test_dir)

    assert_kind_of Array, entries
    assert entries.length >= 3, "Expected at least 3 entries in #{actual_mode} mode, got #{entries.length}"
  end

  def test_scan_directory_nonexistent
    # 存在しないディレクトリをスキャンした場合のエラーハンドリング
    Rufio::NativeScanner.mode = 'ruby'

    assert_raises(StandardError) do
      Rufio::NativeScanner.scan_directory('/nonexistent/path/12345')
    end
  end

  def test_scan_directory_fast
    # 高速スキャン（エントリ数制限付き）
    Rufio::NativeScanner.mode = 'ruby'
    entries = Rufio::NativeScanner.scan_directory_fast(@test_dir, 2)

    assert_kind_of Array, entries
    assert entries.length <= 2, "Expected at most 2 entries, got #{entries.length}"
  end

  def test_version
    # バージョン情報を取得できることを確認
    version = Rufio::NativeScanner.version
    assert_kind_of String, version
    refute_empty version
  end

  def test_library_availability
    # 利用可能なライブラリを確認
    available = Rufio::NativeScanner.available_libraries
    assert_kind_of Hash, available

    # 基本的なライブラリキーは常に存在
    assert available.key?(:rust)
    assert available.key?(:go)

    # magnus/zigは、ライブラリがビルドされている環境でのみ存在
    # CI環境では存在しない可能性があるため、チェックしない

    # ネイティブライブラリが存在しない環境（CI環境など）でも正常に動作することを確認
    # 少なくともRubyモードは常に利用可能
    assert_equal 'ruby', Rufio::NativeScanner.mode if available.values.all? { |v| v == false }
  end

  def test_fallback_to_ruby
    # ネイティブライブラリが使えない場合のフォールバック
    # 強制的にrubyモードにしてテスト
    Rufio::NativeScanner.mode = 'ruby'

    entries = Rufio::NativeScanner.scan_directory(@test_dir)
    assert_kind_of Array, entries
    refute_empty entries
  end

  def test_directory_entry_types
    # ディレクトリとファイルが正しく区別されることを確認
    Rufio::NativeScanner.mode = 'ruby'
    entries = Rufio::NativeScanner.scan_directory(@test_dir)

    file_entry = entries.find { |e| e[:name] == 'file1.txt' }
    dir_entry = entries.find { |e| e[:name] == 'subdir' }

    assert_equal 'file', file_entry[:type] if file_entry
    assert_equal 'directory', dir_entry[:type] if dir_entry
  end

  def test_hidden_files
    # 隠しファイルも含めてスキャンできることを確認
    hidden_file = File.join(@test_dir, '.hidden')
    FileUtils.touch(hidden_file)

    Rufio::NativeScanner.mode = 'ruby'
    entries = Rufio::NativeScanner.scan_directory(@test_dir)

    hidden_entry = entries.find { |e| e[:name] == '.hidden' }
    assert hidden_entry, "Hidden file should be included in scan results"
  end

  def test_symlink_handling
    # シンボリックリンクの扱い
    skip "Symlink test skipped on systems that don't support symlinks" unless File.respond_to?(:symlink)

    target = File.join(@test_dir, 'file1.txt')
    link = File.join(@test_dir, 'link_to_file')

    File.symlink(target, link)

    Rufio::NativeScanner.mode = 'ruby'
    entries = Rufio::NativeScanner.scan_directory(@test_dir)

    link_entry = entries.find { |e| e[:name] == 'link_to_file' }
    assert link_entry, "Symlink should be included in scan results"
  end

  def test_concurrent_scans
    # 複数のスキャンを同時実行できることを確認
    Rufio::NativeScanner.mode = 'ruby'

    threads = 3.times.map do
      Thread.new do
        Rufio::NativeScanner.scan_directory(@test_dir)
      end
    end

    results = threads.map(&:value)

    assert_equal 3, results.length
    results.each do |entries|
      assert_kind_of Array, entries
      assert entries.length >= 3
    end
  end
end
