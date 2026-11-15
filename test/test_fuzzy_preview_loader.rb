# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

# 内蔵検索画面のプレビューを UI スレッドの外で読み込む。最新の要求だけを処理する。
class TestFuzzyPreviewLoader < Minitest::Test
  # 最初の呼び出しだけ release されるまで止まるプレビュー
  class BlockingPreview
    attr_reader :calls

    def initialize
      @calls = Queue.new
      @gate = Queue.new
      @first = true
    end

    def release
      @gate << true
    end

    def preview_file(path, max_lines:)
      @calls << [path, max_lines]
      if @first
        @first = false
        @gate.pop
      end
      { type: 'text', lines: ["preview of #{path}"] }
    end
  end

  def setup
    @dir = Dir.mktmpdir('rufio_preview_loader')
  end

  def teardown
    @loader&.close
    FileUtils.rm_rf(@dir)
  end

  def wait_until(timeout = 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      flunk 'condition not met' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
    end
  end

  def test_loads_text_file_preview
    path = File.join(@dir, 'a.txt')
    File.write(path, "first\nsecond\n")
    @loader = Rufio::FuzzyPreviewLoader.new
    @loader.request(path)
    assert @loader.pending?
    wait_until { @loader.poll }
    refute @loader.pending?
    assert_equal %w[first second], @loader.result(path)[:lines]
  end

  def test_poll_is_false_without_new_result
    @loader = Rufio::FuzzyPreviewLoader.new
    refute @loader.poll
    assert_nil @loader.result('/nowhere')
    refute @loader.pending?
  end

  def test_missing_file_returns_error_preview
    @loader = Rufio::FuzzyPreviewLoader.new
    path = File.join(@dir, 'gone.txt')
    @loader.request(path)
    wait_until { @loader.poll }
    assert_equal 'error', @loader.result(path)[:type]
  end

  def test_only_latest_request_is_processed
    preview = BlockingPreview.new
    @loader = Rufio::FuzzyPreviewLoader.new(previewer: preview)
    @loader.request('/a')
    wait_until { preview.calls.size == 1 }
    @loader.request('/b')
    @loader.request('/c')
    preview.release
    wait_until { @loader.poll }
    assert_equal ['preview of /c'], @loader.result('/c')[:lines]
    assert_nil @loader.result('/b')
    paths = []
    paths << preview.calls.pop.first until preview.calls.empty?
    assert_equal %w[/a /c], paths
  end

  def test_poll_ignores_result_for_previous_request
    preview = BlockingPreview.new
    @loader = Rufio::FuzzyPreviewLoader.new(previewer: preview)
    @loader.request('/a')
    wait_until { preview.calls.size == 1 }
    @loader.request('/b')
    preview.release
    wait_until { @loader.result('/b') }
    @loader.poll
    refute @loader.poll
  end

  def test_line_number_requests_enough_lines
    preview = BlockingPreview.new
    preview.release
    @loader = Rufio::FuzzyPreviewLoader.new(previewer: preview)
    @loader.request('/a', 300)
    wait_until { @loader.poll }
    _, max_lines = preview.calls.pop
    assert_operator max_lines, :>=, 300
    assert_operator max_lines, :<=, Rufio::FuzzyPreviewLoader::MAX_LINES
    @loader.request('/b', 100_000)
    wait_until { @loader.poll }
    _, max_lines = preview.calls.pop
    assert_equal Rufio::FuzzyPreviewLoader::MAX_LINES, max_lines
  end

  def test_recent_results_are_reused_without_reloading
    path = File.join(@dir, 'a.txt')
    other = File.join(@dir, 'b.txt')
    File.write(path, 'a')
    File.write(other, 'b')
    @loader = Rufio::FuzzyPreviewLoader.new
    @loader.request(path)
    wait_until { @loader.poll }
    @loader.request(other)
    wait_until { @loader.poll }
    @loader.request(path)
    refute @loader.pending?
    refute_nil @loader.result(path)
  end

  def test_close_stops_worker_without_waiting_for_preview
    preview = BlockingPreview.new
    @loader = Rufio::FuzzyPreviewLoader.new(previewer: preview)
    @loader.request('/a')
    wait_until { preview.calls.size == 1 }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @loader.close
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.5
    preview.release
    assert @loader.wait(timeout: 5)
    assert_nil @loader.result('/a')
    @loader.request('/b')
    refute @loader.pending?
  end
end
