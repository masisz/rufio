# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'timeout'
require_relative '../lib/rufio/fuzzy_search_session'

class TestFuzzySearchSession < Minitest::Test
  class Batches
    attr_reader :calls

    def initialize(*batches)
      @batches = batches
      @calls = 0
    end

    def each_batch(cancelled:, on_error:)
      @calls += 1
      @batches.each do |batch|
        break if cancelled.call

        yield batch
      end
    end
  end

  class PausedSource < Batches
    attr_reader :ready, :release

    def initialize(first, second)
      super(first, second)
      @ready = Queue.new
      @release = Queue.new
    end

    def each_batch(cancelled:, on_error:)
      @calls += 1
      yield @batches[0]
      @ready << true
      @release.pop
      yield @batches[1] unless cancelled.call
    end
  end

  # A slow query is gated explicitly; tests don't rely on sleep or a large tree.
  class GatedIndex
    attr_reader :entered, :release, :calls, :threads, :closed

    def initialize(block_query)
      @index = Rufio::FuzzySearch.new(native: false)
      @block_query = block_query
      @entered = Queue.new
      @release = Queue.new
      @calls = []
      @threads = []
      @closed = false
    end

    def add(batch)
      @threads << Thread.current
      @index.add(batch)
    end

    def query(query, limit:)
      @threads << Thread.current
      @calls << query
      if query == @block_query
        @entered << true
        @release.pop
      end
      @index.query(query, limit: limit)
    end

    def total_matches
      @index.total_matches
    end

    def close
      @threads << Thread.current
      @closed = true
      @index.close
    end
  end

  def setup
    @sessions = []
    @gates = []
  end

  def teardown
    @sessions.each(&:close)
    @gates.each { |gate| gate.release << true }
    @sessions.each { |session| assert session.wait(timeout: 3), 'Session leaked a worker' }
  end

  def session(source, **options)
    result = Rufio::FuzzySearchSession.new(source: source, native: false, **options)
    @sessions << result
    result.start
  end

  def await
    Timeout.timeout(3) do
      loop do
        return if yield

        Thread.pass
      end
    end
  end

  def settle(search)
    await { search.poll; !search.scanning? && !search.searching? }
  end

  def test_streaming_results_search_again_without_rescanning
    source = PausedSource.new(['search_controller.rb', 'unrelated.txt'], ['search_cache.rb'])
    @gates << source
    search = session(source, limit: 1)
    Timeout.timeout(3) { source.ready.pop }
    search.update_query('sctrl')
    await { search.poll; search.results.length == 1 }
    assert search.scanning?
    assert_equal 'search_controller.rb', search.results.first[:entry][:text]
    assert_equal 2, search.candidate_count
    assert_equal 1, search.total_matches
    source.release << true
    settle(search)
    search.update_query('sc')
    settle(search)
    assert_equal 3, search.candidate_count
    assert_equal 2, search.total_matches
    assert_equal 1, search.results.length
    assert_equal 1, source.calls
    assert search.results.frozen?
    assert search.results.first[:entry].frozen?
    assert search.results.first[:positions].frozen?
  end

  def test_slow_query_does_not_block_input_and_intermediate_queries_are_coalesced
    index = GatedIndex.new('a')
    @gates << index
    search = session(Batches.new(['alpha', 'abc', 'beta']), index_factory: -> { index })
    settle(search)
    search.update_query('a')
    Timeout.timeout(3) { index.entered.pop }
    Timeout.timeout(0.5) do
      search.update_query('ab')
      search.update_query('abc')
    end
    assert_empty search.results
    assert_equal 'abc', search.query
    index.release << true
    settle(search)
    assert_equal ['abc'], search.results.map { |r| r[:entry][:text] }
    assert_equal ['a', 'abc'], index.calls.reject(&:empty?)
    assert_equal 1, index.threads.uniq.length
    refute_equal Thread.current, index.threads.first
  end

  def test_already_published_result_is_discarded_when_input_changes_before_poll
    index = GatedIndex.new('beta')
    @gates << index
    search = session(Batches.new(['alpha', 'beta']), index_factory: -> { index })
    # Producer may complete before or after the first empty search.
    settle(search)
    search.update_query('alpha')
    await { index.calls.include?('alpha') }
    search.update_query('beta')
    Timeout.timeout(3) { index.entered.pop }
    search.poll
    assert_empty search.results
    assert search.searching?
    index.release << true
    settle(search)
    assert_equal ['beta'], search.results.map { |r| r[:entry][:text] }
  end

  def test_close_is_nonblocking_and_index_is_destroyed_only_after_query_returns
    index = GatedIndex.new('slow')
    @gates << index
    search = session(Batches.new(['slow.rb']), index_factory: -> { index })
    settle(search)
    search.update_query('slow')
    Timeout.timeout(3) { index.entered.pop }
    Timeout.timeout(0.5) { search.close; search.close }
    refute search.active?
    refute search.scanning?
    refute search.searching?
    refute search.poll
    refute search.wait(timeout: 0)
    refute index.closed
    index.release << true
    assert search.wait(timeout: 3)
    assert index.closed
    assert_equal 1, index.threads.uniq.length
    assert_empty search.results
    assert_raises(IOError) { search.update_query('again') }
    assert_raises(IOError) { search.start }
  end

  def test_close_wakes_a_producer_waiting_for_queue_space
    index = GatedIndex.new('')
    @gates << index
    produced = Queue.new
    source = Object.new
    source.define_singleton_method(:each_batch) do |cancelled:, on_error:, &block|
      100.times do |i|
        break if cancelled.call

        block.call(["item_#{i}"])
        produced << i
      end
    end
    search = session(source, index_factory: -> { index })
    Timeout.timeout(3) { index.entered.pop }
    # Index worker is blocked: bounded producer queue must not consume all 100.
    await { produced.size >= 4 }
    assert_operator produced.size, :<, 100
    search.close
    index.release << true
    assert search.wait(timeout: 3)
    assert_operator produced.size, :<, 100
  end

  def test_source_errors_keep_partial_results_and_do_not_hang
    source = Object.new
    source.define_singleton_method(:each_batch) do |cancelled:, on_error:, &block|
      block.call([{ text: 'good.rb', path: '/original/good.rb', line_number: 4 }])
      on_error.call('unreadable directory')
      raise IOError, 'scan stopped'
    end
    search = session(source)
    settle(search)
    assert_equal '/original/good.rb', search.results.first[:entry][:path]
    assert_equal 4, search.results.first[:entry][:line_number]
    assert_includes search.errors.join(' '), 'unreadable directory'
    assert_includes search.errors.join(' '), 'scan stopped'
  end

  def test_index_failure_stops_producer_and_reports_error
    source = Batches.new(['ok'])
    search = session(source, index_factory: -> { raise IOError, 'index unavailable' })
    settle(search)
    assert_includes search.errors.join(' '), 'index unavailable'
    assert_empty search.results
    assert search.wait(timeout: 3)
  end

  def test_query_validation_is_synchronous_and_does_not_poison_the_worker
    search = session(Batches.new(['hello']))
    settle(search)
    generation = search.generation
    assert_raises(ArgumentError) { search.update_query("bad\0") }
    assert_raises(ArgumentError) { search.update_query("\xff".b) }
    assert_raises(ArgumentError) { search.update_query('a' * 1025) }
    assert_equal generation, search.generation
    search.update_query('hlo')
    settle(search)
    assert_equal ['hello'], search.results.map { |r| r[:entry][:text] }
  end

  def test_start_and_close_without_work_and_bad_options
    search = Rufio::FuzzySearchSession.new(source: Batches.new)
    @sessions << search
    search.close
    assert search.wait(timeout: 0)
    assert_raises(IOError) { search.start }
    assert_raises(ArgumentError) { Rufio::FuzzySearchSession.new }
    assert_raises(ArgumentError) { Rufio::FuzzySearchSession.new(root: '.', source: Batches.new) }
    assert_raises(ArgumentError) { Rufio::FuzzySearchSession.new(root: '.', limit: -1) }
  end

  def test_native_index_runs_in_session_worker_when_requested
    skip 'Set RUFIO_TEST_FUZZY_LIBRARY for native tests' unless ENV['RUFIO_TEST_FUZZY_LIBRARY']

    factory = lambda do
      index = Rufio::FuzzySearch.new(library: ENV.fetch('RUFIO_TEST_FUZZY_LIBRARY'))
      raise 'Native API missing' unless index.native?

      index
    end
    search = session(Batches.new(['日本語/検索.rb', 'other.rb']), index_factory: factory)
    search.update_query('日検')
    settle(search)
    assert_empty search.errors
    assert_equal [0, 10], search.results.first[:positions]
  end
