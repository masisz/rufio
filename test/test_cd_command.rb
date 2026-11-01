# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

# コマンドモードの :cd <path>（コピペしたパスへの移動）
class TestCdCommand < Minitest::Test
  def setup
    @root = File.realpath(Dir.mktmpdir)
    @dir = File.join(@root, 'my dir')
    FileUtils.mkdir_p(File.join(@dir, 'sub'))
    @file = File.join(@dir, 'note.txt')
    File.write(@file, 'x')
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def resolve(input, base = @root)
    Rufio::PathJump.resolve(input, base)
  end

  # --- PathJump.resolve ---

  def test_resolves_absolute_directory
    assert_equal({ directory: @dir, file: nil }, resolve(@dir))
  end

  def test_resolves_file_to_parent_and_file
    assert_equal({ directory: @dir, file: @file }, resolve(@file))
  end

  def test_relative_path_uses_base_directory
    assert_equal({ directory: File.join(@dir, 'sub'), file: nil }, resolve('sub', @dir))
    assert_equal({ directory: @root, file: nil }, resolve('..', @dir))
  end

  def test_strips_surrounding_quotes_and_whitespace
    assert_equal @dir, resolve("  '#{@dir}'  ")[:directory]
    assert_equal @dir, resolve(%("#{@dir}"))[:directory]
  end

  def test_trailing_newline_from_paste_is_ignored
    assert_equal @dir, resolve("#{@dir}\n")[:directory]
  end

  def test_unescapes_backslash_spaces
    skip 'Windows paths use backslash as separator' if Gem.win_platform?
    assert_equal @dir, resolve(@dir.gsub(' ', '\\ '))[:directory]
  end

  def test_accepts_file_url
    skip 'file URL form differs on Windows' if Gem.win_platform?
    url = "file://#{@dir.gsub(' ', '%20')}"
    assert_equal @dir, resolve(url)[:directory]
  end

  def test_tilde_expands_to_home
    assert_equal File.expand_path('~'), resolve('~')[:directory]
  end

  def test_empty_input_goes_home
    assert_equal File.expand_path('~'), resolve('')[:directory]
  end

  def test_missing_path_returns_error
    result = resolve(File.join(@root, 'nope'))
    assert_nil result[:directory]
    assert_match(/not found/i, result[:error])
  end

  # --- CommandMode ---

  def test_command_mode_returns_cd_request
    result = Rufio::CommandMode.new.execute("cd #{@dir}", working_dir: @root)
    assert_equal({ cd: { directory: @dir, file: nil } }, result)
  end

  def test_command_mode_resolves_relative_to_working_dir
    result = Rufio::CommandMode.new.execute('cd sub', working_dir: @dir)
    assert_equal File.join(@dir, 'sub'), result[:cd][:directory]
  end

  def test_command_mode_returns_error_message_for_missing_path
    result = Rufio::CommandMode.new.execute('cd /no/such/dir', working_dir: @root)
    assert_kind_of String, result
    assert_match(/not found/i, result)
  end

  def test_cd_dash_is_left_to_terminal_ui
    result = Rufio::CommandMode.new.execute('cd -', working_dir: @root)
    assert_equal({ cd: :previous }, result)
  end

  def test_other_commands_starting_with_cd_are_not_captured
    result = Rufio::CommandMode.new.execute('cdx', working_dir: @root)
    refute_kind_of Hash, result
  end

  # --- 補完 ---

  def test_tab_completes_directories_relative_to_browsing_directory
    command_mode = Rufio::CommandMode.new
    command_mode.update_browsing_directory(@root)
    completion = Rufio::CommandCompletion.new(command_mode)
    assert_equal ['cd my dir/'], completion.complete('cd my')
  end

  def test_tab_completion_lists_only_directories
    command_mode = Rufio::CommandMode.new
    command_mode.update_browsing_directory(@dir)
    completion = Rufio::CommandCompletion.new(command_mode)
    assert_equal ['cd sub/'], completion.complete('cd ')
  end

  def test_cd_is_suggested_as_command
    completion = Rufio::CommandCompletion.new(Rufio::CommandMode.new)
    assert_includes completion.complete('c'), 'cd'
  end

  # --- TerminalUI ---

  def build_ui(start)
    listing = Rufio::DirectoryListing.new(start)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(listing)
    ui = Rufio::TerminalUI.new
    handler.set_terminal_ui(ui)
    ui.instance_variable_set(:@directory_listing, listing)
    ui.instance_variable_set(:@keybind_handler, handler)
    [ui, handler, listing]
  end

  def run_command(ui, command)
    ui.activate_command_mode
    command.each_char { |c| ui.handle_command_input(c) }
    ui.handle_command_input("\r")
  end

  def test_terminal_ui_moves_to_directory_and_closes_command_mode
    ui, _handler, listing = build_ui(@root)
    run_command(ui, "cd #{@dir}")
    assert_equal @dir, listing.current_path
    refute ui.command_mode_active?
  end

  def test_terminal_ui_selects_pasted_file
    ui, handler, listing = build_ui(@root)
    run_command(ui, "cd '#{@file}'")
    assert_equal @dir, listing.current_path
    assert_equal @file, handler.current_entry[:path]
  end

  def test_terminal_ui_cd_dash_returns_to_previous_directory
    ui, _handler, listing = build_ui(@root)
    run_command(ui, "cd #{@dir}")
    run_command(ui, 'cd -')
    assert_equal @root, listing.current_path
  end

  def test_terminal_ui_keeps_directory_on_error
    ui, _handler, listing = build_ui(@root)
    shown = nil
    ui.instance_variable_get(:@command_mode_ui).stub(:show_result, ->(result) { shown = result }) do
      run_command(ui, 'cd /no/such/dir')
    end
    assert_equal @root, listing.current_path
    assert_match(/not found/i, shown)
  end
end
