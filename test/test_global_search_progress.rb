# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'timeout'

class TestGlobalSearchProgress < Minitest::Test
  def test_searching_indicator_animates_even_without_matches_and_stops_on_completion
    search = Rufio::GlobalSearch.new
    gate = Queue.new
    now = 10.0
    screen = Rufio::Screen.new(80, 24)
    search.stub(:scan_roots, ->(*) { gate.pop }) do
      Process.stub(:clock_gettime, ->(*) { now }) do
        search.open([{ name: 'Slow', path: '/slow' }])
        search.draw(screen)
        first = Rufio::ColorHelper.strip_ansi(screen.row(2))
        assert_includes first, 'Searching...'
        refute search.poll
        now += 0.2
        assert search.poll, '結果が届かなくてもスピナーを再描画すること'
        search.draw(screen)
        refute_equal first, Rufio::ColorHelper.strip_ansi(screen.row(2))
        gate << true
        Timeout.timeout(3) do
          while search.scanning?
            search.poll
            Thread.pass
          end
        end
        search.draw(screen)
        assert_includes Rufio::ColorHelper.strip_ansi(screen.row(2)), 'Search complete'
        now += 1
        refute search.poll, '完了後はアニメーションで再描画しないこと'
      end
    end
  ensure
    search&.close
  end

  def test_empty_content_query_is_ready_instead_of_searching
    search = Rufio::GlobalSearch.new
    search.open([])
    search.handle_key("\t")
    screen = Rufio::Screen.new(80, 24)
    search.draw(screen)
    refute search.scanning?
    refute_includes Rufio::ColorHelper.strip_ansi(screen.row(2)), 'Searching...'
  ensure
    search&.close
  end
end
