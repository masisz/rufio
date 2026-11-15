# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

# G mode のファイル名検索は s と同じあいまい検索（FuzzySearchSession）で、
# バックグラウンドで照合する。本文検索はリテラルのまま。
class TestGlobalSearchFuzzy < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio-global-fuzzy')
    @a = File.join(@root, 'alpha')
    @b = File.join(@root, 'beta')
    FileUtils.mkdir_p(File.join(@a, 'src'))
    FileUtils.mkdir_p(@b)
    File.write(File.join(@a, 'src', 'sctrl.rb'), 'one')
    File.write(File.join(@a, 's_c_t_r_l_notes.txt'), 'two')
    File.write(File.join(@b, 'Report.md'), 'needle three')
    File.write(File.join(@b, 'skip.log'), 'log')
    @search = Rufio::GlobalSearch.new
    @screen = Rufio::Screen.new(100, 20)
  end

  def teardown
    @search.close
    FileUtils.rm_rf(@root)
  end

  def bookmarks
    [{ name: 'A', path: @a }, { name: 'B', path: @b }]
  end

  def settle
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      @search.poll
      break unless @search.scanning?
      flunk 'search did not settle' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
    end
  end

  def type(text)
    text.each_char { |char| @search.handle_key(char) }
    settle
  end

  def names
    @search.results.map { |result| File.basename(result[:path]) }
  end

  def row_text(y)
    Rufio::ColorHelper.strip_ansi(@screen.row(y))
  end

  def test_file_names_match_fuzzy_subsequences
    @search.open(bookmarks)
    settle
    type('rpt')
    assert_equal ['Report.md'], names
  end

  def test_results_are_ranked_by_score
    @search.open(bookmarks)
    settle
    type('sctrl')
    assert_equal ['sctrl.rb', 's_c_t_r_l_notes.txt'], names
  end

  def test_results_keep_bookmark_and_relative_path
    @search.open(bookmarks)
    settle
    type('sctrl')
    entry = @search.results.first
    assert_equal 'A', entry[:bookmark]
    assert_equal File.join('src', 'sctrl.rb'), entry[:relative_path]
    assert_equal File.join(@a, 'src', 'sctrl.rb'), @search.handle_key("\r")[:path]
  end

  def test_typing_clears_previous_results_until_new_ones_arrive
    @search.open(bookmarks)
    settle
    refute_empty @search.results
    @search.handle_key('r')
    assert_empty @search.results
    assert @search.scanning?
    settle
    refute_empty @search.results
  end

  def test_query_survives_switching_to_content_and_back
    @search.open(bookmarks)
    settle
    type('rpt')
    @search.handle_key("\t")
    assert_equal :content, @search.search_type
    @search.handle_key("\t")
    settle
    assert_equal :filename, @search.search_type
    assert_equal 'rpt', @search.query
    assert_equal ['Report.md'], names
  end

  def test_content_search_stays_literal
    @search.open(bookmarks)
    settle
    @search.handle_key("\t")
    type('nedl')
    assert_empty @search.results
    @search.handle_key("\x15")
    type('needle')
    assert_equal ['Report.md'], names
  end

  def test_matched_characters_are_highlighted
    @search.open(bookmarks)
    settle
    type('rpt')
    @search.draw(@screen)
    y = (3...@screen.height).find { |row| row_text(row).include?('Report.md') } || flunk('result not drawn')
    text = row_text(y)
    start = text.index('Report.md')
    highlighted = (0...@screen.width).select { |x| @screen.get_cell(x, y).bg }
    assert_equal [start, start + 2, start + 5], highlighted
  end

  def test_status_shows_total_matches_and_skipped_files
    Rufio::ConfigLoader.stub(:global_search_excluded_extensions, ['.log']) do
      @search.open(bookmarks)
      settle
    end
    @search.draw(@screen)
    status = row_text(2)
    assert_includes status, '3 matches'
    assert_includes status, '1 skipped'
    refute_includes names, 'skip.log'
  end

  def test_file_name_candidates_are_frozen
    rows = []
    source = Rufio::GlobalSearch::FileNameSource.new(@search, [['A', @a]], false)
    @search.instance_variable_set(:@excluded_extensions, [])
    source.each_batch(cancelled: -> { false }, on_error: ->(_) {}) { |batch| rows.concat(batch) }
    refute_empty rows
    assert rows.all?(&:frozen?)
    assert rows.all? { |row| row.values.all? { |value| !value.is_a?(String) || value.frozen? } }
  end

  def test_close_releases_the_session
    @search.open(bookmarks)
    session = @search.instance_variable_get(:@session)
    refute_nil session
    @search.close
    refute session.active?
    assert_nil @search.instance_variable_get(:@session)
    refute @search.scanning?
  end

  def test_selection_follows_the_same_file_when_results_update
    @search.open(bookmarks)
    settle
    @search.handle_key(:down)
    selected = @search.results[@search.selected_index][:path]
    @search.poll
    assert_equal selected, @search.results[@search.selected_index][:path]
  end
end
