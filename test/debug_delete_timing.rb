#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'fileutils'
require 'tmpdir'

class DeleteTimingTest
  def initialize
    @test_dir = Dir.mktmpdir("rufio_delete_timing_test")
    puts "テストディレクトリ: #{@test_dir}"
  end

  def cleanup
    FileUtils.rm_rf(@test_dir)
    puts "テストディレクトリクリーンアップ完了"
  end

  def test_delete_timing
    puts "=== 削除タイミングテスト開始 ==="
    
    # テストファイル作成
    test_file = File.join(@test_dir, "test_file.txt")
    File.write(test_file, "テストデータ")
    
    puts "1. ファイル作成: #{File.exist?(test_file)}"
    
    # 削除前の状態確認
    puts "2. 削除前存在確認: #{File.exist?(test_file)}"
    
    # 削除実行
    begin
      FileUtils.rm(test_file)
      puts "3. FileUtils.rm実行完了"
    rescue => e
      puts "3. FileUtils.rm失敗: #{e.message}"
      return
    end
    
    # 削除直後の存在確認（複数回）
    5.times do |i|
      exists = File.exist?(test_file)
      puts "4-#{i+1}. 削除直後存在確認#{i+1}回目: #{exists}"
      sleep(0.01) # 10ms待機
    end
    
    # 最終確認
    puts "5. 最終存在確認: #{File.exist?(test_file)}"
  end

  def test_directory_delete_timing
    puts "\n=== ディレクトリ削除タイミングテスト開始 ==="
    
    # テストディレクトリ作成
    test_subdir = File.join(@test_dir, "test_subdir")
    Dir.mkdir(test_subdir)
    File.write(File.join(test_subdir, "inner_file.txt"), "内部ファイル")
    
    puts "1. ディレクトリ作成: #{File.exist?(test_subdir)}"
    puts "2. 内部ファイル確認: #{File.exist?(File.join(test_subdir, 'inner_file.txt'))}"
    
    # 削除実行
    begin
      FileUtils.rm_rf(test_subdir)
      puts "3. FileUtils.rm_rf実行完了"
    rescue => e
      puts "3. FileUtils.rm_rf失敗: #{e.message}"
      return
    end
    
    # 削除直後の存在確認（複数回）
    5.times do |i|
      exists = File.exist?(test_subdir)
      puts "4-#{i+1}. 削除直後存在確認#{i+1}回目: #{exists}"
      sleep(0.01) # 10ms待機
    end
    
    # 最終確認
    puts "5. 最終存在確認: #{File.exist?(test_subdir)}"
  end

  def simulate_rufio_delete_logic_single_file
    puts "\n=== Rufio削除ロジックシミュレーション（単一ファイル） ==="
    
    # 単一ファイル作成
    files = ["single_file.txt"]
    files.each do |filename|
      File.write(File.join(@test_dir, filename), "データ: #{filename}")
    end
    
    success_count = 0
    error_messages = []
    
    files.each do |filename|
      item_path = File.join(@test_dir, filename)
      puts "\n処理中: #{filename}"
      
      begin
        # 存在確認
        unless File.exist?(item_path)
          error_messages << "#{filename}: ファイルが見つかりません"
          next
        end
        puts "  存在確認: OK"
        
        # 削除実行
        FileUtils.rm(item_path)
        puts "  削除実行: 完了"
        
        # 削除後の存在確認（Rufioのロジックと同じ）
        sleep(0.01) # 10ms待機（Rufioと同じ）
        still_exists = File.exist?(item_path)
        puts "  削除後存在確認: #{still_exists}"
        
        if still_exists
          error_messages << "#{filename}: 削除に失敗しました"
          puts "  結果: 失敗（まだ存在している）"
        else
          success_count += 1
          puts "  結果: 成功"
        end
      rescue => e
        error_messages << "#{filename}: #{e.message}"
        puts "  例外: #{e.message}"
      end
    end
    
    puts "\n=== 単一ファイル削除結果 ==="
    puts "成功: #{success_count}個"
    puts "失敗: #{files.length - success_count}個"
    puts "エラーメッセージ: #{error_messages}"
    
    # Rufioの表示ロジックをシミュレート
    total_count = files.length
    has_errors = !error_messages.empty?
    
    puts "DEBUG VALUES:"
    puts "  success_count = #{success_count}"
    puts "  total_count = #{total_count}"
    puts "  has_errors = #{has_errors}"
    puts "  success_count == total_count = #{success_count == total_count}"
    puts "  success_count == total_count && !has_errors = #{success_count == total_count && !has_errors}"
    
    if success_count == total_count && !has_errors
      puts "表示: #{success_count}個のアイテムを削除しました"
    else
      failed_count = total_count - success_count
      puts "表示: #{success_count}個削除、#{failed_count}個失敗"
    end
  end

  def simulate_rufio_delete_logic
    puts "\n=== Rufio削除ロジックシミュレーション（複数ファイル） ==="
    
    # 複数ファイル作成
    files = ["file1.txt", "file2.txt", "file3.txt"]
    files.each do |filename|
      File.write(File.join(@test_dir, filename), "データ: #{filename}")
    end
    
    success_count = 0
    error_messages = []
    
    files.each do |filename|
      item_path = File.join(@test_dir, filename)
      puts "\n処理中: #{filename}"
      
      begin
        # 存在確認
        unless File.exist?(item_path)
          error_messages << "#{filename}: ファイルが見つかりません"
          next
        end
        puts "  存在確認: OK"
        
        # 削除実行
        FileUtils.rm(item_path)
        puts "  削除実行: 完了"
        
        # 削除後の存在確認（Rufioのロジックと同じ）
        if File.exist?(item_path)
          error_messages << "#{filename}: 削除に失敗しました"
          puts "  結果: 失敗（まだ存在している）"
        else
          success_count += 1
          puts "  結果: 成功"
        end
      rescue => e
        error_messages << "#{filename}: #{e.message}"
        puts "  例外: #{e.message}"
      end
    end
    
    puts "\n=== 最終結果 ==="
    puts "成功: #{success_count}個"
    puts "失敗: #{files.length - success_count}個"
    puts "エラーメッセージ: #{error_messages}"
    
    # Rufioの表示ロジックをシミュレート
    total_count = files.length
    has_errors = !error_messages.empty?
    
    if success_count == total_count && !has_errors
      puts "表示: #{success_count}個のアイテムを削除しました"
    else
      failed_count = total_count - success_count
      puts "表示: #{success_count}個削除、#{failed_count}個失敗"
    end
  end

  def run_all_tests
    test_delete_timing
    test_directory_delete_timing
    simulate_rufio_delete_logic_single_file
    simulate_rufio_delete_logic
  end
end

# テスト実行
if __FILE__ == $0
  tester = DeleteTimingTest.new
  begin
    tester.run_all_tests
  ensure
    tester.cleanup
  end
end