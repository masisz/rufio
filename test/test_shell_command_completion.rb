# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'

class TestShellCommandCompletion < Minitest::Test
  def setup
    @completion = Rufio::ShellCommandCompletion.new
  end

  def test_shell_command_completion_class_exists
    assert defined?(Rufio::ShellCommandCompletion), "Rufio::ShellCommandCompletion クラスが定義されていません"
  end

  # === PATHのコマンド補完テスト ===

  def test_complete_path_commands
    # PATHから実行可能なコマンドを補完
    candidates = @completion.complete_command("l")

    # 'ls' や 'less' などが含まれるはず
    assert candidates.any? { |c| c.start_with?("l") }, "l で始まるコマンドが見つかりません"
    # 実際のシステムに依存するが、lsは通常存在する
    assert_includes candidates, "ls" if system("which ls > /dev/null 2>&1")
  end

  def test_complete_path_commands_with_full_match
    # 完全一致の場合もそのコマンドを返す
    candidates = @completion.complete_command("ls")

    assert_includes candidates, "ls" if system("which ls > /dev/null 2>&1")
  end

  def test_complete_path_commands_no_match
    # マッチするコマンドがない場合は空の配列
    candidates = @completion.complete_command("xyzabc123")

    assert_empty candidates
  end

  def test_complete_path_commands_case_insensitive
    # 大文字小文字を区別しない
    candidates = @completion.complete_command("LS")

    # 大文字で入力しても小文字のコマンドが見つかる
    assert candidates.any? { |c| c.downcase == "ls" } if system("which ls > /dev/null 2>&1")
  end

  # === ファイルパス補完テスト ===

  def test_complete_file_path
    # 一時ディレクトリを作成してテスト
    Dir.mktmpdir do |tmpdir|
      # テスト用ファイルを作成
      File.write(File.join(tmpdir, "test_file.txt"), "test")
      File.write(File.join(tmpdir, "test_another.txt"), "test")
      Dir.mkdir(File.join(tmpdir, "test_dir"))

      candidates = @completion.complete_path("#{tmpdir}/test")

      # test で始まるファイル/ディレクトリが見つかる
      assert candidates.any? { |c| c.include?("test_file.txt") }
      assert candidates.any? { |c| c.include?("test_another.txt") }
      assert candidates.any? { |c| c.include?("test_dir") }
    end
  end

  def test_complete_file_path_with_tilde
    # ~ の展開をテスト
    candidates = @completion.complete_path("~/")

    # ホームディレクトリのファイルが見つかる
    refute_empty candidates
    # パスが展開されている
    assert candidates.all? { |c| c.start_with?(ENV['HOME']) || c.start_with?("~/") }
  end

  def test_complete_file_path_directory_only
    # ディレクトリのみを補完
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, "file.txt"), "test")
      Dir.mkdir(File.join(tmpdir, "dir1"))
      Dir.mkdir(File.join(tmpdir, "dir2"))

      candidates = @completion.complete_path("#{tmpdir}/", directories_only: true)

      # ディレクトリのみが含まれる
      assert candidates.any? { |c| c.include?("dir1") }
      assert candidates.any? { |c| c.include?("dir2") }
      refute candidates.any? { |c| c.include?("file.txt") }
    end
  end

  def test_complete_file_path_no_match
    # マッチするパスがない場合
    candidates = @completion.complete_path("/nonexistent/path/xyz")

    assert_empty candidates
  end

  # === コマンド履歴からの補完テスト ===

  def test_complete_from_history
    # 一時ファイルで履歴を作成
    Dir.mktmpdir do |tmpdir|
      history_file = File.join(tmpdir, "history.txt")
      history = Rufio::CommandHistory.new(history_file)

      # シェルコマンドを履歴に追加
      history.add("!git status")
      history.add("!git commit -m 'test'")
      history.add("!ls -la")
      history.save

      # 履歴から補完
      candidates = @completion.complete_from_history("git", history)

      # git で始まるコマンドが見つかる
      assert_includes candidates, "git status"
      assert_includes candidates, "git commit -m 'test'"
      refute_includes candidates, "ls -la"
    end
  end

  def test_complete_from_history_empty
    # 空の履歴
    Dir.mktmpdir do |tmpdir|
      history_file = File.join(tmpdir, "history.txt")
      history = Rufio::CommandHistory.new(history_file)

      candidates = @completion.complete_from_history("git", history)

      assert_empty candidates
    end
  end

  def test_complete_from_history_no_match
    # マッチする履歴がない
    Dir.mktmpdir do |tmpdir|
      history_file = File.join(tmpdir, "history.txt")
      history = Rufio::CommandHistory.new(history_file)

      history.add("!git status")
      history.save

      candidates = @completion.complete_from_history("ls", history)

      assert_empty candidates
    end
  end
end
