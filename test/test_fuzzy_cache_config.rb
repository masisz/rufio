# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

# s / / の一覧キャッシュの上限は既定値で動き、config.rb の FUZZY_SEARCH_CACHE で
# 上限値（MAX_FUZZY_SEARCH_CACHE）まで増減できる。
class TestFuzzyCacheConfig < Minitest::Test
  DEFAULTS = { max_entries: 200_000, max_roots: 4, ttl: 300 }.freeze
  LIMITS = { max_entries: 1_000_000, max_roots: 16, ttl: 86_400 }.freeze

  def cache_config(value)
    Rufio::ConfigLoader.stub(:load_config, { fuzzy_search_cache: value }) { Rufio::ConfigLoader.fuzzy_search_cache }
  end

  def test_defaults_and_limits_are_public
    assert_equal DEFAULTS, Rufio::ConfigLoader::DEFAULT_FUZZY_SEARCH_CACHE
    assert_equal LIMITS, Rufio::ConfigLoader::MAX_FUZZY_SEARCH_CACHE
    assert_equal DEFAULTS[:max_entries], Rufio::FuzzyCandidateCache::DEFAULT_MAX_ENTRIES
    assert_equal DEFAULTS[:max_roots], Rufio::FuzzyCandidateCache::DEFAULT_MAX_ROOTS
    assert_equal DEFAULTS[:ttl], Rufio::FuzzyCandidateCache::DEFAULT_TTL
  end

  def test_defaults_without_setting
    assert_equal DEFAULTS, Rufio::ConfigLoader.stub(:load_config, {}) { Rufio::ConfigLoader.fuzzy_search_cache }
    assert_equal DEFAULTS, cache_config(nil)
  end

  def test_partial_setting_is_merged_with_defaults
    assert_equal({ max_entries: 500_000, max_roots: 4, ttl: 900 }, cache_config({ max_entries: 500_000, ttl: 900 }))
  end

  def test_values_are_capped_at_limits
    assert_equal LIMITS, cache_config({ max_entries: 10**9, max_roots: 1000, ttl: 10**9 })
  end

  def test_zero_disables_or_expires_immediately
    assert_equal({ max_entries: 0, max_roots: 0, ttl: 0 }, cache_config({ max_entries: 0, max_roots: 0, ttl: 0 }))
  end

  def test_invalid_values_fall_back_to_defaults
    assert_equal DEFAULTS, cache_config({ max_entries: -1, max_roots: '8', ttl: 1.5, unknown: 3 })
    assert_equal DEFAULTS, cache_config([1, 2])
    assert_equal DEFAULTS, cache_config({ max_entries: true, max_roots: nil })
  end

  def test_config_rb_constant_is_loaded
    loader = Rufio::ConfigLoader
    original_path = loader::CONFIG_PATH
    had_constant = Object.const_defined?(:FUZZY_SEARCH_CACHE)
    original_value = Object.const_get(:FUZZY_SEARCH_CACHE) if had_constant
    Object.send(:remove_const, :FUZZY_SEARCH_CACHE) if had_constant
    Dir.mktmpdir('rufio_fuzzy_cache_config') do |dir|
      config_path = File.join(dir, 'config.rb')
      File.write(config_path, "FUZZY_SEARCH_CACHE = { max_entries: 400_000, max_roots: 8 }.freeze\n")
      loader.send(:remove_const, :CONFIG_PATH)
      loader.const_set(:CONFIG_PATH, config_path)
      config = loader.send(:load_config_file)
      assert_equal({ max_entries: 400_000, max_roots: 8 }, config[:fuzzy_search_cache])
    end
  ensure
    loader.send(:remove_const, :CONFIG_PATH)
    loader.const_set(:CONFIG_PATH, original_path)
    Object.send(:remove_const, :FUZZY_SEARCH_CACHE) if Object.const_defined?(:FUZZY_SEARCH_CACHE)
    Object.const_set(:FUZZY_SEARCH_CACHE, original_value) if had_constant
  end

  def test_search_controller_builds_cache_from_config
    settings = { max_entries: 12, max_roots: 3, ttl: 45 }
    controller = Rufio::ConfigLoader.stub(:fuzzy_search_cache, settings) do
      Rufio::SearchController.new(nil, Rufio::FileOpener.new)
    end
    cache = controller.instance_variable_get(:@candidate_cache)
    assert_equal 12, cache.instance_variable_get(:@max_entries)
    assert_equal 3, cache.instance_variable_get(:@max_roots)
    assert_equal 45, cache.instance_variable_get(:@ttl)
  end
end
