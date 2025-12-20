#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_helper'

class FilterResetTest
  def self.run_all_tests
    temp_dir = create_test_environment
    
    begin
      puts "=== フィルタリセット機能テスト開始 ==="
      run_tests(temp_dir)
      puts "=== フィルタリセット機能テスト完了 ==="
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
      puts "テスト環境クリーンアップ完了"
    end
  end

  private

  def self.create_test_environment
    temp_dir = Dir.mktmpdir('rufio_filter_test')
    puts "フィルタテスト環境準備完了: #{temp_dir}"
    
    # サブディレクトリを作成
    subdir = File.join(temp_dir, 'subdir')
    Dir.mkdir(subdir)
    
    # ファイルを作成
    File.write(File.join(temp_dir, 'test_file.txt'), 'test content')
    File.write(File.join(temp_dir, 'filter_me.rb'), 'ruby code')
    File.write(File.join(temp_dir, 'ignore_me.md'), 'markdown content')
    File.write(File.join(subdir, 'sub_file.txt'), 'sub content')
    
    temp_dir
  end

  def self.run_tests(temp_dir)
    directory_listing = Rufio::DirectoryListing.new(temp_dir)
    keybind_handler = Rufio::KeybindHandler.new
    keybind_handler.set_directory_listing(directory_listing)
    
    test_filter_reset_on_enter(keybind_handler)
    test_filter_reset_on_parent_navigation(keybind_handler)
  end

  def self.test_filter_reset_on_enter(keybind_handler)
    print "filter_reset_on_directory_enter: "
    
    # まずフィルタなしで全エントリを確認
    all_entries = keybind_handler.get_active_entries
    subdir_entry = all_entries.find { |entry| entry[:name] == 'subdir' && entry[:type] == 'directory' }
    
    if subdir_entry.nil?
      puts "✗ subdirエントリが見つかりません (全エントリ: #{all_entries.map { |e| e[:name] }.join(', ')})"
      return
    end
    
    # フィルタを設定（subdirにマッチしない文字を使用）
    keybind_handler.handle_key(' ')  # フィルタモード開始
    keybind_handler.handle_key('f')  # 'f'でフィルタリング
    keybind_handler.handle_key("\r") # Enterでフィルタ確定
    
    # フィルタが設定されていることを確認
    filter_active_before = keybind_handler.filter_active?
    filter_query_before = keybind_handler.filter_query
    
    # フィルタをクリアしてsubdirを選択
    keybind_handler.handle_key("\e")  # ESCでフィルタクリア
    entries = keybind_handler.get_active_entries
    subdir_index = entries.find_index { |entry| entry[:name] == 'subdir' && entry[:type] == 'directory' }
    
    if subdir_index
      keybind_handler.select_index(subdir_index)
      
      # 再度フィルタを設定（subdirが表示される文字を使用）
      keybind_handler.handle_key(' ')  # フィルタモード開始
      keybind_handler.handle_key('s')  # 's'でフィルタリング（subdirにマッチ）
      keybind_handler.handle_key('u')  # 'u'を追加（subにマッチ）
      keybind_handler.handle_key("\r") # Enterでフィルタ確定
      
      filter_active_before = keybind_handler.filter_active?
      filter_query_before = keybind_handler.filter_query
      
      # ディレクトリに移動
      keybind_handler.handle_key('l')  # Enter: ディレクトリに移動
      
      # フィルタがリセットされていることを確認
      filter_active_after = keybind_handler.filter_active?
      filter_query_after = keybind_handler.filter_query
      
      if filter_active_before && !filter_active_after && filter_query_after.empty?
        puts "✓"
      else
        puts "✗ フィルタがリセットされませんでした (before: #{filter_active_before}/#{filter_query_before}, after: #{filter_active_after}/#{filter_query_after})"
      end
    else
      puts "✗ subdirが見つかりません (エントリ: #{entries.map { |e| e[:name] }.join(', ')})"
    end
  end

  def self.test_filter_reset_on_parent_navigation(keybind_handler)
    print "filter_reset_on_parent_navigation: "
    
    # 現在subdirにいるはず、フィルタを再設定
    keybind_handler.handle_key(' ')  # フィルタモード開始
    keybind_handler.handle_key('s')  # 's'でフィルタリング
    keybind_handler.handle_key("\r") # Enterでフィルタ確定
    
    # フィルタが設定されていることを確認
    filter_active_before = keybind_handler.filter_active?
    filter_query_before = keybind_handler.filter_query
    
    # 親ディレクトリに移動
    keybind_handler.handle_key('h')  # 親ディレクトリに移動
    
    # フィルタがリセットされていることを確認
    filter_active_after = keybind_handler.filter_active?
    filter_query_after = keybind_handler.filter_query
    
    if filter_active_before && !filter_active_after && filter_query_after.empty?
      puts "✓"
    else
      puts "✗ フィルタがリセットされませんでした (before: #{filter_active_before}/#{filter_query_before}, after: #{filter_active_after}/#{filter_query_after})"
    end
  end
end

if __FILE__ == $0
  FilterResetTest.run_all_tests
end