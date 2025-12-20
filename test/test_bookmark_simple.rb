# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'tmpdir'

# Bookmarkクラスを直接読み込み
require_relative '../lib/rufio/bookmark'

# シンプルなテスト実行用のヘルパー
def assert(condition, message = "Assertion failed")
  raise message unless condition
end

def assert_equal(expected, actual, message = "Values not equal")
  unless expected == actual
    raise "#{message}: expected #{expected.inspect}, got #{actual.inspect}"
  end
end

def assert_empty(collection, message = "Collection not empty")
  unless collection.empty?
    raise "#{message}: #{collection.inspect}"
  end
end

def refute(condition, message = "Refutation failed")
  raise message if condition
end

def assert_nil(value, message = "Value not nil")
  unless value.nil?
    raise "#{message}: #{value.inspect}"
  end
end

# テスト実行
def run_tests
  puts "Running Bookmark tests..."
  
  test_config_dir = File.join(Dir.tmpdir, 'rufio_test_config')
  test_config_file = File.join(test_config_dir, 'bookmarks.json')
  
  begin
    # テスト用設定ディレクトリ作成
    FileUtils.mkdir_p(test_config_dir)
    FileUtils.rm_f(test_config_file)
    
    bookmark = Rufio::Bookmark.new(test_config_file)
    
    # Test 1: Initialize creates empty bookmarks
    puts "Test 1: Initialize creates empty bookmarks"
    assert_empty bookmark.list
    puts "✓ Passed"
    
    # Test 2: Add bookmark
    puts "Test 2: Add bookmark"
    # テスト用の存在するディレクトリを作成
    test_dir = File.join(test_config_dir, 'test_directory')
    FileUtils.mkdir_p(test_dir)
    
    result = bookmark.add(test_dir, 'TestDir')
    assert result
    assert_equal 1, bookmark.list.length
    assert_equal File.expand_path(test_dir), bookmark.list.first[:path]
    assert_equal 'TestDir', bookmark.list.first[:name]
    puts "✓ Passed"
    
    # Test 3: Add duplicate name
    puts "Test 3: Add duplicate name"
    test_dir2 = File.join(test_config_dir, 'test_directory2')
    FileUtils.mkdir_p(test_dir2)
    
    result = bookmark.add(test_dir2, 'TestDir')
    refute result
    assert_equal 1, bookmark.list.length
    puts "✓ Passed"
    
    # Test 4: Remove bookmark
    puts "Test 4: Remove bookmark"
    result = bookmark.remove('TestDir')
    assert result
    assert_empty bookmark.list
    puts "✓ Passed"
    
    # Test 5: Find by number
    puts "Test 5: Find by number"
    dirs = []
    names = ['ADir', 'BDir', 'CDir']
    
    names.each_with_index do |name, index|
      dir = File.join(test_config_dir, "test_dir_#{index}")
      FileUtils.mkdir_p(dir)
      dirs << dir
      bookmark.add(dir, name)
    end
    
    result = bookmark.find_by_number(1)
    assert_equal File.expand_path(dirs[0]), result[:path]
    assert_equal 'ADir', result[:name]
    
    result = bookmark.find_by_number(0)
    assert_nil result
    
    result = bookmark.find_by_number(10)
    assert_nil result
    puts "✓ Passed"
    
    # Test 6: Save and load
    puts "Test 6: Save and load persistence"
    bookmark.save
    
    new_bookmark = Rufio::Bookmark.new(test_config_file)
    new_bookmark.load
    
    assert_equal 3, new_bookmark.list.length
    puts "✓ Passed"
    
    puts "\n✅ All tests passed!"
    
  rescue StandardError => e
    puts "\n❌ Test failed: #{e.message}"
    puts e.backtrace.first(5)
    exit 1
  ensure
    # クリーンアップ
    FileUtils.rm_rf(test_config_dir) if Dir.exist?(test_config_dir)
  end
end

# テスト実行
run_tests