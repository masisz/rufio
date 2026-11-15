# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'stringio'

# 全画面の検索画面（内蔵検索・G mode）で結果が減ったとき、前フレームの行が端末に残らない。
class TestSearchScreenRedraw < Minitest::Test
  class ArraySource
    def each_batch(cancelled:, on_error:)
      yield (1..8).map { |i| { text: "item#{i}.txt", path: "/root/item#{i}.txt" } }
    end
  end

  def setup
    @screen = Rufio::Screen.new(40, 14)
    @renderer = Rufio::Renderer.new(40, 14, output: StringIO.new)
  end

  def frame
    @renderer.instance_variable_get(:@front).map { |line| Rufio::ColorHelper.strip_ansi(line).rstrip }
  end

  def wait_for(finder)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      finder.poll
      break unless finder.busy?
      flunk 'fuzzy finder did not settle' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
    end
  end

  def test_fuzzy_finder_erases_rows_of_removed_results
    finder = Rufio::FuzzyFinder.new
    finder.open(Rufio::FuzzySearchSession.new(source: ArraySource.new, native: false), title: 'Files')
    wait_for(finder)
    finder.draw(@screen)
    @renderer.render(@screen)
    assert_includes frame[6], 'item4.txt'

    '8'.each_char { |char| finder.handle_key(char) }
    wait_for(finder)
    finder.draw(@screen)
    @renderer.render(@screen)
    assert_includes frame[3], 'item8.txt'
    assert_equal '', frame[6]
  ensure
    finder&.close
  end

  def test_global_search_erases_rows_of_removed_results
    search = Rufio::GlobalSearch.new
    search.open([])
    entries = (1..8).map { |i| { path: "/root/item#{i}.txt", relative_path: "item#{i}.txt", bookmark: 'b' } }
    search.instance_variable_set(:@entries, entries)
    search.instance_variable_set(:@results, entries.dup)
    search.instance_variable_set(:@scanning, false)
    search.draw(@screen)
    @renderer.render(@screen)
    assert_includes frame[6], 'item4.txt'

    search.handle_key('8')
    search.draw(@screen)
    @renderer.render(@screen)
    assert_includes frame[3], 'item8.txt'
    assert_equal '', frame[6]
  ensure
    search&.close
  end
end
