# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/rufio'

# プレビューモードの `/`: プレビュー中のファイルの中を検索する。
# 一致行の位置は描画側（UIRenderer）が折り返し後の行から求めてビューに渡す。
class TestPreviewSearch < Minitest::Test
  LINES = [
    'alpha one',
    'beta two',
    'gamma three',
    'delta four',
    'ALPHA five',
    'epsilon six'
  ].freeze

  def setup
    @dir = Dir.mktmpdir('rufio_preview_search')
    @path = File.join(@dir, 'notes.txt')
    File.write(@path, "#{LINES.join("\n")}\n")
    @long = File.join(@dir, 'long.txt')
    File.write(@long, (1..200).map { |i| i == 150 ? 'needle here' : "line #{i}" }.join("\n") + "\n")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def view_for(path = @path)
    Rufio::PreviewView.build(path)
  end

  # 描画側がするのと同じ順序で、表示行数と一致行を渡す
  def feed_matches(view, lines: LINES, visible_rows: 4)
    view.visible_rows = visible_rows
    query = view.search_query.to_s.downcase
    matches = query.empty? ? [] : lines.each_index.select { |i| lines[i].downcase.include?(query) }
    view.apply_matches(matches)
    view
  end

  def type(view, text)
    text.each_char { |char| view.handle_key(char) }
  end

  # === 検索の開始と入力 ===

  def test_slash_opens_the_search_prompt
    view = view_for

    assert view.handle_key('/')
    assert view.search_prompt_open?
    assert_includes view.status_line, '/'
  end

  def test_typing_builds_the_query
    view = view_for
    view.handle_key('/')
    type(view, 'alpha')

    assert_equal 'alpha', view.search_query
    assert_includes view.status_line, '/alpha'
  end

  def test_backspace_and_ctrl_u_edit_the_query
    view = view_for
    view.handle_key('/')
    type(view, 'alpha')

    view.handle_key("\u007F")
    assert_equal 'alph', view.search_query

    view.handle_key("\x15")
    assert_equal '', view.search_query
  end

  def test_the_prompt_swallows_scroll_keys
    view = view_for
    view.handle_key('/')

    assert view.handle_key('j'), '入力中のキーはスクロールに使わないこと'
    assert_equal 'j', view.search_query
    assert_equal 0, view.row_offset
  end

  def test_the_search_key_follows_the_keybind_setting
    rebound = Rufio::ConfigLoader.default_keybinds.merge(search: 'S')
    Rufio::ConfigLoader.stub(:keybinds, rebound) do
      view = view_for
      assert view.handle_key('S')
      assert view.search_prompt_open?
      refute view.handle_key('/'), '既定キーは設定で置き換わること'
    end
  end

  # === 一致位置への移動 ===

  def test_the_view_jumps_to_the_first_match_while_typing
    view = view_for
    view.handle_key('/')
    type(view, 'alpha')
    feed_matches(view)

    assert_equal [0, 4], view.search_matches
    assert_equal 0, view.current_match
  end

  def test_matching_ignores_case
    view = view_for
    view.handle_key('/')
    type(view, 'ALPHA')
    feed_matches(view)

    assert_equal [0, 4], view.search_matches
  end

  def test_enter_keeps_the_search_and_closes_the_prompt
    view = view_for
    view.handle_key('/')
    type(view, 'alpha')
    view.handle_key("\r")
    feed_matches(view)

    refute view.search_prompt_open?
    assert_equal 'alpha', view.search_query
    assert_equal [0, 4], view.search_matches
  end

  def test_n_and_shift_n_move_between_matches
    view = view_for
    view.handle_key('/')
    type(view, 'alpha')
    view.handle_key("\r")
    feed_matches(view)

    assert view.handle_key('n')
    feed_matches(view)
    assert_equal 4, view.current_match
    assert_operator view.row_offset, :>, 0, '画面外の一致には追従してスクロールすること'

    assert view.handle_key('N')
    feed_matches(view)
    assert_equal 0, view.current_match
  end

  def test_n_wraps_around
    view = view_for
    view.handle_key('/')
    type(view, 'alpha')
    view.handle_key("\r")
    feed_matches(view)

    view.handle_key('n')
    feed_matches(view)
    view.handle_key('n')
    feed_matches(view)

    assert_equal 0, view.current_match, '最後の一致の次は先頭に戻ること'
  end

  def test_n_does_nothing_without_a_search
    view = view_for

    refute view.handle_key('n')
    refute view.handle_key('N')
  end

  def test_escape_while_typing_cancels_the_search
    view = view_for
    view.handle_key('j')
    view.handle_key('j')
    offset = view.row_offset
    view.handle_key('/')
    type(view, 'alpha')
    feed_matches(view)

    assert view.handle_key("\e")
    refute view.search_prompt_open?
    assert_nil view.search_query
    assert_empty view.search_matches
    assert_equal offset, view.row_offset, 'キャンセルしたら元の位置に戻ること'
  end

  def test_escape_after_the_search_clears_it_before_leaving_preview
    view = view_for
    view.handle_key('/')
    type(view, 'alpha')
    view.handle_key("\r")
    feed_matches(view)

    assert view.handle_key("\e"), 'まず検索を解除すること'
    assert_nil view.search_query
    refute view.handle_key("\e"), '検索がなければ ESC はビューで扱わない（プレビューを抜ける）'
  end

  def test_the_status_line_reports_the_match_count
    view = view_for
    view.handle_key('/')
    type(view, 'alpha')
    view.handle_key("\r")
    feed_matches(view)

    assert_includes view.status_line, 'alpha'
    assert_includes view.status_line, '1/2'
    assert_includes view.status_line, 'n/N'
  end

  def test_the_status_line_reports_no_matches
    view = view_for
    view.handle_key('/')
    type(view, 'zzz')
    view.handle_key("\r")
    feed_matches(view)

    assert_includes view.status_line, 'no matches'
    assert_empty view.search_matches
    assert_nil view.current_match
  end

  def test_the_status_line_mentions_the_search_key
    assert_includes view_for.status_line, '/: search'
  end

  def test_reset_clears_the_search
    view = view_for
    view.handle_key('/')
    type(view, 'alpha')
    view.handle_key("\r")
    feed_matches(view)

    assert view.reset
    assert_nil view.search_query
    assert_empty view.search_matches
  end

  # === プレビューモード経由（NavigationController / KeybindHandler） ===

  def handler_for(name)
    listing = Rufio::DirectoryListing.new(@dir)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(listing)
    index = listing.list_entries.index { |entry| entry[:name] == name }
    refute_nil index
    handler.select_index(index)
    assert handler.focus_preview_pane
    handler
  end

  def test_the_search_starts_from_preview_mode
    handler = handler_for('notes.txt')

    assert handler.handle_key('/')
    assert handler.preview_view.search_prompt_open?
    handler.handle_key('a')
    assert_equal 'a', handler.preview_view.search_query
  end

  def test_escape_closes_the_search_before_leaving_preview_mode
    handler = handler_for('notes.txt')
    handler.handle_key('/')
    handler.handle_key('a')
    handler.handle_key("\r")

    assert handler.handle_key("\e")
    assert handler.preview_focused?, 'ESC は検索を解除するだけであること'
    assert_nil handler.preview_view.search_query

    assert handler.handle_key("\e")
    refute handler.preview_focused?
  end

  # === 描画（UIRenderer） ===

  def renderer_for(name, width: 100, height: 14)
    screen = Rufio::Screen.new(width, height)
    listing = Rufio::DirectoryListing.new(@dir)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(listing)
    ui = Rufio::UIRenderer.new(screen_width: width, screen_height: height,
                               keybind_handler: handler, directory_listing: listing,
                               file_preview: Rufio::FilePreview.new)
    handler.select_index(listing.list_entries.index { |entry| entry[:name] == name })
    assert handler.focus_preview_pane
    [screen, ui, handler]
  end

  def cells_with(screen, width, height, bg)
    (0...height).flat_map do |y|
      (0...width).map do |x|
        cell = screen.get_cell(x, y)
        cell && cell[:bg] == bg ? cell[:char] : nil
      end
    end.compact.join
  end

  def test_matches_are_highlighted_in_the_preview
    screen, ui, handler = renderer_for('notes.txt')
    handler.handle_key('/')
    'alpha'.each_char { |char| handler.handle_key(char) }
    handler.handle_key("\r")
    ui.draw_screen(screen)

    current = cells_with(screen, 100, 14, Rufio::UIRenderer::CURRENT_MATCH_BG)
    others = cells_with(screen, 100, 14, Rufio::UIRenderer::SEARCH_MATCH_BG)
    assert_equal 'alpha', current, '現在の一致は別の色で示すこと'
    assert_equal 'ALPHA', others, '他の一致もハイライトすること'
  end

  def test_the_preview_scrolls_to_a_match_further_down
    screen, ui, handler = renderer_for('long.txt')
    handler.handle_key('/')
    'needle'.each_char { |char| handler.handle_key(char) }
    handler.handle_key("\r")
    ui.draw_screen(screen)

    text = (0...14).map { |y| Rufio::ColorHelper.strip_ansi(screen.row(y)) }.join("\n")
    assert_includes text, 'needle here', '一致した行までスクロールすること'
    assert_operator handler.preview_scroll_offset, :>, 100
  end

  def test_the_query_is_shown_while_typing
    screen, ui, handler = renderer_for('notes.txt')
    handler.handle_key('/')
    'bet'.each_char { |char| handler.handle_key(char) }
    ui.draw_screen(screen)

    text = (0...14).map { |y| Rufio::ColorHelper.strip_ansi(screen.row(y)) }.join("\n")
    assert_includes text, '/bet'
  end
end
