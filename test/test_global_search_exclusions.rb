# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'timeout'

class TestGlobalSearchExclusions < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio-search-exclusions')
    %w[keep.txt skip.LOG archive.TAR.GZ catalog catalogger log .env].each do |name|
      File.write(File.join(@root, name), "needle\n")
    end
    FileUtils.mkdir_p(File.join(@root, 'folder.log'))
    File.write(File.join(@root, 'folder.log', 'inside.txt'), "needle\n")
    @search = Rufio::GlobalSearch.new
  end

  def teardown
    @search.close
    FileUtils.rm_rf(@root)
  end

  def wait_for_scan
    Timeout.timeout(3) do
      while @search.scanning?
        @search.poll
        Thread.pass
      end
    end
  end

  def test_exclusions_apply_to_file_names_and_contents_with_case_and_compound_suffixes
    Rufio::ConfigLoader.stub(:load_config, { global_search_excluded_extensions: ['log', '.tar.gz', '.env'] }) do
      @search.open([{ name: 'Test', path: @root }])
      wait_for_scan
      expected = %w[catalog catalogger inside.txt keep.txt log]
      assert_equal expected, @search.results.map { |r| File.basename(r[:path]) }.sort
      @search.handle_key("\t")
      @search.handle_key('needle')
      wait_for_scan
      assert_equal expected, @search.results.map { |r| File.basename(r[:path]) }.sort
      assert_equal 3, @search.skipped_files
    end
  end

  def test_no_setting_preserves_all_files
    Rufio::ConfigLoader.stub(:load_config, {}) do
      @search.open([{ name: 'Test', path: @root }])
      wait_for_scan
      assert_equal 8, @search.results.length
    end
  end

  def test_invalid_entries_are_ignored_and_extensions_are_normalized
    config = { global_search_excluded_extensions: [' LOG ', '.ZIP', '', '.', nil, 123, 'log'] }
    Rufio::ConfigLoader.stub(:load_config, config) do
      assert_equal %w[.log .zip], Rufio::ConfigLoader.global_search_excluded_extensions
    end
    Rufio::ConfigLoader.stub(:load_config, { global_search_excluded_extensions: 123 }) do
      assert_empty Rufio::ConfigLoader.global_search_excluded_extensions
    end
  end

  def test_config_rb_constant_is_loaded
    loader = Rufio::ConfigLoader
    original_path = loader::CONFIG_PATH
    had_constant = Object.const_defined?(:GLOBAL_SEARCH_EXCLUDED_EXTENSIONS)
    original_value = Object.const_get(:GLOBAL_SEARCH_EXCLUDED_EXTENSIONS) if had_constant
    Object.send(:remove_const, :GLOBAL_SEARCH_EXCLUDED_EXTENSIONS) if had_constant
    config_path = File.join(@root, 'config.rb')
    File.write(config_path, "GLOBAL_SEARCH_EXCLUDED_EXTENSIONS = %w[.log .zip].freeze\n")
    loader.send(:remove_const, :CONFIG_PATH)
    loader.const_set(:CONFIG_PATH, config_path)
    config = loader.send(:load_config_file)
    assert_equal %w[.log .zip], config[:global_search_excluded_extensions]
  ensure
    loader.send(:remove_const, :CONFIG_PATH)
    loader.const_set(:CONFIG_PATH, original_path)
    Object.send(:remove_const, :GLOBAL_SEARCH_EXCLUDED_EXTENSIONS) if Object.const_defined?(:GLOBAL_SEARCH_EXCLUDED_EXTENSIONS)
    Object.const_set(:GLOBAL_SEARCH_EXCLUDED_EXTENSIONS, original_value) if had_constant
  end
end
