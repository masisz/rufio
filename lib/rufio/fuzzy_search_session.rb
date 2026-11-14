# frozen_string_literal: true

require 'thread'
require_relative 'fuzzy_search'
require_relative 'fuzzy_file_source'

module Rufio
  # One-shot asynchronous session. The UI calls start/update_query/poll/close;
  # the index worker alone creates, uses and destroys the fuzzy index. Source
  # producers must check the supplied cancellation callback between batches.
  class FuzzySearchSession
    BATCH_SIZE = 256
    MAX_PENDING_BATCHES = 4
    MAX_ERRORS = 100
    REFRESH_INTERVAL = 0.05
    EMPTY = [].freeze
    State = Struct.new(:generation, :query, :results, :total_matches, :candidate_count,
                       :scanning, :searching, :errors, keyword_init: true)

    attr_reader :snapshot

    def initialize(root: nil, source: nil, native: true, library: nil, limit: 100,
                   index_factory: nil, refresh_interval: REFRESH_INTERVAL)
      raise ArgumentError, 'Specify either root or source' unless root.nil? != source.nil?
      unless limit.is_a?(Integer) && limit.between?(0, FuzzySearch::MAX_RESULTS)
        raise ArgumentError, 'Invalid result limit'
      end
      unless refresh_interval.is_a?(Numeric) && refresh_interval.real? &&
             refresh_interval.finite? && refresh_interval >= 0
        raise ArgumentError, 'Invalid refresh interval'
      end

      @source = source || FuzzyFileSource.new(root, native: native)
      raise ArgumentError, 'Source must implement each_batch' unless @source.respond_to?(:each_batch)

      @index_factory = index_factory || -> { FuzzySearch.new(native: native, library: library) }
      @limit = limit
      @refresh_interval = refresh_interval.to_f
      @mutex = Mutex.new
      @wake = ConditionVariable.new
      @threads = []
      @batches = []
      @revision = 0
      @started = false
      @closed = false
      @failed = false
      @source_done = false
      @error_messages = []
      @pending_snapshot = nil
      @snapshot = State.new(generation: 0, query: ''.freeze, results: EMPTY, total_matches: 0,
                            candidate_count: 0, scanning: false, searching: false, errors: EMPTY).freeze
    end

    def start
      starting = false
      @mutex.synchronize do
        raise IOError, 'Session has already started or closed' if @started || @closed

        @started = true
        starting = true
        change_state(scanning: true, searching: true)
        @threads << Thread.new { run_index }
        @threads << Thread.new { run_source }
      end
      self
    rescue StandardError
      close if starting
      raise
    end

    def active?
      @mutex.synchronize { @started && !@closed }
    end

    def query
      @snapshot.query
    end

    def generation
      @snapshot.generation
    end

    def results
      @snapshot.results
    end

    def total_matches
      @snapshot.total_matches
    end

    def candidate_count
      @snapshot.candidate_count
    end

    def scanning?
      @snapshot.scanning
    end

    def searching?
      @snapshot.searching
    end

    def errors
      @snapshot.errors
    end

    def update_query(text)
      @mutex.synchronize do
        raise IOError, 'Session is not accepting input' unless @started && !cancelled_locked?
        unless text.is_a?(String) && text.bytesize <= FuzzySearch::MAX_QUERY_BYTES
          raise ArgumentError, 'Invalid search query'
        end

        text = text.dup.force_encoding(Encoding::UTF_8)
        raise ArgumentError, 'Invalid UTF-8 or NUL in query' unless text.valid_encoding? && !text.include?("\0")
        return generation if text == query

        # A result for the previous query must not remain selectable, even if
        # the index is still running it or it already arrived before poll.
        @pending_snapshot = nil
        change_state(generation: generation + 1, query: text.freeze, results: EMPTY,
                     total_matches: 0, searching: true)
        @revision += 1
        @wake.broadcast
        generation
      end
    end

    # At most one immutable snapshot is pending; the UI never drains a queue of
    # obsolete results, and the generation check also runs at publication time.
    def poll
      @mutex.synchronize do
        pending = @pending_snapshot
        @pending_snapshot = nil
        return false if @closed || !pending || pending.generation != generation

        @snapshot = pending
        true
      end
    end

    # Nonblocking. No Thread#kill, joins, or native destroy from the caller.
    def close
      @mutex.synchronize do
        return if @closed

        @closed = true
        @batches.clear
        @pending_snapshot = nil
        change_state(results: EMPTY, total_matches: 0, candidate_count: 0, scanning: false, searching: false)
        @wake.broadcast
      end
      nil
    end

    # Explicit cleanup barrier, outside the input loop. A running native query
    # completes before its owner frees the handle. False means cleanup is pending.
    def wait(timeout: nil)
      if timeout && (!timeout.is_a?(Numeric) || !timeout.real? || !timeout.finite? || timeout < 0)
        raise ArgumentError, 'Invalid wait timeout'
      end
      deadline = timeout && monotonic + timeout
      threads = @mutex.synchronize { @threads.dup }
      threads.each do |thread|
        remaining = deadline && [deadline - monotonic, 0].max
        return false unless thread.join(remaining)
      end
      true
    end

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def change_state(**changes)
      @snapshot = State.new(**@snapshot.to_h.merge(changes)).freeze
    end

    def cancelled_locked?
      @closed || @failed
    end

    def cancelled?
      @mutex.synchronize { cancelled_locked? }
    end

    def immutable_entry(value)
      row = value.is_a?(String) ? { text: value } : value
      raise ArgumentError, 'Candidate must contain text' unless row.is_a?(Hash) && row[:text].is_a?(String)

      copied = row.each_with_object({}) do |(key, item), copy|
        unless item.is_a?(String) || item.is_a?(Numeric) || item.is_a?(Symbol) ||
               item.nil? || item == true || item == false
          raise ArgumentError, 'Candidate metadata must contain scalar values'
        end
        copy[key] = item.is_a?(String) ? item.dup.freeze : item
      end
      text = row[:text].dup.force_encoding(Encoding::UTF_8)
      unless text.valid_encoding? && !text.include?("\0") && text.bytesize <= FuzzySearch::MAX_CANDIDATE_BYTES
        raise ArgumentError, 'Invalid candidate text'
      end
      copied[:text] = text.freeze
      copied.freeze
    end

    def enqueue(batch)
      rows = batch.map { |row| immutable_entry(row) }.freeze
      return true if rows.empty?

      @mutex.synchronize do
        while @batches.length >= MAX_PENDING_BATCHES && !cancelled_locked?
          @wake.wait(@mutex)
        end
        return false if cancelled_locked?

        @batches << rows
        @revision += 1
        @wake.broadcast
        true
      end
    end

    def record_error(message)
      @mutex.synchronize do
        return if cancelled_locked? || @error_messages.length >= MAX_ERRORS

        @error_messages << message.to_s.dup.force_encoding(Encoding::UTF_8).scrub.freeze
        @revision += 1
        @wake.broadcast
      end
    end

    def run_source
      @source.each_batch(cancelled: method(:cancelled?), on_error: method(:record_error)) do |batch|
        break if cancelled?

        batch.each_slice(BATCH_SIZE) do |part|
          break unless enqueue(part)
        end
      end
    rescue StandardError, NoMemoryError => e
      record_error("#{e.class}: #{e.message}")
    ensure
      @mutex.synchronize do
        @source = nil
        @source_done = true
        @revision += 1
        @wake.broadcast
      end
    end

    def take_work(previous_revision, refresh_at)
      @mutex.synchronize do
        while @revision == previous_revision && !cancelled_locked?
          remaining = refresh_at && refresh_at - monotonic
          break if remaining && remaining <= 0

          @wake.wait(@mutex, remaining)
        end
        return if cancelled_locked?

        batches = @batches
        @batches = []
        @wake.broadcast
        [@revision, batches]
      end
    end

    def publish(current_generation, text, matches, total, count, searching)
      @mutex.synchronize do
        return if cancelled_locked? || generation != current_generation

        @pending_snapshot = State.new(generation: current_generation, query: text, results: matches,
                                      total_matches: total, candidate_count: count,
                                      scanning: !@source_done || !@batches.empty?, searching: searching,
                                      errors: @error_messages.dup.freeze).freeze
      end
    end

    def run_index
      entries = []
      index = nil
      return if cancelled?

      index = @index_factory.call
      previous_revision = -1
      signature = nil
      matches = EMPTY
      total = 0
      refresh_at = nil
      next_query_at = 0
      while (work = take_work(previous_revision, refresh_at))
        previous_revision, batches = work
        batches.each do |batch|
          break if cancelled?

          index.add(batch.map { |row| row[:text] })
          entries.concat(batch)
        end
        break if cancelled?

        current_generation, text, complete = @mutex.synchronize do
          [generation, query, @source_done && @batches.empty?]
        end
        desired = [current_generation, entries.length]
        dirty = signature != desired
        # Input changes and a complete scan bypass throttling. Candidate-only
        # changes are batched so loading N files doesn't trigger N/B full scans.
        force = signature.nil? || signature[0] != current_generation || complete
        if dirty && (force || monotonic >= next_query_at)
          raw = index.query(text, limit: @limit)
          break if cancelled?

          total = index.total_matches
          matches = raw.map do |match|
            match.merge(positions: match[:positions].dup.freeze, entry: entries.fetch(match[:id])).freeze
          end.freeze
          signature = desired
          dirty = false
          next_query_at = monotonic + @refresh_interval
        end
        refresh_at = dirty ? next_query_at : nil
        publish(current_generation, text, matches, total, entries.length, dirty)
      end
    rescue StandardError, NoMemoryError => e
      fail_session(e)
    ensure
      entries.clear
      begin
        index&.close
      rescue StandardError, NoMemoryError => e
        fail_session(e)
      end
    end

    def fail_session(error)
      @mutex.synchronize do
        return if @closed

        @failed = true
        @batches.clear
        @error_messages << "#{error.class}: #{error.message}".freeze if @error_messages.length < MAX_ERRORS
        @pending_snapshot = State.new(generation: generation, query: query, results: EMPTY,
                                      total_matches: 0, candidate_count: 0, scanning: false, searching: false,
                                      errors: @error_messages.dup.freeze).freeze
        @wake.broadcast
      end
    end
  end
end
