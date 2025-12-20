# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

begin
  require "rufio"
  puts "Rufioモジュールの読み込み: 成功"
rescue LoadError => e
  puts "Rufioモジュールの読み込み: 失敗 - #{e.message}"
end

begin
  # DirectoryListingクラスの存在確認
  listing = Rufio::DirectoryListing.new(".")
  puts "DirectoryListingクラス: 成功 - クラスが正常に作成されました"
  
  # 基本機能のテスト
  entries = listing.list_entries
  puts "list_entries: 成功 - #{entries.length}個のエントリを取得"
  
  if entries.any?
    first_entry = entries.first
    puts "エントリ構造: #{first_entry.keys.join(', ')}"
  end
  
rescue NameError => e
  puts "DirectoryListingクラス: エラー - #{e.message}"
rescue => e
  puts "その他のエラー: #{e.message}"
end

puts "\nテスト完了: 実装の動作確認"