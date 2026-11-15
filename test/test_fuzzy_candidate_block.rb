# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'tmpdir'

# 候補を行（Hash）にせず連結したバイト列で運び、結果に出す候補だけ行にする。
class TestFuzzyCandidateBlock < Minitest::Test
  def build(*names, rows: nil)
    builder = Rufio::FuzzyCandidateBlock::Builder.new
    names.each { |name| builder.add(name) }
    builder.build(rows)
  end

  def test_builder_packs_texts_and_builds_rows_on_demand
    calls = []
    block = build('a.rb', '日本/検索.rb', '', rows: ->(index, text) { calls << index; { text: text, number: index } })

    assert_equal 3, block.size
    assert_equal "a.rb\0日本/検索.rb\0\0".b, block.packed
    assert block.packed.frozen?
    assert_empty calls
    assert_equal({ text: '日本/検索.rb', number: 1 }, block.entry(1))
    assert_equal [1], calls
    assert_equal Encoding::UTF_8, block.text(1).encoding
    assert_equal ['a.rb', '日本/検索.rb', ''], block.texts
  end

  def test_rows_and_their_strings_are_frozen
    block = build('a.rb', rows: ->(_index, text) { { text: text, path: +"/root/#{text}" } })
    row = block.entry(0)

    assert row.frozen?
    assert row[:text].frozen?
    assert row[:path].frozen?
    assert_equal [{ text: 'a.rb', path: '/root/a.rb' }], block.to_a
    assert_equal [{ text: 'a.rb', path: '/root/a.rb' }], [].concat(block)
  end

  def test_default_rows_hold_only_the_text
    assert_equal [{ text: 'a' }, { text: 'b' }], build('a', 'b').to_a
  end

  def test_out_of_range_index_is_rejected
    block = build('a')
    assert_raises(IndexError) { block.entry(1) }
    assert_raises(IndexError) { block.entry(-1) }
  end

  def test_packed_text_is_validated
    assert_equal 2, Rufio::FuzzyCandidateBlock.new("a\0b\0", 2).size
    assert_equal 0, Rufio::FuzzyCandidateBlock.new('', 0).size
    assert_raises(ArgumentError) { Rufio::FuzzyCandidateBlock.new("a\0b\0", 3) }
    assert_raises(ArgumentError) { Rufio::FuzzyCandidateBlock.new("a\0b", 1) }
    assert_raises(ArgumentError) { Rufio::FuzzyCandidateBlock.new("a\xFF\0".b, 1) }
    assert_raises(ArgumentError) { Rufio::FuzzyCandidateBlock.new(nil, 0) }
  end

  def test_builder_rejects_text_longer_than_the_index_accepts
    builder = Rufio::FuzzyCandidateBlock::Builder.new
    builder.add('a' * Rufio::FuzzySearch::MAX_CANDIDATE_BYTES)
    assert_raises(ArgumentError) { builder.add('a' * (Rufio::FuzzySearch::MAX_CANDIDATE_BYTES + 1)) }
    assert_equal 1, builder.size
  end

  def test_path_rows_rebuild_paths_and_keep_exceptions
    original = "/root/bad\xFF.txt".b.force_encoding(Encoding::UTF_8).freeze
    rows = Rufio::FuzzyCandidateBlock::PathRows.new('/root/'.b, Encoding::UTF_8, { 1 => original }.freeze)
    block = build('日本.rb', 'bad?.txt', rows: rows)

    assert_equal '/root/日本.rb', block.entry(0)[:path]
    assert_equal Encoding::UTF_8, block.entry(0)[:path].encoding
    assert_same original, block.entry(1)[:path]
  end

  # add(packed.split("\0")) と同じ ID・スコア・位置になる
  def test_add_packed_matches_add
    names = ['lib/search_controller.rb', '日本語/検索.rb', 'README.md', '']
    [false, true].each do |native|
      plain = Rufio::FuzzySearch.new(native: native)
      packed = Rufio::FuzzySearch.new(native: native)
      next if native && !plain.native?

      plain.add(names)
      packed.add_packed(names.first(2).map { |name| "#{name}\0" }.join.b.freeze)
      packed.add_packed('')
      packed.add_packed(names.last(2).map { |name| "#{name}\0" }.join)
      ['', 'sc', '検', 'md', 'zzz'].each do |query|
        assert_equal plain.query(query), packed.query(query), "native=#{native} query=#{query}"
        assert_equal plain.total_matches, packed.total_matches
      end
    ensure
      plain&.close
      packed&.close
    end
  end

  def test_add_packed_rejects_bad_input_without_adding_anything
    [false, true].each do |native|
      index = Rufio::FuzzySearch.new(native: native)
      next if native && !index.native?

      assert_raises(ArgumentError) { index.add_packed("a\0b") }
      assert_raises(ArgumentError) { index.add_packed("ok\0bad\xFF\0".b) }
      assert_raises(ArgumentError) { index.add_packed("#{'a' * (Rufio::FuzzySearch::MAX_CANDIDATE_BYTES + 1)}\0") }
      assert_raises(ArgumentError) { index.add_packed(nil) }
      index.query('')
      assert_equal 0, index.total_matches, "native=#{native}"
    ensure
      index&.close
    end
  end
