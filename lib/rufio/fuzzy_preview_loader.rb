# frozen_string_literal: true

require 'thread'
require_relative 'file_preview'

module Rufio
  # 内蔵検索画面のプレビューを UI スレッドの外で読む。読み込み量は FilePreview の上限
  # （64 KiB・1 行 500 文字）と MAX_LINES 行に制限する。処理中に選択が変わっても待たせず、
  # 次はその時点の最新の要求だけを処理する。結果は直近 CACHE_SIZE 件を再利用する。
  class FuzzyPreviewLoader
    DEFAULT_LINES = 200
    MAX_LINES = 2_000
    CACHE_SIZE = 16

    def initialize(previewer: FilePreview.new)
      @previewer = previewer
      @mutex = Mutex.new
      @wake = ConditionVariable.new
      @wanted = nil
      @results = {}
      @arrived = false
      @closed = false
      @thread = nil
    end

    def request(path, line_number = nil)
      key = [path, line_number].freeze
      @mutex.synchronize do
        return if @closed || @wanted == key

        @wanted = key
        @arrived = false
        if @results.key?(key)
          @results[key] = @results.delete(key)
        else
          @thread ||= Thread.new { run }
          @wake.signal
        end
      end
      nil
    end

    # 最新の要求の結果が前回の poll 以降に届いたら true
    def poll
      @mutex.synchronize do
        arrived = @arrived
        @arrived = false
        arrived
      end
    end

    def result(path, line_number = nil)
      @mutex.synchronize { @results[[path, line_number]] }
    end

    def pending?
      @mutex.synchronize { !@closed && !@wanted.nil? && !@results.key?(@wanted) }
    end

    # 停止を伝えるだけで待たない。読み込み中のファイル操作が戻った後にワーカーが終わる
    def close
      @mutex.synchronize do
        @closed = true
        @wanted = nil
        @results.clear
        @wake.signal
      end
      nil
    end

    def wait(timeout: nil)
      thread = @mutex.synchronize { @thread }
      thread.nil? || !thread.join(timeout).nil?
    end

    private

    def run
      loop do
        key = @mutex.synchronize do
          @wake.wait(@mutex) until @closed || (@wanted && !@results.key?(@wanted))
          break nil if @closed

          @wanted
        end
        break unless key

        preview = load(*key)
        @mutex.synchronize do
          break if @closed

          @results.delete(key)
          @results[key] = preview
          @results.shift while @results.length > CACHE_SIZE
          @arrived = true if @wanted == key
        end
      end
    end

    def load(path, line_number)
      lines = line_number ? (line_number.to_i + DEFAULT_LINES).clamp(DEFAULT_LINES, MAX_LINES) : DEFAULT_LINES
      @previewer.preview_file(path, max_lines: lines).freeze
    rescue StandardError => e
      { type: 'error', lines: ["#{e.class}: #{e.message}"] }.freeze
    end
  end
end