end

class TestFuzzyFileSource < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio-fuzzy-source')
    FileUtils.mkdir_p(File.join(@root, '.hidden', 'nested'))
    File.write(File.join(@root, '.hidden', 'nested', '日本語.rb'), '')
    File.write(File.join(@root, 'visible.txt'), '')
    @expected = ['.hidden/nested/日本語.rb', 'visible.txt']
    begin
      File.symlink(File.join(@root, 'visible.txt'), File.join(@root, 'file-link'))
      File.symlink(@root, File.join(@root, '.hidden', 'loop'))
      File.symlink(File.join(@root, 'missing'), File.join(@root, 'broken-link'))
      @expected << 'file-link'
    rescue NotImplementedError, SystemCallError
      # Windows may require permission to create symlinks.
    end
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def collect(native)
    rows = []
    errors = []
    source = Rufio::FuzzyFileSource.new(@root, native: native)
    Timeout.timeout(3) do
      source.each_batch(cancelled: -> { false }, on_error: ->(e) { errors << e }) { |batch| rows.concat(batch) }
    end
    assert_empty errors
    assert_equal @expected.sort, rows.map { |r| r[:text] }.sort
    assert rows.all? { |r| File.file?(r[:path]) }
    rows
  end

  def test_ruby_walk_includes_hidden_files_and_file_links_without_following_directory_links
    collect(false)
  end

  def test_native_walk_matches_ruby
    skip 'Native file listing unavailable' unless Rufio::NativeContentSearch.files_available?

    assert_equal collect(false).map { |r| r[:path] }.sort, collect(true).map { |r| r[:path] }.sort
  end

  def test_cancellation_before_start_does_not_touch_filesystem
    source = Rufio::FuzzyFileSource.new(File.join(@root, 'does-not-exist'), native: false)
    source.each_batch(cancelled: -> { true }, on_error: ->(_e) { flunk }) { |_batch| flunk }
  end

  def test_missing_directory_is_reported_through_session
    search = Rufio::FuzzySearchSession.new(root: File.join(@root, 'does-not-exist'), native: false).start
    Timeout.timeout(3) do
      loop do
        search.poll
        break unless search.scanning? || search.searching?

        Thread.pass
      end
    end
    assert_empty search.results
    assert_includes search.errors.join(' '), 'does-not-exist'
  ensure
    search&.close
    assert search.wait(timeout: 3) if search
  end

  def test_invalid_filename_is_scrubbed_only_for_display
    skip 'POSIX raw filenames only' if Gem.win_platform?

    path = File.join(@root, "raw_\xff.rb".b)
    File.write(path, '')
    rows = []
    Rufio::FuzzyFileSource.new(@root, native: false).each_batch(
      cancelled: -> { false }, on_error: ->(e) { flunk e }
    ) { |batch| rows.concat(batch) }
    row = rows.find { |r| r[:path].b == path.b }
    refute_nil row
    assert row[:text].valid_encoding?
    assert_includes row[:text], "\uFFFD"
    assert_equal path.b, row[:path].b
  end

  def test_native_batch_reader_can_cancel_before_first_native_poll
    reader = Rufio::NativeContentSearch.allocate
    assert_empty reader.each_batch(cancelled: -> { true }).to_a
  end
end