end

class TestFuzzySessionWithBlocks < Minitest::Test
  class Batches
    def initialize(batches)
      @batches = batches
    end

    def each_batch(cancelled:, on_error:)
      @batches.each do |batch|
        break if cancelled.call

        yield batch
      end
    end
  end

  def settle(search)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      search.poll
      state = search.snapshot
      return state unless state.scanning || state.searching
      flunk 'session did not finish' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.005
    end
  end

  def block(names, built)
    builder = Rufio::FuzzyCandidateBlock::Builder.new
    names.each { |name| builder.add(name) }
    builder.build(->(index, text) { built << text; { text: text, path: "/root/#{text}", local: index } })
  end

  # 行の配列とブロックが混ざっても ID は追加順で、結果に出た候補だけ行になる
  def test_blocks_and_row_batches_share_one_id_space
    [false, true].each do |native|
      built = []
      names = Array.new(600) { |i| "file_#{i}.txt" }
      source = Batches.new([['first.rb'], block(names, built), [{ text: 'middle.rb', path: '/m' }], block(['last.rb'], built)])
      search = Rufio::FuzzySearchSession.new(source: source, native: native, limit: 5).start
      search.update_query('rb')
      state = settle(search)

      assert_empty state.errors
      assert_equal 603, state.candidate_count
      assert_equal 3, state.total_matches
      assert_equal [0, 601, 602], state.results.map { |result| result[:id] }.sort
      last = state.results.find { |result| result[:id] == 602 }[:entry]
      assert_equal({ text: 'last.rb', path: '/root/last.rb', local: 0 }, last)
      assert last.frozen?
      assert_equal ['last.rb'], built.uniq, "native=#{native}"

      search.update_query('file_599')
      state = settle(search)
      assert_equal [{ text: 'file_599.txt', path: '/root/file_599.txt', local: 599 }], state.results.map { |result| result[:entry] }
      refute_includes built, 'file_0.txt'
    ensure
      search&.close
    end
  end

  class TextIndex
    attr_reader :added

    def initialize
      @added = []
    end

    def add(texts)
      @added.concat(texts)
    end

    def query(_text, limit:)
      @added.each_index.first(limit).map { |id| { id: id, score: 0, positions: [] } }
    end

    def total_matches
      @added.length
    end

    def close; end
  end

  # add_packed を持たない独自のインデックスには表示名の配列を渡す
  def test_index_without_add_packed_receives_texts
    index = TextIndex.new
    search = Rufio::FuzzySearchSession.new(source: Batches.new([block(%w[a b], [])]), index_factory: -> { index }).start
    state = settle(search)

    assert_equal %w[a b], index.added
    assert_equal %w[a b], state.results.map { |result| result[:entry][:text] }
  ensure
    search&.close
  end

  class HeldSource
    def initialize(batch)
      @batch = batch
      @release = Queue.new
    end

    def finish
      @release << true
    end

    def each_batch(cancelled:, on_error:)
      sleep 0.05 # 候補のない最初の検索を先に終わらせる
      yield @batch
      @release.pop
    end
  end

  # 候補のない検索の直後に届いた最初の候補は、集約の間隔を待たずに照合する
  def test_first_candidates_are_searched_without_waiting_for_the_refresh_interval
    source = HeldSource.new(%w[alpha.rb beta.rb])
    search = Rufio::FuzzySearchSession.new(source: source, native: false, refresh_interval: 60).start
    search.update_query('a')
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until search.results.length == 2
      flunk 'first candidates were not searched' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      search.poll
      sleep 0.005
    end
    assert search.scanning?
  ensure
    source&.finish
    search&.close
  end
