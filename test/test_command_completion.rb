# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'

class TestCommandCompletion < Minitest::Test
  def setup
    # プラグインマネージャーをリセット
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    # テスト用プラグインを作成
    @test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end

      def description
        "テスト用プラグイン"
      end

      def commands
        {
          hello: method(:say_hello),
          help: method(:show_help),
          history: method(:show_history)
        }
      end

      private

      def say_hello
        "Hello!"
      end

      def show_help
        "Help!"
      end

      def show_history
        "History!"
      end
    end

    # プラグインを登録
    Rufio::Plugins.const_set(:TestPlugin, @test_plugin)
    Rufio::PluginManager.register(@test_plugin)
  end

  def teardown
    # テスト後のクリーンアップ
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    # テスト用プラグインを削除
    if Rufio::Plugins.const_defined?(:TestPlugin, false)
      Rufio::Plugins.send(:remove_const, :TestPlugin)
    end
  end

  def test_command_completion_class_exists
    assert defined?(Rufio::CommandCompletion), "Rufio::CommandCompletion クラスが定義されていません"
  end

  def test_get_all_completion_candidates
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    completion = Rufio::CommandCompletion.new
    candidates = completion.complete("")

    # すべてのコマンド名を候補として返す
    assert_includes candidates, "hello"
    assert_includes candidates, "help"
    assert_includes candidates, "history"
  end

  def test_complete_with_prefix
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    completion = Rufio::CommandCompletion.new

    # "he" で始まるコマンドを補完
    candidates = completion.complete("he")

    assert_equal 2, candidates.size
    assert_includes candidates, "hello"
    assert_includes candidates, "help"
  end

  def test_complete_with_unique_match
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    completion = Rufio::CommandCompletion.new

    # "his" で始まるコマンドは history のみ
    candidates = completion.complete("his")

    assert_equal 1, candidates.size
    assert_equal "history", candidates.first
  end

  def test_complete_with_no_match
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    completion = Rufio::CommandCompletion.new

    # マッチするコマンドがない
    candidates = completion.complete("xyz")

    assert_empty candidates
  end

  def test_complete_exact_match
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    completion = Rufio::CommandCompletion.new

    # 完全一致の場合も候補を返す
    candidates = completion.complete("hello")

    assert_equal 1, candidates.size
    assert_equal "hello", candidates.first
  end

  def test_complete_case_insensitive
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    completion = Rufio::CommandCompletion.new

    # 大文字小文字を区別しない
    candidates = completion.complete("HE")

    assert_equal 2, candidates.size
    assert_includes candidates, "hello"
    assert_includes candidates, "help"
  end

  def test_get_common_prefix
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    completion = Rufio::CommandCompletion.new

    # 複数の候補がある場合、共通のプレフィックスを返す
    common_prefix = completion.common_prefix("he")

    # "hello" と "help" の共通プレフィックスは "hel"
    assert_equal "hel", common_prefix
  end

  def test_get_common_prefix_with_unique_match
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    completion = Rufio::CommandCompletion.new

    # 候補が1つの場合、そのコマンド名全体を返す
    common_prefix = completion.common_prefix("his")

    assert_equal "history", common_prefix
  end

  def test_get_common_prefix_with_no_match
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    completion = Rufio::CommandCompletion.new

    # 候補がない場合、元の入力をそのまま返す
    common_prefix = completion.common_prefix("xyz")

    assert_equal "xyz", common_prefix
  end
end
