# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/rufio"

# SearchController のユニットテスト
# Phase 5: KeybindHandler から SearchController を抽出するリファクタリングに対応
class TestSearchController < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("rufio_search_ctrl_test")
    setup_test_files

    @directory_listing = Rufio::DirectoryListing.new(@test_dir)
    @file_opener = Rufio::FileOpener.new

    @controller = Rufio::SearchController.new(@directory_listing, @file_opener)
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # === 基本テスト ===

  def test_can_instantiate
    assert_instance_of Rufio::SearchController, @controller
  end

  def test_set_directory_listing
    new_dir = Dir.mktmpdir("rufio_new_search_test")
    begin
      new_listing = Rufio::DirectoryListing.new(new_dir)
      @controller.set_directory_listing(new_listing)
      pass
    ensure
      FileUtils.rm_rf(new_dir)
    end
  end

  # === fzf_available? テスト ===

  def test_fzf_available_returns_boolean
    result = @controller.fzf_available?
    assert [true, false].include?(result), "fzf_available?はtrue/falseを返すこと"
  end

  # === rga_available? テスト ===

  def test_rga_available_returns_boolean
    result = @controller.rga_available?
    assert [true, false].include?(result), "rga_available?はtrue/falseを返すこと"
  end

  # === fzf_search テスト（fzfがない場合） ===

  def test_fzf_search_returns_false_without_fzf
    # fzfが利用不可の場合のフォールバックテスト
    @controller.define_singleton_method(:fzf_available?) { false }
    result = @controller.fzf_search
    refute result, "fzfがない場合はfalseを返すこと"
  end

  # === rga_search テスト（rgaがない場合） ===

  def test_rga_search_returns_false_without_rga
    @controller.define_singleton_method(:rga_available?) { false }
    result = @controller.rga_search
    refute result, "rgaがない場合はfalseを返すこと"
  end

  # === メソッド存在確認テスト ===

  def test_fzf_search_method_exists
    assert @controller.respond_to?(:fzf_search), "fzf_searchメソッドが存在すること"
  end

  def test_rga_search_method_exists
    assert @controller.respond_to?(:rga_search), "rga_searchメソッドが存在すること"
  end

  private

  def setup_test_files
    File.write(File.join(@test_dir, "file1.txt"), "Hello World")
    File.write(File.join(@test_dir, "file2.rb"), "puts 'hello'")
  end
end
