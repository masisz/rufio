# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

class TestFilePreviewLimits < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio-preview-limits')
    @preview = Rufio::FilePreview.new
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write_file(name, content)
    path = File.join(@root, name)
    File.binwrite(path, content)
    path
  end

  def test_pdf_is_not_read_as_text_even_with_an_ascii_header
    path = write_file('large.PDF', "%PDF-1.7\n" + 'a' * 1024 + "\n" + "\xFF" * (128 * 1024))
    @preview.stub(:read_text_file, ->(*) { flunk 'PDF must not be read as text' }) do
      result = @preview.preview_file(path)
      assert_equal 'binary', result[:type]
      assert_equal File.size(path), result[:size]
      assert_equal File.mtime(path), result[:modified]
    end
  end

  def test_long_line_does_not_read_past_the_byte_budget
    path = write_file('long.txt', 'a' * (128 * 1024) + "\nSHOULD NOT BE READ\n")
    result = @preview.preview_file(path)
    assert_equal ['a' * 500 + '...'], result[:lines]
    assert result[:truncated]
  end

  def test_exact_byte_budget_is_not_truncated
    result = @preview.preview_file(write_file('exact.txt', 'a' * (64 * 1024)))
    refute result[:truncated]
    assert_equal ['a' * 500 + '...'], result[:lines]
  end

  def test_byte_budget_preserves_valid_utf8_at_a_split_character
    path = write_file('unicode.txt', "#{'a' * (64 * 1024 - 1)}あ\nTAIL")
    result = @preview.preview_file(path)
    assert result[:truncated]
    assert_equal 1, result[:lines].length
    assert result[:lines].all?(&:valid_encoding?)
  end

  def test_line_limit_reports_remaining_content
    path = write_file('lines.txt', "one\ntwo\nthree\n")
    result = @preview.preview_file(path, max_lines: 2)
    assert_equal %w[one two], result[:lines]
    assert result[:truncated]
  end

  def test_short_text_and_invalid_utf8_remain_supported
    result = @preview.preview_file(write_file('short.txt', "hello\nworld\n"))
    assert_equal %w[hello world], result[:lines]
    refute result[:truncated]
    result = @preview.preview_file(write_file('invalid.txt', "hello\xFFworld\n"))
    assert_equal ['hello?world'], result[:lines]
    assert_equal 'UTF-8', result[:encoding]
  end
end
