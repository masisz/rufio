# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rufio"
require "fileutils"
require "tmpdir"

# 親ディレクトリ移動のデバッグ
test_dir = Dir.mktmpdir("rufio_debug")
original_dir = Dir.pwd
Dir.chdir(test_dir)

FileUtils.mkdir_p("subdir1")
puts "テストディレクトリ: #{test_dir}"

begin
  listing = Rufio::DirectoryListing.new(test_dir)
  puts "初期パス: #{listing.current_path}"
  
  # サブディレクトリに移動
  result = listing.navigate_to("subdir1")
  puts "subdir1への移動: #{result}"
  puts "移動後のパス: #{listing.current_path}"
  
  # 親ディレクトリに戻る
  result = listing.navigate_to_parent
  puts "親ディレクトリへの移動: #{result}"
  puts "移動後のパス: #{listing.current_path}"
  puts "元のパスと同じ?: #{listing.current_path == test_dir}"
  
ensure
  Dir.chdir(original_dir)
  FileUtils.rm_rf(test_dir)
end