end

class TestFuzzyBlockSources < Minitest::Test
  def collect(source)
    batches = []
    source.each_batch(cancelled: -> { false }, on_error: ->(message) { flunk message }) { |batch| batches << batch }
    batches
  end

  def with_tree
    Dir.mktmpdir('rufio_blocks') do |dir|
      root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(root, '日本'))
      File.write(File.join(root, 'a.rb'), '')
      File.write(File.join(root, '日本', '検索.rb'), '')
      yield root
    end
  end

  def test_file_source_emits_blocks_whose_rows_point_at_the_files
    with_tree do |root|
      [false, true].each do |native|
        batches = collect(Rufio::FuzzyFileSource.new(root, native: native))

        assert batches.all? { |batch| batch.is_a?(Rufio::FuzzyCandidateBlock) }, "native=#{native}"
        rows = batches.flat_map(&:to_a).sort_by { |row| row[:text] }
        assert_equal ['a.rb', '日本/検索.rb'], rows.map { |row| row[:text] }
        assert_equal [File.join(root, 'a.rb'), File.join(root, '日本', '検索.rb')], rows.map { |row| row[:path] }
        assert rows.all? { |row| File.file?(row[:path]) }
      end
    end
  end

  # 走査が出したブロックをそのままキャッシュし、再表示でも同じブロックを渡す（コピーしない）
  def test_cache_stores_and_replays_the_scanned_blocks
    with_tree do |root|
      cache = Rufio::FuzzyCandidateCache.new
      source, cached_at = cache.source_for(root, native: false)
      assert_nil cached_at
      scanned = collect(source)

      source, cached_at = cache.source_for(root, native: false)
      refute_nil cached_at
      replayed = collect(source)
      assert_equal scanned.length, replayed.length
      scanned.zip(replayed).each { |first, second| assert_same first, second }
      assert_equal 2, cache.entry_count
    end
  end

  def test_cache_counts_blocks_against_the_entry_limit
    with_tree do |root|
      cache = Rufio::FuzzyCandidateCache.new(max_entries: 1)
      collect(cache.source_for(root, native: false).first)

      assert_nil cache.fetch(root)
    end
  end

  def test_native_listing_splits_large_drains
    skip 'native file listing is not available' unless Rufio::NativeContentSearch.files_available?

    Dir.mktmpdir('rufio_slices') do |dir|
      40.times { |i| File.write(File.join(dir, "file_#{i}.txt"), '') }
      scanner = Rufio::NativeContentSearch.new(roots: [File.realpath(dir)])
      batches = scanner.each_batch(max_events: 8).to_a
      files = batches.flatten(1).select { |event| event.first == :file }

      assert_equal 40, files.length
      assert batches.all? { |batch| batch.length <= 8 }
    ensure
      scanner&.close
    end
  end
end
