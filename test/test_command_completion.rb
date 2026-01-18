# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'

class TestCommandCompletion < Minitest::Test
  def setup
    @command_mode = Rufio::CommandMode.new
  end

  def test_command_completion_class_exists
    assert defined?(Rufio::CommandCompletion), "Rufio::CommandCompletion クラスが定義されていません"
  end

  def test_get_all_completion_candidates
    completion = Rufio::CommandCompletion.new(@command_mode)
    candidates = completion.complete("")

    # 組み込みコマンドを候補として返す
    assert_includes candidates, "hello"
    assert_includes candidates, "stop"
  end

  def test_complete_with_prefix
    completion = Rufio::CommandCompletion.new(@command_mode)

    # "he" で始まるコマンドを補完
    candidates = completion.complete("he")

    assert_includes candidates, "hello"
  end

  def test_complete_with_unique_match
    completion = Rufio::CommandCompletion.new(@command_mode)

    # "hel" で始まるコマンドは hello のみ
    candidates = completion.complete("hel")

    assert_equal 1, candidates.size
    assert_equal "hello", candidates.first
  end

  def test_complete_with_no_match
    completion = Rufio::CommandCompletion.new(@command_mode)

    # マッチするコマンドがない
    candidates = completion.complete("xyz")

    assert_empty candidates
  end

  def test_complete_exact_match
    completion = Rufio::CommandCompletion.new(@command_mode)

    # 完全一致の場合も候補を返す
    candidates = completion.complete("hello")

    assert_equal 1, candidates.size
    assert_equal "hello", candidates.first
  end

  def test_complete_case_insensitive
    completion = Rufio::CommandCompletion.new(@command_mode)

    # 大文字小文字を区別しない
    candidates = completion.complete("HE")

    assert_includes candidates, "hello"
  end

  def test_get_common_prefix
    completion = Rufio::CommandCompletion.new(@command_mode)

    # 補完候補があるプレフィックスの共通部分を返す
    common_prefix = completion.common_prefix("he")

    # "hello" があるので、共通プレフィックスは少なくとも "he" を含む
    assert common_prefix.start_with?("he")
  end

  def test_get_common_prefix_with_unique_match
    completion = Rufio::CommandCompletion.new(@command_mode)

    # 候補が1つの場合、そのコマンド名全体を返す
    common_prefix = completion.common_prefix("hel")

    assert_equal "hello", common_prefix
  end

  def test_get_common_prefix_with_no_match
    completion = Rufio::CommandCompletion.new(@command_mode)

    # 候補がない場合、元の入力をそのまま返す
    common_prefix = completion.common_prefix("xyz")

    assert_equal "xyz", common_prefix
  end

  # === シェルコマンド補完の統合テスト ===

  def test_complete_shell_command
    completion = Rufio::CommandCompletion.new(@command_mode)

    # ! で始まる入力はシェルコマンドとして補完
    candidates = completion.complete("!l")

    # PATH上の l で始まるコマンドが含まれる
    assert candidates.any? { |c| c.start_with?("!l") }
    # lsは通常存在する
    assert_includes candidates, "!ls" if system("which ls > /dev/null 2>&1")
  end

  def test_complete_shell_command_with_space
    completion = Rufio::CommandCompletion.new(@command_mode)

    # コマンド + スペース + パスの場合、パス補完を行う
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, "test.txt"), "test")

      candidates = completion.complete("!ls #{tmpdir}/t")

      # ファイルパスの補完候補が含まれる
      assert candidates.any? { |c| c.include?("test.txt") }
    end
  end

  def test_normal_command_not_affected_by_shell_completion
    completion = Rufio::CommandCompletion.new(@command_mode)

    # ! なしの通常のコマンドは従来通り動作
    candidates = completion.complete("he")

    assert_includes candidates, "hello"
    # シェルコマンドは含まれない（!で始まらない）
    refute candidates.any? { |c| c.start_with?("!") }
  end
end
