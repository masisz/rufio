# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio/fuzzy_search'

class TestFuzzySearch < Minitest::Test
  def build(candidates)
    Rufio::FuzzySearch.new(native: false).tap { |search| search.add(candidates) }
  end

  def test_subsequence_and_byte_positions
    search = build(['lib/search_controller.rb', 'other.rb', '日本語の検索.rb'])
    result = search.query('sctrl')
    assert_equal [0], result.map { |r| r[:id] }
    assert_equal 'sctrl', result.first[:positions].map { |i| 'lib/search_controller.rb'.byteslice(i, 1) }.join
    result = search.query('日検')
    assert_equal [2], result.map { |r| r[:id] }
    assert_equal [0, 12], result.first[:positions]
    assert_empty search.query('検日')
    search.close
  end

  def test_ranking_and_stable_ties
    search = build(['a_b_c', 'abc', 'axbyc', 'abc', 'lib/abc.rb', 'abc/lib.rb'])
    result = search.query('ABC')
    assert_equal [1, 3], result.first(2).map { |r| r[:id] }
    assert_operator result.find { |r| r[:id] == 0 }[:score], :>, result.find { |r| r[:id] == 2 }[:score]
    assert_operator result.find { |r| r[:id] == 4 }[:score], :>, result.find { |r| r[:id] == 5 }[:score]
    search.close
  end

  def test_best_alignment_prefers_later_contiguous_match
    search = build(['a___ab'])
    assert_equal [4, 5], search.query('ab').first[:positions]
    search.close
  end

  def test_limit_total_empty_query_and_append
    search = build(['z', 'a', 'a', 'b'])
    assert_equal [0, 1], search.query('', limit: 2).map { |r| r[:id] }
    assert_equal 4, search.total_matches
    assert_equal [1], search.query('a', limit: 1).map { |r| r[:id] }
    assert_equal 2, search.total_matches
    assert_empty search.query('a', limit: 0)
    assert_equal 2, search.total_matches
    search.add(['a'])
    assert_equal [1, 2, 4], search.query('a').map { |r| r[:id] }
    assert_equal [0, 1, 2, 3, 4], search.query('').map { |r| r[:id] }
    search.close
    search.close
    assert_raises(IOError) { search.query('a') }
    assert_raises(IOError) { search.add(['a']) }
  end

  def test_invalid_input_and_unicode_policy
    search = build(['École', 'école', '😀検索'])
    assert_equal [0], search.query('É').map { |r| r[:id] }
    assert_equal [0, 4], search.query('😀検').first[:positions]
    assert_raises(ArgumentError) { search.add(["bad\0path"]) }
    assert_raises(ArgumentError) { search.add(["\xff".b]) }
    assert_raises(ArgumentError) { search.query('a' * 1025) }
    assert_raises(ArgumentError) { search.query('a', limit: -1) }
    assert_raises(ArgumentError) { search.query("a\0") }
    search.close
  end

  def test_default_and_disabled_engine_fall_back_when_library_is_missing
    search = Rufio::FuzzySearch.new(library: File.join(__dir__, 'missing-fuzzy-library'))
    refute search.native?
    search.add(['hello'])
    assert_equal [0], search.query('hlo').map { |r| r[:id] }
    search.close
  end
end

# Set RUFIO_TEST_FUZZY_LIBRARY to a freshly built library to require native parity.
class TestNativeFuzzySearch < Minitest::Test
  def setup
    skip 'Set RUFIO_TEST_FUZZY_LIBRARY for native tests' unless ENV['RUFIO_TEST_FUZZY_LIBRARY']
    @native = Rufio::FuzzySearch.new(library: ENV.fetch('RUFIO_TEST_FUZZY_LIBRARY'))
    assert @native.native?, 'The requested library must expose the fuzzy API'
    @ruby = Rufio::FuzzySearch.new(native: false)
  end

  def teardown
    @native&.close
    @ruby&.close
  end

  def test_randomized_native_parity_and_top_k
    random = Random.new(160)
    candidates = ['', '日本語/検索.rb', '😀検索', 'a___ab', 'ABC', 'abc']
    350.times { candidates << Array.new(random.rand(1..40)) { ['a', 'b', 'C', '_', '/', '日', '本', '😀'].sample(random: random) }.join }
    [@ruby, @native].each { |s| s.add(candidates.first(100)); s.add(candidates.drop(100)) }
    ['', 'abc', 'ab', '日本', '😀日', 'notfound', 'C', 'a', '日a'].each do |query|
      [0, 1, 7, 1000].each do |limit|
        assert_equal @ruby.query(query, limit: limit), @native.query(query, limit: limit), "#{query.inspect} limit=#{limit}"
        assert_equal @ruby.total_matches, @native.total_matches
      end
    end
  end

  def test_native_close_and_invalid_input
    @native.add(['日本語'])
    assert_raises(ArgumentError) { @native.add(["\xff".b]) }
    assert_equal [0], @native.query('日語').map { |r| r[:id] }
    @native.close
    @native.close
    assert_raises(IOError) { @native.query('日') }
  end
end
