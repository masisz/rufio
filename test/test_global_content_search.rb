# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'timeout'

class TestGlobalContentSearch < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio-content')
    @a = File.join(@root, 'a')
    @b = File.join(@root, 'b')
    FileUtils.mkdir_p([@a, @b])
    File.write(File.join(@a, 'first.txt'), "header\nHello WORLD\n日本語の検索\n")
    File.write(File.join(@b, 'second.txt'), "world again\nno match\nWORLD twice\n")
    File.binwrite(File.join(@b, 'binary.dat'), "\x00world\xff")
    @search = Rufio::GlobalSearch.new
    @search.open([{ name: 'A', path: @a }, { name: 'B', path: @b }])
  end

  def teardown
    @search.close
    FileUtils.rm_rf(@root)
  end

  def wait_for_scan
    Timeout.timeout(3) do
      while @search.scanning?
        @search.poll
        Thread.pass
      end
    end
  end

  def test_tab_switches_to_content_and_finds_lines_across_bookmarks
    @search.handle_key("\t")
    @search.handle_key('world')
    wait_for_scan
    assert_equal :content, @search.search_type
    assert_equal [['first.txt', 2], ['second.txt', 1], ['second.txt', 3]],
                 @search.results.map { |r| [File.basename(r[:path]), r[:line_number]] }.sort
    assert @search.results.any? { |r| r[:match_text].include?('Hello WORLD') }
    assert_equal 1, @search.skipped_files
    screen = Rufio::Screen.new(100, 24)
    @search.draw(screen)
    text = (0...24).map { |y| Rufio::ColorHelper.strip_ansi(screen.row(y)) }.join("\n")
    assert_includes text, 'Content'
    assert_includes text, 'first.txt:2'
    assert_includes text, 'Hello WORLD'
  end

  def test_query_changes_discard_old_results_and_support_japanese
    @search.handle_key("\t")
    @search.handle_key('world')
    @search.handle_key("\x15")
    @search.handle_key('日本語')
    wait_for_scan
    assert_equal 1, @search.results.length
    assert_equal 3, @search.results.first[:line_number]
    assert_includes @search.results.first[:match_text], '日本語'
    @search.handle_key("\x15")
    wait_for_scan
    assert_empty @search.results
  end

  def test_switching_back_preserves_query_and_searches_file_names
    @search.handle_key("\t")
    @search.handle_key('first')
    wait_for_scan
    assert_empty @search.results
    @search.handle_key("\t")
    wait_for_scan
    assert_equal :filename, @search.search_type
    assert_equal 'first', @search.query
    assert_equal ['first.txt'], @search.results.map { |r| File.basename(r[:path]) }
    assert_nil @search.results.first[:line_number]
  end

  def test_query_is_literal_and_cancel_stops_content_search
    File.write(File.join(@a, 'literal.txt'), "[a-z].*\nplain text\n")
    @search.handle_key("\t")
    @search.handle_key('[a-z].*')
    wait_for_scan
    assert_equal 1, @search.results.length
    assert_equal 'literal.txt', File.basename(@search.handle_key("\r")[:path])
    @search.handle_key("\e")
    refute @search.active?
    refute @search.scanning?
  end

  def test_long_line_preview_includes_the_matching_text
    File.write(File.join(@a, 'long.txt'), ('x' * 1000) + 'needle' + ('y' * 1000))
    @search.handle_key("\t")
    @search.handle_key('needle')
    wait_for_scan
    assert_equal 1, @search.results.length
    assert_includes @search.results.first[:match_text], 'needle'
    assert_operator @search.results.first[:match_text].length, :<=, 200
  end
end
