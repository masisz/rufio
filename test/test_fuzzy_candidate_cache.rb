# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

# s / / の再表示用に、ディレクトリごとの候補一覧を容量・有効期限つきで保持する。
class TestFuzzyCandidateCache < Minitest::Test
  class ArraySource
    attr_reader :runs

    def initialize(batches, errors: [])
      @batches = batches
      @errors = errors
      @runs = 0
    end

    def each_batch(cancelled:, on_error:)
      @runs += 1
      @errors.each { |message| on_error.call(message) }
      @batches.each do |batch|
        break if cancelled.call

        yield batch
      end
    end
  end

  def setup
    @now = 100.0
    @cache = Rufio::FuzzyCandidateCache.new(max_entries: 10, max_roots: 2, ttl: 60, clock: -> { @now })
  end

  def rows(*names)
    names.map { |name| { text: name, path: "/root/#{name}" } }
  end

  def drain(source, cancelled: -> { false })
    batches = []
    errors = []
    source.each_batch(cancelled: cancelled, on_error: ->(message) { errors << message }) { |batch| batches << batch }
    [batches, errors]
  end

  def test_store_and_fetch_frozen_rows
    assert @cache.store('/root', rows('a', 'b'), errors: ['denied'])
    entry = @cache.fetch('/root')
    assert_equal %w[a b], entry.rows.map { |row| row[:text] }
    assert_equal ['denied'], entry.errors
    assert_equal 100.0, entry.stored_at
    assert entry.rows.frozen?
    assert entry.rows.first.frozen?
    assert entry.rows.first[:text].frozen?
  end

  def test_root_is_normalized
    @cache.store('/root/../root/', rows('a'))
    refute_nil @cache.fetch('/root')
  end

  def test_entries_expire_after_ttl
    @cache.store('/root', rows('a'))
    @now += 59
    refute_nil @cache.fetch('/root')
    @now += 2
    assert_nil @cache.fetch('/root')
    assert_equal 0, @cache.size
  end

  def test_rejects_lists_over_capacity
    refute @cache.store('/big', rows(*('a'..'k').to_a))
    assert_nil @cache.fetch('/big')
  end

  def test_evicts_least_recently_used_roots
    @cache.store('/one', rows('a'))
    @cache.store('/two', rows('b'))
    @cache.fetch('/one')
    @cache.store('/three', rows('c'))
    refute_nil @cache.fetch('/one')
    assert_nil @cache.fetch('/two')
    refute_nil @cache.fetch('/three')
  end

  def test_evicts_until_total_entries_fit
    @cache.store('/one', rows('a', 'b', 'c', 'd', 'e', 'f'))
    @cache.store('/two', rows('g', 'h', 'i', 'j', 'k'))
    assert_nil @cache.fetch('/one')
    refute_nil @cache.fetch('/two')
    assert_operator @cache.entry_count, :<=, 10
  end

  def test_delete_and_clear
    @cache.store('/one', rows('a'))
    @cache.store('/two', rows('b'))
    @cache.delete('/one')
    assert_nil @cache.fetch('/one')
    @cache.clear
    assert_equal 0, @cache.size
  end

  def test_source_for_miss_records_complete_scan
    scan = ArraySource.new([rows('a'), rows('b')], errors: ['denied'])
    source, cached_at = @cache.source_for('/root') { scan }
    assert_nil cached_at
    batches, errors = drain(source)
    assert_equal [%w[a], %w[b]], batches.map { |batch| batch.map { |row| row[:text] } }
    assert_equal ['denied'], errors
    entry = @cache.fetch('/root')
    assert_equal %w[a b], entry.rows.map { |row| row[:text] }
    assert_equal ['denied'], entry.errors
  end

  def test_source_for_hit_replays_rows_without_scanning
    @cache.store('/root', rows(*('a'..'j').to_a), errors: ['denied'])
    scanned = false
    source, cached_at = @cache.source_for('/root') { scanned = true }
    assert_equal 100.0, cached_at
    batches, errors = drain(source)
    refute scanned
    assert_equal ('a'..'j').to_a, batches.flatten.map { |row| row[:text] }
    assert_equal ['denied'], errors
  end

  def test_cancelled_scan_is_not_stored
    scan = ArraySource.new([rows('a'), rows('b')])
    source, = @cache.source_for('/root') { scan }
    cancelled = false
    source.each_batch(cancelled: -> { cancelled }, on_error: ->(_) {}) { |_| cancelled = true }
    assert_nil @cache.fetch('/root')
  end

  def test_scan_over_capacity_is_yielded_but_not_stored
    scan = ArraySource.new([rows(*('a'..'f').to_a), rows(*('g'..'l').to_a)])
    source, = @cache.source_for('/root') { scan }
    batches, = drain(source)
    assert_equal 12, batches.flatten.length
    assert_nil @cache.fetch('/root')
  end

  def test_source_for_builds_file_source_by_default
    Dir.mktmpdir('rufio_fuzzy_cache') do |dir|
      File.write(File.join(dir, 'a.txt'), 'x')
      source, = @cache.source_for(dir)
      batches, = drain(source)
      assert_equal ['a.txt'], batches.flatten.map { |row| row[:text] }
      refute_nil @cache.fetch(dir)
    end
  end
end
