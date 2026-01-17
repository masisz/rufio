#!/usr/bin/env ruby
# frozen_string_literal: true

# エンコーディングエラーハンドリングの手動テスト

require_relative '../lib/rufio/file_preview'
require_relative '../lib/rufio/text_utils'

puts "=== Encoding Error Handling Test ==="
puts ""

# テストファイルのパス
test_file = File.join(__dir__, 'fixtures', 'invalid_utf8_binary.txt')

if File.exist?(test_file)
  puts "Testing file: #{test_file}"
  puts "File size: #{File.size(test_file)} bytes"
  puts ""

  # FilePreviewでファイルを読み込む
  file_preview = Rufio::FilePreview.new
  result = file_preview.preview_file(test_file)

  puts "Preview result:"
  puts "  Type: #{result[:type]}"
  puts "  Encoding: #{result[:encoding]}"
  puts "  Lines: #{result[:lines].length}"
  puts ""

  puts "Content:"
  result[:lines].each_with_index do |line, i|
    puts "  #{i + 1}: #{line.inspect}"
  end
  puts ""

  # TextUtilsで折り返し処理をテスト
  puts "Testing wrap_preview_lines:"
  wrapped = Rufio::TextUtils.wrap_preview_lines(result[:lines], 50)
  puts "  Wrapped lines: #{wrapped.length}"
  wrapped.each_with_index do |line, i|
    puts "  #{i + 1}: #{line.inspect}"
  end
  puts ""

  puts "✓ No crashes! Encoding errors handled successfully."
else
  puts "✗ Test file not found: #{test_file}"
  exit 1
end
