# frozen_string_literal: true

require_relative "test_helper"
require 'tmpdir'
require 'tempfile'

class TestFileOpener < Minitest::Test
  def setup
    @file_opener = Rufio::FileOpener.new
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_find_application_for_ruby_file
    # テスト用一時ファイルを作成
    file_path = File.join(@tmpdir, "test.rb")
    File.write(file_path, "puts 'hello'")

    test_applications = {
      %w[rb py js] => 'code',
      :default => 'open'
    }

    Rufio::ConfigLoader.stub(:applications, test_applications) do
      application = @file_opener.send(:find_application_for_file, file_path)
      assert_equal 'code', application
    end
  end

  def test_find_application_for_unknown_extension
    file_path = File.join(@tmpdir, "test.unknown")
    File.write(file_path, "test content")

    test_applications = {
      %w[rb py js] => 'code',
      :default => 'open'
    }

    Rufio::ConfigLoader.stub(:applications, test_applications) do
      application = @file_opener.send(:find_application_for_file, file_path)
      assert_equal 'open', application
    end
  end

  def test_open_nonexistent_file
    result = @file_opener.open_file("/path/to/nonexistent/file.txt")
    refute result, "存在しないファイルに対してはfalseを返すべき"
  end

  def test_open_directory
    result = @file_opener.open_file(@tmpdir)
    refute result, "ディレクトリに対してはfalseを返すべき"
  end

  def test_safe_path_prefixes_dash
    assert_equal './-rf', @file_opener.send(:safe_path, '-rf')
    assert_equal '/tmp/-rf', @file_opener.send(:safe_path, '/tmp/-rf')
  end

  def test_application_argv_splits_arguments
    skip 'POSIX only' if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
    assert_equal ['code', '-r'], @file_opener.send(:application_argv, 'code -r')
  end

  # ファイル名にシェルのメタ文字が含まれていてもコマンドが実行されないこと
  def test_open_file_does_not_execute_shell_metacharacters
    skip 'POSIX only' if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/

    file_path = File.join(@tmpdir, 'a;touch pwned_marker $(id) `id`')
    File.write(file_path, 'x')

    captured = []
    @file_opener.define_singleton_method(:run_command) { |argv| captured << argv; true }

    Rufio::ConfigLoader.stub(:applications, { :default => 'open' }) do
      @file_opener.open_file(file_path)
    end

    # パスが加工されず単一の引数として渡される（シェルで解釈されない）
    assert_equal 1, captured.size
    assert_equal file_path, captured.first.last
    assert_equal 2, captured.first.size
  end
end