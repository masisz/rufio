# frozen_string_literal: true

require 'test_helper'
require 'rufio/plugins/file_operations'

class TestPluginsFileOperations < Minitest::Test
  def setup
    # プラグインインスタンスを作成
    @plugin = Rufio::Plugins::FileOperations.new

    # FileOperationsプラグインがPluginManagerに登録されていることを確認
    # (他のテストでクリアされている可能性があるため)
    unless Rufio::PluginManager.plugins.include?(Rufio::Plugins::FileOperations)
      Rufio::PluginManager.register(Rufio::Plugins::FileOperations)
    end
  end

  def test_file_operations_plugin_exists
    assert defined?(Rufio::Plugins::FileOperations),
           "Rufio::Plugins::FileOperations クラスが定義されていません"
  end

  def test_file_operations_inherits_from_plugin
    assert @plugin.is_a?(Rufio::Plugin),
           "FileOperations は Rufio::Plugin を継承している必要があります"
  end

  def test_name_returns_file_operations
    assert_equal "FileOperations", @plugin.name
  end

  def test_description_returns_expected_text
    expected_description = "基本的なファイル操作(コピー、移動、削除)"
    assert_equal expected_description, @plugin.description
  end

  def test_has_no_dependencies
    # 外部gem依存なし
    assert_equal [], Rufio::Plugins::FileOperations.required_gems
  end

  def test_commands_returns_hash_with_three_commands
    commands = @plugin.commands

    assert_kind_of Hash, commands
    assert_equal 3, commands.size
  end

  def test_commands_includes_copy
    commands = @plugin.commands
    assert_includes commands.keys, :copy
    assert_kind_of Method, commands[:copy]
  end

  def test_commands_includes_move
    commands = @plugin.commands
    assert_includes commands.keys, :move
    assert_kind_of Method, commands[:move]
  end

  def test_commands_includes_delete
    commands = @plugin.commands
    assert_includes commands.keys, :delete
    assert_kind_of Method, commands[:delete]
  end

  def test_copy_command_is_callable
    commands = @plugin.commands

    # copyコマンドが呼び出し可能であることを確認
    result = commands[:copy].call
    # エラーが発生しなければ成功
    assert true
  end

  def test_move_command_is_callable
    commands = @plugin.commands

    # moveコマンドが呼び出し可能であることを確認
    result = commands[:move].call
    # エラーが発生しなければ成功
    assert true
  end

  def test_delete_command_is_callable
    commands = @plugin.commands

    # deleteコマンドが呼び出し可能であることを確認
    result = commands[:delete].call
    # エラーが発生しなければ成功
    assert true
  end

  def test_copy_command_returns_string_or_nil
    commands = @plugin.commands
    result = commands[:copy].call

    # スタブ実装なので、文字列かnilを返す
    assert (result.is_a?(String) || result.nil?),
           "copy コマンドは String または nil を返す必要があります"
  end

  def test_move_command_returns_string_or_nil
    commands = @plugin.commands
    result = commands[:move].call

    # スタブ実装なので、文字列かnilを返す
    assert (result.is_a?(String) || result.nil?),
           "move コマンドは String または nil を返す必要があります"
  end

  def test_delete_command_returns_string_or_nil
    commands = @plugin.commands
    result = commands[:delete].call

    # スタブ実装なので、文字列かnilを返す
    assert (result.is_a?(String) || result.nil?),
           "delete コマンドは String または nil を返す必要があります"
  end

  def test_plugin_can_be_instantiated_without_errors
    # 外部gem依存がないので、エラーなくインスタンス化できる
    plugin = Rufio::Plugins::FileOperations.new
    assert_equal "FileOperations", plugin.name
  end

  def test_plugin_is_registered_in_plugin_manager
    # FileOperationsプラグインがPluginManagerに登録されている
    # （Pluginを継承した時点で自動登録される）
    Rufio::PluginManager.load_all

    plugin_classes = Rufio::PluginManager.plugins
    assert_includes plugin_classes, Rufio::Plugins::FileOperations
  end
end
