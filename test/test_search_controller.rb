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

  # === rga_available? テスト ===

  def test_rga_available_returns_boolean
    result = @controller.rga_available?
    assert [true, false].include?(result), "rga_available?はtrue/falseを返すこと"
  end

  # === rga_search テスト（rgaがない場合） ===

  def test_rga_search_returns_false_without_rga
    @controller.define_singleton_method(:rga_available?) { false }
    result = @controller.rga_search
    refute result, "rgaがない場合はfalseを返すこと"
  end

  # === メソッド存在確認テスト ===

  def test_file_search_methods_exist
    assert @controller.respond_to?(:file_search), "file_searchメソッドが存在すること"
    assert @controller.respond_to?(:fzf_search), "互換用のfzf_searchメソッドが存在すること"
    refute @controller.respond_to?(:fzf_available?), "fzfの有無を確認しないこと"
  end

  # === 内蔵ファジー検索（s / /） ===

  def test_file_search_without_terminal_ui_returns_false
    refute @controller.file_search
  end

  def test_file_search_opens_fuzzy_finder_for_current_directory
    ui = FakeTerminalUI.new
    @controller.set_terminal_ui(ui)
    assert_equal true, @controller.file_search
    assert_equal 1, ui.calls.length
    session, title, on_select = ui.calls.first
    assert_instance_of Rufio::FuzzySearchSession, session
    source = session.instance_variable_get(:@source)
    assert_instance_of Rufio::FuzzyFileSource, source
    assert_equal File.expand_path(@test_dir), source.instance_variable_get(:@root)
    assert_includes title, @test_dir
    refute_nil on_select
  ensure
    ui&.calls&.each { |call| call.first.close }
  end

  def test_fzf_search_is_an_alias_of_file_search
    ui = FakeTerminalUI.new
    @controller.set_terminal_ui(ui)
    assert_equal true, @controller.fzf_search
    assert_equal 1, ui.calls.length
  ensure
    ui&.calls&.each { |call| call.first.close }
  end

  def test_file_search_selection_opens_file
    ui = FakeTerminalUI.new
    opened = []
    @file_opener.define_singleton_method(:open_file) { |path| opened << path }
    @controller.set_terminal_ui(ui)
    @controller.file_search
    path = File.join(@test_dir, 'file1.txt')
    assert_equal :needs_refresh, ui.calls.first.last.call({ text: 'file1.txt', path: path })
    assert_equal [path], opened
  ensure
    ui&.calls&.each { |call| call.first.close }
  end

  def test_file_search_selection_ignores_missing_file
    ui = FakeTerminalUI.new
    opened = []
    @file_opener.define_singleton_method(:open_file) { |path| opened << path }
    @controller.set_terminal_ui(ui)
    @controller.file_search
    ui.calls.first.last.call({ text: 'gone', path: File.join(@test_dir, 'gone') })
    assert_empty opened
  ensure
    ui&.calls&.each { |call| call.first.close }
  end

  # === rga 結果選択（F） ===

  def test_rga_search_prompts_and_opens_finder_with_rga_source
    ui = FakeTerminalUI.new
    dialog = FakeDialog.new('hello')
    controller = Rufio::SearchController.new(@directory_listing, @file_opener, dialog)
    controller.define_singleton_method(:rga_available?) { true }
    controller.set_terminal_ui(ui)
    assert_equal true, controller.rga_search
    session, title, = ui.calls.first
    source = session.instance_variable_get(:@source)
    assert_instance_of Rufio::RgaResultSource, source
    assert_equal ['--', 'hello', '.'], source.command.last(3)
    assert_includes title, 'hello'
    assert_equal 1, dialog.prompts
  ensure
    ui&.calls&.each { |call| call.first.close }
  end

  def test_rga_search_with_empty_query_does_not_open_finder
    ui = FakeTerminalUI.new
    controller = Rufio::SearchController.new(@directory_listing, @file_opener, FakeDialog.new(nil))
    controller.define_singleton_method(:rga_available?) { true }
    controller.set_terminal_ui(ui)
    refute controller.rga_search
    assert_empty ui.calls
  end

  def test_rga_selection_opens_file_at_line
    ui = FakeTerminalUI.new
    opened = []
    @file_opener.define_singleton_method(:open_file_with_line) { |path, line| opened << [path, line] }
    controller = Rufio::SearchController.new(@directory_listing, @file_opener, FakeDialog.new('Hello'))
    controller.define_singleton_method(:rga_available?) { true }
    controller.set_terminal_ui(ui)
    controller.rga_search
    path = File.join(@test_dir, 'file1.txt')
    result = ui.calls.first.last.call({ text: 'file1.txt:1:Hello World', path: path, line_number: 1 })
    assert_equal :needs_refresh, result
    assert_equal [[path, 1]], opened
  ensure
    ui&.calls&.each { |call| call.first.close }
  end

  def test_rga_search_method_exists
    assert @controller.respond_to?(:rga_search), "rga_searchメソッドが存在すること"
  end

  class FakeTerminalUI
    attr_reader :calls

    def initialize
      @calls = []
    end

    def start_fuzzy_finder(session, title:, &on_select)
      @calls << [session, title, on_select]
      true
    end
  end

  class FakeDialog
    attr_reader :prompts

    def initialize(answer)
      @answer = answer
      @prompts = 0
    end

    def show_input_dialog(*)
      @prompts += 1
      @answer
    end
  end

  private

  def setup_test_files
    File.write(File.join(@test_dir, "file1.txt"), "Hello World")
    File.write(File.join(@test_dir, "file2.rb"), "puts 'hello'")
  end
end
