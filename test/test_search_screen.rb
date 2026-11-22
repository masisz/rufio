# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'timeout'
require_relative '../lib/rufio/search_screen'

class TestSearchScreen < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio-global')
    @a = File.join(@root, 'alpha')
    @b = File.join(@root, 'beta')
    FileUtils.mkdir_p(File.join(@a, 'nested'))
    FileUtils.mkdir_p(@b)
    File.write(File.join(@a, 'nested', '日本語.txt'), 'one')
    File.write(File.join(@a, 'Report.md'), 'two')
    File.write(File.join(@b, 'report.txt'), 'three')
    @search = Rufio::SearchScreen.new
  end

  def teardown
    @search.close
    FileUtils.rm_rf(@root)
  end

  def scan(bookmarks)
    @search.open(bookmarks)
    Timeout.timeout(3) do
      while @search.scanning?
        @search.poll
        Thread.pass
      end
    end
  end

  # ファイル名検索はバックグラウンドで照合するので、検索語を変えたら結果を待つ
  def settle
    Timeout.timeout(3) do
      while @search.scanning?
        @search.poll
        Thread.pass
      end
    end
  end

  def test_searches_all_bookmarks_recursively_and_case_insensitively
    scan([{ name: 'A', path: @a }, { name: 'B', path: @b }])
    @search.handle_key('REPORT')
    settle
    assert_equal ['Report.md', 'report.txt'], @search.results.map { |r| File.basename(r[:path]) }.sort
    @search.handle_key("\x15")
    @search.handle_key('日本語')
    settle
    assert_equal [File.join(@a, 'nested', '日本語.txt')], @search.results.map { |r| r[:path] }
  end

  def test_overlapping_roots_and_symlink_loops_do_not_duplicate_results
    File.symlink(@a, File.join(@a, 'nested', 'loop'))
    scan([{ name: 'A', path: @a }, { name: 'Nested', path: File.join(@a, 'nested') }])
    assert_equal 2, @search.results.length
    assert_equal 2, @search.results.map { |r| r[:path] }.uniq.length
  end

  def test_missing_roots_and_an_empty_target_are_reported
    scan([{ name: 'Missing', path: File.join(@root, 'missing') }])
    assert_empty @search.results
    refute_empty @search.errors
    scan([])
    screen = Rufio::Screen.new(80, 24)
    @search.draw(screen)
    text = (0...24).map { |y| Rufio::ColorHelper.strip_ansi(screen.row(y)) }.join("\n")
    assert_includes text, 'Nothing to search here.'
    assert_includes text, 'ESC: Back'
  end

  def test_selection_and_cancel
    scan([{ name: 'B', path: @b }])
    assert_equal File.join(@b, 'report.txt'), @search.handle_key("\r")[:path]
    @search.handle_key("\e")
    refute @search.active?
    refute @search.scanning?
  end

  def test_ctrl_j_and_ctrl_k_select_results_without_changing_query
    scan([{ name: 'A', path: @a }, { name: 'B', path: @b }])
    @search.handle_key('re')
    settle
    assert_nil @search.handle_key("\x0a")
    assert_equal 1, @search.selected_index
    @search.handle_key("\x0a")
    assert_equal 1, @search.selected_index
    @search.handle_key("\x0b")
    assert_equal 0, @search.selected_index
    @search.handle_key("\x0b")
    assert_equal 0, @search.selected_index
    assert_equal 're', @search.query
    assert @search.active?
    assert_equal @search.results.first, @search.handle_key("\r")
  end

  def test_typing_does_not_trigger_navigation_and_arrow_selection_keeps_query
    scan([{ name: 'A', path: @a }, { name: 'B', path: @b }])
    @search.handle_key('r')
    @search.handle_key('e')
    settle
    assert_equal 2, @search.results.length
    @search.handle_key(:down)
    assert_equal 1, @search.selected_index
    assert_equal 're', @search.query
    @search.handle_key("\u007f")
    assert_equal 'r', @search.query
    assert_equal 0, @search.selected_index
  end

  def test_cancel_during_scan_and_reopen
    400.times { |index| File.write(File.join(@b, "item#{index}"), '') }
    @search.open([{ name: 'B', path: @b }])
    Timeout.timeout(3) { @search.close }
    refute @search.active?
    scan([{ name: 'A', path: @a }])
    assert_equal 2, @search.results.length
  end

  def test_slash_opens_the_search_screen_without_moving_directory
    handler = Rufio::KeybindHandler.new
    listing = Rufio::DirectoryListing.new(@root)
    handler.set_directory_listing(listing)
    ui = Rufio::TerminalUI.new
    handler.set_terminal_ui(ui)
    ui.instance_variable_set(:@keybind_handler, handler)
    ui.instance_variable_set(:@directory_listing, listing)

    handler.handle_key('/')
    assert ui.search_active?
    assert_equal @root, listing.current_path

    search = ui.instance_variable_get(:@search_screen)
    Timeout.timeout(3) do
      while search.scanning?
        search.poll
        Thread.pass
      end
    end
    search.handle_key('report.txt')
    Timeout.timeout(3) do
      while search.scanning?
        search.poll
        Thread.pass
      end
    end

    ui.handle_search_input("\r")
    refute ui.search_active?
    assert_equal @b, listing.current_path, '選んだファイルのディレクトリへ移動すること'
    assert_equal 'report.txt', handler.current_entry[:name]
  ensure
    ui&.instance_variable_get(:@search_screen)&.close
  end
end
