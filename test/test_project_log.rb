# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

module Rufio
  class TestProjectLog < Minitest::Test
    def setup
      @temp_dir = Dir.mktmpdir
      @log_dir = File.join(@temp_dir, 'logs')
      FileUtils.mkdir_p(@log_dir)

      @project_log = ProjectLog.new(@log_dir)
    end

    def teardown
      FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    end

    # プロジェクトの実行ログはconfigで指定したディレクトリに保存される
    def test_save_log_to_configured_directory
      @project_log.save('test_project', 'echo "test"', 'test output')

      log_files = Dir.glob(File.join(@log_dir, '*.log'))
      assert_equal 1, log_files.length
      assert File.exist?(log_files[0])
    end

    # ログファイルには実行したコマンドと結果が保存される
    def test_log_contains_command_and_output
      @project_log.save('test_project', 'ls -la', 'file1.txt\nfile2.txt')

      log_files = Dir.glob(File.join(@log_dir, '*.log'))
      content = File.read(log_files[0])

      assert_includes content, 'test_project'
      assert_includes content, 'ls -la'
      assert_includes content, 'file1.txt'
      assert_includes content, 'file2.txt'
    end

    # lを押すと実行ログのディレクトリに移動
    def test_navigate_to_log_directory
      result = @project_log.navigate_to_log_dir

      assert_equal @log_dir, result[:path]
    end

    # ログファイルの一覧が左画面に表示される
    def test_list_log_files_on_left_pane
      @project_log.save('project1', 'cmd1', 'output1')
      @project_log.save('project2', 'cmd2', 'output2')

      list = @project_log.list_log_files

      assert_equal 2, list.length
      assert list[0].end_with?('.log')
      assert list[1].end_with?('.log')
    end

    # ログファイルが存在しない場合は空の配列を返す
    def test_empty_log_files_returns_empty_array
      list = @project_log.list_log_files

      assert_equal 0, list.length
    end

    # 右画面にログファイルのプレビューが表示される
    def test_preview_log_file_on_right_pane
      @project_log.save('test_project', 'echo "hello"', 'hello')

      log_files = @project_log.list_log_files
      preview = @project_log.preview(log_files[0])

      assert_includes preview, 'test_project'
      assert_includes preview, 'echo "hello"'
      assert_includes preview, 'hello'
    end

    # 存在しないログファイルのプレビューは空文字列
    def test_preview_nonexistent_log_returns_empty
      preview = @project_log.preview('nonexistent.log')

      assert_equal '', preview
    end

    # ログファイルは時系列で表示される
    def test_log_files_sorted_by_time
      @project_log.save('project1', 'cmd1', 'output1')
      sleep 1.1
      @project_log.save('project2', 'cmd2', 'output2')
      sleep 1.1
      @project_log.save('project3', 'cmd3', 'output3')

      list = @project_log.list_log_files

      # 最新のログが最初に来る
      assert_equal 3, list.length
      content1 = File.read(File.join(@log_dir, list[0]))
      content3 = File.read(File.join(@log_dir, list[2]))

      assert_includes content1, 'project3'
      assert_includes content3, 'project1'
    end
  end
end
