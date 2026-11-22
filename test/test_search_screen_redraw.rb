# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'stringio'

# 全画面の検索画面（`/`）で結果が減ったとき、前フレームの行が端末に残らない。
class TestSearchScreenRedraw < Minitest::Test
  def setup
    @screen = Rufio::Screen.new(40, 14)
    @renderer = Rufio::Renderer.new(40, 14, output: StringIO.new)
  end

  def frame
    @renderer.instance_variable_get(:@front).map { |line| Rufio::ColorHelper.strip_ansi(line).rstrip }
  end

  def test_the_search_screen_erases_rows_of_removed_results
    Dir.mktmpdir('rufio_redraw') do |dir|
      (1..8).each { |i| File.write(File.join(dir, "item#{i}.txt"), '') }
      search = Rufio::SearchScreen.new
      begin
        search.open([{ name: 'b', path: dir }])
        settle_global(search)
        search.draw(@screen)
        @renderer.render(@screen)
        assert_equal 8, frame.count { |line| line.include?('item') }

        search.handle_key('8')
        settle_global(search)
        search.draw(@screen)
        @renderer.render(@screen)
        assert_includes frame[3], 'item8.txt'
        assert_equal '', frame[6]
      ensure
        search.close
      end
    end
  end

  def settle_global(search)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      search.poll
      break unless search.scanning?
      flunk 'global search did not settle' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
    end
  end
end
