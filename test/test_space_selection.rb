# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

# Spaceキーによるファイル選択のテスト
class TestSpaceSelection < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    # テスト用ファイル・ディレクトリを作成
    File.write(File.join(@tmpdir, 'file1.txt'), 'content1')
    File.write(File.join(@tmpdir, 'file2.rb'), 'content2')
    FileUtils.mkdir_p(File.join(@tmpdir, 'subdir1'))

    @handler = Rufio::KeybindHandler.new
    @directory_listing = Rufio::DirectoryListing.new(@tmpdir)
    @handler.set_directory_listing(@directory_listing)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # === SelectionManagerの基本テスト ===

  def test_selection_manager_toggle
    manager = Rufio::SelectionManager.new
    entry = { name: 'test.txt', type: 'file' }

    result = manager.toggle_selection(entry, '/some/path')
    assert result, '最初のトグルはtrueを返すべき'
    assert manager.selected?('test.txt'), 'test.txtが選択されているべき'

    result = manager.toggle_selection(entry, '/some/path')
    refute result, '2回目のトグルはfalseを返すべき'
    refute manager.selected?('test.txt'), 'test.txtが選択解除されているべき'
  end

  def test_selection_manager_source_directory
    manager = Rufio::SelectionManager.new
    entry = { name: 'test.txt', type: 'file' }

    manager.toggle_selection(entry, '/some/path')
    assert_equal '/some/path', manager.source_directory
  end

  # === KeybindHandler経由のSpaceキーテスト ===

  def test_space_key_returns_true
    result = @handler.handle_key(' ')
    assert result, 'Spaceキーはtrueを返すべき'
  end

  def test_space_key_toggles_selection
    entries = @directory_listing.list_entries
    @handler.select_index(0)
    first_entry_name = entries[0][:name]

    @handler.handle_key(' ')

    selected = @handler.selected_items
    assert_includes selected, first_entry_name, "#{first_entry_name}が選択されているべき"
  end

  def test_space_key_shows_as_selected
    entries = @directory_listing.list_entries
    @handler.select_index(0)
    first_entry_name = entries[0][:name]

    @handler.handle_key(' ')

    assert @handler.is_selected?(first_entry_name),
           "is_selected?('#{first_entry_name}')がtrueを返すべき"
  end

  def test_space_key_toggle_off
    entries = @directory_listing.list_entries
    @handler.select_index(0)
    first_entry_name = entries[0][:name]

    @handler.handle_key(' ')
    assert @handler.is_selected?(first_entry_name)

    @handler.handle_key(' ')
    refute @handler.is_selected?(first_entry_name),
           "2回目のSpaceで選択解除されるべき"
  end

  def test_space_key_multiple_files
    entries = @directory_listing.list_entries
    skip 'エントリが2つ未満' if entries.length < 2

    @handler.select_index(0)
    @handler.handle_key(' ')

    @handler.handle_key('j')
    @handler.handle_key(' ')

    selected = @handler.selected_items
    assert_equal 2, selected.length, "2つのファイルが選択されているべき"
    assert_includes selected, entries[0][:name]
    assert_includes selected, entries[1][:name]
  end

  def test_space_key_with_directory_entry
    entries = @directory_listing.list_entries
    dir_index = entries.find_index { |e| e[:type] == 'directory' }
    skip 'ディレクトリエントリが見つからない' unless dir_index

    @handler.select_index(dir_index)
    @handler.handle_key(' ')

    dir_name = entries[dir_index][:name]
    assert @handler.is_selected?(dir_name),
           "ディレクトリも選択できるべき"
  end

  def test_space_key_not_work_in_job_mode
    @handler.enter_job_mode

    entries = @directory_listing.list_entries
    @handler.select_index(0)
    @handler.handle_key(' ')

    assert @handler.selected_items.empty?,
           "ジョブモードではファイル選択されないべき"

    @handler.send(:exit_job_mode)
  end

  def test_is_selected_returns_false_in_different_directory
    entries = @directory_listing.list_entries
    @handler.select_index(0)
    first_entry_name = entries[0][:name]

    @handler.handle_key(' ')
    assert @handler.is_selected?(first_entry_name)

    dir_index = entries.find_index { |e| e[:type] == 'directory' && e[:name] != '..' }
    if dir_index
      @handler.select_index(dir_index)
      @handler.handle_key('l')

      refute @handler.is_selected?(first_entry_name),
             "別ディレクトリでは選択表示されないべき"
    end
  end

  def test_current_entry_returns_valid_entry
    entries = @directory_listing.list_entries
    skip 'エントリがない' if entries.empty?

    @handler.select_index(0)
    entry = @handler.current_entry

    refute_nil entry, 'current_entryはnilではないべき'
    refute_nil entry[:name], 'エントリに:nameキーがあるべき'
  end

  # === ディレクトリ移動後の選択状態のテスト ===

  def test_selection_manager_cross_directory_resets_source
    manager = Rufio::SelectionManager.new

    entry_a = { name: 'file_a.txt', type: 'file' }
    manager.toggle_selection(entry_a, '/dir_a')
    assert_equal '/dir_a', manager.source_directory

    entry_b = { name: 'file_b.txt', type: 'file' }
    manager.toggle_selection(entry_b, '/dir_b')

    assert_equal '/dir_b', manager.source_directory,
                 "異なるディレクトリで選択した場合、source_directoryが更新されるべき"
    assert manager.selected?('file_b.txt')
    refute manager.selected?('file_a.txt'),
           "古いディレクトリの選択はクリアされるべき"
  end

  def test_stale_selection_does_not_block_new_selection
    manager = Rufio::SelectionManager.new

    dotdot = { name: '..', type: 'directory' }
    manager.toggle_selection(dotdot, '/path/to/info')

    assert_equal '/path/to/info', manager.source_directory
    assert_equal 1, manager.count

    new_file = { name: 'my_file.txt', type: 'file' }
    manager.toggle_selection(new_file, '/path/to/original')

    assert_equal '/path/to/original', manager.source_directory,
                 "source_directoryが新しいディレクトリに更新されるべき"
    assert manager.selected?('my_file.txt')
  end

  def test_keybind_handler_selection_after_directory_change
    entries = @directory_listing.list_entries

    @handler.select_index(0)
    first_entry = entries[0][:name]
    @handler.handle_key(' ')
    assert @handler.is_selected?(first_entry)

    dir_index = entries.find_index { |e| e[:type] == 'directory' && e[:name] != '..' }
    skip 'サブディレクトリが見つからない' unless dir_index
    @handler.select_index(dir_index)
    @handler.handle_key('l')

    new_entries = @directory_listing.list_entries
    skip '移動先にエントリがない' if new_entries.empty?
    @handler.select_index(0)
    @handler.handle_key(' ')

    new_entry = new_entries[0][:name]
    assert @handler.is_selected?(new_entry),
           "ディレクトリ移動後もSpaceで選択が表示されるべき"
  end

  # === Logs/ヘルプモードでのインデックスずれテスト ===

  def test_log_viewer_mode_get_active_entries_excludes_dotdot
    # Logsモードではget_active_entriesから..が除外されるべき
    # （get_display_entriesと同じエントリを返す）

    # ログディレクトリを作成してファイルを配置
    log_dir = File.join(@tmpdir, 'logs')
    FileUtils.mkdir_p(log_dir)
    File.write(File.join(log_dir, 'log1.txt'), 'log content 1')
    File.write(File.join(log_dir, 'log2.txt'), 'log content 2')

    # ログディレクトリに移動してログビューワモードをシミュレート
    @directory_listing = Rufio::DirectoryListing.new(log_dir)
    @handler.set_directory_listing(@directory_listing)

    # ログビューワモードに入る前のエントリ（..を含む）
    entries_before = @handler.get_active_entries
    has_dotdot = entries_before.any? { |e| e[:name] == '..' }
    assert has_dotdot, '通常モードでは..が含まれるべき'

    # ログビューワモードをシミュレート（内部状態を直接設定）
    @handler.instance_variable_set(:@in_log_viewer_mode, true)

    # get_active_entriesから..が除外されるべき
    entries_in_log_mode = @handler.get_active_entries
    no_dotdot = entries_in_log_mode.none? { |e| e[:name] == '..' }
    assert no_dotdot, 'Logsモードではget_active_entriesから..が除外されるべき'

    # インデックス0がlog1.txt（..ではない）であること
    @handler.select_index(0)
    entry = @handler.current_entry
    refute_equal '..', entry[:name],
                 'Logsモードのインデックス0は..ではないべき'

    @handler.instance_variable_set(:@in_log_viewer_mode, false)
  end

  def test_help_mode_get_active_entries_excludes_dotdot
    # ヘルプモードでも同様に..が除外されるべき

    # infoディレクトリをシミュレート
    info_dir = File.join(@tmpdir, 'info')
    FileUtils.mkdir_p(info_dir)
    File.write(File.join(info_dir, 'help.md'), '# Help')
    File.write(File.join(info_dir, 'keybindings.md'), '# Keybindings')

    @directory_listing = Rufio::DirectoryListing.new(info_dir)
    @handler.set_directory_listing(@directory_listing)

    # ヘルプモードをシミュレート
    @handler.instance_variable_set(:@in_help_mode, true)

    entries = @handler.get_active_entries
    no_dotdot = entries.none? { |e| e[:name] == '..' }
    assert no_dotdot, 'ヘルプモードではget_active_entriesから..が除外されるべき'

    @handler.select_index(0)
    entry = @handler.current_entry
    refute_equal '..', entry[:name],
                 'ヘルプモードのインデックス0は..ではないべき'

    @handler.instance_variable_set(:@in_help_mode, false)
  end

  def test_log_viewer_mode_space_selects_correct_file
    # Logsモードでカーソル位置のファイルが正しく選択されること
    log_dir = File.join(@tmpdir, 'logs')
    FileUtils.mkdir_p(log_dir)
    File.write(File.join(log_dir, 'aaa.txt'), 'log1')
    File.write(File.join(log_dir, 'bbb.txt'), 'log2')
    File.write(File.join(log_dir, 'ccc.txt'), 'log3')

    @directory_listing = Rufio::DirectoryListing.new(log_dir)
    @handler.set_directory_listing(@directory_listing)
    @handler.instance_variable_set(:@in_log_viewer_mode, true)

    entries = @handler.get_active_entries
    # index 0 = 最初のファイル（..を除外済み）
    @handler.select_index(0)
    first_file = @handler.current_entry[:name]

    # Spaceで選択
    @handler.handle_key(' ')

    # カーソル位置のファイルが選択されているべき（1つ上ではない）
    assert @handler.selected_items.include?(first_file),
           "カーソル位置のファイル '#{first_file}' が選択されるべき（..ではない）"
    refute @handler.selected_items.include?('..'),
           "..が選択されてはならない"

    # index 1に移動して選択
    @handler.handle_key('j')
    second_file = @handler.current_entry[:name]
    @handler.handle_key(' ')

    assert @handler.selected_items.include?(second_file),
           "2番目のファイル '#{second_file}' が選択されるべき"

    @handler.instance_variable_set(:@in_log_viewer_mode, false)
  end
end
