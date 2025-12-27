# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio/info_notice'

class TestInfoNotice < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @info_dir = File.join(@temp_dir, 'info')
    @tracking_dir = File.join(@temp_dir, 'notices')
    FileUtils.mkdir_p(@info_dir)
    FileUtils.mkdir_p(@tracking_dir)

    # Use constructor parameters for testing
    @info_notice = Rufio::InfoNotice.new(info_dir: @info_dir, tracking_dir: @tracking_dir)
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if Dir.exist?(@temp_dir)
  end

  def test_unread_notices_empty_directory
    notices = @info_notice.unread_notices
    assert_empty notices
  end

  def test_unread_notices_with_files
    # Create test notice files
    File.write(File.join(@info_dir, 'notice1.txt'), "# Test Notice 1\nContent line 1\nContent line 2")
    File.write(File.join(@info_dir, 'notice2.txt'), "# Test Notice 2\nContent line A")

    notices = @info_notice.unread_notices
    assert_equal 2, notices.length
    assert_equal 'Test Notice 1', notices[0][:title]
    assert_equal 'Test Notice 2', notices[1][:title]
  end

  def test_extract_title_with_markdown_heading
    file_path = File.join(@info_dir, 'test.txt')
    File.write(file_path, "# Test Title\nContent")

    title = @info_notice.extract_title(file_path)
    assert_equal 'Test Title', title
  end

  def test_extract_title_without_markdown
    file_path = File.join(@info_dir, 'test.txt')
    File.write(file_path, "Plain Title\nContent")

    title = @info_notice.extract_title(file_path)
    assert_equal 'Plain Title', title
  end

  def test_read_content_strips_title
    file_path = File.join(@info_dir, 'test.txt')
    File.write(file_path, "# Title\nLine 1\nLine 2")

    content = @info_notice.read_content(file_path)
    # Should have empty line at start, content lines, empty line, press any key message, empty line at end
    assert_includes content, 'Line 1'
    assert_includes content, 'Line 2'
    refute_includes content, '# Title'
    assert_includes content, 'Press any key to continue...'
  end

  def test_mark_as_shown
    file_path = File.join(@info_dir, 'test.txt')
    File.write(file_path, "# Test\nContent")

    refute @info_notice.shown?(file_path)

    @info_notice.mark_as_shown(file_path)

    assert @info_notice.shown?(file_path)
  end

  def test_unread_notices_excludes_shown
    file1 = File.join(@info_dir, 'notice1.txt')
    file2 = File.join(@info_dir, 'notice2.txt')

    File.write(file1, "# Notice 1\nContent 1")
    File.write(file2, "# Notice 2\nContent 2")

    # Mark first as shown
    @info_notice.mark_as_shown(file1)

    notices = @info_notice.unread_notices
    assert_equal 1, notices.length
    assert_equal 'Notice 2', notices[0][:title]
  end

  def test_read_content_error_handling
    file_path = File.join(@info_dir, 'nonexistent.txt')

    content = @info_notice.read_content(file_path)
    assert_includes content.join(' '), 'Error reading notice'
  end
end
