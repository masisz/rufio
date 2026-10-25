# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'timeout'

# Zig 実装のコンテンツ検索が Ruby 実装と同じ結果を返すことを検証する。
class TestNativeContentSearch < Minitest::Test
  def setup
    skip 'Zig content search not available' unless Rufio::NativeContentSearch.available?

    @root = Dir.mktmpdir('rufio-native-search')
    @a = File.join(@root, 'a')
    @b = File.join(@root, 'b')
    FileUtils.mkdir_p([File.join(@a, 'deep', 'er'), @b])
    File.write(File.join(@a, 'first.txt'), "header\nHello WORLD\n日本語の検索\n")
    File.write(File.join(@a, 'crlf.txt'), "one\r\nWorld two\r\nthree world\r\n")
    File.write(File.join(@a, 'deep', 'er', 'nested.rb'), "# wOrLd\nputs 'x'\n")
    File.write(File.join(@a, 'no_newline.txt'), 'last world')
    File.write(File.join(@a, 'twice.txt'), "world world world\n")
    File.write(File.join(@a, 'image.PNG'), "world\n")
    File.write(File.join(@a, 'report.pdf'), 'not really a pdf')
    File.write(File.join(@b, 'second.txt'), "world again\nno match\nWORLD twice\n")
    File.binwrite(File.join(@b, 'binary.dat'), "\x00world\xff")
    File.binwrite(File.join(@b, 'late_nul.dat'), ('a' * 9000) + "\x00\nworld\n")
    File.write(File.join(@b, 'long.txt'), ('あ' * 500) + 'needle world' + ('y' * 3000) + "\n")
    File.symlink(File.join(@a, 'first.txt'), File.join(@b, 'link_to_file.txt'))
    File.symlink(@a, File.join(@b, 'link_to_dir'))
    @bookmarks = [{ name: 'A', path: @a }, { name: 'B', path: @b }, { name: 'Deep', path: File.join(@a, 'deep') }]
  end

  def teardown
    Rufio::GlobalSearch.native_search = nil
    FileUtils.rm_rf(@root) if @root
  end

  def run_search(native, query, bookmarks = @bookmarks, excluded: ['.png'])
    Rufio::GlobalSearch.native_search = native
    Rufio::ConfigLoader.stub(:global_search_excluded_extensions, excluded) do
      search = Rufio::GlobalSearch.new
      search.open(bookmarks)
      search.handle_key("\t")
      search.handle_key(query)
      Timeout.timeout(10) do
        while search.scanning?
          search.poll
          Thread.pass
        end
      end
      search.poll
      results = search.results.map do |r|
        [r[:bookmark], r[:relative_path], r[:line_number], r[:match_text], r[:path]]
      end.sort_by(&:to_s)
      [results, search.skipped_files, search.errors.length]
    ensure
      search&.close
    end
  end

  def assert_parity(query, bookmarks = @bookmarks)
    expected = run_search(false, query, bookmarks)
    actual = run_search(true, query, bookmarks)
    assert_equal expected, actual
    expected
  end

  def test_native_matches_ruby_for_ascii_query
    results, skipped, = assert_parity('world')
    refute_empty results
    assert_operator skipped, :>=, 2
  end

  def test_native_matches_ruby_for_japanese_and_long_lines
    results, = assert_parity('日本語')
    assert_equal 2, results.length
    results, = assert_parity('needle')
    assert_includes results.first[3], 'needle'
  end

  def test_native_matches_ruby_for_symbols_and_single_char
    assert_parity("'x'")
    assert_parity('#')
    assert_parity('zzz-not-found')
  end

  def test_native_matches_ruby_across_read_chunks
    lines = Array.new(40_000) { |i| (i % 997).zero? ? "line #{i} Target here\n" : "filler line #{i} #{'z' * (i % 50)}\n" }
    File.write(File.join(@a, 'big.log'), lines.join)
    results, = assert_parity('target')
    assert_equal 41, results.length
  end

  def test_native_is_used_when_enabled
    Rufio::GlobalSearch.native_search = true
    assert Rufio::GlobalSearch.native_search?
    Rufio::GlobalSearch.native_search = false
    refute Rufio::GlobalSearch.native_search?
  end

  def test_case_sensitive_non_ascii_queries_fall_back_to_ruby
    refute Rufio::NativeContentSearch.supports_query?('é')
    assert Rufio::NativeContentSearch.supports_query?('日本語')
    assert Rufio::NativeContentSearch.supports_query?('world')
  end

  def test_close_cancels_running_native_search
    200.times { |i| File.write(File.join(@b, "f#{i}.txt"), "world\n" * 2000) }
    Rufio::GlobalSearch.native_search = true
    search = Rufio::GlobalSearch.new
    search.open(@bookmarks)
    search.handle_key("\t")
    search.handle_key('w')
    Timeout.timeout(3) { search.close }
    refute search.scanning?
  end

  def test_engine_streams_records_directly
    engine = Rufio::NativeContentSearch.new(roots: [@a], query: 'world', excluded_extensions: ['.png'],
                                            document_extensions: ['.pdf'])
    events = []
    engine.each_event { |event| events << event }
    matches = events.select { |e| e[0] == :match }
    documents = events.select { |e| e[0] == :document }
    assert_equal [[0, File.join(@a, 'report.pdf')]], documents.map { |e| e[1..2] }
    assert_includes matches.map { |e| [File.basename(e[2]), e[3]] }, ['first.txt', 2]
    assert(matches.all? { |e| e[1].zero? })
  ensure
    engine&.close
  end
end
