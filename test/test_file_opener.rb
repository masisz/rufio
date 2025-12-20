# frozen_string_literal: true

require_relative "test_helper"

class TestFileOpener < Minitest::Test
  def setup
    @file_opener = Rufio::FileOpener.new
  end

  def test_find_application_for_ruby_file
    # テスト用一時ファイルを作成
    file_path = "/tmp/test.rb"
    File.write(file_path, "puts 'hello'")
    
    # プライベートメソッドをテストするため、sendを使用
    application = @file_opener.send(:find_application_for_file, file_path)
    
    # 設定に基づいてcodeアプリケーションが選択されることを確認
    assert_equal 'code', application
    
    # クリーンアップ
    File.delete(file_path) if File.exist?(file_path)
  end

  def test_find_application_for_unknown_extension
    file_path = "/tmp/test.unknown"
    File.write(file_path, "test content")
    
    application = @file_opener.send(:find_application_for_file, file_path)
    
    # 未知の拡張子に対してはデフォルトアプリケーションが選択されることを確認
    assert_equal 'open', application
    
    File.delete(file_path) if File.exist?(file_path)
  end

  def test_open_nonexistent_file
    result = @file_opener.open_file("/path/to/nonexistent/file.txt")
    refute result, "存在しないファイルに対してはfalseを返すべき"
  end

  def test_open_directory
    result = @file_opener.open_file("/tmp")
    refute result, "ディレクトリに対してはfalseを返すべき"
  end

  def test_quote_shell_argument
    # スペースを含む引数
    quoted = @file_opener.send(:quote_shell_argument, "file with spaces.txt")
    assert_equal '"file with spaces.txt"', quoted
    
    # 通常の引数
    normal = @file_opener.send(:quote_shell_argument, "normalfile.txt")
    assert_equal 'normalfile.txt', normal
    
    # ダブルクォートを含む引数
    with_quotes = @file_opener.send(:quote_shell_argument, 'file"with"quotes.txt')
    assert_equal '"file\"with\"quotes.txt"', with_quotes
  end
end