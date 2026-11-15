# frozen_string_literal: true

require_relative "test_helper"
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/rufio"

# Phase 6: KEYBINDS config接続のテスト
# ConfigLoader.default_keybinds, keybinds マージ, KeybindHandler dispatch 動作を検証
class TestKeybindConfig < Minitest::Test
  # === ConfigLoader.default_keybinds ===

  def test_default_keybinds_returns_hash
    keybinds = Rufio::ConfigLoader.default_keybinds
    assert_instance_of Hash, keybinds
  end

  def test_default_keybinds_move_up_is_k
    assert_equal 'k', Rufio::ConfigLoader.default_keybinds[:move_up]
  end

  def test_default_keybinds_move_down_is_j
    assert_equal 'j', Rufio::ConfigLoader.default_keybinds[:move_down]
  end

  def test_default_keybinds_navigate_parent_is_h
    assert_equal 'h', Rufio::ConfigLoader.default_keybinds[:navigate_parent]
  end

  def test_default_keybinds_navigate_enter_is_l
    assert_equal 'l', Rufio::ConfigLoader.default_keybinds[:navigate_enter]
  end

  def test_default_keybinds_top_is_g
    assert_equal 'g', Rufio::ConfigLoader.default_keybinds[:top]
  end

  def test_default_keybinds_bottom_is_closing_brace
    assert_equal '}', Rufio::ConfigLoader.default_keybinds[:bottom]
  end

  def test_default_keybinds_refresh_is_R
    assert_equal 'R', Rufio::ConfigLoader.default_keybinds[:refresh]
  end

  def test_default_keybinds_quit_is_q
    assert_equal 'q', Rufio::ConfigLoader.default_keybinds[:quit]
  end

  def test_default_keybinds_file_search_is_s_and_slash
    keybinds = Rufio::ConfigLoader.default_keybinds
    assert_equal 's', keybinds[:file_search]
    assert_equal '/', keybinds[:file_search_alt]
    refute keybinds.key?(:fzf_search)
    refute keybinds.key?(:fzf_search_alt)
  end

  def test_legacy_fzf_search_names_are_aliases_in_user_config
    Rufio::ConfigLoader.stub(:load_config, { keybinds: { fzf_search: 'x', fzf_search_alt: 'X' } }) do
      keybinds = Rufio::ConfigLoader.keybinds
      assert_equal 'x', keybinds[:file_search]
      assert_equal 'X', keybinds[:file_search_alt]
      refute keybinds.key?(:fzf_search)
      refute keybinds.key?(:fzf_search_alt)
    end
  end

  def test_s_and_slash_dispatch_to_file_search
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(Rufio::DirectoryListing.new(Dir.pwd))
    searched = []
    handler.define_singleton_method(:fzf_search) { searched << :fzf_search; true }
    handler.define_singleton_method(:file_search) { searched << :file_search; true }
    %w[s /].each { |key| handler.handle_key(key) }
    assert_equal %i[file_search file_search], searched
  end

  def test_new_file_search_name_wins_over_legacy_alias
    Rufio::ConfigLoader.stub(:load_config, { keybinds: { file_search: 'y', fzf_search: 'x' } }) do
      assert_equal 'y', Rufio::ConfigLoader.keybinds[:file_search]
    end
  end

  def test_default_keybinds_rga_search_is_F
    assert_equal 'F', Rufio::ConfigLoader.default_keybinds[:rga_search]
  end

  def test_default_keybinds_add_bookmark_is_b
    assert_equal 'b', Rufio::ConfigLoader.default_keybinds[:add_bookmark]
  end

  def test_default_keybinds_bookmark_menu_is_B
    assert_equal 'B', Rufio::ConfigLoader.default_keybinds[:bookmark_menu]
  end

  def test_default_keybinds_contains_all_required_actions
    keybinds = Rufio::ConfigLoader.default_keybinds
    required = [
      :move_up, :move_down, :navigate_parent, :navigate_enter,
      :top, :bottom, :refresh, :open_file,
      :rename, :delete, :create_file, :create_dir,
      :move_selected, :copy_selected, :delete_selected, :open_explorer,
      :select, :filter, :file_search, :file_search_alt, :rga_search,
      :add_bookmark, :bookmark_menu, :zoxide, :start_dir,
      :job_mode, :help, :log_viewer, :command_mode, :quit
    ]
    required.each do |action|
      assert keybinds.key?(action), "default_keybindsに :#{action} が含まれること"
    end
  end

  # === ConfigLoader.keybinds マージ動作 ===

  def test_keybinds_returns_hash_with_move_up
    keybinds = Rufio::ConfigLoader.keybinds
    assert keybinds.key?(:move_up), "keybindsに :move_up が含まれること"
  end

  def test_keybinds_returns_hash_with_quit
    keybinds = Rufio::ConfigLoader.keybinds
    assert keybinds.key?(:quit), "keybindsに :quit が含まれること"
  end

  def test_keybinds_move_down_default_is_j
    # ユーザー設定がなければデフォルトのjが使われること
    keybinds = Rufio::ConfigLoader.keybinds
    assert_equal 'j', keybinds[:move_down]
  end

  # === KeybindHandler のデフォルトキー動作 ===

  def setup
    @test_dir = Dir.mktmpdir("rufio_keybind_cfg_test")
    FileUtils.mkdir_p(File.join(@test_dir, "dir_a"))
    FileUtils.mkdir_p(File.join(@test_dir, "dir_b"))
    File.write(File.join(@test_dir, "file1.txt"), "hello")

    @dl = Rufio::DirectoryListing.new(@test_dir)
    @handler = Rufio::KeybindHandler.new
    @handler.set_directory_listing(@dl)
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def test_j_key_moves_cursor_down
    initial = @handler.current_index
    @handler.handle_key('j')
    assert_equal initial + 1, @handler.current_index
  end

  def test_k_key_moves_cursor_up
    @handler.select_index(1)
    @handler.handle_key('k')
    assert_equal 0, @handler.current_index
  end

  def test_g_key_moves_to_top
    @handler.select_index(2)
    @handler.handle_key('g')
    assert_equal 0, @handler.current_index
  end

  def test_closing_brace_key_moves_to_bottom
    entries = @dl.list_entries
    @handler.handle_key('}')
    assert_equal entries.length - 1, @handler.current_index
  end

  def test_R_key_refreshes_directory
    result = @handler.handle_key('R')
    assert result, "Rキーはtrueを返すこと"
  end

  def test_unknown_key_returns_false
    result = @handler.handle_key('Z')
    refute result, "未知のキーはfalseを返すこと"
  end

  # === カスタムキーバインドの動作確認 ===

  def test_key_map_is_built_from_keybinds
    assert @handler.respond_to?(:key_map, true), "key_map メソッドが存在すること"
  end

  def test_key_map_contains_move_down_key
    key_map = @handler.send(:key_map)
    assert key_map.key?('j'), "key_mapに 'j' が含まれること（デフォルト move_down）"
    assert_equal :move_down, key_map['j']
  end

  def test_key_map_contains_quit_key
    key_map = @handler.send(:key_map)
    assert key_map.key?('q'), "key_mapに 'q' が含まれること（デフォルト quit）"
    assert_equal :quit, key_map['q']
  end
end
