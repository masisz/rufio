#!/usr/bin/env ruby

# シンプルなテストスクリプト - RGA検索機能のテスト
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative '../lib/rufio/keybind_handler'
require_relative '../lib/rufio/directory_listing'
require_relative '../lib/rufio/file_opener'
require_relative '../lib/rufio/config_loader'

puts "=== RGA検索機能のテスト ==="

begin
  # テスト環境の準備
  keybind_handler = Rufio::KeybindHandler.new
  directory_listing = Rufio::DirectoryListing.new(Dir.pwd)
  keybind_handler.set_directory_listing(directory_listing)

  # テスト1: rgaが利用可能かチェック
  puts "テスト1: rga利用可能性チェック"
  rga_available = keybind_handler.send(:rga_available?)
  puts "  結果: #{rga_available ? 'rga利用可能' : 'rga利用不可'}"

  # テスト2: fキーがrga_searchを呼ぶかテスト
  puts "テスト2: fキー処理テスト"
  
  # rga_searchをモック化（実際の入力を避けるため）
  def keybind_handler.rga_search
    puts "    rga_search メソッドが呼び出されました"
    true
  end
  
  result = keybind_handler.handle_key('f')
  puts "  結果: #{result ? '成功' : '失敗'}"

  # テスト3: 無効なキーのテスト
  puts "テスト3: 無効なキーのテスト"
  result = keybind_handler.handle_key('z')
  puts "  結果: #{result == false ? '成功（falseが返された）' : '失敗'}"

  puts "\n=== 全テスト完了 ==="

rescue => e
  puts "エラーが発生しました: #{e.message}"
  puts e.backtrace.join("\n")
end