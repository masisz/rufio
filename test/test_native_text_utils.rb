# frozen_string_literal: true

require 'test_helper'
require 'rufio/native/text_utils'

class TestNativeTextUtils < Minitest::Test
  def test_text_utils_available
    skip "Native text utils not available" unless Rufio::Native::TextUtils.available?
    assert Rufio::Native::TextUtils.available?
  end

  def test_display_width_ascii
    skip "Native text utils not available" unless Rufio::Native::TextUtils.available?

    assert_equal 5, Rufio::Native::TextUtils.display_width('Hello')
    assert_equal 11, Rufio::Native::TextUtils.display_width('Hello World')
  end

  def test_display_width_japanese
    skip "Native text utils not available" unless Rufio::Native::TextUtils.available?

    assert_equal 10, Rufio::Native::TextUtils.display_width('こんにちは')
    assert_equal 12, Rufio::Native::TextUtils.display_width('日本語テスト')
  end

  def test_display_width_mixed
    skip "Native text utils not available" unless Rufio::Native::TextUtils.available?

    assert_equal 15, Rufio::Native::TextUtils.display_width('Hello世界')
  end

  def test_truncate_to_width
    skip "Native text utils not available" unless Rufio::Native::TextUtils.available?

    result = Rufio::Native::TextUtils.truncate_to_width('Hello World', 8)
    assert_equal 'Hello...', result
  end

  def test_truncate_japanese
    skip "Native text utils not available" unless Rufio::Native::TextUtils.available?

    result = Rufio::Native::TextUtils.truncate_to_width('こんにちは世界', 10)
    assert result.include?('...')
    assert Rufio::Native::TextUtils.display_width(result) <= 10
  end

  def test_performance_comparison
    skip "Native text utils not available" unless Rufio::Native::TextUtils.available?
    skip "Performance test - run manually"

    require 'benchmark'

    test_strings = [
      'Hello World',
      'こんにちは世界',
      'Mix 混合 Text テキスト',
      'A' * 100,
      '日' * 50
    ]

    native_time = Benchmark.realtime do
      10000.times do
        test_strings.each do |str|
          Rufio::Native::TextUtils.display_width(str)
        end
      end
    end

    puts "\n📊 Text Utils Performance (5 strings, 10000 iterations):"
    puts "   Native: #{(native_time * 1000).round(2)}ms"
  end
end
