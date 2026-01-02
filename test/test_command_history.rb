# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

class TestCommandHistory < Minitest::Test
  def setup
    # テスト用の一時ディレクトリを作成
    @temp_dir = Dir.mktmpdir
    @history_file = File.join(@temp_dir, 'command_history.txt')
  end

  def teardown
    # テスト後のクリーンアップ
    FileUtils.rm_rf(@temp_dir) if File.exist?(@temp_dir)
  end

  def test_command_history_class_exists
    assert defined?(Rufio::CommandHistory), "Rufio::CommandHistory クラスが定義されていません"
  end

  def test_add_command_to_history
    history = Rufio::CommandHistory.new(@history_file)

    # コマンドを履歴に追加できる
    history.add("!git status")
    history.add("hello")

    assert_equal 2, history.size
  end

  def test_get_previous_command
    history = Rufio::CommandHistory.new(@history_file)
    history.add("!git status")
    history.add("!svn update")
    history.add("hello")

    # 最後のコマンドから順に取得できる
    assert_equal "hello", history.previous
    assert_equal "!svn update", history.previous
    assert_equal "!git status", history.previous
  end

  def test_get_next_command
    history = Rufio::CommandHistory.new(@history_file)
    history.add("!git status")
    history.add("!svn update")
    history.add("hello")

    # 前に戻ってから次に進める
    history.previous  # hello
    history.previous  # !svn update
    assert_equal "hello", history.next
  end

  def test_previous_at_beginning_returns_nil
    history = Rufio::CommandHistory.new(@history_file)
    history.add("command1")

    history.previous  # command1
    # これ以上前はない
    assert_nil history.previous
  end

  def test_next_at_end_returns_empty
    history = Rufio::CommandHistory.new(@history_file)
    history.add("command1")

    # 最新の位置では空文字列を返す
    assert_equal "", history.next
  end

  def test_save_history_to_file
    history = Rufio::CommandHistory.new(@history_file)
    history.add("!git status")
    history.add("hello")
    history.add("!svn update")

    # 履歴をファイルに保存
    history.save

    # ファイルが作成されている
    assert File.exist?(@history_file)

    # ファイルの内容を確認
    content = File.read(@history_file)
    assert_match(/!git status/, content)
    assert_match(/hello/, content)
    assert_match(/!svn update/, content)
  end

  def test_load_history_from_file
    # 履歴ファイルを事前に作成
    File.write(@history_file, "!git status\nhello\n!svn update\n")

    # 履歴を読み込む
    history = Rufio::CommandHistory.new(@history_file)

    assert_equal 3, history.size
    assert_equal "!svn update", history.previous
    assert_equal "hello", history.previous
    assert_equal "!git status", history.previous
  end

  def test_ignore_duplicate_consecutive_commands
    history = Rufio::CommandHistory.new(@history_file)
    history.add("!git status")
    history.add("!git status")  # 同じコマンドを連続で追加
    history.add("hello")

    # 連続する重複は無視される
    assert_equal 2, history.size
    assert_equal "hello", history.previous
    assert_equal "!git status", history.previous
  end

  def test_empty_command_not_added
    history = Rufio::CommandHistory.new(@history_file)
    history.add("")
    history.add("   ")

    # 空のコマンドは追加されない
    assert_equal 0, history.size
  end

  def test_reset_position
    history = Rufio::CommandHistory.new(@history_file)
    history.add("command1")
    history.add("command2")

    history.previous  # command2
    history.previous  # command1

    # 位置をリセット（新しいコマンド入力時などに使用）
    history.reset_position

    # 再度最新から取得できる
    assert_equal "command2", history.previous
  end

  def test_max_history_size
    history = Rufio::CommandHistory.new(@history_file, max_size: 3)

    history.add("command1")
    history.add("command2")
    history.add("command3")
    history.add("command4")

    # 最大サイズを超えると古いものが削除される
    assert_equal 3, history.size

    # 最も古いcommand1は削除されている
    assert_equal "command4", history.previous
    assert_equal "command3", history.previous
    assert_equal "command2", history.previous
    assert_nil history.previous
  end
end
