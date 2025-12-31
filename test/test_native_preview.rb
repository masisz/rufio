# frozen_string_literal: true

require 'test_helper'
require 'rufio/native/preview'
require 'tmpdir'
require 'fileutils'

class TestNativePreview < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir
  end

  def test_preview_available
    skip "Native preview not available" unless Rufio::Native::Preview.available?
    assert Rufio::Native::Preview.available?
  end

  def test_preview_text_file
    skip "Native preview not available" unless Rufio::Native::Preview.available?

    file_path = File.join(@test_dir, 'test.txt')
    File.write(file_path, "Line 1\nLine 2\nLine 3\n")

    result = Rufio::Native::Preview.generate(file_path)

    assert_equal 'text', result[:type]
    assert_equal 3, result[:lines].size
    assert_equal 'Line 1', result[:lines][0]
    assert_equal 'UTF-8', result[:encoding]
    refute result[:truncated]
  end

  def test_preview_code_file
    skip "Native preview not available" unless Rufio::Native::Preview.available?

    file_path = File.join(@test_dir, 'test.rb')
    File.write(file_path, "puts 'Hello'\nputs 'World'\n")

    result = Rufio::Native::Preview.generate(file_path)

    assert_equal 'code', result[:type]
    assert_equal 'ruby', result[:language]
    assert_equal 2, result[:lines].size
  end

  def test_preview_truncation
    skip "Native preview not available" unless Rufio::Native::Preview.available?

    file_path = File.join(@test_dir, 'long.txt')
    content = (1..100).map { |i| "Line #{i}" }.join("\n")
    File.write(file_path, content)

    result = Rufio::Native::Preview.generate(file_path, max_lines: 10)

    assert_equal 10, result[:lines].size
    assert result[:truncated]
  end

  def test_preview_binary_file
    skip "Native preview not available" unless Rufio::Native::Preview.available?

    file_path = File.join(@test_dir, 'binary.bin')
    File.binwrite(file_path, "\x00\x01\x02\x03" * 200)

    result = Rufio::Native::Preview.generate(file_path)

    assert_equal 'binary', result[:type]
    assert_equal 'binary', result[:encoding]
  end

  def test_binary_detection
    skip "Native preview not available" unless Rufio::Native::Preview.available?

    text_file = File.join(@test_dir, 'text.txt')
    File.write(text_file, 'Hello World')

    binary_file = File.join(@test_dir, 'binary.bin')
    File.binwrite(binary_file, "\x00\x01\x02" * 100)

    refute Rufio::Native::Preview.binary?(text_file)
    assert Rufio::Native::Preview.binary?(binary_file)
  end

  def test_performance_comparison
    skip "Native preview not available" unless Rufio::Native::Preview.available?
    skip "Performance test - run manually"

    file_path = File.join(@test_dir, 'large.txt')
    content = (1..1000).map { |i| "Line #{i}: " + ('x' * 80) }.join("\n")
    File.write(file_path, content)

    require 'benchmark'

    native_time = Benchmark.realtime do
      100.times { Rufio::Native::Preview.generate(file_path) }
    end

    puts "\n📊 Preview Performance (1000 lines, 100 iterations):"
    puts "   Native: #{(native_time * 1000).round(2)}ms"
  end
end
