# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rufio"
require "fileutils"
require "tmpdir"

class TestFilePreview
  def initialize
    @test_dir = Dir.mktmpdir("rufio_preview_test")
    @original_dir = Dir.pwd
    Dir.chdir(@test_dir)
    
    # テスト用ファイルを作成
    File.write("text_file.txt", "これはテキストファイルです。\n複数行のテストデータです。\n日本語も含まれています。")
    File.write("ruby_file.rb", "# Ruby ファイル\nputs 'Hello, World!'\nclass Test\n  def initialize\n    @value = 42\n  end\nend")
    File.write("large_file.txt", (1..100).map { |i| "行#{i}" }.join("\n"))
    File.write("empty_file.txt", "")
    
    # バイナリファイル（簡易）
    File.write("binary_file.bin", "\x00\x01\x02\x03\xFF\xFE\xFD")
    
    puts "ファイルプレビューテスト環境準備完了: #{@test_dir}"
  end

  def cleanup
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@test_dir)
    puts "ファイルプレビューテスト環境クリーンアップ完了"
  end

  def test_file_preview_initialization
    begin
      preview = Rufio::FilePreview.new
      if preview.is_a?(Rufio::FilePreview)
        puts "✓ file_preview_initialization"
      else
        puts "✗ file_preview_initialization"
      end
    rescue NameError
      puts "期待通りエラー: FilePreviewクラスが未実装"
    end
  end

  def test_text_file_preview
    begin
      preview = Rufio::FilePreview.new
      content = preview.preview_file("text_file.txt")
      
      if content.is_a?(Hash) && 
         content[:type] == "text" && 
         content[:lines].is_a?(Array) &&
         content[:lines].length > 0
        puts "✓ text_file_preview"
      else
        puts "✗ text_file_preview"
      end
    rescue NameError
      puts "期待通りエラー: FilePreviewクラスが未実装"
    end
  end

  def test_ruby_file_syntax_highlighting
    begin
      preview = Rufio::FilePreview.new
      content = preview.preview_file("ruby_file.rb")
      
      if content.is_a?(Hash) && 
         content[:type] == "code" && 
         content[:language] == "ruby" &&
         content[:lines].is_a?(Array)
        puts "✓ ruby_file_syntax_highlighting"
      else
        puts "✗ ruby_file_syntax_highlighting"
      end
    rescue NameError
      puts "期待通りエラー: FilePreviewクラスが未実装"
    end
  end

  def test_large_file_truncation
    begin
      preview = Rufio::FilePreview.new
      content = preview.preview_file("large_file.txt", max_lines: 10)
      
      if content.is_a?(Hash) && 
         content[:lines].length <= 10 &&
         content[:truncated] == true
        puts "✓ large_file_truncation"
      else
        puts "✗ large_file_truncation"
      end
    rescue NameError
      puts "期待通りエラー: FilePreviewクラスが未実装"
    end
  end

  def test_empty_file_handling
    begin
      preview = Rufio::FilePreview.new
      content = preview.preview_file("empty_file.txt")
      
      if content.is_a?(Hash) && 
         content[:type] == "empty" &&
         content[:lines].empty?
        puts "✓ empty_file_handling"
      else
        puts "✗ empty_file_handling"
      end
    rescue NameError
      puts "期待通りエラー: FilePreviewクラスが未実装"
    end
  end

  def test_binary_file_detection
    begin
      preview = Rufio::FilePreview.new
      content = preview.preview_file("binary_file.bin")
      
      if content.is_a?(Hash) && 
         content[:type] == "binary" &&
         content[:message].include?("バイナリ")
        puts "✓ binary_file_detection"
      else
        puts "✗ binary_file_detection"
      end
    rescue NameError
      puts "期待通りエラー: FilePreviewクラスが未実装"
    end
  end

  def test_nonexistent_file_handling
    begin
      preview = Rufio::FilePreview.new
      content = preview.preview_file("nonexistent.txt")
      
      if content.is_a?(Hash) && 
         content[:type] == "error" &&
         content[:message].include?("ファイルが見つかりません")
        puts "✓ nonexistent_file_handling"
      else
        puts "✗ nonexistent_file_handling"
      end
    rescue NameError
      puts "期待通りエラー: FilePreviewクラスが未実装"
    end
  end

  def test_file_info_extraction
    begin
      preview = Rufio::FilePreview.new
      content = preview.preview_file("text_file.txt")
      
      if content.is_a?(Hash) && 
         content.key?(:size) &&
         content.key?(:modified) &&
         content.key?(:encoding)
        puts "✓ file_info_extraction"
      else
        puts "✗ file_info_extraction"
      end
    rescue NameError
      puts "期待通りエラー: FilePreviewクラスが未実装"
    end
  end

  def test_preview_format_consistency
    begin
      preview = Rufio::FilePreview.new
      
      # 複数のファイルタイプでフォーマットの一貫性をテスト
      text_content = preview.preview_file("text_file.txt")
      ruby_content = preview.preview_file("ruby_file.rb")
      empty_content = preview.preview_file("empty_file.txt")
      
      # 全てがHashで必須キーを持つことを確認
      required_keys = [:type, :lines]
      formats_consistent = [text_content, ruby_content, empty_content].all? do |content|
        content.is_a?(Hash) && required_keys.all? { |key| content.key?(key) }
      end
      
      if formats_consistent
        puts "✓ preview_format_consistency"
      else
        puts "✗ preview_format_consistency"
      end
    rescue NameError
      puts "期待通りエラー: FilePreviewクラスが未実装"
    end
  end

  def run_all_tests
    puts "=== Rufio FilePreview テスト開始 ==="
    test_file_preview_initialization
    test_text_file_preview
    test_ruby_file_syntax_highlighting
    test_large_file_truncation
    test_empty_file_handling
    test_binary_file_detection
    test_nonexistent_file_handling
    test_file_info_extraction
    test_preview_format_consistency
    puts "=== ファイルプレビューテスト完了 ==="
  end
end

# テスト実行
if __FILE__ == $0
  test = TestFilePreview.new
  test.run_all_tests
  test.cleanup
end