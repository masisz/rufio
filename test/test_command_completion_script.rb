# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio'

# スクリプト補完機能のテスト
class TestCommandCompletionScript < Minitest::Test
  def setup
    @command_mode = Rufio::CommandMode.new
    @command_completion = Rufio::CommandCompletion.new(nil, @command_mode)
  end

  # === 基本動作のテスト ===

  def test_complete_with_nil_command_mode_returns_internal_commands
    # CommandModeがnilの場合は内部コマンドのみを返す
    completion = Rufio::CommandCompletion.new(nil, nil)
    candidates = completion.complete('')

    # 内部コマンドが含まれていることを確認
    assert_includes candidates, 'hello'
    assert_includes candidates, 'stop'
  end

  def test_complete_with_command_mode_returns_internal_commands
    # CommandModeがある場合も内部コマンドを返す
    candidates = @command_completion.complete('')

    # 内部コマンドが含まれていることを確認
    assert_includes candidates, 'hello'
    assert_includes candidates, 'stop'
  end

  # === @プレフィックス（スクリプト補完）のテスト ===

  def test_complete_at_prefix_calls_complete_script
    # @プレフィックスの場合にスクリプト補完が呼び出されることを確認
    # ScriptRunnerが設定されていない場合は空配列を返す
    candidates = @command_completion.complete('@')

    # ScriptRunnerが未設定の場合は空配列
    assert_equal [], candidates
  end

  def test_complete_at_prefix_with_script_runner
    # テスト用のモックScriptRunnerを設定
    mock_script_runner = MockScriptRunner.new(['build.sh', 'test.sh', 'deploy.sh'])
    @command_mode.instance_variable_set(:@script_runner, mock_script_runner)

    # @bu で補完
    candidates = @command_completion.complete('@bu')

    # @build.sh が候補に含まれることを確認
    assert_includes candidates, '@build.sh'
  end

  def test_complete_at_prefix_with_partial_match
    # テスト用のモックScriptRunnerを設定
    mock_script_runner = MockScriptRunner.new(['build.sh', 'bundle.sh', 'test.sh'])
    @command_mode.instance_variable_set(:@script_runner, mock_script_runner)

    # @bu で補完すると build.sh と bundle.sh が候補に
    candidates = @command_completion.complete('@bu')

    assert_includes candidates, '@build.sh'
    assert_includes candidates, '@bundle.sh'
    refute_includes candidates, '@test.sh'
  end

  # === 通常コマンドとスクリプト補完の併合テスト ===

  def test_complete_without_at_prefix_includes_scripts
    # @プレフィックスなしの場合も、スクリプトを候補に含める
    mock_script_runner = MockScriptRunner.new(['build.sh', 'test.sh'])
    @command_mode.instance_variable_set(:@script_runner, mock_script_runner)

    # 空入力で補完
    candidates = @command_completion.complete('')

    # 内部コマンドとスクリプト両方が含まれることを確認
    assert_includes candidates, 'hello'
    assert_includes candidates, 'stop'
    # @プレフィックスなしの場合、スクリプトは @付きで表示
    assert_includes candidates, '@build.sh'
    assert_includes candidates, '@test.sh'
  end

  def test_complete_partial_match_includes_both_commands_and_scripts
    # 部分一致の場合、コマンドとスクリプト両方を補完対象とする
    mock_script_runner = MockScriptRunner.new(['help_script.sh', 'hello.sh'])
    @command_mode.instance_variable_set(:@script_runner, mock_script_runner)

    # "he" で補完
    candidates = @command_completion.complete('he')

    # 内部コマンド "hello" が含まれる
    assert_includes candidates, 'hello'
  end

  # === 共通プレフィックスのテスト ===

  def test_common_prefix_with_script_candidates
    mock_script_runner = MockScriptRunner.new(['build.sh', 'bundle.sh'])
    @command_mode.instance_variable_set(:@script_runner, mock_script_runner)

    # @bu の共通プレフィックス
    prefix = @command_completion.common_prefix('@bu')

    # @bu まで共通
    assert_equal '@bu', prefix
  end

  def test_common_prefix_with_single_script_match
    mock_script_runner = MockScriptRunner.new(['build.sh', 'test.sh'])
    @command_mode.instance_variable_set(:@script_runner, mock_script_runner)

    # @bui の共通プレフィックス（build.shのみマッチ）
    prefix = @command_completion.common_prefix('@bui')

    # 完全一致
    assert_equal '@build.sh', prefix
  end

  # モック用のScriptRunnerクラス
  class MockScriptRunner
    def initialize(scripts)
      @scripts = scripts
    end

    def complete(prefix)
      @scripts.select { |s| s.downcase.start_with?(prefix.downcase) }
    end
  end
end
