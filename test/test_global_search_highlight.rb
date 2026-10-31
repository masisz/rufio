# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'timeout'

# G mode の結果一覧で検索語に一致した部分をハイライトする
class TestGlobalSearchHighlight < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio-highlight')
    @dir = File.join(@root, 'first')
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, 'Report_First.txt'), "xx Hello WORLD and world\n")
    File.write(File.join(@dir, 'jp.txt'), "日本語の検索\n")
    @search = Rufio::GlobalSearch.new
    @search.open([{ name: 'first', path: @dir }])
    @screen = Rufio::Screen.new(100, 24)
  end

  def teardown
    @search.close
    FileUtils.rm_rf(@root)
  end

  def wait_for_scan
    Timeout.timeout(5) do
      while @search.scanning?
        @search.poll
        Thread.pass
      end
    end
    @search.poll
  end

  def row_text(y)
    Rufio::ColorHelper.strip_ansi(@screen.row(y))
  end

  def find_row(fragment)
    (0...@screen.height).find { |y| row_text(y).include?(fragment) } || flunk("#{fragment} not drawn")
  end

  # 文字列中の文字位置を画面の x 座標に変換する
  def x_of(text, char_index)
    Rufio::TextUtils.display_width(text[0, char_index])
  end

  def highlighted?(x, y)
    !@screen.get_cell(x, y).bg.nil?
  end

  def assert_highlight(y, char_start, length, expected = true)
    text = row_text(y)
    length.times do |i|
      x = x_of(text, char_start + i)
      assert_equal expected, highlighted?(x, y), "x=#{x} (#{text[char_start + i].inspect}) in #{text.inspect}"
    end
  end

  def test_file_name_matches_are_highlighted_case_insensitively
    @search.handle_key('first')
    wait_for_scan
    @search.draw(@screen)
    y = find_row('Report_First.txt')
    text = row_text(y)
    path_start = text.index('Report_First.txt')
    assert_highlight(y, path_start + 'Report_'.length, 'First'.length)
    assert_highlight(y, path_start, 'Report_'.length, false)
    # ブックマーク名 [first] は検索対象外なのでハイライトしない
    assert_highlight(y, text.index('[first]'), '[first]'.length, false)
  end

  def test_content_snippet_highlights_every_occurrence
    @search.handle_key("\t")
    @search.handle_key('world')
    wait_for_scan
    @search.draw(@screen)
    y = find_row('Hello WORLD and world')
    text = row_text(y)
    assert_highlight(y, text.index('WORLD'), 5)
    assert_highlight(y, text.index('world'), 5)
    assert_highlight(y, text.index('Hello'), 5, false)
    assert_highlight(y, text.index(' and '), 5, false)
    # パス行は本文検索の対象ではないのでハイライトしない
    path_y = find_row('Report_First.txt:1')
    refute((0...@screen.width).any? { |x| highlighted?(x, path_y) })
  end

  def test_full_width_matches_are_highlighted_at_display_columns
    @search.handle_key("\t")
    @search.handle_key('検索')
    wait_for_scan
    @search.draw(@screen)
    y = find_row('日本語の検索')
    text = row_text(y)
    start = text.index('検索')
    assert_highlight(y, start, 2)
    assert_highlight(y, text.index('日本語の'), 4, false)
  end

  def test_nothing_is_highlighted_without_a_query
    wait_for_scan
    @search.draw(@screen)
    (0...@screen.height).each do |y|
      refute((0...@screen.width).any? { |x| highlighted?(x, y) }, "row #{y} has highlight: #{row_text(y)}")
    end
  end
end
